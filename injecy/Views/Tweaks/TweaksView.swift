//
//  TweaksView.swift
//  injecy
//
//  The Tweaks tab: a marketplace catalog plus the user's personal library.
//

import SwiftUI
import NimbleViews
import NimbleExtensions
import NukeUI

// MARK: - Accent
extension CatalogTweak {
	/// Admin-set accent if present, otherwise a stable colour derived from the slug.
	var accent: Color {
		if let hex = accentColor, !hex.isEmpty {
			return Color(hex: hex)
		}
		var hash: UInt64 = 5381
		for byte in slug.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
		let hue = Double(hash % 360) / 360.0
		return Color(hue: hue, saturation: 0.55, brightness: 0.95)
	}

	/// All bundle ids this tweak is compatible with (primary + extras).
	var allTargetBundleIds: [String] {
		var ids = targetBundleIds
		if let b = targetBundleId, !b.isEmpty { ids.append(b) }
		return ids
	}
}

// MARK: - View
struct TweaksView: View {
	enum Segment: Hashable { case market, library, packs }

	@StateObject private var manager = TweaksManager.shared
	@ObservedObject private var library = TweakLibrary.shared
	@ObservedObject private var packStore = TweakPackStore.shared

	enum SortMode: String, CaseIterable {
		case recommended, popular, likes, name
		var label: String {
			switch self {
			case .recommended: return .localized("Recommended")
			case .popular: return .localized("Popular")
			case .likes: return .localized("Most liked")
			case .name: return .localized("A–Z")
			}
		}
		var icon: String {
			switch self {
			case .recommended: return "sparkles"
			case .popular: return "arrow.down.right.circle"
			case .likes: return "heart"
			case .name: return "textformat"
			}
		}
	}

	enum PriceFilter: String, CaseIterable {
		case all, free, paid
		var label: String {
			switch self {
			case .all: return .localized("All")
			case .free: return .localized("Free")
			case .paid: return .localized("Paid")
			}
		}
	}

	@State private var _segment: Segment = .market
	@State private var _search = ""
	@State private var _category = ""
	@State private var _sort: SortMode = .recommended
	@State private var _price: PriceFilter = .all
	@State private var _fileType = ""
	@State private var _selected: CatalogTweak?
	@State private var _isImporting = false
	@State private var _editingPack: TweakPack?
	@State private var _isCreatingPack = false
	@State private var _newPackName = ""
	@State private var _isRequestingTweak = false
	/// The matched-transition source id of whatever was tapped, so the zoom grows
	/// from the exact view (featured card vs. list row) instead of an ambiguous one.
	@State private var _sourceID = ""
	@Namespace private var _namespace

	private var sourceTweaks: [CatalogTweak] {
		switch _segment {
		case .market: return manager.tweaks
		case .library:
			// Show the latest catalog data for owned tweaks (so version/update state is current).
			let byID = Dictionary(uniqueKeysWithValues: manager.tweaks.map { ($0.id, $0) })
			return library.items.map { byID[$0.id] ?? $0.tweak }
		case .packs:
			return []
		}
	}

	/// Distinct categories present in the active segment.
	private var categories: [String] {
		Array(Set(sourceTweaks.map(\.category))).filter { !$0.isEmpty }.sorted()
	}

	/// Distinct file types present in the active segment.
	private var fileTypes: [String] {
		Array(Set(sourceTweaks.map { $0.fileType.lowercased() })).filter { !$0.isEmpty }.sorted()
	}

	/// True when any non-default filter (besides category/search) is active.
	private var hasActiveFilters: Bool { _price != .all || !_fileType.isEmpty }

	/// Search + category + price + type filtered, then sorted by the chosen mode.
	private var displayed: [CatalogTweak] {
		var list = sourceTweaks.filter {
			_search.isEmpty
			|| $0.name.localizedCaseInsensitiveContains(_search)
			|| ($0.targetAppName?.localizedCaseInsensitiveContains(_search) ?? false)
		}
		if !_category.isEmpty { list = list.filter { $0.category == _category } }
		switch _price {
		case .all: break
		case .free: list = list.filter { !$0.isPaid }
		case .paid: list = list.filter { $0.isPaid }
		}
		if !_fileType.isEmpty { list = list.filter { $0.fileType.lowercased() == _fileType } }
		switch _sort {
		case .recommended:
			list.sort {
				if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
				if $0.isRecommended != $1.isRecommended { return $0.isRecommended && !$1.isRecommended }
				if $0.installCount != $1.installCount { return $0.installCount > $1.installCount }
				return $0.name < $1.name
			}
		case .popular: list.sort { $0.installCount > $1.installCount }
		case .likes: list.sort { $0.likes > $1.likes }
		case .name: list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
		}
		return list
	}

