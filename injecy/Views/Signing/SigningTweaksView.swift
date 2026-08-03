//
//  SigningTweaksView.swift
//  injecy
//
//  Tweak injection step of signing: pick tweaks from the marketplace or your library.
//

import SwiftUI
import NimbleViews
import NukeUI

// MARK: - View
struct SigningTweaksView: View {
	@State private var _isBrowsePresenting = false
	@State private var _isAdvancedExpanded = false

	@Binding var options: Options
	/// Bundle id of the app being signed, used to highlight compatible tweaks.
	var targetBundleId: String? = nil
	/// Display name of the app being signed, for the "Suggested for …" section.
	var targetAppName: String? = nil

	// MARK: Body
	var body: some View {
		List {
			Section {
				_browseRow
			}

			Section {
				if options.injectionFiles.isEmpty {
					_emptyRow
				} else {
					ForEach(options.injectionFiles, id: \.absoluteString) { url in
						_selectedRow(url)
							.swipeActions(edge: .trailing, allowsFullSwipe: true) {
								Button(role: .destructive) { _remove(url) } label: {
									Label(.localized("Delete"), systemImage: "trash")
								}
							}
					}
				}
			} header: {
				Text(options.injectionFiles.isEmpty
					 ? .localized("Selected tweaks")
					 : "\(String.localized("Selected tweaks")) · \(options.injectionFiles.count)")
			}

			Section {
				DisclosureGroup(isExpanded: $_isAdvancedExpanded) {
					Picker(selection: $options.injectPath) {
						ForEach(Options.InjectPath.allCases, id: \.self) { Text($0.rawValue).tag($0) }
					} label: {
						Label(.localized("Injection Path"), systemImage: "doc.badge.gearshape")
					}
					Picker(selection: $options.injectFolder) {
						ForEach(Options.InjectFolder.allCases, id: \.self) { Text($0.rawValue).tag($0) }
					} label: {
						Label(.localized("Injection Folder"), systemImage: "folder.badge.gearshape")
					}
					Toggle(isOn: $options.injectIntoExtensions) {
						Label(.localized("Inject into Extensions"), systemImage: "syringe")
					}
				} label: {
					Label(.localized("Injection options"), systemImage: "slider.horizontal.3")
						.font(.subheadline.weight(.medium))
				}
			}
		}
		.listStyle(.insetGrouped)
		.navigationTitle(.localized("Tweaks"))
		.navigationBarTitleDisplayMode(.inline)
		.sheet(isPresented: $_isBrowsePresenting) {
			TweakPickerView(targetBundleId: targetBundleId, targetAppName: targetAppName) { picked in
				for (url, tweak) in picked {
					FileManager.default.moveAndStore(url, with: "FeatherTweak") { stored in
						if !options.injectionFiles.contains(stored) {
							options.injectionFiles.append(stored)
							InjectionRegistry.shared.set(tweak, for: stored)
						}
					}
				}
			}
		}
		.animation(.smooth, value: options.injectionFiles)
	}

