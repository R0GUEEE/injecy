//
//  StorageUsageView.swift
//  injecy
//
//  A premium storage breakdown: a glowing animated donut of categories with per-category
//  sizes you can select and clear. Cache is safe; apps & files ask for confirmation.
//

import SwiftUI
import NimbleViews
import Nuke
import CoreData

// MARK: - Model

private struct StorageCategory: Identifiable {
	let id: String
	let name: String
	let icon: String
	let color: Color
	var bytes: Int64
	/// Destructive (deletes user data, not just cache) — needs confirmation.
	let destructive: Bool
	let clear: () -> Void
}

// MARK: - View

struct StorageUsageView: View {
	@State private var _categories: [StorageCategory] = []
	@State private var _selected: Set<String> = []
	@State private var _loading = true
	@State private var _clearing = false
	@State private var _confirming = false
	@State private var _appear = false

	private var _total: Int64 { _categories.reduce(0) { $0 + $1.bytes } }
	private var _visible: [StorageCategory] { _categories.filter { $0.bytes > 0 } }
	private var _maxBytes: Int64 { max(_visible.map(\.bytes).max() ?? 1, 1) }
	private var _cache: [StorageCategory] { _visible.filter { !$0.destructive } }
	private var _data: [StorageCategory] { _visible.filter { $0.destructive } }
	private var _selectedItems: [StorageCategory] { _categories.filter { _selected.contains($0.id) } }
	private var _selectedBytes: Int64 { _selectedItems.reduce(0) { $0 + $1.bytes } }
	private var _willDeleteData: Bool { _selectedItems.contains { $0.destructive } }
	private var _dominant: Color { _visible.max(by: { $0.bytes < $1.bytes })?.color ?? .accentColor }

	var body: some View {
		ScrollView {
			VStack(spacing: 22) {
				_donut
				_header
				if _loading {
					_loadingCard
				} else if _visible.isEmpty {
					_emptyCard
				} else {
					_grouped(.localized("Cache"), _cache, startIndex: 0)
					_grouped(.localized("Apps & Files"), _data, startIndex: _cache.count)
				}
			}
			.padding(.horizontal, 16)
			.padding(.top, 10)
			.padding(.bottom, 120)
		}
		.background(_background)
		.overlay {
			if _clearing {
				ZStack {
					Color.black.opacity(0.3).ignoresSafeArea()
					VStack(spacing: 16) {
						_ClearingSpinner(accent: _dominant)
						Text(.localized("Clearing…")).font(.headline)
					}
					.padding(30)
					.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
					.shadow(color: .black.opacity(0.25), radius: 20, y: 8)
				}
				.transition(.opacity)
			}
		}
		.animation(.smooth(duration: 0.25), value: _clearing)
		.safeAreaInset(edge: .bottom) { _clearBar }
		.navigationTitle(.localized("Storage"))
		.navigationBarTitleDisplayMode(.inline)
		.task {
			await _compute()
			withAnimation(.spring(response: 0.9, dampingFraction: 0.75)) { _appear = true }
		}
		.confirmationDialog(
			.localized("Delete selected apps & files? This cannot be undone."),
			isPresented: $_confirming, titleVisibility: .visible
		) {
			Button(.localized("Clear Selected"), role: .destructive) { _performClear() }
			Button(.localized("Cancel"), role: .cancel) {}
		}
	}

	private var _background: some View {
		ZStack {
			Color(.systemGroupedBackground)
			// Ambient tint from the dominant category, top-anchored.
			RadialGradient(
				colors: [_dominant.opacity(0.22), .clear],
				center: .top, startRadius: 0, endRadius: 340
			)
			.ignoresSafeArea()
			.animation(.smooth, value: _dominant)
		}
		.ignoresSafeArea()
	}

	// MARK: Donut

	private var _donut: some View {
		ZStack {
			// Soft glow halo.
			Circle()
				.fill(_dominant)
				.frame(width: 150, height: 150)
				.blur(radius: 55)
				.opacity(_loading ? 0.25 : 0.45)
				.scaleEffect(_appear ? 1 : 0.6)

			if _loading {
				Circle().stroke(Color.secondary.opacity(0.14), lineWidth: 30)
					.frame(width: 186, height: 186)
				ProgressView()
			} else if _total == 0 {
				Circle().stroke(Color.secondary.opacity(0.14), lineWidth: 30)
					.frame(width: 186, height: 186)
				Text(.localized("Empty")).font(.headline).foregroundStyle(.secondary)
			} else {
				_DonutRing(
					segments: _visible.map { (Double($0.bytes) / Double(_total), $0.color) },
					animate: _appear ? 1 : 0
				)
				.frame(width: 186, height: 186)

				VStack(spacing: 2) {
					Text(ByteCountFormatter.string(fromByteCount: _total, countStyle: .file))
						.font(.system(.title, design: .rounded).weight(.bold))
						.monospacedDigit()
						.contentTransition(.opacity)
					Text(.localized("Used")).font(.caption.weight(.medium)).foregroundStyle(.secondary)
				}
				.scaleEffect(_appear ? 1 : 0.8)
				.opacity(_appear ? 1 : 0)
			}
		}
		.frame(height: 214)
		.animation(.smooth(duration: 0.6), value: _total)
	}

