//
//  AppleIDManager.swift
//  injecy
//
//  Apple ID sign-in for free 7-day signing (AltSign + self-hosted anisette).
//  Phase 2 / step 1: authentication + 2FA + team fetch. Certificate/profile issuance
//  builds on the resulting account+session+team.
//

import Foundation
import AltSign
import IDeviceSwift

@MainActor
final class AppleIDManager: ObservableObject {
	static let shared = AppleIDManager()

	enum State: Equatable {
		case idle
		case authenticating
		case needsTwoFactor
		case signedIn(team: String)
		case failed(String)
	}

	@Published private(set) var state: State = .idle
	@Published private(set) var issueState: IssueState = .idle

	/// Result of a successful sign-in, used later for certificate/profile issuance.
	private(set) var account: ALTAccount?
	private(set) var session: ALTAppleAPISession?
	private(set) var team: ALTTeam?

	/// Anisette server (self-hosted). Returns the X-Apple-* header JSON.
	private let anisetteURL = URL(string: "https://admin.leadproject.lol/anisette/")!

	/// Held while a 2FA code is awaited; called with the code the user enters.
	private var _twoFactorCompletion: ((String?) -> Void)?

	private init() {}

	// MARK: Sign in

	func signIn(appleID: String, password: String) {
		state = .authenticating
		account = nil; session = nil; team = nil

		Task {
			do {
				let anisette = try await _fetchAnisette()
				_authenticate(appleID: appleID, password: password, anisette: anisette)
			} catch {
				self.state = .failed(_message(error))
			}
		}
	}

	func submitTwoFactor(code: String) {
		guard let completion = _twoFactorCompletion else { return }
		_twoFactorCompletion = nil
		state = .authenticating
		completion(code)
	}

	func cancelTwoFactor() {
		_twoFactorCompletion?(nil)
		_twoFactorCompletion = nil
		state = .idle
	}

	func signOut() {
		account = nil; session = nil; team = nil; state = .idle; issueState = .idle
	}

	// MARK: Internals

	private func _authenticate(appleID: String, password: String, anisette: ALTAnisetteData) {
		ALTAppleAPI.shared.authenticate(
			appleID: appleID,
			password: password,
			anisetteData: anisette,
			verificationHandler: { [weak self] codeCompletion in
				// Called on a background queue when Apple requires a 2FA code.
				Task { @MainActor in
					self?._twoFactorCompletion = codeCompletion
					self?.state = .needsTwoFactor
				}
			},
			completionHandler: { [weak self] account, session, error in
				Task { @MainActor in
					guard let self else { return }
					if let account, let session {
						self.account = account
						self.session = session
						self._fetchTeam(account: account, session: session)
					} else {
						self.state = .failed(self._message(error))
					}
				}
			}
		)
	}

	private func _fetchTeam(account: ALTAccount, session: ALTAppleAPISession) {
		ALTAppleAPI.shared.fetchTeams(for: account, session: session) { [weak self] teams, error in
			Task { @MainActor in
				guard let self else { return }
				guard let team = teams?.first else {
					self.state = .failed(error.map(self._message) ?? "No development team found for this Apple ID.")
					return
				}
				self.team = team
				self.state = .signedIn(team: team.name)
			}
		}
	}

	/// Fetch anisette from our server and map its X-Apple-* keys to AltSign's expected JSON.
	private func _fetchAnisette() async throws -> ALTAnisetteData {
		let (data, _) = try await URLSession.shared.data(from: anisetteURL)
		let h = try JSONDecoder().decode([String: String].self, from: data)

		let isoNow = ISO8601DateFormatter().string(from: Date())
		let mapped: [String: String] = [
			"machineID": h["X-Apple-I-MD-M"] ?? "",
			"oneTimePassword": h["X-Apple-I-MD"] ?? "",
			"localUserID": h["X-Apple-I-MD-LU"] ?? "",
			"routingInfo": h["X-Apple-I-MD-RINFO"] ?? "0",
			"deviceUniqueIdentifier": h["X-Mme-Device-Id"] ?? UUID().uuidString,
			"deviceSerialNumber": h["X-Apple-I-SRL-NO"] ?? "0",
			"deviceDescription": h["X-MMe-Client-Info"] ?? "<MacBookPro13,2> <macOS;13.1;22C65> <com.apple.AuthKit/1 (com.apple.dt.Xcode/3594.4.19)>",
			"date": h["X-Apple-I-Client-Time"] ?? isoNow,
			"locale": h["X-Apple-Locale"] ?? "en_US",
			"timeZone": h["X-Apple-I-TimeZone"] ?? "UTC",
		]
		guard let anisette = ALTAnisetteData(json: mapped) else {
			throw NSError(domain: "injecy.appleid", code: -1,
			              userInfo: [NSLocalizedDescriptionKey: "Invalid anisette data from server."])
		}
		return anisette
	}

