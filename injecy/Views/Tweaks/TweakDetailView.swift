//
//  TweakDetailView.swift
//  injecy
//
//  Distinctive tweak detail page, presented as a zooming full-screen cover.
//

import SwiftUI
import UIKit
import NimbleViews
import NukeUI

// MARK: - View
struct TweakDetailView: View {
	@Environment(\.dismiss) private var dismiss
	@ObservedObject private var library = TweakLibrary.shared
	let tweak: CatalogTweak

	@State private var _selectedScreenshot = 0
	@State private var _isPreviewPresented = false
	@State private var _liked = false
	@State private var _likeCount = 0
	@State private var _likeBusy = false

	private var accent: Color { tweak.accent }

	/// Shareable https link (tappable in chats) → a landing page that opens the
	/// injecy://tweak/<slug> deep link. Prefers the slug, falls back to the id.
	private var _shareURL: URL? {
		let key = tweak.slug.isEmpty ? String(tweak.id) : tweak.slug
		let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
		return URL(string: "https://leadproject.lol/t/\(encoded)")
	}

	private func _toggleLike() {
		guard !_likeBusy else { return }
		_likeBusy = true
		let wasLiked = _liked
		// Optimistic update.
		_liked.toggle()
		_likeCount += _liked ? 1 : -1
		Task {
			if let res = try? await InjecyBackend.shared.toggleLike(tweak.id) {
				_liked = res.liked; _likeCount = res.likes
				if res.liked { LikesManager.shared.markLiked(tweak.id) }
				else { LikesManager.shared.markUnliked(tweak.id) }
			} else {
				_liked = wasLiked; _likeCount += wasLiked ? 1 : -1  // revert
			}
			_likeBusy = false
		}
	}

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(spacing: 22) {
					_hero
					_actionButton
					_chips
					if !tweak.screenshots.isEmpty { _screenshots }
					_about
					_developer
					_compatibility
				}
				.padding(.horizontal)
				.padding(.bottom, 32)
			}
			.background(_backdrop.ignoresSafeArea())
			.scrollIndicators(.hidden)
			.onAppear {
				_likeCount = tweak.likes
				_liked = LikesManager.shared.isLiked(tweak.id)
			}
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					Button {
						dismiss()
					} label: {
						Image(systemName: "xmark")
							.font(.subheadline.weight(.bold))
					}
				}
				if tweak.id > 0, let url = _shareURL {
					ToolbarItem(placement: .topBarTrailing) {
						ShareLink(item: url, subject: Text(tweak.name),
						          message: Text(verbatim: .localized("Check out %@ on injecy", arguments: tweak.name))) {
							Image(systemName: "square.and.arrow.up")
								.font(.subheadline.weight(.semibold))
						}
					}
				}
			}
			.toolbarBackground(.hidden, for: .navigationBar)
			.fullScreenCover(isPresented: $_isPreviewPresented) {
				ScreenshotPreviewView(screenshotURLs: tweak.screenshots, initialIndex: _selectedScreenshot)
			}
		}
	}

	// MARK: Backdrop
	private var _backdrop: some View {
		LinearGradient(
			colors: [accent.opacity(0.30), accent.opacity(0.05), .clear],
			startPoint: .top, endPoint: .center
		)
	}

	// MARK: Hero
	private var _hero: some View {
		VStack(spacing: 14) {
			_icon
				.shadow(color: accent.opacity(0.45), radius: 18, y: 8)
			VStack(spacing: 4) {
				Text(tweak.name)
					.font(.title.bold())
					.multilineTextAlignment(.center)
				if let dev = tweak.developerName {
					Text(dev)
						.font(.subheadline)
						.foregroundStyle(.secondary)
				}
			}
		}
		.padding(.top, 8)
	}

	@ViewBuilder
	private var _icon: some View {
		Group {
			if let url = tweak.iconURL {
				LazyImage(url: url) { state in
					if let image = state.image {
						image.resizable().aspectRatio(contentMode: .fill)
					} else {
						_iconPlaceholder
					}
				}
			} else {
				_iconPlaceholder
			}
		}
		.frame(width: 104, height: 104)
		.clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
	}

	private var _iconPlaceholder: some View {
		RoundedRectangle(cornerRadius: 26, style: .continuous)
			.fill(LinearGradient(colors: [accent, accent.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
			.overlay(
				Image(systemName: "puzzlepiece.extension.fill")
					.font(.system(size: 44))
					.foregroundStyle(.white.opacity(0.9))
			)
	}

	// MARK: Action button
	private var _isInLibrary: Bool { library.contains(tweak.id) }
	private var _isDownloading: Bool { library.isDownloading(tweak.id) }
	private var _hasUpdate: Bool { library.hasUpdate(for: tweak) }

	/// Readable label color on the accent button: black on bright accents, white on dark.
	private var _onAccent: Color {
		var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
		UIColor(accent).getRed(&r, green: &g, blue: &b, alpha: &a)
		return (0.299 * r + 0.587 * g + 0.114 * b) > 0.68 ? .black : .white
	}

	@ViewBuilder
	private var _actionButton: some View {
		Group {
			if _isInLibrary && _hasUpdate {
				_splitButton
			} else {
				_singleButton
			}
		}
		.animation(.smooth(duration: 0.25), value: _isInLibrary)
		.animation(.smooth(duration: 0.25), value: _isDownloading)
		.animation(.smooth(duration: 0.25), value: _hasUpdate)
	}

	/// In-library + update available → "In Library" (muted, removes) | "Update" (accent).
	private var _splitButton: some View {
		HStack(spacing: 10) {
			Button {
				library.remove(tweak.id)
			} label: {
				Label(.localized("In Library"), systemImage: "checkmark.circle.fill")
					.font(.subheadline.weight(.semibold))
					.frame(maxWidth: .infinity).padding(.vertical, 15)
					.background(.ultraThinMaterial, in: Capsule())
					.foregroundStyle(.primary)
			}
			Button {
				Task { await library.update(tweak.id, to: tweak) }
			} label: {
				HStack(spacing: 6) {
					if _isDownloading { ProgressView().tint(_onAccent) }
					else { Image(systemName: "arrow.triangle.2.circlepath") }
					Text(_isDownloading ? .localized("Updating…") : .localized("Update"))
				}
				.font(.subheadline.weight(.semibold))
				.frame(maxWidth: .infinity).padding(.vertical, 15)
				.background(accent, in: Capsule())
				.foregroundStyle(_onAccent)
			}
			.disabled(_isDownloading)
		}
		.buttonStyle(.plain)
	}

	private var _singleButton: some View {
		Button {
			if _isInLibrary { library.remove(tweak.id) }
			else { Task { await library.add(tweak) } }
		} label: {
			HStack(spacing: 8) {
				if _isDownloading {
					ProgressView().tint(_isInLibrary ? Color.primary : _onAccent); Text(.localized("Adding…"))
				} else if _isInLibrary {
					Image(systemName: "checkmark.circle.fill"); Text(.localized("In Library"))
				} else {
					Image(systemName: "plus.circle.fill"); Text(.localized("Add to Library"))
				}
			}
			.font(.headline)
			.frame(maxWidth: .infinity)
			.padding(.vertical, 15)
			.background(_isInLibrary ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(accent), in: Capsule())
			.foregroundStyle(_isInLibrary ? AnyShapeStyle(.primary) : AnyShapeStyle(_onAccent))
		}
		.buttonStyle(.plain)
		.disabled(_isDownloading)
	}

	// MARK: Chips
	private var _chips: some View {
		HStack(spacing: 8) {
			_chip(tweak.category, "tag.fill")
			_chip("v\(tweak.version)", "number")
			if tweak.isPaid { _chip(.localized("Paid"), "star.fill") }
		}
	}

	private func _chip(_ text: String, _ systemImage: String) -> some View {
		Label(text, systemImage: systemImage)
			.font(.caption.weight(.medium))
			.padding(.horizontal, 12)
			.padding(.vertical, 7)
			.background(.ultraThinMaterial, in: Capsule())
	}

	// MARK: Screenshots
	private var _screenshots: some View {
		VStack(alignment: .leading, spacing: 10) {
			_sectionTitle(.localized("Preview"))
			ScrollView(.horizontal, showsIndicators: false) {
				HStack(spacing: 12) {
					ForEach(Array(tweak.screenshots.enumerated()), id: \.offset) { index, url in
						LazyImage(url: url) { state in
							if let image = state.image {
								image.resizable().aspectRatio(contentMode: .fill)
							} else {
								Rectangle().fill(.quaternary)
									.overlay(ProgressView())
							}
						}
						.frame(width: 200, height: 420)
						.clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
						.overlay(
							RoundedRectangle(cornerRadius: 20, style: .continuous)
								.strokeBorder(.white.opacity(0.08), lineWidth: 1)
						)
						.onTapGesture {
							_selectedScreenshot = index
							_isPreviewPresented = true
						}
					}
				}
				.padding(.vertical, 2)
			}
		}
	}

	// MARK: About
	private var _about: some View {
		_card {
			VStack(alignment: .leading, spacing: 12) {
				HStack {
					_sectionTitle(.localized("About"))
					Spacer()
					// Local/imported tweaks (negative id) have no marketplace stats to show or like.
					if tweak.id > 0 {
						_metric("\(_compact(tweak.installCount))", .localized("installs"))
						_likeButton
					}
				}
				ExpandableText(text: tweak.description, lineLimit: 4)
					.font(.subheadline)
					.foregroundStyle(.primary.opacity(0.85))
				if !tweak.tags.isEmpty {
					ScrollView(.horizontal, showsIndicators: false) {
						HStack(spacing: 6) {
							ForEach(tweak.tags, id: \.self) { tag in
								Text("#\(tag)")
									.font(.caption2.weight(.medium))
									.padding(.horizontal, 10).padding(.vertical, 5)
									.background(accent.opacity(0.15), in: Capsule())
									.foregroundStyle(accent)
							}
						}
					}
				}
			}
		}
	}

	// MARK: Developer
	/// Telegram string (@name or link) → a usable URL.
	private var _telegramURL: URL? {
		guard let tg = tweak.developerTelegram?.trimmingCharacters(in: .whitespacesAndNewlines), !tg.isEmpty else { return nil }
		if tg.lowercased().hasPrefix("http") { return URL(string: tg) }
		let handle = tg.hasPrefix("@") ? String(tg.dropFirst()) : tg
		return URL(string: "https://t.me/\(handle)")
	}

	@ViewBuilder
	private var _developer: some View {
		let hasLinks = _telegramURL != nil || tweak.developerURL != nil
		if tweak.developerName != nil || hasLinks {
			_card {
				VStack(alignment: .leading, spacing: 14) {
					_sectionTitle(.localized("Developer"))
					HStack(spacing: 12) {
						ZStack {
							Circle()
								.fill(LinearGradient(colors: [accent, accent.opacity(0.6)],
								                     startPoint: .topLeading, endPoint: .bottomTrailing))
								.frame(width: 46, height: 46)
								.shadow(color: accent.opacity(0.4), radius: 6, y: 3)
							Image(systemName: "person.fill")
								.font(.title3).foregroundStyle(.white)
						}
						VStack(alignment: .leading, spacing: 2) {
							Text(tweak.developerName ?? .localized("Developer"))
								.font(.headline)
							Text(.localized("Tweak author"))
								.font(.caption).foregroundStyle(.secondary)
						}
						Spacer()
					}
					if hasLinks {
						HStack(spacing: 10) {
							if let tg = _telegramURL {
								_devLink(.localized("Telegram"), "paperplane.fill", tg)
							}
							if let web = tweak.developerURL {
								_devLink(.localized("Website"), "safari.fill", web)
							}
						}
					}
				}
			}
		}
	}

	private func _devLink(_ title: String, _ icon: String, _ url: URL) -> some View {
		Link(destination: url) {
			HStack(spacing: 6) {
				Image(systemName: icon).font(.caption)
				Text(title).font(.subheadline.weight(.semibold))
			}
			.frame(maxWidth: .infinity)
			.padding(.vertical, 10)
			.foregroundStyle(accent)
			.background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
		}
	}

	// MARK: Compatibility
	@ViewBuilder
	private var _compatibility: some View {
		if let target = tweak.targetAppName {
			_card {
				HStack(spacing: 12) {
					Image(systemName: "app.dashed")
						.font(.title2)
						.foregroundStyle(accent)
					VStack(alignment: .leading, spacing: 2) {
						Text(.localized("Works with"))
							.font(.caption).foregroundStyle(.secondary)
						Text(target).font(.subheadline.weight(.semibold))
					}
					Spacer()
				}
			}
		}
	}

	// MARK: Building blocks
	private func _sectionTitle(_ text: String) -> some View {
		Text(text).font(.headline)
	}

	private func _metric(_ value: String, _ label: String) -> some View {
		VStack(alignment: .trailing, spacing: 0) {
			Text(value).font(.subheadline.bold())
			Text(label).font(.caption2).foregroundStyle(.secondary)
		}
	}

	private var _likeButton: some View {
		Button {
			_toggleLike()
		} label: {
			HStack(spacing: 5) {
				Image(systemName: _liked ? "heart.fill" : "heart")
					.foregroundStyle(_liked ? .pink : .secondary)
					.scaleEffect(_liked ? 1.1 : 1)
				Text("\(_compact(_likeCount))").font(.subheadline.bold())
			}
			.padding(.horizontal, 10).padding(.vertical, 6)
			.background(_liked ? AnyShapeStyle(Color.pink.opacity(0.14)) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
		}
		.buttonStyle(.plain)
		.disabled(_likeBusy)
		.animation(.smooth(duration: 0.2), value: _liked)
	}

	private func _card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
		content()
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(16)
			.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
	}

	private func _compact(_ n: Int) -> String {
		switch n {
		case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
		case 1_000...: return String(format: "%.1fK", Double(n) / 1_000)
		default: return "\(n)"
		}
	}
}