	// MARK: Browse CTA (row)
	private var _browseRow: some View {
		Button {
			_isBrowsePresenting = true
		} label: {
			HStack(spacing: 14) {
				ZStack {
					RoundedRectangle(cornerRadius: 12, style: .continuous)
						.fill(.white.opacity(0.18)).frame(width: 48, height: 48)
					Image(systemName: "square.grid.2x2.fill").font(.title2).foregroundStyle(.white)
				}
				VStack(alignment: .leading, spacing: 2) {
					Text(.localized("Browse Tweaks")).font(.headline).foregroundStyle(.white)
					Text(.localized("Marketplace & your library"))
						.font(.caption).foregroundStyle(.white.opacity(0.85))
				}
				Spacer()
				Image(systemName: "chevron.right")
					.font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
			}
			.padding(.horizontal, 18).padding(.vertical, 15)
			.frame(maxWidth: .infinity)
			.background(
				LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.75)],
				               startPoint: .topLeading, endPoint: .bottomTrailing),
				in: RoundedRectangle(cornerRadius: 20, style: .continuous)
			)
			.shadow(color: Color.accentColor.opacity(0.3), radius: 10, y: 5)
		}
		.buttonStyle(.plain)
		.listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
		.listRowBackground(Color.clear)
	}

	// MARK: Selected row
	private var _emptyRow: some View {
		HStack(spacing: 10) {
			Image(systemName: "tray").foregroundStyle(.secondary)
			Text(.localized("No tweaks added yet."))
				.font(.subheadline).foregroundStyle(.secondary)
		}
		.padding(.vertical, 6)
	}

	@ViewBuilder
	private func _selectedRow(_ url: URL) -> some View {
		let tweak = InjectionRegistry.shared.tweak(for: url)
		let accent = tweak?.accent ?? .accentColor
		HStack(spacing: 12) {
			Group {
				if let iconURL = tweak?.iconURL {
					LazyImage(url: iconURL) { state in
						if let image = state.image {
						image.resizable().aspectRatio(contentMode: .fill)
					} else {
						Image(systemName: "puzzlepiece.extension").foregroundStyle(.secondary)
					}
					}
				} else {
					RoundedRectangle(cornerRadius: 9, style: .continuous)
						.fill(LinearGradient(colors: [accent, accent.opacity(0.6)],
						                     startPoint: .topLeading, endPoint: .bottomTrailing))
						.overlay(Image(systemName: tweak == nil ? "doc.fill" : "puzzlepiece.extension.fill")
							.font(.system(size: 14)).foregroundStyle(.white))
				}
			}
			.frame(width: 38, height: 38)
			.clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

			VStack(alignment: .leading, spacing: 1) {
				Text(tweak?.name ?? url.lastPathComponent)
					.font(.subheadline.weight(.medium)).lineLimit(1)
				Text(_subtitle(tweak, url))
					.font(.caption2).foregroundStyle(.secondary).lineLimit(1)
			}
		}
	}

	/// "[target ·] v{version} · {TYPE}" for catalog tweaks; file extension for raw files.
	private func _subtitle(_ tweak: CatalogTweak?, _ url: URL) -> String {
		guard let t = tweak else { return url.pathExtension.uppercased() }
		var parts: [String] = []
		if let target = t.targetAppName, !target.isEmpty { parts.append(target) }
		if !t.version.isEmpty, t.version != "—" { parts.append("v\(t.version)") }
		let type = t.fileType.isEmpty ? url.pathExtension : t.fileType
		if !type.isEmpty { parts.append(type.uppercased()) }
		return parts.joined(separator: " · ")
	}

	// MARK: Helpers
	private func _remove(_ url: URL) {
		FileManager.default.deleteStored(url) { removed in
			if let i = options.injectionFiles.firstIndex(where: { $0 == removed }) {
				options.injectionFiles.remove(at: i)
			}
			InjectionRegistry.shared.remove(removed)
		}
	}
}

// MARK: - Tweak picker (Marketplace + Library segments)
struct TweakPickerView: View {
	@Environment(\.dismiss) private var dismiss
	@ObservedObject private var manager = TweaksManager.shared
	@ObservedObject private var library = TweakLibrary.shared
	@ObservedObject private var packStore = TweakPackStore.shared

	let targetBundleId: String?
	var targetAppName: String? = nil
	/// Resolved (file URL, tweak metadata) pairs; marketplace tweaks are downloaded on demand.
	let onResolved: ([(url: URL, tweak: CatalogTweak)]) -> Void

	enum Segment: Hashable { case market, library, packs }
	@State private var _segment: Segment = .market
	@State private var _selected: Set<Int> = []
	@State private var _search = ""
	@State private var _busy = false
	@State private var _isImporting = false
	@State private var _onlyCompatible = false

	struct PickItem: Identifiable {
		let tweak: CatalogTweak
		let libraryFile: URL?
		var id: Int { tweak.id }
		var inLibrary: Bool { libraryFile != nil }
	}

