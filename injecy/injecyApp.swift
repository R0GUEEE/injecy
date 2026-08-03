//
//  injecyApp.swift
//  injecy
//
//  IPA signing + tweak library, on-device. Built on the Feather engine.
//

import SwiftUI
import Nuke
import IDeviceSwift
import OSLog

@main
struct injecyApp: App {
	@UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

	let heartbeat = HeartbeatManager.shared

	@StateObject var downloadManager = DownloadManager.shared
	@StateObject var deepLink = DeepLinkRouter.shared
	let storage = Storage.shared

	@AppStorage("injecy.didOnboardV1") private var _didOnboard = false
	@State private var _whatsNew: WhatsNewInfo?

	@ObservedObject private var _updater = AppUpdater.shared
	@State private var _showUpdate = false
	@State private var _updateDismissed = false

	private var _accent: Color {
		Color(hex: UserDefaults.standard.string(forKey: "Feather.userTintColor") ?? "#848ef9")
	}

	/// A dismissible top banner shown when an app update is available; tap → update panel.
	@ViewBuilder private var _updateBanner: some View {
		if let r = _updater.available, !_updateDismissed, !_showUpdate, _didOnboard {
			HStack(spacing: 11) {
				Image(systemName: "arrow.down.app.fill").font(.title3)
				VStack(alignment: .leading, spacing: 1) {
					Text(.localized("Update available")).font(.subheadline.weight(.semibold))
					Text("injecy \(r.version)").font(.caption).foregroundStyle(.white.opacity(0.85))
				}
				Spacer(minLength: 8)
				Text(.localized("Update")).font(.caption.weight(.bold))
					.padding(.horizontal, 12).padding(.vertical, 6)
					.background(.white.opacity(0.22), in: Capsule())
				Button { withAnimation(.smooth) { _updateDismissed = true } } label: {
					Image(systemName: "xmark").font(.caption.weight(.bold)).padding(6)
				}
			}
			.foregroundStyle(.white)
			.padding(.horizontal, 14).padding(.vertical, 11)
			.background(
				LinearGradient(colors: [_accent, _accent.opacity(0.82)], startPoint: .leading, endPoint: .trailing),
				in: RoundedRectangle(cornerRadius: 16, style: .continuous)
			)
			.shadow(color: _accent.opacity(0.4), radius: 12, y: 5)
			.padding(.horizontal, 12)
			.contentShape(Rectangle())
			.onTapGesture { _showUpdate = true }
			.transition(.move(edge: .top).combined(with: .opacity))
		}
	}

