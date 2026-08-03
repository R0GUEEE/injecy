//
//  AppUpdater.swift
//  injecy
//
//  Self-updater: checks the backend for a newer build, downloads the IPA, verifies its
//  sha256, and imports it so the user can sign it with their certificate and install it
//  over the current version (same bundle id). Stable channel for now; the API already
//  takes a `channel` so beta can be enabled later.
//

import Foundation
import CryptoKit
import CoreData
import UIKit
import IDeviceSwift

@MainActor
final class AppUpdater: ObservableObject {
	static let shared = AppUpdater()

	struct Release: Equatable {
		let version: String
		let build: Int
		let changelog: String
		let ipaURL: URL
		let sha256: String
		let size: Int
		let force: Bool
	}

	enum Phase: Equatable {
		case idle
		case checking
		case upToDate
		case available(Release)
		case downloading(Double)
		case verifying
		case downloaded     // IPA downloaded + verified, awaiting "Install"
		case signing        // importing + signing with the user's certificate
		case installing     // preparing OTA install (upload + itms-services handoff)
		case failed(String)
	}

	@Published private(set) var phase: Phase = .idle
	/// The latest known available release (kept so a banner can show even after dismiss).
	@Published private(set) var available: Release?
	/// Set when the signed update is ready — the update window presents the installer.
	@Published var pendingInstall: AnyApp?

	/// The verified IPA on disk, awaiting install.
	private var _downloadedIPA: URL?
	/// Entities created for the update, deleted after install to keep the Library clean.
	private var _tempImported: AppInfoPresentable?
	private var _tempSigned: AppInfoPresentable?

	private let _channel = "stable"
	private let _lastCheckKey = "injecy.lastUpdateCheck"

	private init() {}

	var currentVersion: String {
		Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
	}
	var currentBuild: Int {
		Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
	}

	/// Check on launch at most once every 6 hours; `manual` bypasses the throttle.
	func checkOnLaunch() {
		let last = UserDefaults.standard.double(forKey: _lastCheckKey)
		if Date().timeIntervalSince1970 - last < 6 * 3600 { return }
		check(manual: false)
	}

