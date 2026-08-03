//
//  ToastView.swift
//  injecy
//
//  Lightweight top banner for transient success/info messages (e.g. tweak imports),
//  with an optional action button — replaces intrusive system alerts.
//

import SwiftUI

// MARK: - Manager

@MainActor
final class ToastManager: ObservableObject {
	static let shared = ToastManager()
	private init() {}

	@Published var current: Toast?
	private var _dismissTask: Task<Void, Never>?

	struct Toast: Identifiable, Equatable {
		let id = UUID()
		var title: String
		var subtitle: String?
		var systemImage: String
		var tint: Color
		var actionTitle: String?
		var action: (() -> Void)?

		static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }
	}

	func show(
		title: String,
		subtitle: String? = nil,
		systemImage: String = "checkmark.circle.fill",
		tint: Color = .green,
		actionTitle: String? = nil,
		action: (() -> Void)? = nil
	) {
		let toast = Toast(title: title, subtitle: subtitle, systemImage: systemImage,
		                  tint: tint, actionTitle: actionTitle, action: action)
		withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
			current = toast
		}
		_dismissTask?.cancel()
		_dismissTask = Task { [weak self] in
			try? await Task.sleep(nanoseconds: 4_200_000_000)
			guard !Task.isCancelled else { return }
			self?.dismiss()
		}
	}

	func dismiss() {
		_dismissTask?.cancel()
		withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
			current = nil
		}
	}
}

// MARK: - Overlay

struct ToastOverlay: View {
	@ObservedObject private var manager = ToastManager.shared

	var body: some View {
		VStack {
			if let toast = manager.current {
				_banner(toast)
					.padding(.horizontal, 14)
					.transition(.move(edge: .top).combined(with: .opacity))
			}
			Spacer(minLength: 0)
		}
		.animation(.spring(response: 0.42, dampingFraction: 0.82), value: manager.current)
	}

	private func _banner(_ toast: ToastManager.Toast) -> some View {
		HStack(spacing: 12) {
			Image(systemName: toast.systemImage)
				.font(.title3.weight(.semibold))
				.foregroundStyle(toast.tint)

			VStack(alignment: .leading, spacing: 1) {
				Text(toast.title)
					.font(.subheadline.weight(.semibold))
					.lineLimit(1)
				if let subtitle = toast.subtitle {
					Text(subtitle)
						.font(.caption)
						.foregroundStyle(.secondary)
						.lineLimit(1)
				}
			}

			Spacer(minLength: 8)

			if let actionTitle = toast.actionTitle, let action = toast.action {
				Button {
					action()
					ToastManager.shared.dismiss()
				} label: {
					Text(actionTitle)
						.font(.subheadline.weight(.semibold))
						.foregroundStyle(toast.tint)
						.padding(.horizontal, 12).padding(.vertical, 6)
						.background(toast.tint.opacity(0.14), in: Capsule())
				}
				.buttonStyle(.plain)
			}
		}
		.padding(.horizontal, 14).padding(.vertical, 12)
		.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: 20, style: .continuous)
				.strokeBorder(.primary.opacity(0.08), lineWidth: 1)
		)
		.shadow(color: .black.opacity(0.18), radius: 18, y: 8)
		.contentShape(Rectangle())
		.onTapGesture { ToastManager.shared.dismiss() }
	}
}