//
//  InjecyLiveActivity.swift
//  injecyWidgets
//
//  The Dynamic Island + Lock Screen presentation for a background job.
//

import SwiftUI
import WidgetKit
import ActivityKit

@available(iOS 16.2, *)
struct InjecyLiveActivity: Widget {
	var body: some WidgetConfiguration {
		ActivityConfiguration(for: InjecyActivityAttributes.self) { context in
			_LockScreenView(context: context)
				.activityBackgroundTint(Color.black.opacity(0.55))
				.activitySystemActionForegroundColor(.white)
		} dynamicIsland: { context in
			let accent = _accent(context.attributes.accentHex)
			let phase = context.state.phase
			let pct = Int((context.state.progress * 100).rounded())

			return DynamicIsland {
				DynamicIslandExpandedRegion(.leading) {
					_iconBadge(phase: phase, accent: accent)
				}
				DynamicIslandExpandedRegion(.trailing) {
					if !phase.isTerminal {
						Text("\(pct)%")
							.font(.system(.title3, design: .rounded).weight(.bold))
							.monospacedDigit()
							.foregroundStyle(accent)
					}
				}
				DynamicIslandExpandedRegion(.bottom) {
					VStack(alignment: .leading, spacing: 8) {
						HStack(spacing: 6) {
							Text(context.attributes.name)
								.font(.subheadline.weight(.semibold))
								.lineLimit(1)
							Spacer(minLength: 6)
							Text(context.state.statusText)
								.font(.caption)
								.foregroundStyle(.secondary)
								.lineLimit(1)
						}
						_bar(progress: phase.isTerminal ? 1 : context.state.progress, accent: accent)
					}
					.padding(.horizontal, 2)
					.padding(.top, 4)
				}
			} compactLeading: {
				Image(systemName: phase.symbol)
					.font(.system(size: 15, weight: .semibold))
					.foregroundStyle(accent)
			} compactTrailing: {
				if phase.isTerminal {
					Image(systemName: phase.symbol).foregroundStyle(accent)
				} else {
					_ProgressRing(progress: context.state.progress, accent: accent)
						.frame(width: 17, height: 17)
				}
			} minimal: {
				if phase.isTerminal {
					Image(systemName: phase.symbol).foregroundStyle(accent)
				} else {
					_ProgressRing(progress: context.state.progress, accent: accent)
						.frame(width: 17, height: 17)
				}
			}
			.keylineTint(accent)
		}
	}

	// MARK: Helpers

	private func _iconBadge(phase: InjecyJobPhase, accent: Color) -> some View {
		ZStack {
			RoundedRectangle(cornerRadius: 10, style: .continuous)
				.fill(accent.opacity(0.20))
			Image(systemName: phase.symbol)
				.font(.system(size: 15, weight: .semibold))
				.foregroundStyle(accent)
		}
		.frame(width: 32, height: 32)
	}

	private func _bar(progress: Double, accent: Color) -> some View {
		GeometryReader { geo in
			ZStack(alignment: .leading) {
				Capsule().fill(accent.opacity(0.22))
				Capsule().fill(accent)
					.frame(width: max(6, geo.size.width * progress))
			}
		}
		.frame(height: 6)
	}

	private func _accent(_ hex: String?) -> Color {
		Color(hexString: hex ?? "") ?? Color(red: 0.52, green: 0.56, blue: 0.98)
	}
}

// MARK: - Lock Screen / banner

@available(iOS 16.2, *)
private struct _LockScreenView: View {
	let context: ActivityViewContext<InjecyActivityAttributes>

	var body: some View {
		let accent = Color(hexString: context.attributes.accentHex ?? "") ?? Color(red: 0.52, green: 0.56, blue: 0.98)
		let phase = context.state.phase
		let pct = Int((context.state.progress * 100).rounded())

		HStack(spacing: 14) {
			ZStack {
				RoundedRectangle(cornerRadius: 14, style: .continuous)
					.fill(accent.opacity(0.20))
					.frame(width: 48, height: 48)
				Image(systemName: phase.symbol)
					.font(.system(size: 22, weight: .semibold))
					.foregroundStyle(accent)
			}

			VStack(alignment: .leading, spacing: 6) {
				HStack(alignment: .firstTextBaseline) {
					Text(context.attributes.name)
						.font(.subheadline.weight(.semibold))
						.lineLimit(1)
					Spacer(minLength: 8)
					if !phase.isTerminal {
						Text("\(pct)%")
							.font(.system(.subheadline, design: .rounded).weight(.bold))
							.monospacedDigit()
							.foregroundStyle(accent)
					}
				}
				if phase.isTerminal {
					Text(context.state.statusText)
						.font(.caption)
						.foregroundStyle(.secondary)
				} else {
					GeometryReader { geo in
						ZStack(alignment: .leading) {
							Capsule().fill(accent.opacity(0.22))
							Capsule().fill(accent)
								.frame(width: max(6, geo.size.width * context.state.progress))
						}
					}
					.frame(height: 6)
					Text(context.state.statusText)
						.font(.caption)
						.foregroundStyle(.secondary)
						.lineLimit(1)
				}
			}
		}
		.padding(16)
	}
}

// MARK: - Progress ring (compact / minimal)

@available(iOS 16.2, *)
private struct _ProgressRing: View {
	let progress: Double
	let accent: Color

	var body: some View {
		ZStack {
			Circle().stroke(accent.opacity(0.25), lineWidth: 2.6)
			Circle()
				.trim(from: 0, to: max(0.02, min(1, progress)))
				.stroke(accent, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
				.rotationEffect(.degrees(-90))
		}
		.padding(1.4)
	}
}

// MARK: - Color(hex) for the widget target

extension Color {
	init?(hexString: String) {
		var s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
		s = s.replacingOccurrences(of: "#", with: "")
		guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
		self.init(
			red: Double((v & 0xFF0000) >> 16) / 255,
			green: Double((v & 0x00FF00) >> 8) / 255,
			blue: Double(v & 0x0000FF) / 255
		)
	}
}