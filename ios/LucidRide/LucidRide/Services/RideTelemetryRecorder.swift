import Foundation
import CoreLocation

/// Phone-side waypoint structure pushed to `ride_telemetry`.
struct Waypoint {
    let userId: String
    let activityId: String
    let recordedAt: Date
    let lat: Double?
    let lon: Double?
    let altitude_m: Double?
    let baro_alt_m: Double?
    let speed_mps: Double?
    let course_deg: Double?
    let h_acc_m: Double?
    let v_acc_m: Double?
    let heart_rate: Int?
    let zone_index: Int?
    let pitch_rad: Double?
    let roll_rad: Double?
    let yaw_rad: Double?
    let user_accel_x: Double?
    let user_accel_y: Double?
    let user_accel_z: Double?
}

/// Aggregates phone-side telemetry during an active ride and persists it.
///
/// Subscribes to `LocationService` (GPS + barometric altitude),
/// `MotionService` (IMU), and `HUDState.liveHR` via direct reads each tick.
/// Accumulates per-second waypoints, flushes batches to `ride_telemetry`,
/// and writes a summary back to `activities.metadata` on `stop()`.
///
/// Honest scope: this is best-effort recording, not safety-critical. If a
/// network flush fails, the batch is requeued for the next attempt. If the
/// app is killed mid-ride, the in-memory buffer is lost (but everything
/// already flushed is durable on the server).
@MainActor
final class RideTelemetryRecorder {

    private let activityId: String
    private let userId: String
    private weak var state: HUDState?

    private var sampleTimer: Timer?
    private var flushTimer: Timer?
    private var waypointBuffer: [Waypoint] = []
    private var flushedCount: Int = 0

    // Accumulators
    private var totalDistance_m: Double = 0
    private var maxSpeed_mps: Double = 0
    private var speedSum: Double = 0
    private var speedCount: Int = 0
    private var elevationGain_m: Double = 0
    private var elevationLoss_m: Double = 0
    private var hrSum: Double = 0
    private var hrCount: Int = 0
    private var hrMax: Double = 0
    private var hrMin: Double = .infinity
    private var zoneSeconds: [Int: TimeInterval] = [:]
    private var maxLean_rad: Double = 0
    private var maxAccelG: Double = 0
    private var lastLocationForDelta: CLLocation?
    private var lastAltitude_m: Double?
    private var lastSampleAt: Date?

    private let supabase = SupabaseClient.shared
    private let location = LocationService.shared
    private let motion   = MotionService.shared

    init(activityId: String, userId: String, state: HUDState) {
        self.activityId = activityId
        self.userId = userId
        self.state = state
    }

    func start() {
        location.start()
        motion.start()

        // Sampler — 1 Hz waypoints + accumulator advance.
        sampleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }

        // Flusher — batch upload every 30s.
        flushTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.flush() }
        }
    }

    /// Stop sampling, flush remaining waypoints, write summary onto the activity.
    func stop() async {
        sampleTimer?.invalidate(); sampleTimer = nil
        flushTimer?.invalidate(); flushTimer = nil
        location.stop()
        motion.stop()
        await flush()
        await writeSummary()
    }

    // MARK: - Per-second sampler

    private func sample() {
        let now = Date()
        let loc  = location.lastLocation
        let baro = location.baroAltitude
        let hr   = state?.liveHR
        let zone = (hr.map { HUDState.zoneIndex(for: $0) }) ?? -1

        // Zone-seconds — advance bucket of the *previous* zone by elapsed time.
        if let last = lastSampleAt, zone >= 0 {
            let delta = now.timeIntervalSince(last)
            zoneSeconds[zone, default: 0] += delta
        }
        lastSampleAt = now

        // Distance accumulator — reject impossible jumps + tiny GPS noise.
        if let cur = loc, let prev = lastLocationForDelta {
            let d = cur.distance(from: prev)
            if d > 0.5 && d < 500 { totalDistance_m += d }
        }
        if let cur = loc { lastLocationForDelta = cur }

        // Speed — CL gives -1 when unknown.
        if let s = loc?.speed, s >= 0 {
            maxSpeed_mps = max(maxSpeed_mps, s)
            speedSum += s
            speedCount += 1
        }

        // Elevation gain/loss — prefer barometric (smoother than GPS altitude).
        let altitude: Double? = baro ?? loc?.altitude
        if let alt = altitude {
            if let prev = lastAltitude_m {
                let d = alt - prev
                if d >  0.3 { elevationGain_m += d }
                else if d < -0.3 { elevationLoss_m -= d }
            }
            lastAltitude_m = alt
        }

        // HR aggregates.
        if let h = hr {
            hrSum += h
            hrCount += 1
            hrMax = max(hrMax, h)
            hrMin = min(hrMin, h)
        }

        // IMU summary extremes. Guard NaN/inf — IMU emits non-finite values
        // during sensor warm-up; max(0, NaN) = NaN, which would poison the summary.
        if let r = motion.roll_rad, r.isFinite {
            maxLean_rad = max(maxLean_rad, abs(r))
        }
        if let ax = motion.userAccelX, ax.isFinite,
           let ay = motion.userAccelY, ay.isFinite,
           let az = motion.userAccelZ, az.isFinite {
            let g = (ax * ax + ay * ay + az * az).squareRoot()
            if g.isFinite { maxAccelG = max(maxAccelG, g) }
        }

        // Buffer waypoint.
        let speedRaw: Double? = {
            guard let s = loc?.speed, s >= 0 else { return nil }
            return s
        }()
        let courseRaw: Double? = {
            guard let c = loc?.course, c >= 0 else { return nil }
            return c
        }()
        let wp = Waypoint(
            userId: userId,
            activityId: activityId,
            recordedAt: now,
            lat:          loc?.coordinate.latitude,
            lon:          loc?.coordinate.longitude,
            altitude_m:   loc?.altitude,
            baro_alt_m:   baro,
            speed_mps:    speedRaw,
            course_deg:   courseRaw,
            h_acc_m:      loc?.horizontalAccuracy,
            v_acc_m:      loc?.verticalAccuracy,
            heart_rate:   hr.map { Int($0) },
            zone_index:   zone >= 0 ? zone : nil,
            pitch_rad:    motion.pitch_rad,
            roll_rad:     motion.roll_rad,
            yaw_rad:      motion.yaw_rad,
            user_accel_x: motion.userAccelX,
            user_accel_y: motion.userAccelY,
            user_accel_z: motion.userAccelZ
        )
        waypointBuffer.append(wp)
    }

    // MARK: - Persistence

    private func flush() async {
        guard !waypointBuffer.isEmpty else { return }
        let batch = waypointBuffer
        waypointBuffer.removeAll(keepingCapacity: true)
        do {
            try await supabase.insertTelemetryBatch(waypoints: batch)
            flushedCount += batch.count
        } catch {
            // Best-effort: requeue for next flush.
            waypointBuffer.insert(contentsOf: batch, at: 0)
        }
    }

    private func writeSummary() async {
        let avgSpeed_mps = speedCount > 0 ? speedSum / Double(speedCount) : 0
        let totalWaypoints = flushedCount + waypointBuffer.count

        var summary: [String: Any] = [
            "phone_telemetry": true,
            "distance_m":      totalDistance_m,
            "max_speed_kmh":   maxSpeed_mps * 3.6,
            "avg_speed_kmh":   avgSpeed_mps * 3.6,
            "elev_gain_m":     elevationGain_m,
            "elev_loss_m":     elevationLoss_m,
            "max_lean_deg":    maxLean_rad * 180.0 / Double.pi,
            "max_accel_g":     maxAccelG,
            "waypoints":       totalWaypoints,
            "zone_seconds":    zoneSeconds.reduce(into: [String: Double]()) { $0["\($1.key)"] = $1.value }
        ]
        // Strip NaN/inf — JSON encoder would fail.
        for (k, v) in summary {
            if let d = v as? Double, !d.isFinite { summary[k] = 0.0 }
        }

        let hrAvg = hrCount > 0 ? hrSum / Double(hrCount) : nil
        let hrMaxFinal: Double? = hrMax > 0 ? hrMax : nil
        let hrMinFinal: Double? = hrMin.isFinite ? hrMin : nil

        try? await supabase.finalizeRideTelemetry(
            activityId: activityId,
            summary: summary,
            hrAvg: hrAvg,
            hrMax: hrMaxFinal,
            hrMin: hrMinFinal
        )
    }
}