	private var _header: some View {
		VStack(spacing: 5) {
			Text(.localized("Storage Usage")).font(.title3.bold())
			Text(.localized("All cached data can be re-created when you need it again."))
				.font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
		}
		.padding(.horizontal, 8)
		.opacity(_appear ? 1 : 0)
		.offset(y: _appear ? 0 : 8)
	}

	// MARK: Groups

	@ViewBuilder
	private func _grouped(_ title: String, _ items: [StorageCategory], startIndex: Int) -> some View {
		if !items.isEmpty {
			VStack(alignment: .leading, spacing: 9) {
				Text(title.uppercased())
					.font(.caption.weight(.semibold))
					.foregroundStyle(.secondary)
					.padding(.leading, 16)
				VStack(spacing: 0) {
					ForEach(Array(items.enumerated()), id: \.element.id) { index, cat in
						_row(cat, order: startIndex + index)
						if index < items.count - 1 {
							Divider().padding(.leading, 64)
						}
					}
				}
				.background(
					RoundedRectangle(cornerRadius: 22, style: .continuous)
						.fill(Color(.secondarySystemGroupedBackground))
						.shadow(color: .black.opacity(0.05), radius: 8, y: 3)
				)
			}
		}
	}

	private func _row(_ cat: StorageCategory, order: Int) -> some View {
		let isOn = _selected.contains(cat.id)
		return Button {
			let gen = UIImpactFeedbackGenerator(style: .light); gen.impactOccurred()
			withAnimation(.spring(response: 0.32, dampingFraction: 0.6)) {
				if isOn { _selected.remove(cat.id) } else { _selected.insert(cat.id) }
			}
		} label: {
			HStack(spacing: 13) {
				// Gradient icon chip with glow.
				ZStack {
					RoundedRectangle(cornerRadius: 13, style: .continuous)
						.fill(LinearGradient(colors: [cat.color, cat.color.opacity(0.6)],
						                     startPoint: .topLeading, endPoint: .bottomTrailing))
						.frame(width: 40, height: 40)
						.shadow(color: cat.color.opacity(0.5), radius: 7, y: 3)
					Image(systemName: cat.icon)
						.font(.system(size: 17, weight: .semibold))
						.foregroundStyle(.white)
				}

				VStack(alignment: .leading, spacing: 5) {
					HStack(spacing: 6) {
						Text(cat.name).font(.body.weight(.medium)).foregroundStyle(.primary)
						Spacer(minLength: 6)
						Text(ByteCountFormatter.string(fromByteCount: cat.bytes, countStyle: .file))
							.font(.subheadline.weight(.medium)).foregroundStyle(.secondary).monospacedDigit()
					}
					// Mini usage bar (relative to the largest category).
					GeometryReader { geo in
						ZStack(alignment: .leading) {
							Capsule().fill(Color.secondary.opacity(0.15))
							Capsule()
								.fill(LinearGradient(colors: [cat.color, cat.color.opacity(0.7)],
								                     startPoint: .leading, endPoint: .trailing))
								.frame(width: _appear ? max(6, geo.size.width * (Double(cat.bytes) / Double(_maxBytes))) : 0)
						}
					}
					.frame(height: 5)
				}

				// Animated selection check.
				ZStack {
					Circle()
						.strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1.8)
						.frame(width: 23, height: 23)
						.opacity(isOn ? 0 : 1)
					Circle()
						.fill(cat.color)
						.frame(width: 23, height: 23)
						.scaleEffect(isOn ? 1 : 0.1)
						.opacity(isOn ? 1 : 0)
					Image(systemName: "checkmark")
						.font(.caption2.weight(.bold)).foregroundStyle(.white)
						.scaleEffect(isOn ? 1 : 0.1).opacity(isOn ? 1 : 0)
				}
			}
			.padding(.horizontal, 14).padding(.vertical, 13)
			.background(isOn ? cat.color.opacity(0.07) : Color.clear)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.opacity(_appear ? 1 : 0)
		.offset(y: _appear ? 0 : 14)
		.animation(.spring(response: 0.55, dampingFraction: 0.8).delay(Double(order) * 0.05), value: _appear)
	}

