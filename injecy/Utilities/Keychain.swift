//
//  Keychain.swift
//  injecy
//
//  Tiny Keychain wrapper for the device token + HMAC signing secret.
//

import Foundation
import Security

enum Keychain {
	private static let service = "lol.injecy.app"

	@discardableResult
	static func write(_ key: String, _ value: String) -> Bool {
		let data = Data(value.utf8)
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: key,
		]
		SecItemDelete(query as CFDictionary)
		var add = query
		add[kSecValueData as String] = data
		add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
		return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
	}

	static func read(_ key: String) -> String? {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: key,
			kSecReturnData as String: true,
			kSecMatchLimit as String: kSecMatchLimitOne,
		]
		var result: AnyObject?
		guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
		      let data = result as? Data else { return nil }
		return String(data: data, encoding: .utf8)
	}

	@discardableResult
	static func delete(_ key: String) -> Bool {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: key,
		]
		return SecItemDelete(query as CFDictionary) == errSecSuccess
	}
}
