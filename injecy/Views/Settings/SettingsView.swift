//
//  SettingsView.swift
//  Feather
//
//  Created by samara on 10.04.2025.
//

import SwiftUI
import NimbleViews
import UIKit
import Darwin
import IDeviceSwift

// MARK: - View
struct SettingsView: View {
	@AppStorage("feather.selectedCert") private var _storedSelectedCert: Int = 0
	@State private var _currentIcon: String? = UIApplication.shared.alternateIconName
	@State private var _isRequestingTweak = false
	@State private var _isReportingBug = false
	@State private var _isUpdatePresenting = false
	@ObservedObject private var _updater = AppUpdater.shared
	
	// MARK: Fetch
	@FetchRequest(
		entity: CertificatePair.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)],
		animation: .snappy
	) private var _certificates: FetchedResults<CertificatePair>
	
	/// A warning card at the top of Settings when the selected cert is missing / expired /
	/// expiring — so signing & updates don't silently fail.
	@ViewBuilder
	private var _certWarningBanner: some View {
		if let cert = selectedCertificate, let exp = cert.expiration {
			let days = Int(exp.timeIntervalSinceNow / 86400)
			if exp < Date() {
				_certBanner(icon: "xmark.seal.fill", color: .red,
				            title: .localized("Certificate expired"),
				            message: .localized("Signing and updates will fail — add a valid certificate."))
			} else if days <= 7 {
				_certBanner(icon: "exclamationmark.triangle.fill", color: .orange,
				            title: .localized("Certificate expiring soon"),
				            message: .localized("Expires in %lld days.", arguments: days))
			}
		} else if selectedCertificate == nil {
			_certBanner(icon: "person.badge.key", color: .orange,
			            title: .localized("No certificate selected"),
			            message: .localized("Add a signing certificate to sign and update apps."))
		}
	}

	private func _certBanner(icon: String, color: Color, title: String, message: String) -> some View {
		Section {
			NavigationLink(destination: CertificatesView()) {
				HStack(spacing: 12) {
					Image(systemName: icon).font(.title2).foregroundStyle(color)
					VStack(alignment: .leading, spacing: 2) {
						Text(title).font(.subheadline.weight(.semibold))
						Text(message).font(.caption).foregroundStyle(.secondary)
					}
				}
				.padding(.vertical, 2)
			}
		}
		.listRowBackground(color.opacity(0.12))
	}

	private var selectedCertificate: CertificatePair? {
		guard
			_storedSelectedCert >= 0,
			_storedSelectedCert < _certificates.count
		else {
			return nil
		}
		return _certificates[_storedSelectedCert]
	}

    
	private let _donationsUrl = "https://github.com/sponsors/claration"
	private let _githubUrl = "https://github.com/claration/Feather"
    
	// MARK: Body
	var body: some View {
		NBNavigationView(.localized("Settings")) {
			Form {
				_certWarningBanner

				#if !NIGHTLY && !DEBUG
					SettingsDonationCellView(site: _donationsUrl)
				#endif

				_feedback()
                
				Section {
					NavigationLink(destination: AppearanceView()) {
						Label(.localized("Appearance"), systemImage: "paintbrush")
					}
					NavigationLink(destination: AppIconView(currentIcon: $_currentIcon)) {
						Label(.localized("App Icon"), systemImage: "app.badge")
					}
				}
                
				NBSection(.localized("Certificates")) {
                    
					if let cert = selectedCertificate {
						CertificatesCellView(cert: cert)
					} else {
						Text(.localized("No Certificate"))
							.font(.footnote)
							.foregroundColor(.disabled())
					}
					NavigationLink(destination: CertificatesView()) {
						Label(.localized("Certificates"), systemImage: "checkmark.seal")
					}
                 
				} footer: {
					Text(.localized("Add and manage certificates used for signing applications."))
				}
                
				NBSection(.localized("Features")) {
					NavigationLink(destination: ConfigurationView()) {
						Label(.localized("Signing Options"), systemImage: "signature")
					}
					NavigationLink(destination: ArchiveView()) {
						Label(.localized("Archive & Compression"), systemImage: "archivebox")
					}
					NavigationLink(destination: InstallationView()) {
						Label(.localized("Installation"), systemImage: "arrow.down.circle")
					}
				} footer: {
					Text(.localized("Configure the apps way of installing, its zip compression levels, and custom modifications to apps."))
				}
                
				_directories()
                
				NBSection(.localized("Help")) {
					Button {
						_isUpdatePresenting = true
					} label: {
						HStack {
							Label(.localized("Check for Updates"), systemImage: "arrow.down.app")
							Spacer()
							if case .available = _updater.phase {
								Text(.localized("Update available"))
									.font(.caption.weight(.semibold))
									.foregroundStyle(Color.accentColor)
							} else {
								Text("\(_updater.currentVersion)")
									.font(.caption).foregroundStyle(.secondary)
							}
						}
					}
					Button {
						_isRequestingTweak = true
					} label: {
						Label(.localized("Request a Tweak"), systemImage: "plus.bubble")
					}
					Button {
						_isReportingBug = true
					} label: {
						Label(.localized("Report a Bug"), systemImage: "ladybug")
					}
				} footer: {
					Text(.localized("Can't find a tweak, or hit a bug? Let us know — it goes straight to the team."))
				}

				Section {
					NavigationLink(destination: BackupView()) {
						Label(.localized("Backup & Restore"), systemImage: "arrow.up.arrow.down.circle")
					}
					NavigationLink(destination: ResetView()) {
						Label(.localized("Reset"), systemImage: "trash")
					}
				} footer: {
					Text(.localized("Back up your certificates and library, or reset the app's contents."))
				}
			}
			.sheet(isPresented: $_isRequestingTweak) { RequestTweakView() }
			.sheet(isPresented: $_isReportingBug) { BugReportView() }
			.sheet(isPresented: $_isUpdatePresenting) { AppUpdateView() }
		}
	}
}

