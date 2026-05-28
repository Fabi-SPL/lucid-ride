import Foundation
import CoreMotion

/// Wraps `CMMotionManager` for ride telemetry recording. Publishes the latest
/// attitude (pitch/roll/yaw) and user acceleration (gravity-removed) so
/// `RideTelemetryRecorder` can fold them into per-second waypoints.
///
/// Realtime caveat: phone-in-pocket = noisy. Phone-on-mount = usable but needs
/// per-ride zero-calibration to mean anything for lean angle. v1 records raw
/// values; post-ride analysis decides whether the signal is meaningful.
final class MotionService: ObservableObject {

    static let shared = MotionService()

    @Published private(set) var pitch_rad: Double?
    @Published private(set) var roll_rad: Double?
    @Published private(set) var yaw_rad: Double?
    @Published private(set) var userAccelX: Double?   // g, gravity removed
    @Published private(set) var userAccelY: Double?
    @Published private(set) var userAccelZ: Double?

    private let manager = CMMotionManager()

    private init() {
        manager.deviceMotionUpdateInterval = 1.0 / 10.0   // 10 Hz
    }

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        guard !manager.isDeviceMotionActive else { return }
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.pitch_rad  = motion.attitude.pitch
            self.roll_rad   = motion.attitude.roll
            self.yaw_rad    = motion.attitude.yaw
            self.userAccelX = motion.userAcceleration.x
            self.userAccelY = motion.userAcceleration.y
            self.userAccelZ = motion.userAcceleration.z
        }
    }

    func stop() {
        if manager.isDeviceMotionActive {
            manager.stopDeviceMotionUpdates()
        }
        pitch_rad = nil; roll_rad = nil; yaw_rad = nil
        userAccelX = nil; userAccelY = nil; userAccelZ = nil
    }
}
