//
//  AppUpdateView.swift
//  injecy
//
//  Update check + download UI for the self-updater. The actual sign + install happens
//  through the normal flow (Library → sign with your certificate → install over self).
//

import SwiftUI

struct AppUpdateView: View {
	@Environment(\.dismiss) private var dismiss
	@ObservedObject private var updater = AppUpdater.shared

	private var accent: Color {
		Color(hex: UserDefaults.standard.string(forKey: "Feather.userTintColor") ?? "#848ef9")
	}

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(spacing: 20) {
					_header
					_content
				}
				.padding()
			}
			.background(Color(.systemGroupedBackground).ignoresSafeArea())
			.navigationTitle(.localized("Updates"))
			.navigationBarTitleDisplayMode(.inline)
			.toolbar { ToolbarItem(placement: .topBarLeading) {
				Button { dismiss() } label: { Image(systemName: "xmark") }
			} }
			.onAppear { if updater.available == nil { updater.check(manual: true) } }
			.sheet(item: $updater.pendingInstall, onDismiss: { updater.cleanupAfterInstall() }) { app in
				InstallPreviewView(app: app.base)
					.presentationDetents([.height(200)])
					.presentationDragIndicator(.visible)
			}
		}
		.tint(accent)
	}

	private var _header: some View {
		VStack(spacing: 10) {
			ZStack {
				Circle().fill(accent.opacity(0.15)).frame(width: 84, height: 84)
				Image(systemName: "arrow.down.app.fill").font(.system(size: 36)).foregroundStyle(accent)
			}
			Text(verbatim: "injecy")
				.font(.title3.bold())
			Text("\(String.localized("Version")) \(updater.currentVersion)")
				.font(.caption).foregroundStyle(.secondary)
		}
		.padding(.top, 8)
	}

	@ViewBuilder
	private var _content: some View {
		switch updater.phase {
		case .checking:
			_card { HStack(spacing: 10) { ProgressView(); Text(.localized("Checking for updates…")) } }

		case .upToDate, .idle:
			_card {
				VStack(spacing: 10) {
					Label(.localized("You're up to date"), systemImage: "checkmark.circle.fill")
						.foregroundStyle(.green)
					Button(.localized("Check Again")) { updater.check(manual: true) }
						.font(.subheadline.weight(.semibold))
				}
			}

		case .available, .downloading, .verifying:
			if let r = updater.available {
				_releaseCard(r)
			} else {
				_card { ProgressView() }
			}

		case .signing:
			_card {
				VStack(spacing: 14) {
					_PreparingAnimation(accent: accent)
					Text(.localized("Signing update…")).font(.headline)
				}
				.padding(.vertical, 4)
			}

		case .installing:
			_card {
				VStack(spacing: 14) {
					_PreparingAnimation(accent: accent)
					Text(.localized("Preparing install…")).font(.headline)
					Text(.localized("Tap Install on the prompt. injecy will close to finish updating — reopen it after."))
						.font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
				}
				.padding(.vertical, 4)
			}

		case .downloaded:
			_card {
				VStack(spacing: 10) {
					Image(systemName: "checkmark.seal.fill").font(.largeTitle).foregroundStyle(.green)
					Text(.localized("Update downloaded")).font(.headline)
					Text(.localized("It will be signed with your certificate and installed over the current version."))
						.font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
					Button { updater.install() } label: { _button(.localized("Install Update")) }
				}
			}

		case .failed(let msg):
			_card {
				VStack(spacing: 10) {
					Label(.localized("Update failed"), systemImage: "exclamationmark.triangle.fill")
						.foregroundStyle(.orange)
					Text(msg).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
					Button(.localized("Try Again")) { updater.check(manual: true) }
						.font(.subheadline.weight(.semibold))
				}
			}
		}
	}

	private func _releaseCard(_ r: AppUpdater.Release) -> some View {
		_card {
			VStack(alignment: .leading, spacing: 12) {
				HStack {
					VStack(alignment: .leading, spacing: 2) {
						Text(.localized("Update available")).font(.headline)
						Text("v\(r.version) (\(r.build))").font(.subheadline).foregroundStyle(.secondary)
					}
					Spacer()
					if r.force {
						Text(.localized("Required")).font(.caption2.weight(.bold))
							.padding(.horizontal, 8).padding(.vertical, 4)
							.background(.red.opacity(0.15), in: Capsule()).foregroundStyle(.red)
					}
				}
				if !r.changelog.isEmpty {
					Text(.localized("What's New")).font(.subheadline.weight(.semibold))
					Text(r.changelog).font(.subheadline).foregroundStyle(.primary.opacity(0.85))
						.frame(maxWidth: .infinity, alignment: .leading)
				}
				_downloadControl(r)
			}
		}
	}

	/// The "Download Update" button that smoothly morphs into an in-place progress bar
	/// (real bytes-downloaded fraction), then a "Verifying…" fill.
	private func _downloadControl(_ r: AppUpdater.Release) -> some View {
		let state: (fraction: Double, label: String, busy: Bool) = {
			switch updater.phase {
			case .downloading(let p):
				return (max(0.02, p), "\(String.localized("Downloading…")) \(Int((p * 100).rounded()))%", true)
			case .verifying:
				return (1.0, .localized("Verifying…"), true)
			default:
				return (0, .localized("Download Update"), false)
			}
		}()

		return Button {
			if !state.busy { updater.download(r) }
		} label: {
			ZStack {
				Capsule().fill(accent)
				GeometryReader { geo in
					Rectangle()
						.fill(.white.opacity(0.30))
						.frame(width: geo.size.width * (state.busy ? state.fraction : 0))
						.animation(.linear(duration: 0.25), value: state.fraction)
				}
				Text(state.label)
					.font(.headline.weight(.semibold))
					.foregroundStyle(.white)
					.contentTransition(.opacity)
			}
			.frame(height: 52)
			.clipShape(Capsule())
			.contentShape(Capsule())
		}
		.buttonStyle(.plain)
		.disabled(state.busy)
		.animation(.smooth(duration: 0.3), value: state.busy)
	}

	private func _button(_ title: String) -> some View {
		Text(title).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
			.background(accent, in: Capsule()).foregroundStyle(.white)
	}

	private func _card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
		content()
			.frame(maxWidth: .infinity)
			.padding(16)
			.background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
	}
}