	/// `displayed` grouped into category sections (preserving the chosen sort within each).
	private var groupedDisplayed: [(category: String, items: [CatalogTweak])] {
		Dictionary(grouping: displayed, by: { $0.category.isEmpty ? "general" : $0.category })
			.map { (category: $0.key, items: $0.value) }
			.sorted { $0.category < $1.category }
	}

	/// Highlighted tweaks for the marketplace hero carousel — admin-curated
	/// (is_recommended); falls back to most-installed if none are marked.
	private var featured: [CatalogTweak] {
		let recommended = manager.tweaks.filter(\.isRecommended)
		let source = recommended.isEmpty ? manager.tweaks.sorted { $0.installCount > $1.installCount } : recommended
		return Array(source.prefix(5))
	}

	// MARK: Body
	var body: some View {
		NBNavigationView(.localized("Tweaks"), displayMode: .inline) {
			content
				.searchable(text: $_search, placement: .navigationBarDrawer(displayMode: .automatic),
				            prompt: Text(.localized("Search tweaks")))
				.animation(.smooth(duration: 0.28), value: _segment)
			.toolbar {
				if _segment == .library {
					ToolbarItem(placement: .topBarTrailing) {
						Button {
							_isImporting = true
						} label: {
							Image(systemName: "square.and.arrow.down")
						}
					}
				}
				if _segment == .packs {
					ToolbarItem(placement: .topBarTrailing) {
						Button {
							_newPackName = ""
							_isCreatingPack = true
						} label: {
							Image(systemName: "plus")
						}
					}
				}
			}
		}
		.onAppear { manager.load(); LikesManager.shared.load(); packStore.loadOfficial() }
		.fullScreenCover(item: $_selected) { tweak in
			TweakDetailView(tweak: tweak)
				.compatNavigationTransition(id: _sourceID, ns: _namespace)
		}
		.sheet(isPresented: $_isImporting) {
			FileImporterRepresentableView(
				allowedContentTypes: [.dylib, .deb],
				allowsMultipleSelection: true,
				onDocumentsPicked: { urls in
					for url in urls { library.addCustomFile(url) }
				}
			)
			.ignoresSafeArea()
		}
		.sheet(item: $_editingPack) { pack in
			TweakPackEditorView(packID: pack.id)
		}
		.sheet(isPresented: $_isRequestingTweak) {
			RequestTweakView(prefillName: _search)
		}
		.alert(.localized("New Pack"), isPresented: $_isCreatingPack) {
			TextField(.localized("Pack name"), text: $_newPackName)
			Button(.localized("Cancel"), role: .cancel) { }
			Button(.localized("Create")) {
				let name = _newPackName.trimmingCharacters(in: .whitespaces)
				_editingPack = packStore.create(name: name.isEmpty ? .localized("New Pack") : name)
			}
		} message: {
			Text(.localized("Give your pack a name, then add tweaks to it."))
		}
	}

	/// Present the detail, remembering which view the zoom should originate from.
	private func _open(_ tweak: CatalogTweak, source: String) {
		_sourceID = source
		_selected = tweak
	}

	// MARK: Error banner
	private func _errorBanner(_ message: String) -> some View {
		HStack(spacing: 8) {
			Image(systemName: "wifi.exclamationmark")
			VStack(alignment: .leading, spacing: 1) {
				Text(.localized("Couldn't reach the catalog"))
					.font(.caption.weight(.semibold))
				Text(message).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
			}
			Spacer()
			Button(.localized("Retry")) { manager.load() }
				.font(.caption.weight(.semibold))
		}
		.padding(.horizontal, 12).padding(.vertical, 9)
		.background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
		.foregroundStyle(.orange)
		.padding(.horizontal).padding(.bottom, 8)
	}

	/// Full "you're offline" state shown when there's no cached catalog to fall back on.
	private var _offlineState: some View {
		VStack(spacing: 14) {
			Image(systemName: "wifi.slash")
				.font(.system(size: 44))
				.foregroundStyle(.secondary)
			VStack(spacing: 4) {
				Text(.localized("You're offline")).font(.headline)
				Text(.localized("Connect to the internet to browse tweaks."))
					.font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
			}
			Button {
				manager.load()
			} label: {
				Label(.localized("Retry"), systemImage: "arrow.clockwise")
					.font(.subheadline.weight(.semibold))
					.padding(.horizontal, 20).padding(.vertical, 10)
					.background(Color.accentColor.opacity(0.15), in: Capsule())
			}
			.buttonStyle(.plain)
		}
		.padding(.vertical, 40)
	}

