//
//  TweakPackStore.swift
//  injecy
//
//  Tweak packs: a named bundle of tweaks you can apply in one tap at injection time.
//  User packs are stored locally on-device; official packs come from the marketplace
//  (fetched separately and merged read-only). A pack references tweaks by id, mixing
//  marketplace tweaks (id > 0) and your own imported tweaks (id < 0).
//

import Foundation

// MARK: - Model

struct TweakPack: Identifiable, Codable, Hashable {
	var id: String
	var name: String
	/// Tweak ids in the pack — marketplace (> 0) and local/imported (< 0).
	var tweakIDs: [Int]
	var createdAt: Date
	/// Official packs come from the marketplace and can't be edited locally.
	var isOfficial: Bool
	/// Optional accent hex (mainly for official packs); nil = derived.
	var accentHex: String?

	var count: Int { tweakIDs.count }

	init(
		id: String = UUID().uuidString,
		name: String,
		tweakIDs: [Int] = [],
		createdAt: Date = Date(),
		isOfficial: Bool = false,
		accentHex: String? = nil
	) {
		self.id = id; self.name = name; self.tweakIDs = tweakIDs
		self.createdAt = createdAt; self.isOfficial = isOfficial; self.accentHex = accentHex
	}
}

// MARK: - Store

@MainActor
final class TweakPackStore: ObservableObject {
	static let shared = TweakPackStore()

	/// User-created packs (local). Official packs are exposed via `officialPacks`.
	@Published private(set) var packs: [TweakPack] = []
	/// Official packs fetched from the marketplace (read-only).
	@Published private(set) var officialPacks: [TweakPack] = []

	private let _key = "injecy.tweakPacks"
	private init() { _load() }

	/// Everything to show in the Packs tab: official first, then your own.
	var all: [TweakPack] { officialPacks + packs }

	// MARK: Queries

	func pack(_ id: String) -> TweakPack? { all.first { $0.id == id } }
	func contains(_ tweakID: Int, in packID: String) -> Bool {
		pack(packID)?.tweakIDs.contains(tweakID) ?? false
	}

	// MARK: Mutations (user packs only)

	@discardableResult
	func create(name: String, tweakIDs: [Int] = []) -> TweakPack {
		let pack = TweakPack(name: name, tweakIDs: tweakIDs)
		packs.insert(pack, at: 0)
		_save()
		return pack
	}

	func rename(_ id: String, to name: String) {
		guard let i = packs.firstIndex(where: { $0.id == id }) else { return }
		packs[i].name = name
		_save()
	}

	func delete(_ id: String) {
		packs.removeAll { $0.id == id }
		_save()
	}

	func setTweaks(_ ids: [Int], for id: String) {
		guard let i = packs.firstIndex(where: { $0.id == id }) else { return }
		packs[i].tweakIDs = ids
		_save()
	}

	func toggle(_ tweakID: Int, in id: String) {
		guard let i = packs.firstIndex(where: { $0.id == id }) else { return }
		if let j = packs[i].tweakIDs.firstIndex(of: tweakID) {
			packs[i].tweakIDs.remove(at: j)
		} else {
			packs[i].tweakIDs.append(tweakID)
		}
		_save()
	}

	/// Drop a tweak id from every user pack (e.g. when a library tweak is removed).
	func purge(_ tweakID: Int) {
		var changed = false
		for i in packs.indices where packs[i].tweakIDs.contains(tweakID) {
			packs[i].tweakIDs.removeAll { $0 == tweakID }
			changed = true
		}
		if changed { _save() }
	}

	// MARK: Official packs

	func setOfficialPacks(_ packs: [TweakPack]) { officialPacks = packs }

	/// Fetch admin-curated official packs from the marketplace.
	func loadOfficial() {
		Task {
			guard let server = try? await InjecyBackend.shared.fetchPacks() else { return }
			self.officialPacks = server.map {
				TweakPack(
					id: "official-\($0.id)",
					name: $0.name,
					tweakIDs: $0.tweakIDs,
					createdAt: Date(),
					isOfficial: true,
					accentHex: $0.accentColor
				)
			}
		}
	}

	// MARK: Persistence

	private func _load() {
		guard
			let data = UserDefaults.standard.data(forKey: _key),
			let decoded = try? JSONDecoder().decode([TweakPack].self, from: data)
		else { return }
		packs = decoded
	}

	private func _save() {
		if let data = try? JSONEncoder().encode(packs) {
			UserDefaults.standard.set(data, forKey: _key)
		}
	}
}