	private var _loadingCard: some View {
		HStack(spacing: 10) { ProgressView(); Text(.localized("Calculating…")).foregroundStyle(.secondary) }
			.frame(maxWidth: .infinity).padding(.vertical, 24)
			.background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
	}

	private var _emptyCard: some View {
		VStack(spacing: 8) {
			Image(systemName: "sparkles").font(.title).foregroundStyle(_dominant)
			Text(.localized("Nothing to clean up.")).foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity).padding(.vertical, 26)
		.background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
	}

	// MARK: Clear bar

	private var _clearBar: some View {
		Group {
			if !_loading && !_visible.isEmpty {
				let tint = _willDeleteData ? Color.red : Color.accentColor
				Button {
					if _willDeleteData { _confirming = true } else { _performClear() }
				} label: {
					HStack(spacing: 8) {
						if _clearing {
							ProgressView().tint(.white)
						} else {
							Image(systemName: _willDeleteData ? "trash.fill" : "sparkles")
						}
						Text(_selected.isEmpty
							 ? .localized("Select items to clear")
							 : "\(String.localized("Clear")) · \(ByteCountFormatter.string(fromByteCount: _selectedBytes, countStyle: .file))")
							.font(.headline)
					}
					.frame(maxWidth: .infinity).padding(.vertical, 16)
					.foregroundStyle(.white)
					.background(
						Capsule().fill(
							_selected.isEmpty
							? AnyShapeStyle(Color.secondary.opacity(0.6))
							: AnyShapeStyle(LinearGradient(colors: [tint, tint.opacity(0.75)],
							                               startPoint: .leading, endPoint: .trailing))
						)
					)
					.shadow(color: (_selected.isEmpty ? Color.clear : tint).opacity(0.45), radius: 12, y: 5)
				}
				.disabled(_selected.isEmpty || _clearing)
				.animation(.smooth, value: _willDeleteData)
				.animation(.smooth, value: _selectedBytes)
				.padding(.horizontal, 16).padding(.bottom, 12).padding(.top, 6)
				.background(.ultraThinMaterial)
			}
		}
	}

	// MARK: Logic

	private func _performClear() {
		_clearing = true
		let toClear = _selectedItems
		Task { @MainActor in
			for cat in toClear { cat.clear() }
			UINotificationFeedbackGenerator().notificationOccurred(.success)
			// Let async cache purges (Nuke DataCache.removeAll) settle before re-measuring.
			try? await Task.sleep(nanoseconds: 450_000_000)
			_appear = false
			await _compute()
			withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) { _appear = true }
			_clearing = false
		}
	}

	private func _compute() async {
		_loading = true
		let cats = await Task.detached(priority: .utility) { () -> [StorageCategory] in
			var imagesBytes = Int64(URLCache.shared.currentDiskUsage)
			if let nuke = ImagePipeline.shared.configuration.dataCache as? DataCache {
				imagesBytes += Int64(nuke.totalSize)
			}
			let fm = FileManager.default
			return [
				StorageCategory(id: "images", name: .localized("Images"), icon: "photo.fill", color: .blue,
				                bytes: imagesBytes, destructive: false) { ResetView.clearNetworkCache() },
				StorageCategory(id: "tweaks", name: .localized("Tweak cache"), icon: "puzzlepiece.extension.fill", color: .orange,
				                bytes: Self.directorySize(TweakLibrary.shared.cacheDirectory), destructive: false) { TweakLibrary.shared.clearCache() },
				StorageCategory(id: "catalog", name: .localized("Catalog"), icon: "books.vertical.fill", color: .purple,
				                bytes: Self.fileSize(TweaksManager.shared.catalogCacheURL), destructive: false) { TweaksManager.shared.clearCatalogCache() },
				StorageCategory(id: "temp", name: .localized("Temporary Files"), icon: "clock.fill", color: .green,
				                bytes: Self.directorySize(fm.temporaryDirectory), destructive: false) { ResetView.clearWorkCache() },
				StorageCategory(id: "signed", name: .localized("Signed Apps"), icon: "checkmark.seal.fill", color: .pink,
				                bytes: Self.directorySize(fm.signed), destructive: true) {
					Storage.shared.clearContext(request: Signed.fetchRequest())
					Self.clearDirectory(fm.signed)
				},
				StorageCategory(id: "imported", name: .localized("Imported Apps"), icon: "square.and.arrow.down.fill", color: .teal,
				                bytes: Self.directorySize(fm.unsigned), destructive: true) {
					Storage.shared.clearContext(request: Imported.fetchRequest())
					Self.clearDirectory(fm.unsigned)
				},
				StorageCategory(id: "archives", name: .localized("Archives"), icon: "archivebox.fill", color: .indigo,
				                bytes: Self.directorySize(fm.archives), destructive: true) { Self.clearDirectory(fm.archives) },
			]
		}.value

		_categories = cats
		let cacheIDs = Set(cats.filter { !$0.destructive && $0.bytes > 0 }.map { $0.id })
		_selected.formIntersection(Set(cats.map { $0.id }))
		if _selected.isEmpty { _selected = cacheIDs }
		_loading = false
	}

	// MARK: Sizing

	static func directorySize(_ url: URL) -> Int64 {
		guard let en = FileManager.default.enumerator(
			at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]
		) else { return 0 }
		var total: Int64 = 0
		for case let f as URL in en {
			let v = try? f.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
			total += Int64(v?.totalFileAllocatedSize ?? v?.fileSize ?? 0)
		}
		return total
	}

	static func fileSize(_ url: URL) -> Int64 {
		Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
	}

	static func clearDirectory(_ url: URL) {
		guard let files = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else { return }
		for f in files { try? FileManager.default.removeItem(at: f) }
	}
}