	// MARK: Segment bar
	private var _segmentBar: some View {
		Picker("", selection: $_segment.animation(.smooth(duration: 0.28))) {
			Text(.localized("Marketplace")).tag(Segment.market)
			Text(.localized("My Library")).tag(Segment.library)
			Text(.localized("Packs")).tag(Segment.packs)
		}
		.pickerStyle(.segmented)
		.padding(.horizontal)
		.padding(.top, 10)
		.padding(.bottom, 10)
	}

	/// Library tweaks with a newer marketplace version.
	private var _updates: [(library: LibraryTweak, latest: CatalogTweak)] {
		library.updates(against: manager.tweaks)
	}

	// MARK: Filter bar (categories + sort)
	private var _filterBar: some View {
		HStack(spacing: 8) {
			ScrollView(.horizontal, showsIndicators: false) {
				HStack(spacing: 8) {
					_chip(.localized("All"), selected: _category.isEmpty) { _category = "" }
					ForEach(categories, id: \.self) { c in
						_chip(c.capitalized, selected: _category == c) { _category = c }
					}
				}
				.padding(.horizontal)
			}
			Menu {
				Picker(.localized("Sort"), selection: $_sort) {
					ForEach(SortMode.allCases, id: \.self) { mode in
						Label(mode.label, systemImage: mode.icon).tag(mode)
					}
				}
				Picker(.localized("Price"), selection: $_price) {
					ForEach(PriceFilter.allCases, id: \.self) { p in
						Text(p.label).tag(p)
					}
				}
				if !fileTypes.isEmpty {
					Picker(.localized("File type"), selection: $_fileType) {
						Text(.localized("All types")).tag("")
						ForEach(fileTypes, id: \.self) { t in
							Text(t.uppercased()).tag(t)
						}
					}
				}
				if hasActiveFilters {
					Divider()
					Button(.localized("Clear filters"), systemImage: "xmark.circle") {
						_price = .all; _fileType = ""
					}
				}
			} label: {
				Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "arrow.up.arrow.down")
					.font(.subheadline.weight(.semibold))
					.foregroundStyle(hasActiveFilters ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
					.padding(8)
					.background(Color(.secondarySystemGroupedBackground), in: Circle())
			}
			.padding(.trailing)
		}
		.padding(.bottom, 8)
		.animation(.smooth(duration: 0.2), value: _category)
	}

