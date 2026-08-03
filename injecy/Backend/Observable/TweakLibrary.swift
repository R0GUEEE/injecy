//
//  TweakLibrary.swift
//  injecy
//
//  The user's personal tweak library: tweaks added from the marketplace, with their
//  files downloaded locally so they can be injected during signing — offline-ready.
//

import Foundation
import NimbleExtensions

// MARK: - Model

struct LibraryTweak: Identifiable, Codable, Hashable {
	let tweak: CatalogTweak
	/// File name inside the library directory; nil if the file couldn't be downloaded.
	var fileName: String?
	var addedAt: Date

	var id: Int { tweak.id }
	/// Tweaks imported by the user locally use negative ids (no marketplace entry).
	var isCustom: Bool { tweak.id < 0 }
}

// MARK: - Store

@MainActor
final class TweakLibrary: ObservableObject {
	static let shared = TweakLibrary()

	@Published private(set) var items: [LibraryTweak] = []
	/// IDs currently being downloaded, for per-row spinners.
	@Published private(set) var downloading: Set<Int> = []

	private let _key = "injecy.tweakLibrary"
	private let _cacheKey = "injecy.tweakCacheIndex"
	private let _dir: URL
	private let _cacheDir: URL

	private init() {
		let base = FileManager.default
			.urls(for: .documentDirectory, in: .userDomainMask)[0]
			.appendingPathComponent("injecy", isDirectory: true)
		_dir = base.appendingPathComponent("TweakLibrary", isDirectory: true)
		_cacheDir = base.appendingPathComponent("TweakCache", isDirectory: true)
		try? FileManager.default.createDirectoryIfNeeded(at: _dir)
		try? FileManager.default.createDirectoryIfNeeded(at: _cacheDir)
		_load()
	}

	/// On-disk cache of downloaded marketplace tweaks (id_version → filename), so a tweak
	/// added during signing but not saved to the library isn't re-downloaded next time.
	private var _cacheIndex: [String: String] {
		get { (UserDefaults.standard.dictionary(forKey: _cacheKey) as? [String: String]) ?? [:] }
		set { UserDefaults.standard.set(newValue, forKey: _cacheKey) }
	}

	// MARK: Queries

	/// On-disk download cache directory (safe to purge; re-downloads on demand).
	var cacheDirectory: URL { _cacheDir }
	/// The user's saved-tweak files directory (library data, not cache).
	var libraryDirectory: URL { _dir }
	/// UserDefaults key holding the library index (for backup/restore).
	var storageKey: String { _key }
	/// Re-read the library index from disk (after a restore).
	func reload() { _load() }

	func contains(_ id: Int) -> Bool { items.contains { $0.id == id } }
	func isDownloading(_ id: Int) -> Bool { downloading.contains(id) }

	/// Local file URL for a library tweak, if its file is present.
	func fileURL(for item: LibraryTweak) -> URL? {
		guard let name = item.fileName else { return nil }
		let url = _dir.appendingPathComponent(name)
		return FileManager.default.fileExists(atPath: url.path) ? url : nil
	}

	// MARK: Mutations

	/// Add a tweak to the library, downloading its file if a URL is available.
	func add(_ tweak: CatalogTweak) async {
		guard !contains(tweak.id), !downloading.contains(tweak.id) else { return }
		downloading.insert(tweak.id)
		defer { downloading.remove(tweak.id) }

		var fileName: String?
		if tweak.downloadURL != nil {
			do {
				let (data, suggested) = try await InjecyBackend.shared.downloadTweak(tweak)
				let safe = suggested.replacingOccurrences(of: "/", with: "_")
				let dest = _dir.appendingPathComponent("\(tweak.id)_\(safe)")
				try? FileManager.default.removeItem(at: dest)
				try data.write(to: dest)
				fileName = dest.lastPathComponent
				TweaksManager.shared.bumpInstall(tweak.id)
			} catch {
				// Keep the entry without a file; it just won't be injectable until re-added.
			}
		}

		items.insert(LibraryTweak(tweak: tweak, fileName: fileName, addedAt: Date()), at: 0)
		_save()
	}

	/// Import a user-provided tweak file (.dylib/.deb/…) into the library as a custom entry.
	@discardableResult
	func addCustomFile(_ url: URL) -> LibraryTweak? {
		let scoped = url.startAccessingSecurityScopedResource()
		defer { if scoped { url.stopAccessingSecurityScopedResource() } }

		let ext = url.pathExtension.isEmpty ? "dylib" : url.pathExtension
		let displayName = url.deletingPathExtension().lastPathComponent
		let dest = _dir.appendingPathComponent("custom_\(UUID().uuidString).\(ext)")
		do {
			try FileManager.default.copyItem(at: url, to: dest)
		} catch {
			return nil
		}

		let cid = Int.random(in: Int.min / 2 ... -1)
		let tweak = CatalogTweak(
			id: cid,
			slug: "custom-\(UUID().uuidString.prefix(8))",
			name: displayName.isEmpty ? "Imported tweak" : displayName,
			description: "Imported by you · .\(ext)",
			version: "—",
			category: "Imported",
			iconURL: nil, downloadURL: nil,
			targetAppName: nil, targetBundleId: nil,
			isPaid: false, developerName: nil,
			screenshots: [], tags: [], installCount: 0, likes: 0, isRecommended: false,
			fileType: ext.lowercased()
		)
		let item = LibraryTweak(tweak: tweak, fileName: dest.lastPathComponent, addedAt: Date())
		items.insert(item, at: 0)
		_save()
		return item
	}

