//
//  TweaksManager.swift
//  injecy
//
//  Catalog of tweaks served by the injecy marketplace. For now this is backed by
//  mock data; it is structured to be swapped for the `/api/injecy/v1/tweaks` API.
//

import Foundation
import NimbleJSON

// MARK: - Model

/// A tweak entry in the injecy catalog. Mirrors the backend `Tweak` model
/// (bot/database/models.py) so the API response can decode straight into this.
struct CatalogTweak: Identifiable, Codable, Hashable {
	let id: Int
	let slug: String
	let name: String
	let description: String
	let version: String
	let category: String
	let iconURL: URL?
	let downloadURL: URL?
	/// Human name of the app this tweak targets (nil = generic).
	let targetAppName: String?
	/// Bundle id this tweak targets, used to suggest tweaks for an imported IPA.
	let targetBundleId: String?
	/// Additional bundle ids this tweak is also compatible with.
	let targetBundleIds: [String]
	/// Optional admin-set hex accent (e.g. "#848ef9"); nil = derived from slug.
	let accentColor: String?
	/// Manual order within a category (lower = higher), set in the admin.
	let sortOrder: Int
	let isPaid: Bool
	/// Developer / author display name.
	let developerName: String?
	/// Optional developer website URL.
	let developerURL: URL?
	/// Optional developer Telegram (@name or a t.me link).
	let developerTelegram: String?
	/// Screenshot image URLs for the detail page.
	let screenshots: [URL]
	/// Free-form tags.
	let tags: [String]
	var installCount: Int
	var likes: Int
	/// Whether the marketplace highlights this tweak (controlled from the admin).
	let isRecommended: Bool
	/// File extension/type (dylib, deb, framework, bundle, appex). Empty if unknown.
	let fileType: String

	enum CodingKeys: String, CodingKey {
		case id, slug, name, description, version, category, screenshots, tags, likes
		case iconURL = "icon_url"
		case downloadURL = "download_url"
		case targetAppName = "target_app_name"
		case targetBundleId = "target_bundle_id"
		case targetBundleIds = "target_bundle_ids"
		case accentColor = "accent_color"
		case sortOrder = "sort_order"
		case isPaid = "is_paid"
		case developerName = "developer_name"
		case developerURL = "developer_url"
		case developerTelegram = "developer_telegram"
		case installCount = "install_count"
		case isRecommended = "is_recommended"
		case fileType = "file_type"
	}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		id = try c.decode(Int.self, forKey: .id)
		slug = try c.decode(String.self, forKey: .slug)
		name = try c.decode(String.self, forKey: .name)
		description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
		version = try c.decodeIfPresent(String.self, forKey: .version) ?? ""
		category = try c.decodeIfPresent(String.self, forKey: .category) ?? "general"
		iconURL = try c.decodeIfPresent(URL.self, forKey: .iconURL)
		downloadURL = try c.decodeIfPresent(URL.self, forKey: .downloadURL)
		targetAppName = try c.decodeIfPresent(String.self, forKey: .targetAppName)
		targetBundleId = try c.decodeIfPresent(String.self, forKey: .targetBundleId)
		targetBundleIds = try c.decodeIfPresent([String].self, forKey: .targetBundleIds) ?? []
		accentColor = try c.decodeIfPresent(String.self, forKey: .accentColor)
		sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
		isPaid = try c.decodeIfPresent(Bool.self, forKey: .isPaid) ?? false
		developerName = try c.decodeIfPresent(String.self, forKey: .developerName)
		developerURL = try c.decodeIfPresent(URL.self, forKey: .developerURL)
		developerTelegram = try c.decodeIfPresent(String.self, forKey: .developerTelegram)
		screenshots = try c.decodeIfPresent([URL].self, forKey: .screenshots) ?? []
		tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
		installCount = try c.decodeIfPresent(Int.self, forKey: .installCount) ?? 0
		likes = try c.decodeIfPresent(Int.self, forKey: .likes) ?? 0
		isRecommended = try c.decodeIfPresent(Bool.self, forKey: .isRecommended) ?? false
		fileType = try c.decodeIfPresent(String.self, forKey: .fileType) ?? ""
	}

	init(
		id: Int, slug: String, name: String, description: String, version: String, category: String,
		iconURL: URL?, downloadURL: URL?, targetAppName: String?, targetBundleId: String?,
		isPaid: Bool, developerName: String?, screenshots: [URL], tags: [String],
		installCount: Int, likes: Int, isRecommended: Bool, fileType: String = "",
		targetBundleIds: [String] = [], accentColor: String? = nil, sortOrder: Int = 0,
		developerURL: URL? = nil, developerTelegram: String? = nil
	) {
		self.id = id; self.slug = slug; self.name = name; self.description = description
		self.version = version; self.category = category; self.iconURL = iconURL
		self.downloadURL = downloadURL; self.targetAppName = targetAppName
		self.targetBundleId = targetBundleId; self.isPaid = isPaid; self.developerName = developerName
		self.screenshots = screenshots; self.tags = tags; self.installCount = installCount
		self.likes = likes; self.isRecommended = isRecommended; self.fileType = fileType
		self.targetBundleIds = targetBundleIds; self.accentColor = accentColor
		self.sortOrder = sortOrder
		self.developerURL = developerURL; self.developerTelegram = developerTelegram
	}
}

// MARK: - Manager

@MainActor
final class TweaksManager: ObservableObject {
	static let shared = TweaksManager()

	@Published var tweaks: [CatalogTweak] = []
	@Published var isLoading = false
	@Published var error: String?