	func check(manual: Bool) {
		if case .checking = phase { return }
		phase = .checking
		UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: _lastCheckKey)
		Task {
			do {
				let info = try await InjecyBackend.shared.checkAppVersion(channel: _channel)
				guard
					info.available,
					let build = info.build, build > currentBuild,
					let urlString = info.ipaURL, let url = URL(string: urlString)
				else {
					self.available = nil
					self.phase = .upToDate
					return
				}
				let release = Release(
					version: info.version ?? "?",
					build: build,
					changelog: info.changelog ?? "",
					ipaURL: url,
					sha256: (info.sha256 ?? "").lowercased(),
					size: info.size ?? 0,
					force: info.force ?? false
				)
				self.available = release
				// If this exact build was already downloaded, jump straight to install.
				let dest = self._downloadDestination(release)
				if FileManager.default.fileExists(atPath: dest.path) {
					self._downloadedIPA = dest
					self.phase = .downloaded
				} else {
					self.phase = .available(release)
				}
			} catch {
				self.phase = manual ? .failed(error.localizedDescription) : .idle
			}
		}
	}

	/// Stable on-disk location for a given build's downloaded IPA (persists across the
	/// update window, so re-opening it doesn't re-download).
	private func _downloadDestination(_ release: Release) -> URL {
		FileManager.default.temporaryDirectory.appendingPathComponent("injecy-update-\(release.build).ipa")
	}

	/// Download the update IPA into the update window (not the Library) and verify it.
	/// Reuses an already-downloaded build instead of fetching it again.
	func download(_ release: Release) {
		let dest = _downloadDestination(release)
		if FileManager.default.fileExists(atPath: dest.path),
		   (try? _verify(dest, sha256: release.sha256)) != nil {
			_downloadedIPA = dest
			phase = .downloaded
			return
		}
		phase = .downloading(0)
		Task {
			do {
				let tmp = try await _download(release)
				phase = .verifying
				try _verify(tmp, sha256: release.sha256)
				try? FileManager.default.removeItem(at: dest)
				try FileManager.default.moveItem(at: tmp, to: dest)
				_downloadedIPA = dest
				phase = .downloaded
			} catch {
				phase = .failed(error.localizedDescription)
			}
		}
	}

	/// Sign the downloaded update with the user's selected certificate, then hand it to the
	/// installer. Nothing is left in the Library — the temp entities are cleaned up after.
	func install() {
		guard let ipa = _downloadedIPA else { return }
		guard let cert = Storage.shared.getCertificate(
			for: UserDefaults.standard.integer(forKey: "feather.selectedCert")
		) else {
			phase = .failed(.localized("Select a signing certificate in Settings first."))
			return
		}
		if let exp = cert.expiration, exp < Date() {
			phase = .failed(.localized("Your certificate has expired. Add a valid one in Settings → Certificates."))
			return
		}
		// Remember the changelog so a "What's New" shows once the new build launches.
		if let r = available {
			UserDefaults.standard.set(
				["build": String(r.build), "version": r.version, "changelog": r.changelog],
				forKey: "injecy.pendingWhatsNew"
			)
		}
		let useIDevice = UserDefaults.standard.integer(forKey: "Feather.installationMethod") == 1
		phase = .signing
		Task {
			do {
				let signed = try await _importAndSign(ipa, cert: cert)
				_tempSigned = signed

				if useIDevice {
					// installd can replace the running app — hand it to the standard installer.
					self.pendingInstall = AnyApp(base: signed)
					self.phase = .downloaded
				} else {
					// Server method can't replace itself (the local server dies at install).
					// Fall back to remote OTA: package → upload the signed IPA → itms-services,
					// so iOS downloads it from the backend and survives the app being killed.
					try await _installViaRemoteOTA(signed)
				}
			} catch {
				phase = .failed(error.localizedDescription)
			}
		}
	}

	/// Import (hidden) + sign the downloaded IPA with the same bundle id so it replaces self.
	private func _importAndSign(_ ipa: URL, cert: CertificatePair) async throws -> AppInfoPresentable {
		let handler = AppFileHandler(file: ipa)
		try await handler.copy()
		try await handler.extract()
		try await handler.move()
		try await handler.addToDatabase()
		guard let imported = _fetchImported(uuid: handler.uuid) else {
			throw _err(.localized("Couldn't prepare the update."))
		}
		_tempImported = imported

		var options = OptionsManager.shared.options
		options.ppqProtection = false
		// Force the SAME bundle id as the RUNNING app so the update overwrites it — the
		// installed copy may have a PPQ suffix or custom id (e.g. installed via another
		// signer), which wouldn't match the IPA's clean id and would install as a 2nd app.
		options.appIdentifier = Bundle.main.bundleIdentifier
		options.injectionFiles = []
		options.post_installAppAfterSigned = false
		options.post_deleteAppAfterSigned = false

		try await _sign(imported, options: options, cert: cert)
		guard let signed = _fetchNewestSigned() else {
			throw _err(.localized("Signing failed."))
		}
		Storage.shared.deleteApp(for: imported)
		_tempImported = nil
		return signed
	}

	/// Package the signed app, upload it to the backend, then open itms-services so iOS
	/// downloads it from the server (survives this app being terminated at install time).
	private func _installViaRemoteOTA(_ signed: AppInfoPresentable) async throws {
		phase = .installing
		let vm = InstallerStatusViewModel(isIdevice: false)
		let archiver = ArchiveHandler(app: signed, viewModel: vm)
		try await archiver.move()
		let ipaURL = try await archiver.archive()
		let data = try Data(contentsOf: ipaURL)

		let manifestURL = try await InjecyBackend.shared.uploadSelfUpdate(
			ipaData: data,
			version: available?.version ?? currentVersion,
			build: available?.build ?? currentBuild,
			bundleId: Bundle.main.bundleIdentifier ?? "lol.injecy.app.w3lt"
		)

		// Clean up local copies — iOS pulls the IPA from the backend now.
		Storage.shared.deleteApp(for: signed)
		_tempSigned = nil
		try? FileManager.default.removeItem(at: ipaURL)

		let encoded = manifestURL.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) ?? manifestURL
		guard let itms = URL(string: "itms-services://?action=download-manifest&url=\(encoded)") else {
			throw _err(.localized("Couldn't start the install."))
		}
		await UIApplication.shared.open(itms)
		// iOS can't replace a RUNNING app — it parks the icon on "Waiting…" until injecy
		// quits. Give the user a moment to confirm the system prompt, then suspend so the
		// install proceeds.
		try? await Task.sleep(nanoseconds: 3_500_000_000)
		UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
	}

	/// Remove the signed update from the Library once the installer is dismissed.
	func cleanupAfterInstall() {
		if let signed = _tempSigned { Storage.shared.deleteApp(for: signed) }
		if let imported = _tempImported { Storage.shared.deleteApp(for: imported) }
		_tempSigned = nil; _tempImported = nil
		_downloadedIPA.map { try? FileManager.default.removeItem(at: $0) }
		_downloadedIPA = nil
		pendingInstall = nil
		phase = .idle
	}

	private func _sign(_ app: AppInfoPresentable, options: Options, cert: CertificatePair) async throws {
		try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
			FR.signPackageFile(app, using: options, icon: nil, certificate: cert) { error in
				if let error { cont.resume(throwing: error) } else { cont.resume() }
			}
		}
	}

	private func _fetchImported(uuid: String) -> Imported? {
		let req: NSFetchRequest<Imported> = Imported.fetchRequest()
		req.predicate = NSPredicate(format: "uuid == %@", uuid)
		req.fetchLimit = 1
		return try? Storage.shared.context.fetch(req).first
	}

	private func _fetchNewestSigned() -> Signed? {
		let req: NSFetchRequest<Signed> = Signed.fetchRequest()
		req.sortDescriptors = [NSSortDescriptor(keyPath: \Signed.date, ascending: false)]
		req.fetchLimit = 1
		return try? Storage.shared.context.fetch(req).first
	}

	private func _err(_ message: String) -> NSError {
		NSError(domain: "injecy.update", code: -3, userInfo: [NSLocalizedDescriptionKey: message])
	}

	// MARK: Internals

	private func _download(_ release: Release) async throws -> URL {
		// Uses a session-level delegate (not a per-task delegate — that doesn't reliably
		// deliver didWriteData) so the progress bar reflects real bytes downloaded. Falls
		// back to the known release size if the server omits Content-Length.
		let downloader = _ProgressDownloader(expectedSize: Int64(release.size)) { [weak self] fraction in
			Task { @MainActor in
				guard let self else { return }
				if case .downloading(let cur) = self.phase, Int(cur * 100) == Int(fraction * 100) { return }
				self.phase = .downloading(fraction)
			}
		}
		return try await downloader.download(release.ipaURL)
	}

	private func _verify(_ url: URL, sha256 expected: String) throws {
		guard !expected.isEmpty else { return } // server didn't provide a hash
		let data = try Data(contentsOf: url, options: .mappedIfSafe)
		let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
		guard digest == expected else {
			throw NSError(domain: "injecy.update", code: -1,
			              userInfo: [NSLocalizedDescriptionKey: String.localized("Download verification failed (checksum mismatch).")])
		}
	}
}