	/// Resolve a file URL to inject for a tweak: library copy → cache → download (and cache).
	func resolveForSigning(_ tweak: CatalogTweak) async -> URL? {
		if let item = items.first(where: { $0.id == tweak.id }), let f = fileURL(for: item) {
			return f
		}
		let key = "\(tweak.id)_\(tweak.version)"
		if let name = _cacheIndex[key] {
			let url = _cacheDir.appendingPathComponent(name)
			if FileManager.default.fileExists(atPath: url.path) { return url }
		}
		guard tweak.id > 0, tweak.downloadURL != nil,
		      let (data, suggested) = try? await InjecyBackend.shared.downloadTweak(tweak) else { return nil }
		let safe = suggested.replacingOccurrences(of: "/", with: "_")
		let dest = _cacheDir.appendingPathComponent("c\(tweak.id)_\(UUID().uuidString.prefix(6))_\(safe)")
		guard (try? data.write(to: dest)) != nil else { return nil }
		var idx = _cacheIndex; idx[key] = dest.lastPathComponent; _cacheIndex = idx
		return dest
	}

	/// Re-download a library tweak to its latest version.
	func update(_ id: Int, to tweak: CatalogTweak) async {
		guard let idx = items.firstIndex(where: { $0.id == id }), !downloading.contains(id) else { return }
		downloading.insert(id); defer { downloading.remove(id) }
		guard tweak.downloadURL != nil,
		      let (data, suggested) = try? await InjecyBackend.shared.downloadTweak(tweak) else { return }
		if let old = items[idx].fileName {
			try? FileManager.default.removeItem(at: _dir.appendingPathComponent(old))
		}
		let safe = suggested.replacingOccurrences(of: "/", with: "_")
		let dest = _dir.appendingPathComponent("\(tweak.id)_\(safe)")
		try? FileManager.default.removeItem(at: dest)
		guard (try? data.write(to: dest)) != nil else { return }
		items[idx] = LibraryTweak(tweak: tweak, fileName: dest.lastPathComponent, addedAt: items[idx].addedAt)
		_save()
	}

	/// True if this (latest catalog) tweak is in the library at an older version.
	func hasUpdate(for tweak: CatalogTweak) -> Bool {
		guard tweak.id > 0, let item = items.first(where: { $0.id == tweak.id }) else { return false }
		return item.tweak.version != tweak.version
	}

	/// Library tweaks whose marketplace version differs from the stored one.
	func updates(against catalog: [CatalogTweak]) -> [(library: LibraryTweak, latest: CatalogTweak)] {
		let byID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
		return items.compactMap { item in
			guard item.id > 0, let latest = byID[item.id], latest.version != item.tweak.version else { return nil }
			return (library: item, latest: latest)
		}
	}

	func remove(_ id: Int) {
		guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
		if let name = items[idx].fileName {
			try? FileManager.default.removeItem(at: _dir.appendingPathComponent(name))
		}
		items.remove(at: idx)
		_save()
		// Drop the tweak from any local packs that referenced it.
		TweakPackStore.shared.purge(id)
	}

	/// Clear the download cache (tweaks resolved during signing but not saved to the library).
	/// The library itself is left intact — marketplace tweaks re-download on demand.
	func clearCache() {
		if let files = try? FileManager.default.contentsOfDirectory(at: _cacheDir, includingPropertiesForKeys: nil) {
			for f in files { try? FileManager.default.removeItem(at: f) }
		}
		UserDefaults.standard.removeObject(forKey: _cacheKey)
	}

	// MARK: Persistence

	private func _load() {
		guard
			let data = UserDefaults.standard.data(forKey: _key),
			let decoded = try? JSONDecoder().decode([LibraryTweak].self, from: data)
		else { return }
		items = decoded
	}

	private func _save() {
		if let data = try? JSONEncoder().encode(items) {
			UserDefaults.standard.set(data, forKey: _key)
		}
	}
}

// MARK: - Injection registry
/// In-memory map of injected file URL → its tweak metadata, so the signing screen can
/// show names/icons for chosen tweaks even after navigating away and back.
@MainActor
final class InjectionRegistry {
	static let shared = InjectionRegistry()
	private init() {}

	private var _map: [String: CatalogTweak] = [:]

	func set(_ tweak: CatalogTweak, for url: URL) { _map[url.absoluteString] = tweak }
	func tweak(for url: URL) -> CatalogTweak? { _map[url.absoluteString] }
	func remove(_ url: URL) { _map[url.absoluteString] = nil }
}