// MARK: - Animated "working" indicator (rotating gradient ring + pulsing glyph)

private struct _PreparingAnimation: View {
	let accent: Color
	@State private var _rotate = false
	@State private var _pulse = false

	var body: some View {
		ZStack {
			Circle()
				.fill(accent.opacity(0.12))
				.frame(width: 72, height: 72)
			Circle()
				.trim(from: 0, to: 0.72)
				.stroke(
					AngularGradient(colors: [accent.opacity(0.0), accent.opacity(0.5), accent], center: .center),
					style: StrokeStyle(lineWidth: 5, lineCap: .round)
				)
				.frame(width: 62, height: 62)
				.rotationEffect(.degrees(_rotate ? 360 : 0))
			Image(systemName: "arrow.down.app.fill")
				.font(.system(size: 24, weight: .semibold))
				.foregroundStyle(accent)
				.scaleEffect(_pulse ? 1.12 : 0.9)
				.shadow(color: accent.opacity(0.5), radius: _pulse ? 10 : 3)
		}
		.onAppear {
			withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) { _rotate = true }
			withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) { _pulse = true }
		}
	}

}

// MARK: - What's New (shown once after an in-app update)

struct WhatsNewInfo: Identifiable {
	let id = UUID()
	let version: String
	let changelog: String
}

struct WhatsNewView: View {
	let info: WhatsNewInfo
	@Environment(\.dismiss) private var dismiss

	private var accent: Color {
		Color(hex: UserDefaults.standard.string(forKey: "Feather.userTintColor") ?? "#848ef9")
	}

	var body: some View {
		VStack(spacing: 22) {
			Spacer(minLength: 12)
			ZStack {
				Circle().fill(accent.opacity(0.15)).frame(width: 92, height: 92)
				Image(systemName: "sparkles").font(.system(size: 40)).foregroundStyle(accent)
			}
			VStack(spacing: 6) {
				Text(.localized("What's New")).font(.largeTitle.bold())
				Text("injecy \(info.version)").font(.subheadline).foregroundStyle(.secondary)
			}
			ScrollView {
				Text(info.changelog.isEmpty ? .localized("Bug fixes and improvements.") : info.changelog)
					.font(.body).foregroundStyle(.primary.opacity(0.9))
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding()
			}
			.frame(maxHeight: 260)
			.background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
			Spacer(minLength: 8)
			Button { dismiss() } label: {
				Text(.localized("Continue"))
					.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
					.background(accent, in: Capsule()).foregroundStyle(.white)
			}
		}
		.padding(24)
		.interactiveDismissDisabled(false)
	}
}