	/// Show a "What's New" sheet once, right after an in-app update lands on the new build.
	private func _checkWhatsNew() {
		guard
			let payload = UserDefaults.standard.dictionary(forKey: "injecy.pendingWhatsNew") as? [String: String],
			let build = Int(payload["build"] ?? ""),
			build == AppUpdater.shared.currentBuild
		else { return }
		UserDefaults.standard.removeObject(forKey: "injecy.pendingWhatsNew")
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
			_whatsNew = WhatsNewInfo(version: payload["version"] ?? "", changelog: payload["changelog"] ?? "")
		}
	}

	var body: some Scene {
		WindowGroup {
			VStack {
				// Import/download progress is shown inside the Library tab ("Importing"
				// section); the top header bar was removed to avoid a duplicate.
				VariedTabbarView()
					.environment(\.managedObjectContext, storage.context)
					.onOpenURL(perform: _handleURL)
					.transition(.move(edge: .top).combined(with: .opacity))
					.fullScreenCover(isPresented: Binding(
						get: { !_didOnboard },
						set: { if $0 == false { _didOnboard = true } }
					)) {
						OnboardingView(onFinish: { _didOnboard = true })
							.environment(\.managedObjectContext, storage.context)
					}
				.fullScreenCover(item: $deepLink.presentedTweak) { tweak in
					TweakDetailView(tweak: tweak)
				}
			}
			.overlay(ToastOverlay())
			.overlay(alignment: .top) {
				_updateBanner
					.animation(.spring(response: 0.5, dampingFraction: 0.8), value: _updater.available != nil)
					.animation(.smooth, value: _updateDismissed)
			}
			.sheet(item: $_whatsNew) { info in
				WhatsNewView(info: info).presentationDetents([.medium, .large])
			}
			.sheet(isPresented: $_showUpdate) { AppUpdateView() }
			.animation(.smooth, value: downloadManager.manualDownloads.description)
			.onReceive(NotificationCenter.default.publisher(for: .heartbeatInvalidHost)) { _ in
				DispatchQueue.main.async {
					UIAlertController.showAlertWithOk(
						title: "InvalidHostID",
						message: .localized("Your pairing file is invalid and is incompatible with your device, please import a valid pairing file.")
					)
				}
			}
			.onAppear {
				if let style = UIUserInterfaceStyle(rawValue: UserDefaults.standard.integer(forKey: "Feather.userInterfaceStyle")) {
					UIApplication.topViewController()?.view.window?.overrideUserInterfaceStyle = style
				}

				UIApplication.topViewController()?.view.window?.tintColor = UIColor(Color(hex: UserDefaults.standard.string(forKey: "Feather.userTintColor") ?? "#848ef9"))

				AppUpdater.shared.checkOnLaunch()
				_checkWhatsNew()
			}
		}
	}

	private func _handleURL(_ url: URL) {
		if url.scheme == "injecy" || url.scheme == "feather" {
			/// injecy://tweak/<slug-or-id>
			if url.host == "tweak" {
				let key = url.lastPathComponent
				if url.pathComponents.count > 1, !key.isEmpty {
					DeepLinkRouter.shared.openTweak(key)
				}
				return
			}
			/// injecy://import-certificate?p12=<base64>&mobileprovision=<base64>&password=<base64>
			if url.host == "import-certificate" {
				guard
					let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
					let queryItems = components.queryItems
				else {
					return
				}

				func queryValue(_ name: String) -> String? {
					queryItems.first(where: { $0.name == name })?.value?.removingPercentEncoding
				}

				guard
					let p12Base64 = queryValue("p12"),
					let provisionBase64 = queryValue("mobileprovision"),
					let passwordBase64 = queryValue("password"),
					let passwordData = Data(base64Encoded: passwordBase64),
					let password = String(data: passwordData, encoding: .utf8)
				else {
					return
				}

				let generator = UINotificationFeedbackGenerator()
				generator.prepare()

				guard
					let p12URL = FileManager.default.decodeAndWrite(base64: p12Base64, pathComponent: ".p12"),
					let provisionURL = FileManager.default.decodeAndWrite(base64: provisionBase64, pathComponent: ".mobileprovision"),
					FR.checkPasswordForCertificate(for: p12URL, with: password, using: provisionURL)
				else {
					generator.notificationOccurred(.error)
					return
				}

				FR.handleCertificateFiles(
					p12URL: p12URL,
					provisionURL: provisionURL,
					p12Password: password
				) { error in
					if let error = error {
						UIAlertController.showAlertWithOk(title: .localized("Error"), message: error.localizedDescription)
					} else {
						generator.notificationOccurred(.success)
					}
				}

				return
			}
			/// injecy://export-certificate?callback_template=<template>
			if url.host == "export-certificate" {
				guard
					let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
				else {
					return
				}

				let queryItems = components.queryItems?.reduce(into: [String: String]()) { $0[$1.name.lowercased()] = $1.value } ?? [:]
				guard let callbackTemplate = queryItems["callback_template"]?.removingPercentEncoding else { return }

				FR.exportCertificateAndOpenUrl(using: callbackTemplate)
			}
			/// injecy://source/<url>
			if let fullPath = url.validatedScheme(after: "/source/") {
				FR.handleSource(fullPath) { }
			}
			/// injecy://install/<url.ipa>
			if
				let fullPath = url.validatedScheme(after: "/install/"),
				let downloadURL = URL(string: fullPath)
			{
				_ = DownloadManager.shared.startDownload(from: downloadURL)
			}
		} else {
			let ext = url.pathExtension.lowercased()
			if ext == "ipa" || ext == "tipa" {
				if FileManager.default.isFileFromFileProvider(at: url) {
					guard url.startAccessingSecurityScopedResource() else { return }
				}
				// Route through an archiving "download" so the Library shows import progress
				// instead of silently importing (e.g. when opened/shared from another app).
				let id = "FeatherManualDownload_\(UUID().uuidString)"
				let dl = DownloadManager.shared.startArchive(from: url, id: id)
				try? DownloadManager.shared.handlePachageFile(url: url, dl: dl)
				return
			}
			// A tweak file (.dylib/.deb/.framework) shared into injecy → add to the library,
			// with a top toast (not a system alert) + an "Open" shortcut to its detail page.
			if ext == "dylib" || ext == "deb" || ext == "framework" {
				Task { @MainActor in
					let generator = UINotificationFeedbackGenerator()
					generator.prepare()
					if let added = TweakLibrary.shared.addCustomFile(url) {
						generator.notificationOccurred(.success)
						ToastManager.shared.show(
							title: .localized("Added to Library"),
							subtitle: added.tweak.name,
							systemImage: "puzzlepiece.extension.fill",
							tint: Color(hex: UserDefaults.standard.string(forKey: "Feather.userTintColor") ?? "#848ef9"),
							actionTitle: .localized("Open"),
							action: { DeepLinkRouter.shared.presentedTweak = added.tweak }
						)
					} else {
						generator.notificationOccurred(.error)
					}
				}
				return
			}
		}
	}
}

