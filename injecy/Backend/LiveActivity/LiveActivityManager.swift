//
//  LiveActivityManager.swift
//  injecy
//
//  Starts / updates / ends Live Activities for background jobs (download → sign →
//  install). Safe to call from any thread and any OS — it no-ops below iOS 16.2
//  or when the user has Live Activities disabled. All state is touched on main.
//

import Foundation
import ActivityKit

final class LiveActivityManager {
	static let shared = LiveActivityManager()
	private init() {}

	/// Keyed by job id. Only touched on the main thread. `Any` avoids leaking the
	/// availability-gated generic type into stored properties.
	private var _activities: [String: Any] = [:]
	/// Last content pushed per id, to skip no-op updates (ActivityKit rate-limits pushes,
	/// so we only send when the phase, status, or rounded progress actually changed).
	private var _lastPush: [String: String] = [:]

	private var _accentHex: String {
		UserDefaults.standard.string(forKey: "Feather.userTintColor") ?? "#848ef9"
	}

	/// Begin (or restart) a Live Activity for the given job id.
	func start(id: String, name: String, phase: InjecyJobPhase, status: String, progress: Double = 0) {
		guard #available(iOS 16.2, *) else { return }
		DispatchQueue.main.async {
			guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
			if self._activities[id] != nil { return } // already running

			let attributes = InjecyActivityAttributes(name: name, accentHex: self._accentHex)
			let state = InjecyActivityAttributes.ContentState(phase: phase, progress: progress, statusText: status)
			do {
				let activity = try Activity.request(
					attributes: attributes,
					content: .init(state: state, staleDate: nil)
				)
				self._activities[id] = activity
				self._lastPush[id] = nil
			} catch {
				// A failed Live Activity must never block the real job.
			}
		}
	}

	/// Update progress / phase of a running activity.
	func update(id: String, phase: InjecyJobPhase? = nil, status: String? = nil, progress: Double? = nil) {
		guard #available(iOS 16.2, *) else { return }
		DispatchQueue.main.async {
			guard let activity = self._activities[id] as? Activity<InjecyActivityAttributes> else { return }
			var state = activity.content.state
			if let phase { state.phaseRaw = phase.rawValue }
			if let progress { state.progress = max(0, min(1, progress)) }
			if let status { state.statusText = status }

			// Skip no-op pushes (progress rounded to whole %) — ActivityKit rate-limits.
			let signature = "\(state.phaseRaw)|\(state.statusText)|\(Int((state.progress * 100).rounded()))"
			guard self._lastPush[id] != signature else { return }
			self._lastPush[id] = signature

			Task { await activity.update(.init(state: state, staleDate: nil)) }
		}
	}

	/// Finish an activity (auto-dismisses shortly after).
	func end(id: String, phase: InjecyJobPhase = .done, status: String) {
		guard #available(iOS 16.2, *) else { return }
		DispatchQueue.main.async {
			guard let activity = self._activities[id] as? Activity<InjecyActivityAttributes> else { return }
			self._activities[id] = nil
			self._lastPush[id] = nil
			let finalState = InjecyActivityAttributes.ContentState(
				phase: phase,
				progress: phase == .done ? 1 : activity.content.state.progress,
				statusText: status
			)
			Task {
				await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .after(.now + 4))
			}
		}
	}
}