	private func isCompatible(_ t: CatalogTweak) -> Bool {
		guard let target = targetBundleId else { return false }
		return t.allTargetBundleIds.contains(target)
	}

	private var libByID: [Int: LibraryTweak] {
		Dictionary(uniqueKeysWithValues: library.items.map { ($0.id, $0) })
	}

	private var marketItems: [PickItem] {
		manager.tweaks.map { PickItem(tweak: $0, libraryFile: libByID[$0.id].flatMap(library.fileURL)) }
	}
	private var libraryItems: [PickItem] {
		library.items.map { PickItem(tweak: $0.tweak, libraryFile: library.fileURL(for: $0)) }
	}
	/// Resolve any selected id to its file/metadata regardless of the active segment.
	private var allByID: [Int: PickItem] {
		var d: [Int: PickItem] = [:]
		for it in marketItems { d[it.id] = it }
		for it in libraryItems where d[it.id] == nil { d[it.id] = it }
		return d
	}

	/// Whether compatibility info is available for this signing session.
	private var canMatch: Bool { targetBundleId != nil }

	private var shown: [PickItem] {
		let base = _segment == .market ? marketItems : libraryItems
		var filtered = base.filter {
			_search.isEmpty
			|| $0.tweak.name.localizedCaseInsensitiveContains(_search)
			|| ($0.tweak.targetAppName?.localizedCaseInsensitiveContains(_search) ?? false)
		}
		if _onlyCompatible { filtered = filtered.filter { isCompatible($0.tweak) } }
		return filtered.sorted {
			if isCompatible($0.tweak) != isCompatible($1.tweak) { return isCompatible($0.tweak) }
			return $0.tweak.name < $1.tweak.name
		}
	}
	private var shownCompatible: [PickItem] { shown.filter { isCompatible($0.tweak) } }
	private var shownOther: [PickItem] { shown.filter { !isCompatible($0.tweak) } }

	/// Show the "Suggested / More" section split when matching is possible and useful.
	private var showSections: Bool {
		canMatch && !_onlyCompatible && _search.isEmpty
		&& !shownCompatible.isEmpty && !shownOther.isEmpty
	}

	private var suggestedTitle: String {
		if let name = targetAppName, !name.isEmpty {
			return "\(String.localized("Suggested for")) \(name)"
		}
		return .localized("Suggested for this app")
	}