	/// Base URL of the injecy client API. Replace with the production host.
	/// Endpoint contract (to be implemented in botbot): `GET /api/injecy/v1/tweaks`.
	var apiBaseURL = "https://api.injecy.lol/api/injecy/v1"

	/// On-disk cache of the last successfully fetched catalog, for offline use.
	private let _cacheURL: URL = {
		FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
			.appendingPathComponent("injecy", isDirectory: true)
			.appendingPathComponent("catalog.json")
	}()

	private init() {}

	/// Tweaks grouped by category, for a sectioned list.
	var byCategory: [(category: String, items: [CatalogTweak])] {
		Dictionary(grouping: tweaks, by: \.category)
			.map { (category: $0.key, items: $0.value.sorted { $0.name < $1.name }) }
			.sorted { $0.category < $1.category }
	}

	/// Load the catalog. Currently mock; swap the body for a fetch against
	/// `\(apiBaseURL)/tweaks` once the backend endpoint exists.
	func load() {
		guard !isLoading else { return }
		isLoading = true
		error = nil

		// Show cached catalog immediately (offline-friendly) while the network refresh runs.
		if tweaks.isEmpty, let cached = _loadCache() {
			tweaks = cached
		}

		Task {
			do {
				let fresh = try await InjecyBackend.shared.fetchTweaks()
				self.tweaks = fresh
				self._saveCache(fresh)
			} catch {
				print("[injecy] catalog load failed: \(error)")
				self.error = error.localizedDescription
				// Keep whatever we already have; otherwise cache; otherwise bundled samples.
				if self.tweaks.isEmpty {
					self.tweaks = self._loadCache() ?? Self.mockTweaks
				}
			}
			self.isLoading = false
		}
	}

	/// Optimistically reflect a download in the install counter, so the UI moves
	/// immediately; the server increments authoritatively and the next fetch reconciles.
	func bumpInstall(_ id: Int) {
		guard let idx = tweaks.firstIndex(where: { $0.id == id }) else { return }
		tweaks[idx].installCount += 1
		_saveCache(tweaks)
	}

	// MARK: - Offline cache

	private func _saveCache(_ list: [CatalogTweak]) {
		try? FileManager.default.createDirectory(
			at: _cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
		if let data = try? JSONEncoder().encode(list) {
			try? data.write(to: _cacheURL)
		}
	}

	/// Location of the cached catalog file (offline copy).
	var catalogCacheURL: URL { _cacheURL }

	/// Remove the cached catalog file (offline copy). Next load fetches fresh.
	func clearCatalogCache() {
		try? FileManager.default.removeItem(at: _cacheURL)
	}

	private func _loadCache() -> [CatalogTweak]? {
		guard let data = try? Data(contentsOf: _cacheURL),
		      let list = try? JSONDecoder().decode([CatalogTweak].self, from: data),
		      !list.isEmpty else { return nil }
		return list
	}

	// MARK: - Mock data

	private static func shots(_ seeds: [Int]) -> [URL] {
		seeds.compactMap { URL(string: "https://picsum.photos/seed/injecy\($0)/600/1300") }
	}

	static let mockTweaks: [CatalogTweak] = [
		CatalogTweak(
			id: 1, slug: "youtube-reborn", name: "YouTube Reborn",
			description: "Block ads, background playback, picture-in-picture, video & audio downloads, and a pile of UI customizations for YouTube. Reborn is one of the most complete YouTube tweaks available, actively maintained and compatible with the latest app versions.",
			version: "5.0.1", category: "Media",
			iconURL: nil, downloadURL: nil,
			targetAppName: "YouTube", targetBundleId: "com.google.ios.youtube", isPaid: false,
			developerName: "Lillie Pad", screenshots: shots([11, 12, 13]),
			tags: ["ads", "downloads", "background"], installCount: 184_233, likes: 12_004, isRecommended: true
		),
		CatalogTweak(
			id: 2, slug: "cercube", name: "Cercube",
			description: "Download videos and audio in any quality, background playback, and extra YouTube controls. Cercube adds a download button right into the player and supports batch downloads.",
			version: "6.2.0", category: "Media",
			iconURL: nil, downloadURL: nil,
			targetAppName: "YouTube", targetBundleId: "com.google.ios.youtube", isPaid: true,
			developerName: "InsanelyDeepak", screenshots: shots([21, 22]),
			tags: ["downloads", "premium"], installCount: 52_910, likes: 4_320, isRecommended: false
		),
		CatalogTweak(
			id: 3, slug: "instagram-rocket", name: "Rocket for Instagram",
			description: "Save photos & videos, hide ads, ghost mode (don't send read receipts or typing status), zoom on profile pictures, and many more privacy and convenience features for Instagram.",
			version: "2.4.3", category: "Social",
			iconURL: nil, downloadURL: nil,
			targetAppName: "Instagram", targetBundleId: "com.burbn.instagram", isPaid: false,
			developerName: "SoCoffee", screenshots: shots([31, 32, 33]),
			tags: ["privacy", "downloads"], installCount: 98_120, likes: 8_770, isRecommended: true
		),
		CatalogTweak(
			id: 4, slug: "bhtwitter", name: "BHTwitter",
			description: "Customization and privacy tweaks for X / Twitter: hide promoted tweets, download media, custom app icons, confirm before posting, and disable trackers.",
			version: "3.9.0", category: "Social",
			iconURL: nil, downloadURL: nil,
			targetAppName: "X", targetBundleId: "com.atebits.Tweetie2", isPaid: false,
			developerName: "BandarHL", screenshots: shots([41, 42]),
			tags: ["privacy", "customization"], installCount: 71_540, likes: 6_110, isRecommended: false
		),
	]
}
