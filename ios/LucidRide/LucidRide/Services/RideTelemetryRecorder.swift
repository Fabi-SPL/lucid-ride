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
final class RideTelemetryRecorder: ObservableObject {

    private let activityId: String
    private let userId: String
    private weak var state: HUDState?

    /// Auto-paused when speed < 1.5 km/h for > 30 s (REVER-pattern). Surfaces
    /// to the HUD so the user sees "⏸ Auto-paused" instead of thinking the
    /// recorder froze. Resume on speed > 5 km/h.
    @Published private(set) var isAutoPaused: Bool = false
    private var lowSpeedRunSeconds: TimeInterval = 0
    private static let pauseThresholdSeconds: TimeInterval = 30
    private static let pauseSpeedThreshold_mps: Double = 1.5 / 3.6
    private static let resumeSpeedThreshold_mps: Double = 5.0 / 3.6

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
    private var pausedSeconds: TimeInterval = 0
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
        let motionStats = motion.consumeRollingStats()

        // Auto-pause state machine. Use GPS speed (course is unreliable at low
        // speed). When speed < 1.5 km/h for > 30 s, pause; resume on > 5 km/h.
        let speedNow_mps: Double = max(0, loc?.speed ?? -1)
        let elapsedTick: TimeInterval = lastSampleAt.map { now.timeIntervalSince($0) } ?? 0
        if speedNow_mps < Self.pauseSpeedThreshold_mps {
            lowSpeedRunSeconds += elapsedTick
            if !isAutoPaused && lowSpeedRunSeconds > Self.pauseThresholdSeconds {
                isAutoPaused = true
            }
        } else if speedNow_mps > Self.resumeSpeedThreshold_mps {
            lowSpeedRunSeconds = 0
            if isAutoPaused { isAutoPaused = false }
        }

        // Zone-seconds — advance bucket of the *current* HR zone by tick. If
        // auto-paused, accumulate to `pausedSeconds` instead so the zone bar
        // reflects active-ride time only.
        if lastSampleAt != nil, zone >= 0 {
            if isAutoPaused { pausedSeconds += elapsedTick }
            else            { zoneSeconds[zone, default: 0] += elapsedTick }
        }
        lastSampleAt = now

        // Skip everything below this line when auto-paused EXCEPT we still
        // store the waypoint with `is_paused = true` so the post-ride map can
        // visualize stops.
        let recordingActive = !isAutoPaused

        // Distance accumulator — reject impossible jumps + tiny GPS noise.
        if recordingActive, let cur = loc, let prev = lastLocationForDelta {
            let d = cur.distance(from: prev)
            if d > 0.5 && d < 500 { totalDistance_m += d }
        }
        if let cur = loc { lastLocationForDelta = cur }

        // Speed — CL gives -1 when unknown.
        if recordingActive, let s = loc?.speed, s >= 0 {
            maxSpeed_mps = max(maxSpeed_mps, s)
            speedSum += s
            speedCount += 1
        }

        // Elevation gain/loss — prefer barometric (smoother than GPS altitude).
        let altitude: Double? = baro ?? loc?.altitude
        if recordingActive, let alt = altitude {
            if let prev = lastAltitude_m {
                let d = alt - prev
                if d >  0.3 { elevationGain_m += d }
                else if d < -0.3 { elevationLoss_m -= d }
            }
            lastAltitude_m = alt
        } else if let alt = altitude {
            lastAltitude_m = alt   // keep baseline fresh during pause
        }

        // HR aggregates (continue accumulating during pause — HR doesn't stop
        // when you stop moving, and the data is interesting either way).
        if let h = hr {
            hrSum += h
            hrCount += 1
            hrMax = max(hrMax, h)
            hrMin = min(hrMin, h)
        }

        // IMU summary extremes — consume rolling stats (max within this 1 s
        // window, sampled at 100 Hz). Preserves peak lean / accel events that
        // would otherwise be averaged out at 1 Hz.
        if recordingActive {
            if motionStats.maxAbsRoll_rad.isFinite { maxLean_rad = max(maxLean_rad, motionStats.maxAbsRoll_rad) }
            if motionStats.maxAccelG.isFinite { maxAccelG = max(maxAccelG, motionStats.maxAccelG) }
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
            pitch_rad:    motionStats.avgPitch_rad ?? motion.pitch_rad,
            roll_rad:     motionStats.avgRoll_rad  ?? motion.roll_rad,
            yaw_rad:      motionStats.avgYaw_rad   ?? motion.yaw_rad,
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
            "paused_seconds":  pausedSeconds,
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