	private func _chip(_ title: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Text(title)
				.font(.subheadline.weight(.medium))
				.padding(.horizontal, 13).padding(.vertical, 6)
				.background(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)), in: Capsule())
				.foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
		}
		.buttonStyle(.plain)
	}

	// MARK: Content
	/// Single `List` so it's the only scroll view under the nav bar — that lets the
	/// `.searchable` bar (and the in-list controls) collapse on scroll for more viewport.
	@ViewBuilder
	private var content: some View {
		List {
			// Scrollable top controls.
			_segmentBar
				.listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 4, trailing: 12))
				.listRowSeparator(.hidden)
				.listRowBackground(Color.clear)

			if _segment == .packs {
				_packsRows
			} else {
				if _segment == .market, let err = manager.error {
					_errorBanner(err)
						.listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
						.listRowSeparator(.hidden)
						.listRowBackground(Color.clear)
				}
				if !sourceTweaks.isEmpty {
					_filterBar
						.listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
						.listRowSeparator(.hidden)
						.listRowBackground(Color.clear)
				}

				if _segment == .market, manager.isLoading, manager.tweaks.isEmpty {
					ForEach(0..<6, id: \.self) { _ in
						_SkeletonRow()
							.listRowSeparator(.hidden)
							.listRowBackground(Color.clear)
					}
				} else if _segment == .market, manager.tweaks.isEmpty, manager.error != nil {
					_centeredRow { _offlineState }
				} else if displayed.isEmpty && !(_segment == .library && _category.isEmpty && _search.isEmpty && !_updates.isEmpty) {
					_centeredRow { _empty }
				} else {
					if _segment == .market, _category.isEmpty, _search.isEmpty, !featured.isEmpty {
						_featuredSection
					}
					if _segment == .library, _category.isEmpty, _search.isEmpty, !_updates.isEmpty {
						_updatesSection
					}
					if _search.isEmpty {
						ForEach(groupedDisplayed, id: \.category) { group in
							Section {
								ForEach(group.items.prefix(5)) { _cell($0) }
								if group.items.count > 5 {
									_showAllRow(group)
								}
							} header: {
								Text(group.category.capitalized)
									.font(.title3.bold())
									.foregroundStyle(.primary)
									.textCase(nil)
									.padding(.leading, -4)
							}
						}
					} else {
						ForEach(displayed) { _cell($0) }
					}
				}
			}
		}
		.listStyle(.plain)
		.refreshable { manager.load() }
		.animation(.smooth(duration: 0.35), value: library.items)
		.animation(.smooth(duration: 0.25), value: displayed.map(\.id))
		.animation(.smooth(duration: 0.28), value: _segment)
	}

	// MARK: Packs

	/// Resolve a pack's tweak ids to catalog/library metadata for previews.
	private func _packTweaks(_ pack: TweakPack) -> [CatalogTweak] {
		let market = Dictionary(uniqueKeysWithValues: manager.tweaks.map { ($0.id, $0) })
		let local = Dictionary(uniqueKeysWithValues: library.items.map { ($0.id, $0.tweak) })
		return pack.tweakIDs.compactMap { market[$0] ?? local[$0] }
	}

	@ViewBuilder
	private var _packsRows: some View {
		if packStore.all.isEmpty {
			_centeredRow { _packsEmpty }
		} else {
			if !packStore.officialPacks.isEmpty {
				Section {
					ForEach(packStore.officialPacks) { _packRow($0) }
				} header: { _packsHeader(.localized("Official packs"), "checkmark.seal.fill") }
			}
			Section {
				ForEach(packStore.packs) { pack in
					_packRow(pack)
						.swipeActions(edge: .trailing, allowsFullSwipe: true) {
							Button(role: .destructive) { packStore.delete(pack.id) } label: {
								Label(.localized("Delete"), systemImage: "trash")
							}
						}
				}
				_newPackRow
			} header: { _packsHeader(.localized("Your packs"), "square.stack.3d.up.fill") }
		}
	}

	private func _packsHeader(_ title: String, _ systemImage: String) -> some View {
		Label(title, systemImage: systemImage)
			.font(.headline).foregroundStyle(.primary).textCase(nil)
			.listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
			.listRowSeparator(.hidden)
			.listRowBackground(Color.clear)
	}

	private var _packsEmpty: some View {
		VStack(spacing: 12) {
			Image(systemName: "square.stack.3d.up").font(.largeTitle).foregroundStyle(.secondary)
			Text(.localized("No packs yet")).font(.headline)
			Text(.localized("Create a pack to apply several tweaks at once when signing."))
				.font(.subheadline).foregroundStyle(.secondary)
				.multilineTextAlignment(.center).padding(.horizontal, 40)
			Button {
				_newPackName = ""; _isCreatingPack = true
			} label: {
				Label(.localized("New Pack"), systemImage: "plus")
					.font(.subheadline.weight(.semibold))
					.padding(.horizontal, 16).padding(.vertical, 10)
					.background(Color.accentColor, in: Capsule()).foregroundStyle(.white)
			}
			.buttonStyle(.plain)
		}
	}

	@ViewBuilder
	private func _packRow(_ pack: TweakPack) -> some View {
		let tweaks = _packTweaks(pack)
		let accent: Color = pack.accentHex.map { Color(hex: $0) } ?? tweaks.first?.accent ?? .accentColor
		Button {
			_editingPack = pack
		} label: {
			HStack(spacing: 13) {
				ZStack {
					RoundedRectangle(cornerRadius: 13, style: .continuous)
						.fill(LinearGradient(colors: [accent, accent.opacity(0.6)],
						                     startPoint: .topLeading, endPoint: .bottomTrailing))
					Image(systemName: "square.stack.3d.up.fill")
						.font(.title3).foregroundStyle(.white)
				}
				.frame(width: 48, height: 48)

				VStack(alignment: .leading, spacing: 3) {
					HStack(spacing: 6) {
						Text(pack.name).font(.headline).lineLimit(1)
						if pack.isOfficial {
							Image(systemName: "checkmark.seal.fill").font(.caption2).foregroundStyle(accent)
						}
					}
					Text("\(pack.count) \(pack.count == 1 ? String.localized("tweak") : String.localized("tweaks"))")
						.font(.caption).foregroundStyle(.secondary)
				}
				Spacer(minLength: 8)
				// Small overlapping icon previews.
				HStack(spacing: -8) {
					ForEach(Array(tweaks.prefix(3).enumerated()), id: \.offset) { _, t in
						TweakCellIcon(tweak: t, size: 26)
							.overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 0).clipShape(Circle()).opacity(0))
					}
				}
				Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
			}
			.padding(12)
			.background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial))
			.overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(accent.opacity(0.12), lineWidth: 1))
			.contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
		}
		.buttonStyle(.plain)
		.listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
		.listRowSeparator(.hidden)
		.listRowBackground(Color.clear)
	}

	private var _newPackRow: some View {
		Button {
			_newPackName = ""; _isCreatingPack = true
		} label: {
			HStack(spacing: 10) {
				Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(Color.accentColor)
				Text(.localized("New Pack")).font(.subheadline.weight(.semibold)).foregroundStyle(Color.accentColor)
				Spacer()
			}
			.padding(.vertical, 8).padding(.horizontal, 4)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 10, trailing: 16))
		.listRowSeparator(.hidden)
		.listRowBackground(Color.clear)
	}

	private func _centeredRow<V: View>(@ViewBuilder _ inner: () -> V) -> some View {
		HStack { Spacer(); inner(); Spacer() }
			.frame(minHeight: 360)
			.listRowSeparator(.hidden)
			.listRowBackground(Color.clear)
	}

	// MARK: "Show all" (category overflow)
	@ViewBuilder
	private func _showAllRow(_ group: (category: String, items: [CatalogTweak])) -> some View {
		NavigationLink {
			_categoryAll(group)
		} label: {
			HStack(spacing: 6) {
				Text("\(String.localized("Show all")) (\(group.items.count))")
					.font(.subheadline.weight(.semibold))
				Spacer()
				Image(systemName: "chevron.right").font(.caption.weight(.bold))
			}
			.foregroundStyle(Color.accentColor)
			.padding(.vertical, 4)
		}
		.listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 10, trailing: 16))
		.listRowSeparator(.hidden)
		.listRowBackground(Color.clear)
	}

	private func _categoryAll(_ group: (category: String, items: [CatalogTweak])) -> some View {
		let accent = group.items.first?.accent ?? .accentColor
		return List {
			_categoryHero(group, accent: accent)
			ForEach(group.items) { _cell($0, sourcePrefix: "all") }
		}
		.listStyle(.plain)
		.navigationTitle(group.category.capitalized)
		.navigationBarTitleDisplayMode(.inline)
	}

	/// Accent hero header shown at the top of a category's full list.
	private func _categoryHero(_ group: (category: String, items: [CatalogTweak]), accent: Color) -> some View {
		ZStack(alignment: .bottomLeading) {
			LinearGradient(
				colors: [accent.opacity(0.55), accent.opacity(0.18), .clear],
				startPoint: .topTrailing, endPoint: .bottomLeading
			)
			HStack(spacing: 14) {
				ZStack {
					RoundedRectangle(cornerRadius: 16, style: .continuous)
						.fill(LinearGradient(colors: [accent, accent.opacity(0.6)],
						                     startPoint: .topLeading, endPoint: .bottomTrailing))
						.frame(width: 56, height: 56)
						.shadow(color: accent.opacity(0.45), radius: 10, y: 4)
					Image(systemName: "square.grid.2x2.fill")
						.font(.title2).foregroundStyle(.white)
				}
				VStack(alignment: .leading, spacing: 3) {
					Text(group.category.capitalized)
						.font(.title.bold())
					Text("\(group.items.count) \(group.items.count == 1 ? String.localized("tweak") : String.localized("tweaks"))")
						.font(.subheadline).foregroundStyle(.secondary)
				}
				Spacer()
			}
			.padding(.horizontal, 16).padding(.vertical, 18)
		}
		.frame(height: 130)
		.clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
		.listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 10, trailing: 12))
		.listRowSeparator(.hidden)
		.listRowBackground(Color.clear)
	}

	// MARK: Updates section (library)
	private var _updatesSection: some View {
		Section {
			ForEach(_updates, id: \.library.id) { entry in
				_updateRow(entry.library, latest: entry.latest)
			}
		} header: {
			HStack {
				Label("\(String.localized("Updates available")) · \(_updates.count)",
				      systemImage: "arrow.triangle.2.circlepath")
					.font(.title3.bold()).foregroundStyle(.primary).textCase(nil)
				Spacer()
				Button(.localized("Update all")) {
					for e in _updates {
						let latest = e.latest
						Task { await library.update(latest.id, to: latest) }
					}
				}
				.font(.caption.weight(.semibold)).textCase(nil)
			}
			.padding(.leading, -4)
		}
	}

	@ViewBuilder
	private func _updateRow(_ item: LibraryTweak, latest: CatalogTweak) -> some View {
		HStack(spacing: 12) {
			TweakCellIcon(tweak: latest, size: 44)
			VStack(alignment: .leading, spacing: 2) {
				Text(latest.name).font(.headline).lineLimit(1)
				Text("v\(item.tweak.version) → v\(latest.version)")
					.font(.caption).foregroundStyle(.secondary)
			}
			Spacer(minLength: 8)
			if library.isDownloading(item.id) {
				ProgressView()
			} else {
				Button(.localized("Update")) {
					Task { await library.update(latest.id, to: latest) }
				}
				.font(.caption.weight(.bold))
				.buttonStyle(.borderedProminent)
				.buttonBorderShape(.capsule)
				.controlSize(.small)
			}
		}
		.padding(12)
		.background(latest.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
		.overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(latest.accent.opacity(0.25), lineWidth: 1))
		.listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
		.listRowSeparator(.hidden)
		.listRowBackground(Color.clear)
	}

	// MARK: Cell (row)
	@ViewBuilder
	private func _cell(_ tweak: CatalogTweak, sourcePrefix: String = "row") -> some View {
		let sourceID = "\(sourcePrefix)-\(tweak.id)"
		Button {
			_open(tweak, source: sourceID)
		} label: {
			TweakCellView(tweak: tweak, updatable: _segment == .library && library.hasUpdate(for: tweak))
		}
		.buttonStyle(.plain)
		.listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
		.listRowSeparator(.hidden)
		.listRowBackground(Color.clear)
		.compatMatchedTransitionSource(id: sourceID, ns: _namespace)
		.swipeActions(edge: .trailing, allowsFullSwipe: true) {
			if _segment == .library {
				Button(role: .destructive) {
					library.remove(tweak.id)
				} label: {
					Label(.localized("Remove"), systemImage: "trash")
				}
			}
		}
	}

	// MARK: Featured carousel (marketplace only) — plain rows to avoid section spacing.
	@ViewBuilder
	private var _featuredSection: some View {
		Label(.localized("Featured"), systemImage: "sparkles")
			.font(.title3.bold())
			.foregroundStyle(.primary)
			.listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 2, trailing: 16))
			.listRowSeparator(.hidden)
			.listRowBackground(Color.clear)

		ScrollView(.horizontal, showsIndicators: false) {
			HStack(spacing: 14) {
				ForEach(featured) { tweak in
					Button { _open(tweak, source: "feat-\(tweak.id)") } label: {
						FeaturedTweakCard(tweak: tweak)
					}
					.buttonStyle(.plain)
					.compatMatchedTransitionSource(id: "feat-\(tweak.id)", ns: _namespace)
				}
			}
			.padding(.horizontal, 16)
		}
		.listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
		.listRowSeparator(.hidden)
		.listRowBackground(Color.clear)
	}

	private var _empty: some View {
		VStack(spacing: 12) {
			Spacer()
			Image(systemName: _segment == .library ? "tray" : "puzzlepiece.extension")
				.font(.largeTitle)
				.foregroundStyle(.secondary)
			Text(verbatim: _segment == .library
				 ? .localized("Your library is empty. Add tweaks from the marketplace.")
				 : (_search.isEmpty ? .localized("No tweaks available.") : .localized("No tweaks match your search.")))
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
				.padding(.horizontal, 40)
			if _segment == .library {
				Button {
					withAnimation(.smooth(duration: 0.28)) { _segment = .market }
				} label: {
					Label(.localized("Browse Marketplace"), systemImage: "sparkles")
						.font(.subheadline.weight(.semibold))
						.padding(.horizontal, 16).padding(.vertical, 10)
						.background(Color.accentColor, in: Capsule())
						.foregroundStyle(.white)
				}
				.buttonStyle(.plain)
			}
			if _segment == .market, !_search.isEmpty {
				Button {
					_isRequestingTweak = true
				} label: {
					Label(.localized("Request this tweak"), systemImage: "plus.bubble")
						.font(.subheadline.weight(.semibold))
						.padding(.horizontal, 16).padding(.vertical, 10)
						.background(Color.accentColor, in: Capsule())
						.foregroundStyle(.white)
				}
				.buttonStyle(.plain)
			}
			Spacer()
		}
		.frame(maxWidth: .infinity)
	}
}