// MARK: - View extension
extension SettingsView {
	@ViewBuilder
	private func _feedback() -> some View {
		Section {
			NavigationLink(destination: AboutView()) {
				Label {
					Text(verbatim: .localized("About %@", arguments: Bundle.main.name))
				} icon: {
					FRAppIconView(size: 23)
				}
			}
		}
	}
    
	@ViewBuilder
	private func _directories() -> some View {
		NBSection(.localized("Misc")) {
			Button(.localized("Open Documents"), systemImage: "folder") {
				UIApplication.open(URL.documentsDirectory.toSharedDocumentsURL()!)
			}
			Button(.localized("Open Archives"), systemImage: "folder") {
				UIApplication.open(FileManager.default.archives.toSharedDocumentsURL()!)
			}
			Button(.localized("Open Certificates"), systemImage: "folder") {
				UIApplication.open(FileManager.default.certificates.toSharedDocumentsURL()!)
			}
		} footer: {
			Text(.localized("All of the apps files are contained in the documents directory, here are some quick links to these."))
		}
	}
    
	private func _makeGitHubIssueURL(url: String) -> String {
		var configurationSection = "### App Configuration:\n"
		
		switch UserDefaults.standard.integer(forKey: "Feather.installationMethod") {
		case 0: // Server
			let serverMethod = UserDefaults.standard.integer(forKey: "Feather.serverMethod")
			let ipFix = UserDefaults.standard.bool(forKey: "Feather.ipFix")
			let serverType = (serverMethod == 0) ? "Fully Local" : "Semi Local"
			configurationSection += "- Install method: `Server`\n"
			configurationSection += "  - Server type: `\(serverType)`\n"
			configurationSection += "  - IP Fix: `\(ipFix)`\n"
		case 1: // idevice
			let pairingPath = HeartbeatManager.pairingFile()
			let pairingExists = FileManager.default.fileExists(atPath: pairingPath)
			let pairingStatus = pairingExists ? "`Present`" : "`Not Present`"
			configurationSection += "- Install method: `idevice`\n"
			configurationSection += "  - Pairing file: \(pairingStatus)\n"
		default:
			configurationSection += "- Install method: `Unknown`\n"
		}
        
		let body = """
		### Device Information
		- Device: `\(MobileGestalt().getStringForName("PhysicalHardwareNameString") ?? "Unknown")`
		- iOS Version: `\(UIDevice.current.systemVersion)`
		- App Version: `\(Bundle.main.version)`
		
		\(configurationSection)
		
		### Issue Description
		<!-- Describe your issue here -->
		
		### Steps to Reproduce
		1. 
		2. 
		3. 
		
		### Expected Behavior
		
		### Actual Behavior
		"""
		let encodedTitle = "[Bug] replace this with a descriptive title "
			.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
		let encodedBody = body
			.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
		return "\(url)/issues/new?template=bug.yml&title=\(encodedTitle)&text=\(encodedBody)"
	}
}
