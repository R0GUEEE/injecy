//
//  BackupManager.swift
//  injecy
//
//  Export / restore of the user's certificates and tweak library — so moving to a new
//  phone (or recovering) doesn't mean re-importing everything by hand. Produces a single
//  .zip the user can share/save, and restores from it.
//
//  ⚠️ The archive contains certificate private keys + their passwords in the clear, so it
//  should be treated like the certificate itself (kept private).
//

import Foundation
import Zip
import CoreData

@MainActor
final class BackupManager {
	static let shared = BackupManager()
	private init() {}

	// MARK: Export

	/// Build a backup archive (certificates + tweak library) and return its URL to share.
	func export() async throws -> URL {
		let fm = FileManager.default
		let work = fm.temporaryDirectory.appendingPathComponent("injecy-backup-\(UUID().uuidString)")
		let certsDir = work.appendingPathComponent("certs")
		let libDir = work.appendingPathComponent("library")
		try fm.createDirectory(at: certsDir, withIntermediateDirectories: true)
		try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

		// Certificates: copy each cert's files + a small meta (nickname + password).
		let req: NSFetchRequest<CertificatePair> = CertificatePair.fetchRequest()
		let certs = (try? Storage.shared.context.fetch(req)) ?? []
		for cert in certs {
			guard
				let uuid = cert.uuid,
				let src = Storage.shared.getUuidDirectory(for: cert),
				fm.fileExists(atPath: src.path)
			else { continue }
			let dest = certsDir.appendingPathComponent(uuid)
			try? fm.copyItem(at: src, to: dest)
			let meta: [String: String] = ["nickname": cert.nickname ?? "", "password": cert.password ?? ""]
			if let data = try? JSONSerialization.data(withJSONObject: meta) {
				try? data.write(to: dest.appendingPathComponent("_meta.json"))
			}
		}

		// Tweak library: files + the index.
		let libSrc = TweakLibrary.shared.libraryDirectory
		if fm.fileExists(atPath: libSrc.path) {
			try? fm.copyItem(at: libSrc, to: libDir.appendingPathComponent("files"))
		}
		if let indexData = UserDefaults.standard.data(forKey: TweakLibrary.shared.storageKey) {
			try? indexData.write(to: libDir.appendingPathComponent("index.json"))
		}

		let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
		let zipURL = fm.temporaryDirectory.appendingPathComponent("injecy-backup-\(df.string(from: Date())).zip")
		try? fm.removeItem(at: zipURL)
		try Zip.zipFiles(paths: [certsDir, libDir], zipFilePath: zipURL, password: nil, progress: nil)
		try? fm.removeItem(at: work)
		return zipURL
	}

	// MARK: Restore

	struct RestoreResult { var certificates = 0; var libraryRestored = false }

	/// Restore certificates + library from a backup archive. Certificates are re-imported
	/// through the normal handler; the library index is replaced with the backup's.
	@discardableResult
	func restore(from url: URL) async throws -> RestoreResult {
		let fm = FileManager.default
		let scoped = url.startAccessingSecurityScopedResource()
		defer { if scoped { url.stopAccessingSecurityScopedResource() } }

		let unzip = fm.temporaryDirectory.appendingPathComponent("injecy-restore-\(UUID().uuidString)")
		try? fm.removeItem(at: unzip)
		try Zip.unzipFile(url, destination: unzip, overwrite: true, password: nil, progress: nil)
		defer { try? fm.removeItem(at: unzip) }

		var result = RestoreResult()

		// Certificates
		let certsDir = unzip.appendingPathComponent("certs")
		if let folders = try? fm.contentsOfDirectory(at: certsDir, includingPropertiesForKeys: nil) {
			for folder in folders where folder.hasDirectoryPath {
				let contents = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
				guard
					let p12 = contents.first(where: { $0.pathExtension.lowercased() == "p12" }),
					let prov = contents.first(where: { $0.pathExtension.lowercased() == "mobileprovision" })
				else { continue }
				var password = "", nickname = ""
				if let metaURL = contents.first(where: { $0.lastPathComponent == "_meta.json" }),
				   let data = try? Data(contentsOf: metaURL),
				   let meta = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
					password = meta["password"] ?? ""
					nickname = meta["nickname"] ?? ""
				}
				await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
					FR.handleCertificateFiles(
						p12URL: p12, provisionURL: prov, p12Password: password, certificateName: nickname
					) { _ in cont.resume() }
				}
				result.certificates += 1
			}
		}

		// Tweak library
		let libDir = unzip.appendingPathComponent("library")
		let filesSrc = libDir.appendingPathComponent("files")
		if let items = try? fm.contentsOfDirectory(at: filesSrc, includingPropertiesForKeys: nil) {
			let dest = TweakLibrary.shared.libraryDirectory
			try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
			for item in items {
				let d = dest.appendingPathComponent(item.lastPathComponent)
				try? fm.removeItem(at: d)
				try? fm.copyItem(at: item, to: d)
			}
		}
		if let indexData = try? Data(contentsOf: libDir.appendingPathComponent("index.json")) {
			UserDefaults.standard.set(indexData, forKey: TweakLibrary.shared.storageKey)
			TweakLibrary.shared.reload()
			result.libraryRestored = true
		}

		return result
	}
}