// MARK: - Featured card
struct FeaturedTweakCard: View {
	let tweak: CatalogTweak

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack {
				_icon
				Spacer()
				Text("v\(tweak.version)")
					.font(.caption2.weight(.semibold))
					.padding(.horizontal, 8).padding(.vertical, 4)
					.background(.white.opacity(0.18), in: Capsule())
			}
			Spacer(minLength: 0)
			Text(tweak.name)
				.font(.headline)
				.foregroundStyle(.white)
				.lineLimit(1)
			if let target = tweak.targetAppName {
				Text(target)
					.font(.caption)
					.foregroundStyle(.white.opacity(0.85))
					.lineLimit(1)
			}
		}
		.padding(14)
		.frame(width: 215, height: 130, alignment: .leading)
		.background(
			LinearGradient(
				colors: [tweak.accent, tweak.accent.opacity(0.65)],
				startPoint: .topLeading, endPoint: .bottomTrailing
			),
			in: RoundedRectangle(cornerRadius: 22, style: .continuous)
		)
		.foregroundStyle(.white)
		.shadow(color: tweak.accent.opacity(0.35), radius: 10, y: 5)
	}

	@ViewBuilder
	private var _icon: some View {
		Group {
			if let url = tweak.iconURL {
				LazyImage(url: url) { state in
					if let image = state.image {
						image.resizable().aspectRatio(contentMode: .fill)
					} else {
						RoundedRectangle(cornerRadius: 12, style: .continuous)
							.fill(LinearGradient(colors: [tweak.accent, tweak.accent.opacity(0.6)],
							                     startPoint: .topLeading, endPoint: .bottomTrailing))
							.overlay(Image(systemName: "puzzlepiece.extension.fill").font(.system(size: 19)).foregroundStyle(.white))
					}
				}
			} else {
				RoundedRectangle(cornerRadius: 12, style: .continuous)
					.fill(LinearGradient(colors: [tweak.accent, tweak.accent.opacity(0.6)],
					                     startPoint: .topLeading, endPoint: .bottomTrailing))
					.overlay(Image(systemName: "puzzlepiece.extension.fill").font(.system(size: 19)).foregroundStyle(.white))
			}
		}
		.frame(width: 44, height: 44)
		.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
	}
}