	var body: some View {
		NavigationStack {
			ZStack {
				Color(.systemGroupedBackground).ignoresSafeArea()
				_content
			}
			.navigationTitle(.localized("Add Tweaks"))
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					Button { dismiss() } label: { Image(systemName: "xmark").font(.subheadline.weight(.semibold)) }
						.disabled(_busy)
				}
				ToolbarItem(placement: .topBarTrailing) {
					if _segment == .library {
						Button { _isImporting = true } label: { Image(systemName: "square.and.arrow.down") }
							.disabled(_busy)
					}
				}
			}
			.safeAreaInset(edge: .top) { _header }
			.safeAreaInset(edge: .bottom) { _addBar }
		}
		.onAppear { manager.load() }
		.interactiveDismissDisabled(_busy)
		.animation(.smooth(duration: 0.25), value: _selected.isEmpty)
		.sheet(isPresented: $_isImporting) {
			FileImporterRepresentableView(
				allowedContentTypes: [.dylib, .deb],
				allowsMultipleSelection: true,
				onDocumentsPicked: { urls in for url in urls { library.addCustomFile(url) } }
			)
			.ignoresSafeArea()
		}
	}

	// MARK: Content
	@ViewBuilder
	private var _content: some View {
		if _segment == .packs {
			_packsContent
		} else if _segment == .market, manager.isLoading, manager.tweaks.isEmpty {
			ProgressView()
		} else if shown.isEmpty {
			_emptyState
		} else {
			ScrollView {
				LazyVStack(spacing: 10) {
					if showSections {
						_sectionLabel(suggestedTitle, systemImage: "checkmark.seal.fill", accent: true)
						ForEach(shownCompatible) { _card($0) }
						_sectionLabel(.localized("More tweaks"), systemImage: "square.grid.2x2", accent: false)
						ForEach(shownOther) { _card($0) }
					} else {
						ForEach(shown) { _card($0) }
					}
				}
				.padding(.horizontal).padding(.top, 4).padding(.bottom, 96)
			}
			.scrollDismissesKeyboard(.immediately)
		}
	}

	// MARK: Packs content
	@ViewBuilder
	private var _packsContent: some View {
		if packStore.all.isEmpty {
			_placeholder("square.stack.3d.up", .localized("No packs yet"),
			             .localized("Create packs in the Tweaks tab, then apply them here in one tap."))
		} else {
			ScrollView {
				LazyVStack(spacing: 10) {
					ForEach(packStore.all) { _packCard($0) }
				}
				.padding(.horizontal).padding(.top, 4).padding(.bottom, 96)
			}
			.scrollDismissesKeyboard(.immediately)
		}
	}

	private func _packCard(_ pack: TweakPack) -> some View {
		let ids = pack.tweakIDs.filter { allByID[$0] != nil }
		let tweaks = ids.compactMap { allByID[$0]?.tweak }
		let accent: Color = pack.accentHex.map { Color(hex: $0) } ?? tweaks.first?.accent ?? .accentColor
		let allSelected = !ids.isEmpty && ids.allSatisfy(_selected.contains)
		return Button {
			if allSelected { ids.forEach { _selected.remove($0) } }
			else { ids.forEach { _selected.insert($0) } }
		} label: {
			HStack(spacing: 12) {
				ZStack {
					RoundedRectangle(cornerRadius: 12, style: .continuous)
						.fill(LinearGradient(colors: [accent, accent.opacity(0.6)],
						                     startPoint: .topLeading, endPoint: .bottomTrailing))
					Image(systemName: "square.stack.3d.up.fill").font(.title3).foregroundStyle(.white)
				}
				.frame(width: 44, height: 44)

				VStack(alignment: .leading, spacing: 4) {
					Text(pack.name).font(.headline).lineLimit(1)
					HStack(spacing: -6) {
						ForEach(Array(tweaks.prefix(4).enumerated()), id: \.offset) { _, t in
							TweakCellIcon(tweak: t, size: 22)
						}
						if tweaks.count > 0 {
							Text(ids.count == pack.tweakIDs.count
								 ? "\(tweaks.count) \(tweaks.count == 1 ? String.localized("tweak") : String.localized("tweaks"))"
								 : "\(ids.count)/\(pack.tweakIDs.count)")
								.font(.caption2).foregroundStyle(.secondary).padding(.leading, 10)
						}
					}
				}
				Spacer(minLength: 8)
				Image(systemName: allSelected ? "checkmark.circle.fill" : (ids.contains(where: _selected.contains) ? "minus.circle.fill" : "circle"))
					.font(.title3)
					.foregroundStyle(allSelected || ids.contains(where: _selected.contains) ? accent : Color.secondary.opacity(0.45))
			}
			.padding(12)
			.background(RoundedRectangle(cornerRadius: 16, style: .continuous)
				.fill(allSelected ? accent.opacity(0.10) : Color(.secondarySystemGroupedBackground)))
			.overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
				.strokeBorder(allSelected ? accent.opacity(0.6) : .clear, lineWidth: 1.5))
			.contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
		}
		.buttonStyle(.plain)
		.disabled(ids.isEmpty)
		.opacity(ids.isEmpty ? 0.5 : 1)
	}

	private func _sectionLabel(_ title: String, systemImage: String, accent: Bool) -> some View {
		HStack(spacing: 6) {
			Image(systemName: systemImage)
			Text(title).font(.subheadline.weight(.bold))
			Spacer()
		}
		.foregroundStyle(accent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
		.padding(.top, 6)
		.padding(.horizontal, 4)
	}

	@ViewBuilder
	private var _emptyState: some View {
		if _onlyCompatible {
			_placeholder("checkmark.seal", .localized("No compatible tweaks"),
			             .localized("No tweaks target this app yet. Turn off “Only compatible” to see everything."))
		} else if _segment == .library {
			_placeholder("tray", .localized("Your library is empty"),
			             .localized("Import your own tweak with the button above, or add some from the Marketplace."))
		} else if !_search.isEmpty {
			_placeholder("magnifyingglass", .localized("Nothing found"), .localized("Try a different search."))
		} else {
			_placeholder("puzzlepiece.extension", .localized("No tweaks available"), .localized("Check back later."))
		}
	}

	// MARK: Header (segment + search + compatible banner)
	private var _header: some View {
		VStack(spacing: 10) {
			Picker("", selection: $_segment.animation(.smooth(duration: 0.25))) {
				Text(.localized("Marketplace")).tag(Segment.market)
				Text(.localized("Library")).tag(Segment.library)
				Text(.localized("Packs")).tag(Segment.packs)
			}
			.pickerStyle(.segmented)

			HStack(spacing: 8) {
				Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
				TextField(.localized("Search tweaks"), text: $_search)
					.autocorrectionDisabled().textInputAutocapitalization(.never)
				if !_search.isEmpty {
					Button { _search = "" } label: {
						Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
					}
				}
			}
			.padding(.horizontal, 12).padding(.vertical, 10)
			.background(.quaternary.opacity(0.5), in: Capsule())
			.frame(height: _segment == .packs ? 0 : nil)
			.opacity(_segment == .packs ? 0 : 1)
			.clipped()

			if _segment != .packs, !shownCompatible.isEmpty {
				Button {
					let ids = shownCompatible.map(\.id)
					if ids.allSatisfy(_selected.contains) { ids.forEach { _selected.remove($0) } }
					else { ids.forEach { _selected.insert($0) } }
				} label: {
					HStack(spacing: 8) {
						Image(systemName: "checkmark.seal.fill")
						Text("\(shownCompatible.count) \(String.localized("compatible"))")
							.font(.subheadline.weight(.semibold))
						Spacer()
						Text(shownCompatible.map(\.id).allSatisfy(_selected.contains)
							 ? .localized("Deselect") : .localized("Select all"))
							.font(.caption.weight(.semibold))
					}
					.padding(.horizontal, 14).padding(.vertical, 9)
					.background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
					.foregroundStyle(Color.accentColor)
				}
			}

			// Only-compatible filter — available whenever we know the target app.
			if _segment != .packs, canMatch && (!shownCompatible.isEmpty || _onlyCompatible) {
				Toggle(isOn: $_onlyCompatible.animation(.smooth(duration: 0.2))) {
					Label(.localized("Only compatible"), systemImage: "line.3.horizontal.decrease.circle")
						.font(.caption.weight(.semibold))
				}
				.toggleStyle(.button)
				.tint(.accentColor)
				.controlSize(.small)
				.frame(maxWidth: .infinity, alignment: .leading)
			}
		}
		.padding(.horizontal).padding(.top, 6).padding(.bottom, 10)
		.background(.bar)
	}

	@ViewBuilder
	private var _addBar: some View {
		if !_selected.isEmpty {
			Button { _add() } label: {
				HStack(spacing: 8) {
					if _busy { ProgressView().tint(.white) }
					Text(_busy ? .localized("Adding…")
						 : "\(String.localized("Add")) \(_selected.count) \(_selected.count == 1 ? String.localized("tweak") : String.localized("tweaks"))")
				}
				.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
				.background(Color.accentColor, in: Capsule()).foregroundStyle(.white)
			}
			.disabled(_busy)
			.padding(.horizontal).padding(.top, 10).padding(.bottom, 8)
			.background(.bar)
			.transition(.move(edge: .bottom).combined(with: .opacity))
		}
	}

	private func _add() {
		_busy = true
		let lookup = allByID
		Task {
			var pairs: [(url: URL, tweak: CatalogTweak)] = []
			for id in _selected {
				guard let item = lookup[id] else { continue }
				// Resolves library copy → cache → download (and caches), so re-using a
				// non-library tweak doesn't download it again.
				if let url = await TweakLibrary.shared.resolveForSigning(item.tweak) {
					pairs.append((url, item.tweak))
				}
			}
			_busy = false
			onResolved(pairs)
			dismiss()
		}
	}

	private func _placeholder(_ icon: String, _ title: String, _ subtitle: String) -> some View {
		VStack(spacing: 10) {
			Image(systemName: icon).font(.largeTitle).foregroundStyle(.secondary)
			Text(title).font(.headline)
			Text(subtitle).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
		}
		.padding(40)
	}

	@ViewBuilder
	private func _card(_ item: PickItem) -> some View {
		let selected = _selected.contains(item.id)
		let accent = item.tweak.accent
		Button {
			if selected { _selected.remove(item.id) } else { _selected.insert(item.id) }
		} label: {
			HStack(spacing: 12) {
				_icon(item)
				VStack(alignment: .leading, spacing: 5) {
					Text(item.tweak.name).font(.headline).lineLimit(1)
					if item.tweak.id >= 0, let target = item.tweak.targetAppName, !target.isEmpty {
						Text(target).font(.caption).foregroundStyle(.secondary).lineLimit(1)
					}
					HStack(spacing: 6) {
						if item.tweak.id < 0 { _tag(.localized("Imported"), color: .secondary) }
						if !item.tweak.version.isEmpty, item.tweak.version != "—" {
							_tag("v\(item.tweak.version)", color: .secondary)
						}
						if !item.tweak.fileType.isEmpty { _tag(item.tweak.fileType.uppercased(), color: .secondary) }
						if isCompatible(item.tweak) { _tag(.localized("Compatible"), color: accent) }
						if _segment == .market && item.inLibrary { _tag(.localized("In Library"), color: .secondary) }
					}
				}
				Spacer(minLength: 8)
				Image(systemName: selected ? "checkmark.circle.fill" : "circle")
					.font(.title3).foregroundStyle(selected ? accent : Color.secondary.opacity(0.45))
					.scaleEffect(selected ? 1.12 : 1)
			}
			.padding(12)
			.background(
				RoundedRectangle(cornerRadius: 16, style: .continuous)
					.fill(selected ? accent.opacity(0.10) : Color(.secondarySystemGroupedBackground))
			)
			.overlay(
				RoundedRectangle(cornerRadius: 16, style: .continuous)
					.strokeBorder(selected ? accent.opacity(0.6) : .clear, lineWidth: 1.5)
			)
			.contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
		}
		.buttonStyle(.plain)
		.animation(.smooth(duration: 0.2), value: selected)
	}

	private func _tag(_ text: String, color: Color) -> some View {
		Text(text)
			.font(.caption2.weight(.semibold))
			.padding(.horizontal, 6).padding(.vertical, 2)
			.background(color.opacity(0.16), in: Capsule())
			.foregroundStyle(color)
	}

	@ViewBuilder
	private func _icon(_ item: PickItem) -> some View {
		Group {
			if let url = item.tweak.iconURL {
				LazyImage(url: url) { state in
					if let image = state.image {
						image.resizable().aspectRatio(contentMode: .fill)
					} else {
						Image(systemName: "puzzlepiece.extension").foregroundStyle(.secondary)
					}
				}
			} else {
				RoundedRectangle(cornerRadius: 11, style: .continuous)
					.fill(LinearGradient(colors: [item.tweak.accent, item.tweak.accent.opacity(0.6)],
					                     startPoint: .topLeading, endPoint: .bottomTrailing))
					.overlay(Image(systemName: item.tweak.id < 0 ? "doc.fill" : "puzzlepiece.extension.fill")
						.font(.system(size: 16)).foregroundStyle(.white))
			}
		}
		.frame(width: 42, height: 42)
		.clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
	}
}