class AppDelegate: NSObject, UIApplicationDelegate {
	func application(
		_ application: UIApplication,
		didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
	) -> Bool {
		_createPipeline()
		_createDocumentsDirectories()
		ResetView.clearWorkCache()
		_addDefaultCertificates()
		return true
	}

	private func _createPipeline() {
		DataLoader.sharedUrlCache.diskCapacity = 0

		let pipeline = ImagePipeline {
			let dataLoader: DataLoader = {
				let config = URLSessionConfiguration.default
				config.urlCache = nil
				return DataLoader(configuration: config)
			}()
			let dataCache = try? DataCache(name: "lol.injecy.app.datacache") // disk cache
			let imageCache = Nuke.ImageCache() // memory cache
			dataCache?.sizeLimit = 500 * 1024 * 1024
			imageCache.costLimit = 100 * 1024 * 1024
			$0.dataCache = dataCache
			$0.imageCache = imageCache
			$0.dataLoader = dataLoader
			$0.dataCachePolicy = .automatic
			$0.isStoringPreviewsInMemoryCache = false
		}

		ImagePipeline.shared = pipeline
	}

	private func _createDocumentsDirectories() {
		let fileManager = FileManager.default

		let directories: [URL] = [
			fileManager.archives,
			fileManager.certificates,
			fileManager.signed,
			fileManager.unsigned
		]

		for url in directories {
			try? fileManager.createDirectoryIfNeeded(at: url)
		}
	}

	private func _addDefaultCertificates() {
		guard
			UserDefaults.standard.bool(forKey: "feather.didImportDefaultCertificates") == false,
			let signingAssetsURL = Bundle.main.url(forResource: "signing-assets", withExtension: nil)
		else {
			return
		}

		do {
			let folderContents = try FileManager.default.contentsOfDirectory(
				at: signingAssetsURL,
				includingPropertiesForKeys: nil,
				options: .skipsHiddenFiles
			)

			for folderURL in folderContents {
				guard folderURL.hasDirectoryPath else { continue }

				let certName = folderURL.lastPathComponent

				let p12Url = folderURL.appendingPathComponent("cert.p12")
				let provisionUrl = folderURL.appendingPathComponent("cert.mobileprovision")
				let passwordUrl = folderURL.appendingPathComponent("cert.txt")

				guard
					FileManager.default.fileExists(atPath: p12Url.path),
					FileManager.default.fileExists(atPath: provisionUrl.path),
					FileManager.default.fileExists(atPath: passwordUrl.path)
				else {
					Logger.misc.warning("Skipping \(certName): missing required files")
					continue
				}

				let password = try String(contentsOf: passwordUrl, encoding: .utf8)

				FR.handleCertificateFiles(
					p12URL: p12Url,
					provisionURL: provisionUrl,
					p12Password: password,
					certificateName: certName,
					isDefault: true
				) { _ in

				}
			}
			UserDefaults.standard.set(true, forKey: "feather.didImportDefaultCertificates")
		} catch {
			Logger.misc.error("Failed to list signing-assets: \(error)")
		}
	}
}