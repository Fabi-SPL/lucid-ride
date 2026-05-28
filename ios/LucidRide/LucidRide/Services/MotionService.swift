import Foundation
import CoreMotion

/// Wraps `CMMotionManager` for ride telemetry recording. Now runs at **100 Hz**
/// (per deep-research recommendation 2026-05-28) so cornering events aren't
/// smoothed across 100 ms windows; the recorder still flushes waypoints at
/// 1 Hz but consumes the max-since-last-tick via `consumeRollingStats()` to
/// preserve peak signal.
///
/// Realtime caveat: phone-in-pocket = noisy. Phone-on-mount = usable but needs
/// per-ride zero-calibration to mean anything for lean angle. v1 records raw
/// values; post-ride analysis decides whether the signal is meaningful.
final class MotionService: ObservableObject {

    static let shared = MotionService()

    /// Latest motion frame (overwritten 100×/sec while running). Used for
    /// "current" attitude display in any live UI surface.
    @Published private(set) var pitch_rad: Double?
    @Published private(set) var roll_rad: Double?
    @Published private(set) var yaw_rad: Double?
    @Published private(set) var userAccelX: Double?
    @Published private(set) var userAccelY: Double?
    @Published private(set) var userAccelZ: Double?

    private let manager = CMMotionManager()

    // Rolling per-second peaks (reset by consumeRollingStats()).
    private let statsLock = NSLock()
    private var rollingMaxAbsRoll: Double = 0
    private var rollingMaxAccelG: Double = 0
    private var rollingPitchSum: Double = 0
    private var rollingPitchN: Int = 0
    private var rollingRollSum: Double = 0
    private var rollingRollN: Int = 0
    private var rollingYawSum: Double = 0
    private var rollingYawN: Int = 0

    private init() {
        manager.deviceMotionUpdateInterval = 1.0 / 100.0   // 100 Hz (was 10 Hz)
    }

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        guard !manager.isDeviceMotionActive else { return }
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let pitch = motion.attitude.pitch
            let roll  = motion.attitude.roll
            let yaw   = motion.attitude.yaw
            let ax = motion.userAcceleration.x
            let ay = motion.userAcceleration.y
            let az = motion.userAcceleration.z

            self.pitch_rad  = pitch
            self.roll_rad   = roll
            self.yaw_rad    = yaw
            self.userAccelX = ax
            self.userAccelY = ay
            self.userAccelZ = az

            // Accumulate rolling stats. Guard NaN/inf — IMU emits them during
            // sensor warm-up; max(0, NaN) = NaN would otherwise poison.
            self.statsLock.lock()
            if roll.isFinite {
                self.rollingMaxAbsRoll = max(self.rollingMaxAbsRoll, abs(roll))
                self.rollingRollSum += roll; self.rollingRollN += 1
            }
            if pitch.isFinite { self.rollingPitchSum += pitch; self.rollingPitchN += 1 }
            if yaw.isFinite { self.rollingYawSum += yaw; self.rollingYawN += 1 }
            if ax.isFinite && ay.isFinite && az.isFinite {
                let g = (ax * ax + ay * ay + az * az).squareRoot()
                if g.isFinite { self.rollingMaxAccelG = max(self.rollingMaxAccelG, g) }
            }
            self.statsLock.unlock()
        }
    }

    func stop() {
        if manager.isDeviceMotionActive { manager.stopDeviceMotionUpdates() }
        pitch_rad = nil; roll_rad = nil; yaw_rad = nil
        userAccelX = nil; userAccelY = nil; userAccelZ = nil
        statsLock.lock()
        resetRollingStatsLocked()
        statsLock.unlock()
    }

    /// Returns the peak / mean motion stats since the last call AND resets them.
    /// Called by the 1 Hz recorder sampler so each waypoint carries the worst-
    /// case lean / accel observed during that second instead of a single frame.
    func consumeRollingStats() -> RollingMotionStats {
        statsLock.lock()
        defer {
            resetRollingStatsLocked()
            statsLock.unlock()
        }
        return RollingMotionStats(
            maxAbsRoll_rad: rollingMaxAbsRoll,
            maxAccelG:      rollingMaxAccelG,
            avgPitch_rad:   rollingPitchN > 0 ? rollingPitchSum / Double(rollingPitchN) : nil,
            avgRoll_rad:    rollingRollN  > 0 ? rollingRollSum  / Double(rollingRollN)  : nil,
            avgYaw_rad:     rollingYawN   > 0 ? rollingYawSum   / Double(rollingYawN)   : nil,
            samples:        rollingRollN
        )
    }

    private func resetRollingStatsLocked() {
        rollingMaxAbsRoll = 0; rollingMaxAccelG = 0
        rollingPitchSum = 0; rollingPitchN = 0
        rollingRollSum = 0;  rollingRollN  = 0
        rollingYawSum = 0;   rollingYawN   = 0
    }
}

struct RollingMotionStats {
    let maxAbsRoll_rad: Double   // max |roll| since last consume — useful for lean peaks
    let maxAccelG:      Double   // max ||userAccel|| since last consume — useful for braking/launch peaks
    let avgPitch_rad:   Double?  // nil if zero samples
    let avgRoll_rad:    Double?
    let avgYaw_rad:     Double?
    let samples:        Int      // how many 100Hz frames were folded into this second
}
