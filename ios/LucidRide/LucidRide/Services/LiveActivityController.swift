import Foundation
import ActivityKit

/// Manages the lifecycle of the ride Live Activity (Dynamic Island +
/// Lock Screen card). Created when a ride starts, updated by the recorder
/// at 1 Hz, ended when the ride ends.
///
/// All updates are local — no APNs, no network. The system enforces a
/// per-hour update budget; we stay at 1 Hz which is well within limits.
final class LiveActivityController {

    static let shared = LiveActivityController()

    private var activity: Activity<RideActivityAttributes>?

    private init() {}

    /// Start a Live Activity for a new ride. Silent if Live Activities are
    /// disabled at the system level (Settings → Face ID & Passcode →
    /// Live Activities) — the recorder still works either way.
    func start(startedAt: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // If we already have one (shouldn't, but defensive), end it first.
        if activity != nil {
            Task { await endNow() }
        }
        let attrs = RideActivityAttributes(startedAt: startedAt)
        let initial = RideActivityAttributes.ContentState(
            speedKmh: 0, heartRate: 0, zoneIndex: -1,
            elapsedSeconds: 0, distanceMeters: 0, leanDeg: 0,
            isPaused: false
        )
        do {
            let req = try Activity.request(
                attributes: attrs,
                content: ActivityContent(state: initial, staleDate: nil),
                pushType: nil
            )
            self.activity = req
        } catch {
            // Live Activities can fail to start for many reasons (budget exhausted,
            // user disabled, etc.). Recorder telemetry is unaffected.
        }
    }

    /// Push the current state. Called by RideTelemetryRecorder's 1 Hz sampler.
    func update(speedKmh: Int, heartRate: Int, zoneIndex: Int,
                elapsedSeconds: Int, distanceMeters: Int,
                leanDeg: Int, isPaused: Bool) {
        guard let activity else { return }
        let state = RideActivityAttributes.ContentState(
            speedKmh:       speedKmh,
            heartRate:      heartRate,
            zoneIndex:      zoneIndex,
            elapsedSeconds: elapsedSeconds,
            distanceMeters: distanceMeters,
            leanDeg:        leanDeg,
            isPaused:       isPaused
        )
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    /// End the live activity (call when ride ends). Best effort — if the
    /// activity reference is gone, no-op.
    func end() {
        Task { await endNow() }
    }

    private func endNow() async {
        guard let activity else { return }
        let finalState = activity.content.state
        await activity.end(ActivityContent(state: finalState, staleDate: nil),
                           dismissalPolicy: .default)
        self.activity = nil
    }
}