// MARK: - Reusable icon
struct TweakCellIcon: View {
	let tweak: CatalogTweak
	var size: CGFloat = 48

	var body: some View {
		Group {
			if let url = tweak.iconURL {
				LazyImage(url: url) { state in
					if let image = state.image {
						image.resizable().aspectRatio(contentMode: .fill)
					} else {
						_placeholder
					}
				}
			} else {
				_placeholder
			}
		}
		.frame(width: size, height: size)
		.clipShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
	}

	/// Color-based placeholder derived from the tweak's accent.
	private var _placeholder: some View {
		RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
			.fill(LinearGradient(
				colors: [tweak.accent, tweak.accent.opacity(0.6)],
				startPoint: .topLeading, endPoint: .bottomTrailing
			))
			.overlay(
				Image(systemName: tweak.id < 0 ? "doc.fill" : "puzzlepiece.extension.fill")
					.font(.system(size: size * 0.42))
					.foregroundStyle(.white.opacity(0.95))
			)
	}
}

// MARK: - Cell
struct TweakCellView: View {
	let tweak: CatalogTweak
	/// When true (update available in the library), the card uses a neutral grey style.
	var updatable: Bool = false

	var body: some View {
		HStack(spacing: 13) {
			_icon
			VStack(alignment: .leading, spacing: 3) {
				HStack(spacing: 6) {
					Text(tweak.name)
						.font(.headline)
						.lineLimit(1)
					if tweak.isPaid {
						Text(.localized("PAID"))
							.font(.system(size: 8, weight: .heavy))
							.padding(.horizontal, 5).padding(.vertical, 2)
							.background(tweak.accent, in: Capsule())
							.foregroundStyle(.white)
					}
				}
				HStack(spacing: 8) {
					if let target = tweak.targetAppName, !target.isEmpty {
						Text(target)
							.font(.caption)
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
					if tweak.installCount > 0 {
						_stat("arrow.down.to.line", tweak.installCount.injecyCompact)
					}
					if tweak.likes > 0 {
						_stat("heart.fill", tweak.likes.injecyCompact)
					}
				}
				Text(tweak.description)
					.font(.caption2)
					.foregroundStyle(.tertiary)
					.lineLimit(1)
			}
			Spacer(minLength: 8)
			if updatable {
				Label(.localized("Update"), systemImage: "arrow.triangle.2.circlepath")
					.labelStyle(.iconOnly)
					.font(.caption.weight(.bold))
					.foregroundStyle(.secondary)
			}
			VStack(alignment: .trailing, spacing: 4) {
				Text("v\(tweak.version)")
					.font(.caption2.weight(.medium))
					.foregroundStyle(updatable ? .secondary : tweak.accent)
					.padding(.horizontal, 8)
					.padding(.vertical, 4)
					.background((updatable ? Color.secondary : tweak.accent).opacity(0.14), in: Capsule())
				if !tweak.fileType.isEmpty {
					Text(tweak.fileType.uppercased())
						.font(.system(size: 9, weight: .semibold))
						.foregroundStyle(.secondary)
						.padding(.horizontal, 7)
						.padding(.vertical, 3)
						.background(Color.secondary.opacity(0.12), in: Capsule())
				}
			}
		}
		.padding(12)
		.background(
			RoundedRectangle(cornerRadius: 18, style: .continuous)
				.fill(updatable ? AnyShapeStyle(Color(.secondarySystemGroupedBackground)) : AnyShapeStyle(.ultraThinMaterial))
		)
		.overlay(
			RoundedRectangle(cornerRadius: 18, style: .continuous)
				.strokeBorder((updatable ? Color.secondary : tweak.accent).opacity(0.12), lineWidth: 1)
		)
		.contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
	}

	private func _stat(_ systemName: String, _ text: String) -> some View {
		HStack(spacing: 2) {
			Image(systemName: systemName).font(.system(size: 8))
			Text(text).font(.caption2)
		}
		.foregroundStyle(.secondary)
	}

	@ViewBuilder
	private var _icon: some View {
		Group {
			if let url = tweak.iconURL {
				LazyImage(url: url) { state in
					if let image = state.image {
						image.resizable().aspectRatio(contentMode: .fill)
					} else {
						Image(systemName: "puzzlepiece.extension").foregroundStyle(.secondary)
					}
				}
			} else {
				RoundedRectangle(cornerRadius: 13, style: .continuous)
					.fill(LinearGradient(
						colors: [tweak.accent, tweak.accent.opacity(0.6)],
						startPoint: .topLeading, endPoint: .bottomTrailing
					))
					.overlay(
						Image(systemName: "puzzlepiece.extension.fill")
							.font(.system(size: 20))
							.foregroundStyle(.white.opacity(0.95))
					)
			}
		}
		.frame(width: 48, height: 48)
		.clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
	}
}

// MARK: - Compact count formatting (1234 → "1.2k")
extension Int {
	var injecyCompact: String {
		switch self {
		case 1_000_000...:
			return String(format: "%.1fM", Double(self) / 1_000_000).replacingOccurrences(of: ".0M", with: "M")
		case 1_000...:
			return String(format: "%.1fk", Double(self) / 1_000).replacingOccurrences(of: ".0k", with: "k")
		default:
			return "\(self)"
		}
	}
}

// MARK: - Skeleton loading row (shimmer)

private struct _SkeletonRow: View {
	@State private var _shimmer = false

