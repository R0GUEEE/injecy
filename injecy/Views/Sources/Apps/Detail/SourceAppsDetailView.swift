//
//  SourceAppsDetailView.swift
//  Feather
//
//  Created by samsam on 7/25/25.
//

import SwiftUI
import Combine
import AltSourceKit
import NimbleViews
import NukeUI

// MARK: - SourceAppsDetailView
struct SourceAppsDetailView: View {
	@ObservedObject var downloadManager = DownloadManager.shared
	@State private var _downloadProgress: Double = 0
	@State var cancellable: AnyCancellable? // Combine
	@State private var _isScreenshotPreviewPresented: Bool = false
	@State private var _selectedScreenshotIndex: Int = 0
	
	var currentDownload: Download? {
		downloadManager.getDownload(by: app.currentUniqueId)
	}
	
	var source: ASRepository
	var app: ASRepository.App
	
	var body: some View {
		ScrollView {
			if #available(iOS 18, *) {
				_header().flexibleHeaderContent()
			}
			
			VStack(alignment: .leading, spacing: 10) {
				HStack(alignment: .center, spacing: 14) {
					Group {
						if let iconURL = app.iconURL {
							LazyImage(url: iconURL) { state in
								if let image = state.image {
									image.appIconStyle(size: 96, isCircle: false)
								} else {
									standardIcon
								}
							}
						} else {
							standardIcon
						}
					}
					.shadow(color: .black.opacity(0.22), radius: 12, y: 6)

					VStack(alignment: .leading, spacing: 5) {
						Text(app.currentName)
							.font(.title3.bold())
							.foregroundColor(.primary)
							.lineLimit(2)
						Text(app.developer ?? app.currentDescription ?? .localized("An awesome application"))
							.font(.subheadline)
							.foregroundColor(.secondary)
							.lineLimit(2)

						if let updated = SourceAppsCellView.relativeUpdated(app: app) {
							_metaPill("\(String.localized("Updated")) \(updated)", "clock.arrow.circlepath")
								.padding(.top, 1)
						}
					}

					Spacer(minLength: 8)

					DownloadButtonView(app: app)
				}
				.padding(16)
				.background(
					RoundedRectangle(cornerRadius: 24, style: .continuous)
						.fill(.ultraThinMaterial)
				)
				.overlay(
					RoundedRectangle(cornerRadius: 24, style: .continuous)
						.strokeBorder(.primary.opacity(0.06), lineWidth: 1)
				)
				
				_infoPills(app: app)
					.padding(.top, 2)
				Divider()

				if let screenshotURLs = app.screenshotURLs {
					NBSection(.localized("Screenshots")) {
						_screenshots(screenshotURLs: screenshotURLs)
					}
                    
					Divider()
				}
				
				if
					let currentVer = app.currentVersion,
					let whatsNewDesc = app.currentAppVersion?.localizedDescription
				{
					NBSection(.localized("What's New")) {
						AppVersionInfo(
							version: currentVer,
							date: app.currentDate?.date,
							description: whatsNewDesc
						)
						if let versions = app.versions {
							NavigationLink(
								destination: VersionHistoryView(app: app, versions: versions)
									.navigationTitle(.localized("Version History"))
									.navigationBarTitleDisplayMode(.large)
							) {
								Text(.localized("Version History"))
							}
						}
					}
					
					Divider()
				}
				
				if let appDesc = app.localizedDescription {
					NBSection(.localized("Description")) {
						VStack(alignment: .leading, spacing: 2) {
							ExpandableText(text: appDesc, lineLimit: 3)
						}
						.frame(maxWidth: .infinity, alignment: .leading)
					}
					
					Divider()
				}
                
				NBSection(.localized("Information")) {
					let rows = _informationRows()
					VStack(spacing: 0) {
						ForEach(rows.indices, id: \.self) { i in
							_infoRow(icon: rows[i].icon, title: rows[i].title, value: rows[i].value, mono: rows[i].mono)
							if i < rows.count - 1 {
								Divider().padding(.leading, 46)
							}
						}
					}
					.background(
						RoundedRectangle(cornerRadius: 18, style: .continuous)
							.fill(Color(.secondarySystemBackground))
					)
				}
				
				if let appPermissions = app.appPermissions {
					NBSection(.localized("Permissions")) {
						Group {
							if let entitlements = appPermissions.entitlements {
								NBTitleWithSubtitleView(
									title: .localized("Entitlements"),
									subtitle: entitlements.map(\.name).joined(separator: "\n")
								)
							} else {
								Text(.localized("No Entitlements listed."))
									.font(.subheadline)
									.foregroundStyle(.secondary)
							}
							if let privacyItems = appPermissions.privacy {
								ForEach(privacyItems, id: \.self) { item in
									NBTitleWithSubtitleView(
										title: item.name,
										subtitle: item.usageDescription
									)
								}
							} else {
								Text(.localized("No Privacy Permissions listed."))
									.font(.subheadline)
									.foregroundStyle(.secondary)
							}
						}
						.padding()
						.background(
							RoundedRectangle(cornerRadius: 18, style: .continuous)
								.fill(Color(.quaternarySystemFill))
						)
					}
				}
			}
			.padding([.horizontal, .bottom])
			.padding(.top, {
				if #available(iOS 18, *) {
					8
				} else {
					0
				}
			}())
		}
		.flexibleHeaderScrollView()
		.shouldSetInset()
		.toolbar {
			NBToolbarButton(
				systemImage: "square.and.arrow.up",
				placement: .topBarTrailing
			) {
				let sharedString = """
				\(app.currentName) - \(app.currentVersion ?? "0")
				\(app.currentDescription ?? .localized("An awesome application"))
				---
				\(source.website?.absoluteString ?? source.name ?? "")
				"""
				UIActivityViewController.show(activityItems: [sharedString])
			}
		}
		.fullScreenCover(isPresented: $_isScreenshotPreviewPresented) {
			if let screenshotURLs = app.screenshotURLs {
				ScreenshotPreviewView(
					screenshotURLs: screenshotURLs,
					initialIndex: _selectedScreenshotIndex
				)
			}
		}
	}
	
	var standardIcon: some View {
		Image("App_Unknown").appIconStyle(size: 104, isCircle: false)
	}

	private func _metaPill(_ text: String, _ systemImage: String) -> some View {
		HStack(spacing: 3) {
			Image(systemName: systemImage).font(.system(size: 9))
			Text(text).font(.caption2.weight(.semibold)).lineLimit(1)
		}
		.fixedSize()
		.foregroundStyle(.secondary)
		.padding(.horizontal, 8).padding(.vertical, 3)
		.background(Color.secondary.opacity(0.12), in: Capsule())
	}
	
	var standardHeader: some View {
		Image("App_Unknown")
			.resizable()
			.aspectRatio(contentMode: .fill)
			.frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
			.clipped()
	}
}

