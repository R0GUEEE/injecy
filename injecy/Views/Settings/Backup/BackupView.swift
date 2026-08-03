//
//  BackupView.swift
//  injecy
//
//  Export / restore certificates + tweak library as a single file.
//

import SwiftUI
import UniformTypeIdentifiers

struct BackupView: View {
	@State private var _busy = false
	@State private var _importing = false
	@State private var _message: String?
	@State private var _isError = false

	var body: some View {
		List {
			Section {
				Button {
					_export()
				} label: {
					Label(.localized("Export Backup"), systemImage: "square.and.arrow.up")
				}
				Button {
					_importing = true
				} label: {
					Label(.localized("Restore from Backup"), systemImage: "square.and.arrow.down")
				}
			} footer: {
				Text(.localized("Saves your certificates and tweak library into one file to move to a new device. Keep it private — it contains your certificate keys and passwords."))
			}

			if let message = _message {
				Section {
					Label(message, systemImage: _isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
						.foregroundStyle(_isError ? .orange : .green)
						.font(.subheadline)
				}
			}
		}
		.disabled(_busy)
		.overlay {
			if _busy {
				ZStack {
					Color.black.opacity(0.15).ignoresSafeArea()
					ProgressView().padding(28)
						.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
				}
			}
		}
		.navigationTitle(.localized("Backup & Restore"))
		.navigationBarTitleDisplayMode(.inline)
		.fileImporter(isPresented: $_importing, allowedContentTypes: [.zip, .archive, .item]) { result in
			if case .success(let url) = result { _restore(url) }
		}
	}

	private func _export() {
		_busy = true; _message = nil
		Task {
			do {
				let url = try await BackupManager.shared.export()
				_busy = false
				UIActivityViewController.show(activityItems: [url])
			} catch {
				_busy = false; _isError = true
				_message = error.localizedDescription
			}
		}
	}

	private func _restore(_ url: URL) {
		_busy = true; _message = nil
		Task {
			do {
				let r = try await BackupManager.shared.restore(from: url)
				_busy = false; _isError = false
				UINotificationFeedbackGenerator().notificationOccurred(.success)
				let lib = r.libraryRestored ? " " + String.localized("and your library") : ""
				_message = String.localized("Restored %lld certificate(s).", arguments: r.certificates) + lib
			} catch {
				_busy = false; _isError = true
				_message = error.localizedDescription
			}
		}
	}
}
