//
//  TweakPackEditorView.swift
//  injecy
//
//  View / edit a tweak pack: rename, add or remove tweaks (from the marketplace or your
//  library), or delete it. Official packs are read-only.
//

import SwiftUI
import NukeUI

struct TweakPackEditorView: View {
	@Environment(\.dismiss) private var dismiss
	@ObservedObject private var packStore = TweakPackStore.shared
	@ObservedObject private var manager = TweaksManager.shared
	@ObservedObject private var library = TweakLibrary.shared

	let packID: String

	@State private var _name = ""
	@State private var _isAdding = false
	@State private var _nameLoaded = false

	private var pack: TweakPack? { packStore.pack(packID) }
	private var isOfficial: Bool { pack?.isOfficial ?? false }

	/// Tweak ids → metadata (marketplace + library).
	private func metadata() -> [Int: CatalogTweak] {
		var d: [Int: CatalogTweak] = [:]
		for t in manager.tweaks { d[t.id] = t }
		for it in library.items where d[it.id] == nil { d[it.id] = it.tweak }
		return d
	}

	private var tweaks: [CatalogTweak] {
		guard let pack else { return [] }
		let meta = metadata()
		return pack.tweakIDs.compactMap { meta[$0] }
	}

	var body: some View {
		NavigationStack {
			Group {
				if pack == nil {
					ContentUnavailableCompat()
				} else {
					_form
				}
			}
			.navigationTitle(pack?.name ?? .localized("Pack"))
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					Button { dismiss() } label: { Image(systemName: "xmark").font(.subheadline.weight(.semibold)) }
				}
				if !isOfficial {
					ToolbarItem(placement: .topBarTrailing) {
						Button { _isAdding = true } label: { Image(systemName: "plus") }
					}
				}
			}
		}
		.onAppear {
			if !_nameLoaded { _name = pack?.name ?? ""; _nameLoaded = true }
		}
		.sheet(isPresented: $_isAdding) {
			TweakPackSelectorView(packID: packID)
		}
	}

	@ViewBuilder
	private var _form: some View {
		List {
			if !isOfficial {
				Section(.localized("Name")) {
					TextField(.localized("Pack name"), text: $_name)
						.onSubmit { _commitName() }
						.submitLabel(.done)
				}
			}

			Section {
				if tweaks.isEmpty {
					HStack(spacing: 10) {
						Image(systemName: "tray").foregroundStyle(.secondary)
						Text(.localized("No tweaks in this pack yet."))
							.font(.subheadline).foregroundStyle(.secondary)
					}
				} else {
					ForEach(tweaks) { tweak in
						_tweakRow(tweak)
							.swipeActions(edge: .trailing, allowsFullSwipe: true) {
								if !isOfficial {
									Button(role: .destructive) {
										packStore.toggle(tweak.id, in: packID)
									} label: { Label(.localized("Remove"), systemImage: "trash") }
								}
							}
					}
				}

				if !isOfficial {
					Button {
						_isAdding = true
					} label: {
						Label(.localized("Add tweaks"), systemImage: "plus.circle.fill")
					}
				}
			} header: {
				Text("\(String.localized("Tweaks")) · \(tweaks.count)")
			}

			if !isOfficial {
				Section {
					Button(role: .destructive) {
						packStore.delete(packID)
						dismiss()
					} label: {
						Label(.localized("Delete Pack"), systemImage: "trash")
							.frame(maxWidth: .infinity)
					}
				}
			}
		}
	}

	private func _tweakRow(_ tweak: CatalogTweak) -> some View {
		HStack(spacing: 12) {
			TweakCellIcon(tweak: tweak, size: 38)
			VStack(alignment: .leading, spacing: 2) {
				Text(tweak.name).font(.subheadline.weight(.medium)).lineLimit(1)
				if let target = tweak.targetAppName, !target.isEmpty {
					Text(target).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
				} else if tweak.id < 0 {
					Text(.localized("Imported")).font(.caption2).foregroundStyle(.secondary)
				}
			}
			Spacer()
		}
	}

	private func _commitName() {
		let trimmed = _name.trimmingCharacters(in: .whitespaces)
		guard !trimmed.isEmpty else { _name = pack?.name ?? ""; return }
		packStore.rename(packID, to: trimmed)
	}
}

// MARK: - Selector (add/remove tweaks live)

struct TweakPackSelectorView: View {
	@Environment(\.dismiss) private var dismiss
	@ObservedObject private var packStore = TweakPackStore.shared
	@ObservedObject private var manager = TweaksManager.shared
	@ObservedObject private var library = TweakLibrary.shared

	let packID: String
	@State private var _search = ""

	enum Segment: Hashable { case market, library }
	@State private var _segment: Segment = .market

	private var items: [CatalogTweak] {
		let base: [CatalogTweak] = _segment == .market
			? manager.tweaks
			: library.items.map(\.tweak)
		let filtered = base.filter {
			_search.isEmpty
			|| $0.name.localizedCaseInsensitiveContains(_search)
			|| ($0.targetAppName?.localizedCaseInsensitiveContains(_search) ?? false)
		}
		return filtered.sorted { $0.name < $1.name }
	}

	var body: some View {
		NavigationStack {
			List {
				Picker("", selection: $_segment) {
					Text(.localized("Marketplace")).tag(Segment.market)
					Text(.localized("Library")).tag(Segment.library)
				}
				.pickerStyle(.segmented)
				.listRowSeparator(.hidden)

				ForEach(items) { tweak in
					Button {
						packStore.toggle(tweak.id, in: packID)
					} label: {
						HStack(spacing: 12) {
							TweakCellIcon(tweak: tweak, size: 36)
							VStack(alignment: .leading, spacing: 2) {
								Text(tweak.name).font(.subheadline.weight(.medium)).lineLimit(1)
								if let target = tweak.targetAppName, !target.isEmpty {
									Text(target).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
								}
							}
							Spacer()
							Image(systemName: packStore.contains(tweak.id, in: packID) ? "checkmark.circle.fill" : "circle")
								.foregroundStyle(packStore.contains(tweak.id, in: packID) ? Color.accentColor : Color.secondary.opacity(0.4))
						}
						.contentShape(Rectangle())
					}
					.buttonStyle(.plain)
				}
			}
			.listStyle(.plain)
			.searchable(text: $_search, prompt: Text(.localized("Search tweaks")))
			.navigationTitle(.localized("Add tweaks"))
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .topBarTrailing) {
					Button(.localized("Done")) { dismiss() }.font(.headline)
				}
			}
		}
		.onAppear { manager.load() }
	}
}

// MARK: - Compat empty state

private struct ContentUnavailableCompat: View {
	var body: some View {
		VStack(spacing: 8) {
			Image(systemName: "square.stack.3d.up.slash").font(.largeTitle).foregroundStyle(.secondary)
			Text(.localized("Pack not found")).font(.headline)
		}
	}
}
