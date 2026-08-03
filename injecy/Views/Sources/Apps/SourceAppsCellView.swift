//
//  SourceAppsCellView.swift
//  Feather
//
//  Created by samara on 3.05.2025.
//

import SwiftUI
import AltSourceKit
import NimbleViews
import Combine
import NukeUI

// MARK: - View
struct SourceAppsCellView: View {
	@AppStorage("Feather.storeCellAppearance") private var _storeCellAppearance: Int = 0

	var source: ASRepository
	var app: ASRepository.App

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 14) {
				_icon
					.overlay(alignment: .bottomTrailing) {
						if let iconURL = source.currentIconURL {
							LazyImage(url: iconURL) { state in
								if let image = state.image {
									image.appIconStyle(size: 20, isCircle: true,
									                   background: Color(uiColor: .secondarySystemBackground))
										.offset(x: 5, y: 5)
								}
							}
						}
					}

				VStack(alignment: .leading, spacing: 3) {
					Text(app.currentName)
						.font(.headline)
						.lineLimit(1)
					Text(Self.appDescription(app: app))
						.font(.subheadline)
						.foregroundStyle(.secondary)
						.lineLimit(2)

					if let updated = Self.relativeUpdated(app: app) {
						HStack(spacing: 4) {
							Image(systemName: "clock.arrow.circlepath").font(.system(size: 9))
							Text("\(String.localized("Updated")) \(updated)")
								.font(.caption2.weight(.medium))
								.lineLimit(1)
						}
						.fixedSize()
						.foregroundStyle(.secondary)
						.padding(.horizontal, 8).padding(.vertical, 3)
						.background(Color.secondary.opacity(0.12), in: Capsule())
						.padding(.top, 1)
					}
				}

				Spacer(minLength: 8)
				DownloadButtonView(app: app)
			}

			if
				_storeCellAppearance != 0,
				let desc = app.localizedDescription
			{
				Text(desc)
					.frame(maxWidth: .infinity, alignment: .leading)
					.font(.subheadline)
					.foregroundStyle(.secondary)
			}
		}
	}

	@ViewBuilder
	private var _icon: some View {
		if let iconURL = app.iconURL {
			LazyImage(url: iconURL) { state in
				if let image = state.image {
					image.appIconStyle(size: 56, isCircle: false)
				} else {
					_standardIcon
				}
			}
		} else {
			_standardIcon
		}
	}

	private var _standardIcon: some View {
		Image("App_Unknown").appIconStyle(size: 56, isCircle: false)
	}

	static func appDescription(app: ASRepository.App) -> String {
		let optionalComponents: [String?] = [
			app.currentVersion,
			app.currentDescription ?? .localized("An awesome application")
		]

		let components: [String] = optionalComponents.compactMap { value in
			guard
				let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
				!trimmed.isEmpty
			else {
				return nil
			}
			return trimmed
		}

		return components.joined(separator: " • ")
	}

	/// A cached "N ago" formatter (e.g. "2 days ago", "1 week ago").
	private static let _relFormatter: RelativeDateTimeFormatter = {
		let f = RelativeDateTimeFormatter()
		f.unitsStyle = .full
		return f
	}()

	static func relativeUpdated(app: ASRepository.App) -> String? {
		guard let date = app.currentDate?.date else { return nil }
		return _relFormatter.localizedString(for: date, relativeTo: Date())
	}
}