// MARK: - Download with reliable progress (session-level delegate)

private final class _ProgressDownloader: NSObject, URLSessionDownloadDelegate {
	private let onProgress: (Double) -> Void
	private let expectedSize: Int64
	private var _continuation: CheckedContinuation<URL, Error>?
	private var _session: URLSession?

	init(expectedSize: Int64, onProgress: @escaping (Double) -> Void) {
		self.expectedSize = expectedSize
		self.onProgress = onProgress
		super.init()
	}

	func download(_ url: URL) async throws -> URL {
		let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
		_session = session
		return try await withCheckedThrowingContinuation { cont in
			_continuation = cont
			session.downloadTask(with: url).resume()
		}
	}

	func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
	                didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
	                totalBytesExpectedToWrite: Int64) {
		let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedSize
		guard total > 0 else { return }
		onProgress(min(1, Double(totalBytesWritten) / Double(total)))
	}

	func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
	                didFinishDownloadingTo location: URL) {
		// Must move synchronously here — `location` is deleted once this returns.
		let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipa")
		let code = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 200
		do {
			guard code == 200 else {
				throw NSError(domain: "injecy.update", code: -2,
				              userInfo: [NSLocalizedDescriptionKey: String.localized("Download failed.")])
			}
			try? FileManager.default.removeItem(at: dest)
			try FileManager.default.moveItem(at: location, to: dest)
			_continuation?.resume(returning: dest)
		} catch {
			_continuation?.resume(throwing: error)
		}
		_continuation = nil
		_session?.finishTasksAndInvalidate()
	}

	func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		guard let error else { return } // success handled in didFinishDownloadingTo
		_continuation?.resume(throwing: error)
		_continuation = nil
		_session?.finishTasksAndInvalidate()
	}
}