	private func _message(_ error: Error?) -> String {
		guard let error else { return "Unknown error." }
		return (error as NSError).localizedDescription
	}

	private func _err(_ message: String) -> NSError {
		NSError(domain: "injecy.appleid", code: -2, userInfo: [NSLocalizedDescriptionKey: message])
	}
}

// MARK: - Certificate issuance (step 3)

extension AppleIDManager {
	enum IssueState: Equatable {
		case idle
		case working(String)
		case issued(bundleID: String, certUUID: String)
		case failed(String)
	}

	/// Issues a free 7-day signing certificate + provisioning profile for `baseBundleID`
	/// and stores it as a `CertificatePair`. The resolved bundle id may differ (a unique
	/// suffix is appended if the original App ID can't be registered) — sign the app with
	/// the returned `bundleID`.
	func issueFreeCertificate(forBundleID baseBundleID: String?, appName: String?) {
		guard let session, let team else {
			issueState = .failed(.localized("Sign in with your Apple ID first."))
			return
		}
		issueState = .working(.localized("Preparing…"))
		Task { await self._issue(session: session, team: team, baseBundleID: baseBundleID, appName: appName) }
	}

	private func _issue(session: ALTAppleAPISession, team: ALTTeam, baseBundleID: String?, appName: String?) async {
		do {
			let udid = try _deviceUDID()

			// Register this device (tolerate "already registered").
			issueState = .working(.localized("Registering device…"))
			_ = try? await _registerDevice(udid: udid, team: team, session: session)

			// Free accounts can't reuse old certs (no private key), so revoke existing ones first.
			issueState = .working(.localized("Creating certificate…"))
			let existing = try await _fetchCertificates(team: team, session: session)
			for cert in existing { _ = try? await _revoke(cert, team: team, session: session) }
			let certificate = try await _addCertificate(team: team, session: session)

			issueState = .working(.localized("Registering App ID…"))
			let (appID, finalBundleID) = try await _ensureAppID(base: baseBundleID, appName: appName, team: team, session: session)

			issueState = .working(.localized("Fetching provisioning profile…"))
			let profile = try await _fetchProfile(appID: appID, team: team, session: session)

			issueState = .working(.localized("Saving…"))
			let uuid = try await _saveCertPair(certificate: certificate, profile: profile, nickname: appName ?? team.name)

			issueState = .issued(bundleID: finalBundleID, certUUID: uuid)
		} catch {
			issueState = .failed(_message(error))
		}
	}

	// MARK: UDID