	var body: some View {
		HStack(spacing: 14) {
			RoundedRectangle(cornerRadius: 13, style: .continuous)
				.frame(width: 52, height: 52)
			VStack(alignment: .leading, spacing: 8) {
				RoundedRectangle(cornerRadius: 5).frame(width: 140, height: 12)
				RoundedRectangle(cornerRadius: 5).frame(width: 200, height: 10)
			}
			Spacer()
		}
		.foregroundStyle(Color.secondary.opacity(0.18))
		.overlay(
			LinearGradient(
				colors: [.clear, Color.white.opacity(0.35), .clear],
				startPoint: .leading, endPoint: .trailing
			)
			.frame(width: 120)
			.offset(x: _shimmer ? 260 : -260)
			.blendMode(.plusLighter)
		)
		.mask(
			HStack(spacing: 14) {
				RoundedRectangle(cornerRadius: 13).frame(width: 52, height: 52)
				VStack(alignment: .leading, spacing: 8) {
					RoundedRectangle(cornerRadius: 5).frame(width: 140, height: 12)
					RoundedRectangle(cornerRadius: 5).frame(width: 200, height: 10)
				}
				Spacer()
			}
		)
		.padding(.vertical, 6)
		.onAppear {
			withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { _shimmer = true }
		}
	}
}