// MARK: - Glowing animated donut

private struct _DonutRing: View {
	/// (fraction 0…1, color) — fractions should sum to ~1.
	let segments: [(Double, Color)]
	/// 0 → collapsed, 1 → fully drawn (for the entrance animation).
	var animate: Double

	var body: some View {
		let lw: CGFloat = 30
		let cum = _cumulative()
		return ZStack {
			// Faint track.
			Circle().stroke(Color.secondary.opacity(0.10), lineWidth: lw)

			// Glow pass (blurred, behind).
			ForEach(Array(cum.enumerated()), id: \.offset) { _, seg in
				Circle()
					.trim(from: seg.start * animate, to: seg.end * animate)
					.stroke(seg.color, style: StrokeStyle(lineWidth: lw, lineCap: .round))
					.rotationEffect(.degrees(-90))
			}
			.blur(radius: 9)
			.opacity(0.7)

			// Crisp pass.
			ForEach(Array(cum.enumerated()), id: \.offset) { _, seg in
				Circle()
					.trim(from: seg.start * animate, to: seg.end * animate)
					.stroke(
						LinearGradient(colors: [seg.color, seg.color.opacity(0.75)],
						               startPoint: .topLeading, endPoint: .bottomTrailing),
						style: StrokeStyle(lineWidth: lw, lineCap: .round)
					)
					.rotationEffect(.degrees(-90))
			}
		}
		.padding(lw / 2 + 2)
		.animation(.spring(response: 1.0, dampingFraction: 0.8), value: animate)
	}

	private func _cumulative() -> [(start: Double, end: Double, color: Color)] {
		var result: [(Double, Double, Color)] = []
		var acc = 0.0
		let items = segments.filter { $0.0 > 0 }
		// Tiny gap so rounded caps of neighbours read as separate arcs.
		let gap = items.count > 1 ? 0.012 : 0.0
		for (frac, color) in items {
			let start = acc + gap / 2
			let end = acc + frac - gap / 2
			if end > start { result.append((start, end, color)) }
			acc += frac
		}
		return result
	}
}

// MARK: - Clearing animation

private struct _ClearingSpinner: View {
	let accent: Color
	@State private var _rotate = false
	@State private var _pulse = false

	var body: some View {
		ZStack {
			Circle().fill(accent.opacity(0.14)).frame(width: 76, height: 76)
			Circle()
				.trim(from: 0, to: 0.7)
				.stroke(
					AngularGradient(colors: [accent.opacity(0), accent.opacity(0.5), accent], center: .center),
					style: StrokeStyle(lineWidth: 5, lineCap: .round)
				)
				.frame(width: 64, height: 64)
				.rotationEffect(.degrees(_rotate ? 360 : 0))
			Image(systemName: "sparkles")
				.font(.system(size: 24, weight: .semibold))
				.foregroundStyle(accent)
				.scaleEffect(_pulse ? 1.15 : 0.85)
		}
		.onAppear {
			withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { _rotate = true }
			withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { _pulse = true }
		}
	}
}
