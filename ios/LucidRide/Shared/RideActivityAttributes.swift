import Foundation
import ActivityKit

/// ActivityKit attributes shared between the main LucidRide app and the
/// `LucidRideWidget` extension. The main app calls
/// `Activity<RideActivityAttributes>.request(...)` on ride start and
/// `activity.update(using:)` from the recorder tick; the widget extension
/// renders the lock-screen card + Dynamic Island layouts.
///
/// Static `attributes` carry one-time data (ride start time). Dynamic
/// `ContentState` carries the live-updating values (speed, HR, lean, etc.).
struct RideActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Speed in km/h, rounded to int (Dynamic Island doesn't render decimals well).
        var speedKmh: Int
        /// Live heart rate in BPM. 0 = unknown / not yet polled.
        var heartRate: Int
        /// Zone index: 0 = warm-up, 1 = aerobic, 2 = threshold, 3 = redline, -1 = unknown.
        var zoneIndex: Int
        /// Elapsed seconds since ride started.
        var elapsedSeconds: Int
        /// Distance traveled in meters.
        var distanceMeters: Int
        /// GPS-derived lean angle in degrees (signed: + right, - left). 0 = straight.
        var leanDeg: Int
        /// True when auto-pause is active (recorder paused itself due to low speed).
        var isPaused: Bool
    }

    /// When the ride started (immutable for the lifetime of this activity).
    let startedAt: Date
}
