//
//  FeedbackViews.swift
//  injecy
//
//  User-submitted tweak requests and bug reports, sent to the injecy backend
//  (and forwarded to admins). See InjecyBackend.submit / uploadScreenshot.
//

import SwiftUI
import PhotosUI

private var injecyAccent: Color {
	Color(hex: UserDefaults.standard.string(forKey: "Feather.userTintColor") ?? "#848ef9")
}

// MARK: - Request a tweak

struct RequestTweakView: View {
	@Environment(\.dismiss) private var dismiss
	/// Prefill the name (e.g. from a failed search).
	var prefillName: String = ""

	@State private var _name = ""
	@State private var _targetApp = ""
	@State private var _version = ""
	@State private var _link = ""
	@State private var _desc = ""
	@State private var _contact = ""
	@State private var _state: SubmitState = .idle

	var body: some View {
		NavigationStack {
			Form {
				Section {
					TextField(.localized("Tweak name"), text: $_name)
					TextField(.localized("Target app (optional)"), text: $_targetApp)
					TextField(.localized("Version (optional)"), text: $_version)
				} header: {
					Text(.localized("What tweak do you want?"))
				}

				Section(.localized("Link (optional)")) {
					TextField("https://…", text: $_link)
						.textInputAutocapitalization(.never).autocorrectionDisabled()
						.keyboardType(.URL)
				}

				Section(.localized("Details")) {
					TextField(.localized("Anything else? (optional)"), text: $_desc, axis: .vertical)
						.lineLimit(3...6)
				}

				Section {
					TextField(.localized("Contact (Telegram / email, optional)"), text: $_contact)
						.textInputAutocapitalization(.never).autocorrectionDisabled()
				} footer: {
					Text(.localized("So we can reach you if we add it."))
				}

				_submitSection
			}
			.navigationTitle(.localized("Request a Tweak"))
			.navigationBarTitleDisplayMode(.inline)
			.toolbar { ToolbarItem(placement: .topBarLeading) {
				Button { dismiss() } label: { Image(systemName: "xmark") }
			} }
			.onAppear { if _name.isEmpty { _name = prefillName } }
		}
		.tint(injecyAccent)
	}

	@ViewBuilder
	private var _submitSection: some View {
		Section {
			if case .done = _state {
				Label(.localized("Request sent — thank you!"), systemImage: "checkmark.seal.fill")
					.foregroundStyle(.green)
			} else {
				Button {
					_submit()
				} label: {
					HStack {
						if case .sending = _state { ProgressView() }
						Text(.localized("Send Request"))
					}
				}
				.disabled(_name.trimmingCharacters(in: .whitespaces).isEmpty || _state == .sending)
				if case .failed(let m) = _state {
					Text(m).font(.caption).foregroundStyle(.red)
				}
			}
		}
	}

	private func _submit() {
		_state = .sending
		let payload: [String: String] = [
			"kind": "tweak_request",
			"title": _name,
			"target_app": _targetApp,
			"version": _version,
			"link": _link,
			"body": _desc,
			"contact": _contact,
		]
		Task {
			do {
				_ = try await InjecyBackend.shared.submit(payload)
				_state = .done
				try? await Task.sleep(nanoseconds: 900_000_000)
				dismiss()
			} catch {
				_state = .failed(error.localizedDescription)
			}
		}
	}
}

// MARK: - Report a bug

struct BugReportView: View {
	@Environment(\.dismiss) private var dismiss

	@State private var _desc = ""
	@State private var _contact = ""
	@State private var _includeLogs = true
	@State private var _photoItem: PhotosPickerItem?
	@State private var _image: UIImage?
	@State private var _state: SubmitState = .idle

	private var _appVersion: String {
		let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
		let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
		return "\(v) (\(b))"
	}
	private var _deviceInfo: String {
		"\(UIDevice.current.model) · iOS \(UIDevice.current.systemVersion)"
	}

	var body: some View {
		NavigationStack {
			Form {
				Section(.localized("What went wrong?")) {
					TextField(.localized("Describe the bug…"), text: $_desc, axis: .vertical)
						.lineLimit(4...8)
				}

				Section(.localized("Screenshot (optional)")) {
					PhotosPicker(selection: $_photoItem, matching: .images) {
						Label(_image == nil ? .localized("Attach screenshot") : .localized("Change screenshot"),
						      systemImage: "photo")
					}
					if let img = _image {
						Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 180)
							.clipShape(RoundedRectangle(cornerRadius: 12))
					}
				}

				Section {
					TextField(.localized("Contact (Telegram / email, optional)"), text: $_contact)
						.textInputAutocapitalization(.never).autocorrectionDisabled()
					Toggle(.localized("Include diagnostic logs"), isOn: $_includeLogs)
				} footer: {
					Text("\(String.localized("Attached automatically:")) \(_appVersion) · \(_deviceInfo)")
				}

				_submitSection
			}
			.navigationTitle(.localized("Report a Bug"))
			.navigationBarTitleDisplayMode(.inline)
			.toolbar { ToolbarItem(placement: .topBarLeading) {
				Button { dismiss() } label: { Image(systemName: "xmark") }
			} }
			.onChange(of: _photoItem) { item in
				guard let item else { return }
				Task {
					if let data = try? await item.loadTransferable(type: Data.self),
					   let img = UIImage(data: data) { _image = img }
				}
			}
		}
		.tint(injecyAccent)
	}

	@ViewBuilder
	private var _submitSection: some View {
		Section {
			if case .done = _state {
				Label(.localized("Report sent — thank you!"), systemImage: "checkmark.seal.fill")
					.foregroundStyle(.green)
			} else {
				Button {
					_submit()
				} label: {
					HStack {
						if case .sending = _state { ProgressView() }
						Text(.localized("Send Report"))
					}
				}
				.disabled(_desc.trimmingCharacters(in: .whitespaces).isEmpty || _state == .sending)
				if case .failed(let m) = _state {
					Text(m).font(.caption).foregroundStyle(.red)
				}
			}
		}
	}

	private func _submit() {
		_state = .sending
		let payload: [String: String] = [
			"kind": "bug",
			"title": String(_desc.prefix(60)),
			"body": _desc,
			"contact": _contact,
			"app_version": _appVersion,
			"device_info": _deviceInfo,
			"logs": _includeLogs ? _collectLogs() : "",
		]
		let image = _image
		Task {
			do {
				let id = try await InjecyBackend.shared.submit(payload)
				if let image, let jpeg = image.jpegData(compressionQuality: 0.7) {
					try? await InjecyBackend.shared.uploadScreenshot(submissionID: id, jpeg: jpeg)
				}
				_state = .done
				try? await Task.sleep(nanoseconds: 900_000_000)
				dismiss()
			} catch {
				_state = .failed(error.localizedDescription)
			}
		}
	}

	/// Best-effort recent diagnostic context (kept short).
	private func _collectLogs() -> String {
		var lines: [String] = []
		lines.append("app: \(_appVersion)")
		lines.append("device: \(_deviceInfo)")
		if let cert = UserDefaults.standard.value(forKey: "feather.selectedCert") {
			lines.append("selectedCert: \(cert)")
		}
		lines.append("pairing: \(FileManager.default.fileExists(atPath: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("pairingFile.plist").path) ? "present" : "absent")")
		return lines.joined(separator: "\n")
	}
}

// MARK: - Shared state

private enum SubmitState: Equatable {
	case idle, sending, done
	case failed(String)
}