// MARK: - SourceAppsDetailView (Extension): Builders
extension SourceAppsDetailView {
	@available(iOS 18.0, *)
	@ViewBuilder
	private func _header() -> some View {
		ZStack {
			if let iconURL = source.currentIconURL {
				LazyImage(url: iconURL) { state in
					if let image = state.image {
						image.resizable()
							.aspectRatio(contentMode: .fill)
							.frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
							.clipped()
					} else {
						standardHeader
					}
				}
			} else {
				standardHeader
			}
			
			NBVariableBlurView()
				.rotationEffect(.degrees(-180))
				.overlay(
					LinearGradient(
						gradient: Gradient(colors: [
							Color.black.opacity(0.8),
							Color.black.opacity(0)
						]),
						startPoint: .top,
						endPoint: .bottom
					)
				)
		}
	}
	
	@ViewBuilder
	private func _infoPills(app: ASRepository.App) -> some View {
		let pillItems = _buildPills(from: app)
		HStack(spacing: 6) {
			ForEach(pillItems.indices, id: \.hashValue) { index in
				let pill = pillItems[index]
				NBPillView(
					title: pill.title,
					icon: pill.icon,
					color: pill.color,
					index: index,
					count: pillItems.count
				)
			}
		}
	}
	
	private func _buildPills(from app: ASRepository.App) -> [NBPillItem] {
		var pills: [NBPillItem] = []
		
		if let version = app.currentVersion {
			pills.append(NBPillItem(title: version, icon: "tag", color: Color.accentColor))
		}
		
		if let size = app.size {
			pills.append(NBPillItem(title: size.formattedByteCount, icon: "archivebox", color: .secondary))
		}
		
		return pills
	}
	
	private struct _InfoRowData {
		let icon: String
		let title: String
		let value: String
		var mono: Bool = false
	}

	private func _informationRows() -> [_InfoRowData] {
		var rows: [_InfoRowData] = []
		if let s = source.name {
			rows.append(.init(icon: "shippingbox", title: .localized("Source"), value: s))
		}
		if let d = app.developer {
			rows.append(.init(icon: "person", title: .localized("Developer"), value: d))
		}
		if let size = app.size {
			rows.append(.init(icon: "internaldrive", title: .localized("Size"), value: size.formattedByteCount))
		}
		if let c = app.category {
			rows.append(.init(icon: "square.grid.2x2", title: .localized("Category"), value: c.capitalized))
		}
		if let v = app.currentVersion {
			rows.append(.init(icon: "number", title: .localized("Version"), value: v))
		}
		if let date = app.currentDate?.date {
			rows.append(.init(icon: "clock", title: .localized("Updated"),
			                  value: DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)))
		}
		if let bundleId = app.id {
			rows.append(.init(icon: "barcode", title: .localized("Identifier"), value: bundleId, mono: true))
		}
		return rows
	}

	private func _infoRow(icon: String, title: String, value: String, mono: Bool) -> some View {
		HStack(spacing: 12) {
			Image(systemName: icon)
				.font(.footnote)
				.foregroundStyle(.secondary)
				.frame(width: 20)
			Text(title)
				.font(.subheadline)
				.foregroundStyle(.secondary)
			Spacer(minLength: 12)
			Text(value)
				.font(mono ? .footnote.monospaced() : .subheadline)
				.foregroundStyle(.primary)
				.multilineTextAlignment(.trailing)
				.lineLimit(mono ? 1 : 2)
				.truncationMode(mono ? .middle : .tail)
				.textSelection(.enabled)
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 12)
	}

	@ViewBuilder
	private func _screenshots(screenshotURLs: [URL]) -> some View {
		ScrollView(.horizontal, showsIndicators: false) {
			HStack(spacing: 12) {
				ForEach(screenshotURLs.indices, id: \.self) { index in
					let url = screenshotURLs[index]
					LazyImage(url: url) { state in
						if let image = state.image {
							image
								.resizable()
								.aspectRatio(contentMode: .fit)
								.frame(
									maxWidth: UIScreen.main.bounds.width - 32,
									maxHeight: 400
								)
								.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
								.overlay {
									RoundedRectangle(cornerRadius: 16, style: .continuous)
										.strokeBorder(.gray.opacity(0.3), lineWidth: 1)
								}
								.onTapGesture {
									_selectedScreenshotIndex = index
									_isScreenshotPreviewPresented = true
								}
						}
					}
				}
			}
			.padding(.horizontal)
			.compatScrollTargetLayout()
		}
		.compatScrollTargetBehavior()
		.padding(.horizontal, -16)
	}
}
