//
//  InjecyBackend.swift
//  injecy
//
//  Client for the injecy API (/api/injecy/v1). Registers the device, stores its token
//  + HMAC signing secret in the Keychain, and signs every request
//  (X-INJ-Timestamp/Nonce/Signature) so the server can reject forged or replayed calls.
//

import Foundation
import CryptoKit

enum InjecyError: Error, LocalizedError {
	case http(Int)
	case notRegistered
	case badResponse

	var errorDescription: String? {
		switch self {
		case .http(let code): "Server returned \(code)."
		case .notRegistered: "Device is not registered."
		case .badResponse: "Unexpected server response."
		}
	}
}

actor InjecyBackend {
	static let shared = InjecyBackend()

	/// Public client API base — its own domain, separate from the admin panel. All server
	/// URLs (icons, downloads, self-update manifest/ipa) derive from this host, so the
	/// itms-services install prompt reads "api.leadproject.lol".
	private let base = URL(string: "https://api.leadproject.lol/api/injecy/v1")!
	/// Build secret, shared with the server's INJECY_CLIENT_SECRET. Gates /register.
	/// Loaded from Secrets.swift (git-ignored) — copy Secrets.swift.example to get started.
	private let buildSecret = InjecySecrets.buildSecret

	private var token: String?
	private var signingSecret: String?

	private struct TweaksResponse: Decodable { let total: Int; let items: [CatalogTweak] }
	private struct RegisterResponse: Decodable { let token: String; let signing_secret: String }

	// MARK: Identity

	private var deviceID: String {
		let key = "injecy.deviceID"
		if let v = UserDefaults.standard.string(forKey: key) { return v }
		let v = UUID().uuidString
		UserDefaults.standard.set(v, forKey: key)
		return v
	}

	private var platform: String {
		#if targetEnvironment(macCatalyst)
		return "maccatalyst"
		#else
		return "ios"
		#endif
	}

	private var appVersion: String {
		Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
	}

	// MARK: Registration

	private func loadCreds() {
		if token == nil { token = Keychain.read("injecy.token") }
		if signingSecret == nil { signingSecret = Keychain.read("injecy.secret") }
	}

	private func register() async throws {
		var req = URLRequest(url: base.appendingPathComponent("register"))
		req.httpMethod = "POST"
		req.setValue("application/json", forHTTPHeaderField: "Content-Type")
		req.setValue(buildSecret, forHTTPHeaderField: "X-Injecy-Secret")
		req.httpBody = try JSONSerialization.data(withJSONObject: [
			"device_id": deviceID,
			"platform": platform,
			"app_version": appVersion,
		])

		let (data, resp) = try await URLSession.shared.data(for: req)
		guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
			throw InjecyError.http((resp as? HTTPURLResponse)?.statusCode ?? 0)
		}
		let r = try JSONDecoder().decode(RegisterResponse.self, from: data)
		token = r.token
		signingSecret = r.signing_secret
		Keychain.write("injecy.token", r.token)
		Keychain.write("injecy.secret", r.signing_secret)
	}

	private func ensureRegistered() async throws {
		loadCreds()
		if token == nil || signingSecret == nil {
			try await register()
		}
	}

	// MARK: Signed requests

	private func perform(
		path: String,
		method: String = "GET",
		query: [URLQueryItem] = [],
		body: Data = Data(),
		contentType: String? = nil,
		retryOn401: Bool = true
	) async throws -> (Data, HTTPURLResponse) {
		try await ensureRegistered()

		var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
		if !query.isEmpty { comps.queryItems = query }
		guard let url = comps.url else { throw InjecyError.badResponse }

		var req = URLRequest(url: url)
		req.httpMethod = method
		if !body.isEmpty {
			req.httpBody = body
			req.setValue(contentType ?? "application/json", forHTTPHeaderField: "Content-Type")
		}
		_sign(&req, method: method, canonicalPath: comps.path, body: body)

		let (data, resp) = try await URLSession.shared.data(for: req)
		guard let http = resp as? HTTPURLResponse else { throw InjecyError.badResponse }

		// Token/secret may have rotated or been wiped — re-register once and retry.
		if http.statusCode == 401, retryOn401 {
			try await register()
			return try await perform(path: path, method: method, query: query, body: body, contentType: contentType, retryOn401: false)
		}
		guard http.statusCode == 200 else { throw InjecyError.http(http.statusCode) }
		return (data, http)
	}

	private func _sign(_ req: inout URLRequest, method: String, canonicalPath: String, body: Data) {
		guard let token, let signingSecret else { return }
		let ts = String(Int(Date().timeIntervalSince1970))
		let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
		let bodyHash = SHA256.hash(data: body).hexEncoded
		let canonical = [method.uppercased(), canonicalPath, ts, nonce, bodyHash].joined(separator: "\n")
		let sig = HMAC<SHA256>.authenticationCode(
			for: Data(canonical.utf8),
			using: SymmetricKey(data: Data(signingSecret.utf8))
		).hexEncoded

		req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		req.setValue(ts, forHTTPHeaderField: "X-INJ-Timestamp")
		req.setValue(nonce, forHTTPHeaderField: "X-INJ-Nonce")
		req.setValue(sig, forHTTPHeaderField: "X-INJ-Signature")
	}

	// MARK: API

	func fetchTweaks(search: String = "", category: String = "") async throws -> [CatalogTweak] {
		var query: [URLQueryItem] = []
		if !search.isEmpty { query.append(URLQueryItem(name: "q", value: search)) }
		if !category.isEmpty { query.append(URLQueryItem(name: "category", value: category)) }
		let (data, _) = try await perform(path: "tweaks", query: query)
		return try JSONDecoder().decode(TweaksResponse.self, from: data).items
	}

	/// Fetch a single tweak by slug (for share deep links).
	func fetchTweak(slug: String) async throws -> CatalogTweak {
		let (data, _) = try await perform(path: "tweaks/slug/\(slug)")
		return try JSONDecoder().decode(CatalogTweak.self, from: data)
	}

	/// Fetch a single tweak by numeric id.
	func fetchTweak(id: Int) async throws -> CatalogTweak {
		let (data, _) = try await perform(path: "tweaks/\(id)")
		return try JSONDecoder().decode(CatalogTweak.self, from: data)
	}

	/// Download a tweak's file. Returns the bytes and a suggested filename (with extension),
	/// parsed from Content-Disposition so the correct file type is preserved for injection.
	func downloadTweak(_ tweak: CatalogTweak) async throws -> (data: Data, filename: String) {
		let (data, http) = try await perform(path: "tweaks/\(tweak.id)/download")
		let suggested = _filename(from: http) ?? "\(tweak.slug).dylib"
		return (data, suggested)
	}

	private func _filename(from resp: HTTPURLResponse) -> String? {
		guard let cd = resp.value(forHTTPHeaderField: "Content-Disposition") else { return nil }
		// e.g. attachment; filename="thing.deb"
		guard let range = cd.range(of: "filename=") else { return nil }
		var name = String(cd[range.upperBound...])
		name = name.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
		return name.isEmpty ? nil : name
	}

	// MARK: App updates
	struct AppUpdateInfo: Decodable {
		let available: Bool
		let version: String?
		let build: Int?
		let changelog: String?
		let minIOS: String?
		let ipaURL: String?
		let sha256: String?
		let size: Int?
		let force: Bool?
		enum CodingKeys: String, CodingKey {
			case available, version, build, changelog, sha256, size, force
			case minIOS = "min_ios"
			case ipaURL = "ipa_url"
		}
	}

	func checkAppVersion(channel: String = "stable") async throws -> AppUpdateInfo {
		let (data, _) = try await perform(path: "app-version", query: [
			URLQueryItem(name: "channel", value: channel),
			URLQueryItem(name: "platform", value: "ios"),
		])
		return try JSONDecoder().decode(AppUpdateInfo.self, from: data)
	}

	/// Upload a locally-signed self-update IPA to a short-lived backend slot and get back
	/// the itms-services manifest URL (used for the OTA fallback when IDevice isn't set up).
	func uploadSelfUpdate(ipaData: Data, version: String, build: Int, bundleId: String) async throws -> String {
		let (data, _) = try await perform(
			path: "self-update/upload", method: "POST",
			query: [
				URLQueryItem(name: "version", value: version),
				URLQueryItem(name: "build", value: String(build)),
				URLQueryItem(name: "bundle_id", value: bundleId),
			],
			body: ipaData, contentType: "application/octet-stream"
		)
		struct Resp: Decodable { let manifest_url: String }
		return try JSONDecoder().decode(Resp.self, from: data).manifest_url
	}

	// MARK: Packs
	struct ServerPack: Decodable {
		let id: Int
		let slug: String
		let name: String
		let description: String?
		let accentColor: String?
		let tweakIDs: [Int]
		enum CodingKeys: String, CodingKey {
			case id, slug, name, description
			case accentColor = "accent_color"
			case tweakIDs = "tweak_ids"
		}
	}
	private struct PacksResponse: Decodable { let items: [ServerPack] }

	func fetchPacks() async throws -> [ServerPack] {
		let (data, _) = try await perform(path: "packs")
		return try JSONDecoder().decode(PacksResponse.self, from: data).items
	}

	// MARK: Submissions (tweak requests + bug reports)
	private struct SubmissionResponse: Decodable { let id: Int }

	/// Submit a tweak request or bug report. Returns the created submission id.
	func submit(_ payload: [String: String]) async throws -> Int {
		let data = try JSONSerialization.data(withJSONObject: payload)
		let (resp, _) = try await perform(path: "submissions", method: "POST", body: data)
		return try JSONDecoder().decode(SubmissionResponse.self, from: resp).id
	}

	/// Attach a screenshot (JPEG) to a submission.
	func uploadScreenshot(submissionID: Int, jpeg: Data) async throws {
		_ = try await perform(path: "submissions/\(submissionID)/screenshot", method: "POST", body: jpeg, contentType: "image/jpeg")
	}

	// MARK: Likes
	private struct LikesResponse: Decodable { let items: [Int] }
	private struct LikeToggleResponse: Decodable { let liked: Bool; let likes: Int }

	func likedTweaks() async throws -> [Int] {
		let (data, _) = try await perform(path: "likes")
		return try JSONDecoder().decode(LikesResponse.self, from: data).items
	}

	func toggleLike(_ id: Int) async throws -> (liked: Bool, likes: Int) {
		let (data, _) = try await perform(path: "tweaks/\(id)/like", method: "POST")
		let r = try JSONDecoder().decode(LikeToggleResponse.self, from: data)
		return (r.liked, r.likes)
	}
}

// MARK: - Likes manager
@MainActor
final class LikesManager: ObservableObject {
	static let shared = LikesManager()
	@Published private(set) var liked: Set<Int> = []
	private init() {}

	func load() {
		Task {
			if let ids = try? await InjecyBackend.shared.likedTweaks() {
				self.liked = Set(ids)
			}
		}
	}

	func isLiked(_ id: Int) -> Bool { liked.contains(id) }
	func markLiked(_ id: Int) { liked.insert(id) }
	func markUnliked(_ id: Int) { liked.remove(id) }
}

// MARK: - Hex helper
private extension Sequence where Element == UInt8 {
	var hexEncoded: String { map { String(format: "%02x", $0) }.joined() }
}
