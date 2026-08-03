//
//  DeepLinkRouter.swift
//  injecy
//
//  Resolves injecy:// deep links (e.g. injecy://tweak/<slug-or-id>) and presents the
//  matching content over the app root, so links work regardless of the active tab.
//

import Foundation

@MainActor
final class DeepLinkRouter: ObservableObject {
	static let shared = DeepLinkRouter()

	/// When set, the app root presents the tweak's detail page.
	@Published var presentedTweak: CatalogTweak?

	private init() {}

	/// Open a tweak by slug or numeric id (accepts either form).
	func openTweak(_ key: String) {
		let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !key.isEmpty else { return }

		// Already in the loaded catalog?
		if let local = TweaksManager.shared.tweaks.first(where: { $0.slug == key || String($0.id) == key }) {
			presentedTweak = local
			return
		}

		// Warm the catalog and fetch the single tweak directly.
		if TweaksManager.shared.tweaks.isEmpty { TweaksManager.shared.load() }
		Task {
			do {
				let tweak: CatalogTweak
				if let id = Int(key) {
					tweak = try await InjecyBackend.shared.fetchTweak(id: id)
				} else {
					tweak = try await InjecyBackend.shared.fetchTweak(slug: key)
				}
				self.presentedTweak = tweak
			} catch {
				// Tweak not found / unavailable — silently ignore.
			}
		}
	}
}
