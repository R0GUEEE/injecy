//
//  OnboardingView.swift
//  injecy
//
//  First-run welcome: what injecy is + import a signing certificate.
//  Uses the app's user tint colour throughout to match the rest of the UI.
//

import SwiftUI

struct OnboardingView: View {
	var onFinish: () -> Void

	@State private var _page = 0
	@State private var _isCertPresenting = false
	@FetchRequest(
		entity: CertificatePair.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)]
	) private var _certificates: FetchedResults<CertificatePair>

	/// The app's chosen tint (same one applied to the window), so onboarding matches the app.
	private var accent: Color {
		Color(hex: UserDefaults.standard.string(forKey: "Feather.userTintColor") ?? "#848ef9")
	}

	private let _pages: [OnboardPage] = [
		.init(icon: "", useAppIcon: true,
		      title: "Welcome to injecy",
		      subtitle: "Sign and install apps, and inject tweaks into them — right on your device, no jailbreak."),
		.init(icon: "square.grid.2x2.fill",
		      title: "A library of tweaks",
		      subtitle: "Browse the marketplace, save tweaks to your library, or import your own — then add them to any app."),
		.init(icon: "iphone.and.arrow.forward",
		      title: "Two ways to install",
		      subtitle: "Server is quick and works anywhere. IDevice needs a pairing file once, but can update injecy itself. Choose either later in Settings → Installation."),
		.init(icon: "checkmark.seal.fill",
		      title: "Sign with your certificate",
		      subtitle: "To sign apps you need a certificate — a .p12 key and a .mobileprovision profile. Import yours to get going."),
	]

	private var _hasCert: Bool { !_certificates.isEmpty }
	private var _isLast: Bool { _page == _pages.count - 1 }

	var body: some View {
		ZStack {
			LinearGradient(
				colors: [accent.opacity(0.28), accent.opacity(0.05), .clear],
				startPoint: .top, endPoint: .center
			)
			.ignoresSafeArea()

			VStack(spacing: 0) {
				TabView(selection: $_page) {
					ForEach(Array(_pages.enumerated()), id: \.offset) { index, page in
						_pageView(page).tag(index)
					}
				}
				.tabViewStyle(.page(indexDisplayMode: .never))
				.animation(.smooth, value: _page)

				_dots
				_controls
			}
		}
		.tint(accent)
		.sheet(isPresented: $_isCertPresenting) { CertificatesAddView() }
	}

	// MARK: Page
	private func _pageView(_ page: OnboardPage) -> some View {
		VStack(spacing: 28) {
			Spacer()
			_AnimatedIcon(systemName: page.icon, useAppIcon: page.useAppIcon, tint: accent)
			VStack(spacing: 12) {
				Text(.localized(page.title))
					.font(.largeTitle.bold())
					.multilineTextAlignment(.center)
				Text(.localized(page.subtitle))
					.font(.body)
					.foregroundStyle(.secondary)
					.multilineTextAlignment(.center)
					.padding(.horizontal, 32)
			}
			Spacer()
		}
		.padding()
	}

	// MARK: Dots
	private var _dots: some View {
		HStack(spacing: 8) {
			ForEach(_pages.indices, id: \.self) { i in
				Capsule()
					.fill(i == _page ? accent : Color.secondary.opacity(0.3))
					.frame(width: i == _page ? 22 : 7, height: 7)
					.animation(.smooth(duration: 0.3), value: _page)
			}
		}
		.padding(.bottom, 22)
	}

	// MARK: Controls
	@ViewBuilder
	private var _controls: some View {
		VStack(spacing: 12) {
			if _isLast {
				if _hasCert {
					_primary("Get Started", icon: "checkmark") { onFinish() }
				} else {
					_primary("Import Certificate", icon: "square.and.arrow.down") {
						_isCertPresenting = true
					}
					Button(.localized("Skip for now")) { onFinish() }
						.font(.subheadline.weight(.medium))
						.foregroundStyle(.secondary)
				}
			} else {
				_primary("Continue", icon: "arrow.right") {
					withAnimation(.smooth) { _page += 1 }
				}
			}
		}
		.padding(.horizontal, 24)
		.padding(.bottom, 28)
		.animation(.smooth(duration: 0.3), value: _hasCert)
		.animation(.smooth(duration: 0.3), value: _isLast)
		.onChange(of: _hasCert) { has in
			if has, _isLast { onFinish() }
		}
	}

	private func _primary(_ title: String, icon: String, _ action: @escaping () -> Void) -> some View {
		Button(action: action) {
			HStack(spacing: 8) {
				Text(.localized(title))
				Image(systemName: icon)
			}
			.font(.headline)
			.frame(maxWidth: .infinity)
			.padding(.vertical, 16)
			.background(accent, in: Capsule())
			.foregroundStyle(.white)
			.shadow(color: accent.opacity(0.35), radius: 12, y: 6)
		}
		.buttonStyle(.plain)
	}
}

// MARK: - Page model
private struct OnboardPage {
	let icon: String
	var useAppIcon: Bool = false
	let title: String
	let subtitle: String
}

// MARK: - Animated icon
private struct _AnimatedIcon: View {
	let systemName: String
	var useAppIcon: Bool = false
	let tint: Color
	@State private var _show = false

	var body: some View {
		ZStack {
			Circle()
				.fill(tint.opacity(0.14))
				.frame(width: 168, height: 168)
				.scaleEffect(_show ? 1 : 0.6)
				.opacity(_show ? 1 : 0)

			if useAppIcon {
				FRAppIconView(size: 96)
					.clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
					.scaleEffect(_show ? 1 : 0.4)
					.opacity(_show ? 1 : 0)
					.rotationEffect(.degrees(_show ? 0 : -10))
			} else {
				Image(systemName: systemName)
					.font(.system(size: 70, weight: .semibold))
					.foregroundStyle(tint)
					.scaleEffect(_show ? 1 : 0.4)
					.opacity(_show ? 1 : 0)
					.rotationEffect(.degrees(_show ? 0 : -10))
			}
		}
		.onAppear {
			_show = false
			withAnimation(.spring(response: 0.6, dampingFraction: 0.62)) { _show = true }
		}
	}
}
