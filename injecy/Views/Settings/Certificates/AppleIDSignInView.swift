//
//  AppleIDSignInView.swift
//  injecy
//
//  Beta: sign in with an Apple ID to issue a free 7-day signing certificate.
//

import SwiftUI

struct AppleIDSignInView: View {
	@Environment(\.dismiss) private var dismiss
	@ObservedObject private var manager = AppleIDManager.shared

	/// Bundle id / name of the app being signed, used when issuing the free profile.
	var bundleID: String? = nil
	var appName: String? = nil

	@State private var _appleID = ""
	@State private var _password = ""
	@State private var _code = ""

	private var accent: Color {
		Color(hex: UserDefaults.standard.string(forKey: "Feather.userTintColor") ?? "#848ef9")
	}

	var body: some View {
		NavigationStack {
			ZStack {
				Color(.systemGroupedBackground).ignoresSafeArea()
				ScrollView {
					VStack(spacing: 20) {
						_header
						_content
					}
					.padding()
				}
				.scrollDismissesKeyboard(.interactively)
			}
			.navigationTitle(.localized("Apple ID"))
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					Button { dismiss() } label: { Image(systemName: "xmark").font(.subheadline.weight(.semibold)) }
				}
			}
		}
		.tint(accent)
	}

	// MARK: Header
	private var _header: some View {
		VStack(spacing: 10) {
			ZStack {
				Circle().fill(accent.opacity(0.15)).frame(width: 92, height: 92)
				Image(systemName: "person.badge.key.fill").font(.system(size: 38)).foregroundStyle(accent)
			}
			Text(.localized("Sign in with Apple ID"))
				.font(.title2.bold())
			Text(.localized("Issues a free certificate (valid 7 days) so you can sign apps without your own .p12."))
				.font(.subheadline).foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
			Text(.localized("Beta · your Apple ID stays on this device."))
				.font(.caption2).foregroundStyle(.tertiary)
		}
	}

	// MARK: Content by state
	@ViewBuilder
	private var _content: some View {
		switch manager.state {
		case .needsTwoFactor:
			_twoFactor
		case .signedIn(let team):
			_signedIn(team)
		default:
			_credentials
		}
	}

	private var _credentials: some View {
		VStack(spacing: 14) {
			VStack(spacing: 10) {
				TextField(.localized("Apple ID email"), text: $_appleID)
					.textContentType(.username).keyboardType(.emailAddress)
					.textInputAutocapitalization(.never).autocorrectionDisabled()
					.padding(12).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
				SecureField(.localized("Password"), text: $_password)
					.textContentType(.password)
					.padding(12).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
			}

			if case .failed(let msg) = manager.state {
				Text(msg).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
			}

			Button {
				manager.signIn(appleID: _appleID, password: _password)
			} label: {
				_buttonLabel(manager.state == .authenticating ? .localized("Signing in…") : .localized("Sign In"),
				             busy: manager.state == .authenticating)
			}
			.disabled(_appleID.isEmpty || _password.isEmpty || manager.state == .authenticating)
		}
	}

	private var _twoFactor: some View {
		VStack(spacing: 14) {
			Text(.localized("Enter the 6-digit verification code sent to your trusted devices."))
				.font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
			TextField(.localized("Verification code"), text: $_code)
				.keyboardType(.numberPad).multilineTextAlignment(.center)
				.font(.title2.monospacedDigit())
				.padding(12).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
			Button {
				manager.submitTwoFactor(code: _code)
			} label: {
				_buttonLabel(.localized("Verify"), busy: false)
			}
			.disabled(_code.count < 6)
			Button(.localized("Cancel")) { manager.cancelTwoFactor(); _code = "" }
				.font(.subheadline).foregroundStyle(.secondary)
		}
	}

	@ViewBuilder
	private func _signedIn(_ team: String) -> some View {
		VStack(spacing: 14) {
			Image(systemName: "checkmark.seal.fill").font(.system(size: 44)).foregroundStyle(.green)
			Text(.localized("Signed in")).font(.headline)
			Text(team).font(.subheadline).foregroundStyle(.secondary)

			switch manager.issueState {
			case .working(let step):
				HStack(spacing: 8) { ProgressView(); Text(step).font(.subheadline).foregroundStyle(.secondary) }
					.padding(.top, 4)

			case .issued(let bundleID, _):
				VStack(spacing: 8) {
					Image(systemName: "checkmark.circle.fill").font(.system(size: 34)).foregroundStyle(.green)
					Text(.localized("Free certificate ready")).font(.headline)
					Text(.localized("Valid for 7 days. The app will be signed as:"))
						.font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
					Text(bundleID).font(.caption.monospaced()).foregroundStyle(.primary)
						.padding(.horizontal, 10).padding(.vertical, 5)
						.background(accent.opacity(0.12), in: Capsule())
				}
				Button { dismiss() } label: { _buttonLabel(.localized("Done"), busy: false) }

			case .failed(let msg):
				Text(msg).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
				Button {
					manager.issueFreeCertificate(forBundleID: bundleID, appName: appName)
				} label: { _buttonLabel(.localized("Try Again"), busy: false) }

			case .idle:
				Text(.localized("Issue a free certificate to sign this app for 7 days."))
					.font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
				Button {
					manager.issueFreeCertificate(forBundleID: bundleID, appName: appName)
				} label: { _buttonLabel(.localized("Issue Free Certificate"), busy: false) }
			}
		}
	}

	private func _buttonLabel(_ title: String, busy: Bool) -> some View {
		HStack(spacing: 8) {
			if busy { ProgressView().tint(.white) }
			Text(title)
		}
		.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
		.background(accent, in: Capsule()).foregroundStyle(.white)
	}
}