	private func _deviceUDID() throws -> String {
		// Use the exact same path the heartbeat/installer reads from.
		let path = HeartbeatManager.pairingFile()
		let url = URL(fileURLWithPath: path)
		guard FileManager.default.fileExists(atPath: path), let data = try? Data(contentsOf: url) else {
			throw _err(.localized("No pairing file found. Import a pairing file in Settings → Installation first — it's required to read this device's UDID."))
		}
		guard let plist = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] else {
			throw _err(.localized("Pairing file is not a valid plist."))
		}
		for key in ["UDID", "DeviceUDID", "udid", "deviceUDID"] {
			if let udid = plist[key] as? String, !udid.isEmpty { return udid }
		}
		throw _err(.localized("Pairing file has no UDID. Re-export a pairing file that includes the device UDID."))
	}

	// MARK: App ID

	private func _ensureAppID(base: String?, appName: String?, team: ALTTeam, session: ALTAppleAPISession) async throws -> (ALTAppID, String) {
		let desired = (base?.isEmpty == false ? base! : "lol.injecy.free")
		let rawName = (appName?.isEmpty == false ? appName! : "injecy")
		// Apple App ID names allow only ASCII letters, numbers and spaces.
		let name = rawName.unicodeScalars
			.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
			.reduce(into: "") { $0.append($1) }
			.trimmingCharacters(in: .whitespaces)
		let appIDName = name.isEmpty ? "injecy" : name

		// Reuse an existing App ID with the same bundle id if present.
		let existing = try await _fetchAppIDs(team: team, session: session)
		if let match = existing.first(where: { $0.bundleIdentifier == desired }) {
			return (match, desired)
		}

		var lastError: Error?
		for bundleID in [desired, "\(desired).\(_rand6())"] {
			do {
				let appID = try await _addAppID(name: appIDName, bundleID: bundleID, team: team, session: session)
				return (appID, bundleID)
			} catch { lastError = error }
		}
		throw lastError ?? _err(.localized("Could not register an App ID for this app."))
	}

	private func _rand6() -> String {
		let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
		return String((0..<6).map { _ in chars.randomElement()! })
	}

	// MARK: Persist

	private func _saveCertPair(certificate: ALTCertificate, profile: ALTProvisioningProfile, nickname: String) async throws -> String {
		guard let p12 = certificate.p12Data() else {
			throw _err(.localized("Failed to export the issued certificate."))
		}
		let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
		let p12URL = tmp.appendingPathComponent("injecy.p12")
		let provisionURL = tmp.appendingPathComponent("injecy.mobileprovision")
		try p12.write(to: p12URL)
		try profile.data.write(to: provisionURL)

		let handler = CertificateFileHandler(
			key: p12URL,
			provision: provisionURL,
			password: nil,
			nickname: nickname,
			isDefault: false
		)
		try await handler.copy()
		try await handler.addToDatabase()
		try? FileManager.default.removeItem(at: tmp)
		return handler.uuid
	}

	// MARK: AltSign async wrappers

	private func _registerDevice(udid: String, team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTDevice {
		try await withCheckedThrowingContinuation { cont in
			ALTAppleAPI.shared.registerDevice(name: "injecy", identifier: udid, type: .iphone, team: team, session: session) { device, error in
				if let device { cont.resume(returning: device) }
				else { cont.resume(throwing: error ?? self._err("registerDevice failed")) }
			}
		}
	}

	private func _fetchCertificates(team: ALTTeam, session: ALTAppleAPISession) async throws -> [ALTCertificate] {
		try await withCheckedThrowingContinuation { cont in
			ALTAppleAPI.shared.fetchCertificates(for: team, session: session) { certs, error in
				if let certs { cont.resume(returning: certs) }
				else { cont.resume(throwing: error ?? self._err("fetchCertificates failed")) }
			}
		}
	}

	private func _revoke(_ certificate: ALTCertificate, team: ALTTeam, session: ALTAppleAPISession) async throws {
		try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
			ALTAppleAPI.shared.revoke(certificate, for: team, session: session) { success, error in
				if success { cont.resume() }
				else { cont.resume(throwing: error ?? self._err("revoke failed")) }
			}
		}
	}

	private func _addCertificate(team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTCertificate {
		try await withCheckedThrowingContinuation { cont in
			ALTAppleAPI.shared.addCertificate(machineName: "injecy", to: team, session: session) { cert, error in
				if let cert { cont.resume(returning: cert) }
				else { cont.resume(throwing: error ?? self._err("addCertificate failed")) }
			}
		}
	}

	private func _fetchAppIDs(team: ALTTeam, session: ALTAppleAPISession) async throws -> [ALTAppID] {
		try await withCheckedThrowingContinuation { cont in
			ALTAppleAPI.shared.fetchAppIDs(for: team, session: session) { appIDs, error in
				if let appIDs { cont.resume(returning: appIDs) }
				else { cont.resume(throwing: error ?? self._err("fetchAppIDs failed")) }
			}
		}
	}

	private func _addAppID(name: String, bundleID: String, team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTAppID {
		try await withCheckedThrowingContinuation { cont in
			ALTAppleAPI.shared.addAppID(withName: name, bundleIdentifier: bundleID, team: team, session: session) { appID, error in
				if let appID { cont.resume(returning: appID) }
				else { cont.resume(throwing: error ?? self._err("addAppID failed")) }
			}
		}
	}

	private func _fetchProfile(appID: ALTAppID, team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTProvisioningProfile {
		try await withCheckedThrowingContinuation { cont in
			ALTAppleAPI.shared.fetchProvisioningProfile(for: appID, deviceType: .iphone, team: team, session: session) { profile, error in
				if let profile { cont.resume(returning: profile) }
				else { cont.resume(throwing: error ?? self._err("fetchProvisioningProfile failed")) }
			}
		}
	}
}
