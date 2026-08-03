//
//  InjecyActivityAttributes.swift
//  injecy
//
//  Shared between the app and the widget extension — describes the Live Activity
//  (Dynamic Island / Lock Screen) shown while a tweak or app is downloaded,
//  signed and installed in the background.
//

import Foundation
import ActivityKit

/// The stage a background job is currently in. `statusText` (localized) is carried
/// separately in the content state so the widget doesn't need the app's localizer.
public enum InjecyJobPhase: String, Codable, Hashable {
	case downloading
	case importing
	case signing
	case installing
	case done
	case failed

	/// SF Symbol shown for the phase (the widget maps from the raw value).
	public var symbol: String {
		switch self {
		case .downloading: return "arrow.down.circle.fill"
		case .importing:   return "tray.and.arrow.down.fill"
		case .signing:     return "signature"
		case .installing:  return "square.and.arrow.down.fill"
		case .done:        return "checkmark.circle.fill"
		case .failed:      return "exclamationmark.triangle.fill"
		}
	}

	public var isTerminal: Bool { self == .done || self == .failed }
}

@available(iOS 16.2, *)
public struct InjecyActivityAttributes: ActivityAttributes {
	public struct ContentState: Codable, Hashable {
		public var phaseRaw: String
		public var progress: Double
		public var statusText: String

		public init(phase: InjecyJobPhase, progress: Double, statusText: String) {
			self.phaseRaw = phase.rawValue
			self.progress = progress
			self.statusText = statusText
		}

		public var phase: InjecyJobPhase { InjecyJobPhase(rawValue: phaseRaw) ?? .downloading }
	}

	/// The app/tweak being processed (e.g. "YouTube Reborn").
	public var name: String
	/// Optional hex accent (e.g. "#848ef9") for the Dynamic Island keyline / bars.
	public var accentHex: String?

	public init(name: String, accentHex: String? = nil) {
		self.name = name
		self.accentHex = accentHex
	}
}
