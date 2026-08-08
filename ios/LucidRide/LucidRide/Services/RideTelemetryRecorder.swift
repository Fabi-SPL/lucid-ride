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
    let lean_deg_gps: Double?    // GPS-derived lean angle (signed: + right, - left)
    let compass_deg: Double?     // true compass bearing, valid even at standstill
    let is_paused: Bool          // recorder was in auto-pause state for this tick
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
    private var lastFlushNote: String = "no flush yet"
    private var sampleCount: Int = 0

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
    private var maxLeanGps_deg: Double = 0

    // Outlier rejection. A phone on a bike sees GPS jumps and mount vibration; both used
    // to land in ride metadata verbatim (879 km/h tops, 8.08 g peaks).
    private static let speedCeiling_mps: Double = 55      // 198 km/h — far above the bike, far below a GPS jump
    private static let maxAccel_mps2:    Double = 12      // 1.2 g, generous for a 125
    private static let accelCeiling_g:   Double = 3.0
    private var lastAcceptedSpeed_mps: Double = 0
    private var lastSpeedAt: Date? = nil
    private var rejectedSpeedSamples = 0
    // Peak G is reported as the SECOND highest per-second maximum. A single vibration
    // spike is one sample; real hard braking spans several seconds.
    private var accelTop1: Double = 0
    private var accelTop2: Double = 0
    private var maxImuLean_deg: Double = 0       // calibrated gravity-based lean peak
    private var leanBaselineDeg: Double? = nil   // gravity angle captured at upright start
    private var lastLocationForDelta: CLLocation?
    private var lastAltitude_m: Double?
    private var lastSampleAt: Date?

    // GPS-lean state — keeps the last 3 valid bearings for smoothing per
    // RaceChrono/AiM 3-sample FIR consensus (deep-research 2026-05-28).
    private var bearingHistory: [(t: Date, bearing: Double, speed_mps: Double)] = []

    private let supabase = SupabaseClient.shared
    private let location = LocationService.shared
    private let motion   = MotionService.shared
    private let live     = LiveActivityController.shared
    private let health   = HealthKitController.shared
    private let rideStartedAt: Date

    init(activityId: String, userId: String, state: HUDState) {
        self.activityId = activityId
        self.userId = userId
        self.state = state
        self.rideStartedAt = Date()
    }

    func start() {
        location.start()
        motion.start()
        live.start(startedAt: rideStartedAt)
        health.startWorkout(startedAt: rideStartedAt)

        // Sampler — driven by BOTH a 1 Hz timer (foreground / while stopped)
        // AND every GPS fix (works in the background, where the timer is
        // suspended). sample() throttles itself to ~1 Hz so the two don't
        // double-count. This is the fix for rides that logged almost nothing
        // once the screen locked.
        sampleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        location.onLocationUpdate = { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }

        // Flusher — batch upload every 10s (was 30s; short test rides never
        // reached the first flush otherwise).
        flushTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.flush() }
        }
    }

    /// Recorder heartbeat for the on-device debug line. Tells us, with zero
    /// dependence on the network, whether sampling + flushing are actually
    /// happening: `buf` grows = sampler runs; `sent` grows = inserts land;
    /// `ERR <n>` = the insert is failing with that code (negative = URLError).
    private func pushDebug() {
        let v = Int((state?.liveSpeedKmh ?? 0).rounded())
        let l = Int((state?.liveLeanDeg ?? 0).rounded())
        let gps = lastLocationForDelta != nil ? "fix" : "noGPS"
        state?.liveDebug = "buf \(waypointBuffer.count)·sent \(flushedCount)·v\(v)·L\(l)·\(gps)·\(lastFlushNote)"
    }

    /// Stop sampling, flush remaining waypoints, write summary onto the activity.
    func stop() async {
        sampleTimer?.invalidate(); sampleTimer = nil
        flushTimer?.invalidate(); flushTimer = nil
        location.onLocationUpdate = nil
        location.stop()
        motion.stop()
        // Persist data FIRST (remaining waypoints + summary) so a force-quit
        // during the slower HealthKit finish can't lose hr_avg / distance.
        await flush()
        await writeSummary()
        // Foreground bulk-drain: END is on-screen with full signal, so push
        // everything the ride stashed to disk now instead of waiting for the
        // system to grant a background slot.
        await TelemetryUploader.shared.flushPendingNow()
        live.end()
        await health.finishWorkout(endedAt: Date())
        // If anything failed to upload, ask iOS to retry in the background
        // when signal comes back. No-op when nothing's pending.
        TelemetryUploader.shared.scheduleFlushIfNeeded()
    }

    // MARK: - Per-second sampler

    private func sample() {
        let now = Date()
        // Throttle: the 1 Hz timer AND every GPS callback both call this; keep
        // a single ~1 Hz cadence so they don't double-count.
        if let last = lastSampleAt, now.timeIntervalSince(last) < 0.8 { return }
        let loc  = location.lastLocation
        let baro = location.baroAltitude
        let hr   = state?.liveHR
        let zone = (hr.map { HUDState.zoneIndex(for: $0) }) ?? -1
        let motionStats = motion.consumeRollingStats()

        // Auto-pause state machine. Use GPS speed (course is unreliable at low
        // speed). When speed < 1.5 km/h for > 30 s, pause; resume on > 5 km/h.
        let elapsedTick: TimeInterval = lastSampleAt.map { now.timeIntervalSince($0) } ?? 0
        // CoreLocation reports speed = -1 at walking pace / sparse fixes, which
        // zeroed the HUD speed, starved the lean calc, and falsely auto-paused.
        // Fall back to position-delta speed when Doppler is unavailable.
        let effSpeed_mps: Double? = effectiveSpeedMps(cur: loc, prev: lastLocationForDelta, dt: elapsedTick)
        let speedNow_mps: Double = max(0, effSpeed_mps ?? -1)
        // Auto-pause REMOVED (Fabi: it false-paused at red lights and was
        // confusing on the lock screen). Record continuously — stops are part
        // of the ride. isAutoPaused stays false the whole ride.

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

        // Feed GPS to HealthKit route builder (HK aggregates internally).
        if recordingActive, let cur = loc, cur.horizontalAccuracy < 30 {
            health.addLocation(cur)
        }

        // Speed — effSpeed_mps already falls back to position-delta when CL's
        // Doppler speed is -1 (walking pace / sparse fixes). That fallback is what
        // produced 879 km/h all-time tops: one bad fix "moves" you 200 m in a second.
        // Reject anything past a physical ceiling or implying more than 1.2 g of
        // acceleration since the last accepted sample; a real top-speed run survives
        // both, an isolated GPS jump survives neither.
        if recordingActive, let s = effSpeed_mps, s >= 0 {
            let dt = lastSpeedAt.map { now.timeIntervalSince($0) } ?? 1
            let window = max(dt, 0.5)
            let plausible = s <= Self.speedCeiling_mps
                && (speedCount == 0 || abs(s - lastAcceptedSpeed_mps) <= Self.maxAccel_mps2 * window)
            if plausible {
                maxSpeed_mps = max(maxSpeed_mps, s)
                speedSum += s
                speedCount += 1
                lastAcceptedSpeed_mps = s
            } else {
                rejectedSpeedSamples += 1
            }
            lastSpeedAt = now
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
        // Phone-IMU lean is OFF by default — a free-rotating mount makes it
        // meaningless. Use a rigid sensor (RaceBox) for real lean. We still
        // record peak G (magnitude is far less mount-sensitive than lean angle).
        let leanOn = UserDefaults.standard.bool(forKey: "lucidride.leanEnabled")
        if recordingActive {
            if leanOn, motionStats.maxAbsRoll_rad.isFinite { maxLean_rad = max(maxLean_rad, motionStats.maxAbsRoll_rad) }
            let g = motionStats.maxAccelG
            if g.isFinite, g <= Self.accelCeiling_g {
                if g > accelTop1 { accelTop2 = accelTop1; accelTop1 = g }
                else if g > accelTop2 { accelTop2 = g }
                maxAccelG = accelTop2
            }
        }

        // GPS-derived lean angle (RaceChrono/AiM formula: atan(v² / (r·g)) with
        // 3-sample FIR smoothing and turn radius from consecutive bearings).
        let leanGpsDeg: Double? = (recordingActive && leanOn) ? gpsLeanAngleDeg(loc: loc, speedMps: speedNow_mps, now: now) : nil
        if let l = leanGpsDeg, l.isFinite {
            maxLeanGps_deg = max(maxLeanGps_deg, abs(l))
        }

        // Recalibrate-on-demand: re-zero lean to the current resting position.
        // Fabi taps "zero" with the bike upright in its fixed mount (flat on the
        // tank). Clears the baseline so the next sample re-captures it.
        if state?.leanZeroRequested == true {
            leanBaselineDeg = nil
            maxImuLean_deg = 0
            state?.leanZeroRequested = false
        }

        // IMU lean from the gravity vector — the REAL bike body angle (vs GPS
        // lean which only sees path curvature). MOUNT-AGNOSTIC: works whether
        // the phone lies FLAT on the tank or stands UPRIGHT on a stand, as long
        // as its long edge runs along the bike. Lean = how far gravity tips
        // toward the device's lateral (x) axis, out of the forward+up (y-z)
        // plane: atan2(gx, hypot(gy, gz)). Baseline captured at the first sample
        // (or on recalibrate) assumes the bike is upright at that moment.
        var imuLeanDeg: Double? = nil
        if leanOn, let gx = motion.gravityX, let gy = motion.gravityY, let gz = motion.gravityZ {
            // Lateral axis depends on mount: phone long-edge ACROSS the bike
            // (landscape) → lateral = y; long-edge ALONG the bike (portrait) →
            // lateral = x. Toggle in Settings ("mounted sideways"); default y.
            let lateralY = (UserDefaults.standard.object(forKey: "lucidride.leanLateralY") as? Bool) ?? true
            let raw = (lateralY
                       ? atan2(gy, (gx * gx + gz * gz).squareRoot())
                       : atan2(gx, (gy * gy + gz * gz).squareRoot())) * 180.0 / Double.pi
            if leanBaselineDeg == nil { leanBaselineDeg = raw }
            var l = raw - (leanBaselineDeg ?? raw)
            if l > 180 { l -= 360 }
            if l < -180 { l += 360 }
            if l.isFinite {
                // Negate: as mounted, gravity-x grew toward the device's LEFT, so a
                // right lean came out negative and the HUD read "LEFT" while leaning
                // right (Fabi, 2026-06-07). Flip → right = positive = RIGHT, matching
                // the GPS-lean convention and the gauge tilt. Live HUD + recorded.
                imuLeanDeg = -l
                maxImuLean_deg = max(maxImuLean_deg, abs(l))
            }
        }

        // Buffer waypoint.
        let speedRaw: Double? = effSpeed_mps.flatMap { $0 >= 0 ? $0 : nil }
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
            user_accel_z: motion.userAccelZ,
            lean_deg_gps: leanGpsDeg,
            compass_deg:  location.compassHeading,
            is_paused:    isAutoPaused
        )
        waypointBuffer.append(wp)

        // Push to Dynamic Island + Lock Screen (silent no-op if disabled).
        let elapsed = Int(now.timeIntervalSince(rideStartedAt))
        let speedKmh = Int(((effSpeed_mps ?? 0).rounded()) * 3.6)
        live.update(
            speedKmh:       max(0, speedKmh),
            heartRate:      hr.map { Int($0) } ?? 0,
            zoneIndex:      zone,
            elapsedSeconds: elapsed,
            distanceMeters: Int(totalDistance_m),
            leanDeg:        Int(leanGpsDeg ?? 0),
            isPaused:       isAutoPaused
        )

        // Mirror the live values into HUDState so the in-ride HUD renders them.
        // (HR + elapsed are already maintained by HUDState's own pollers.)
        if let st = state {
            st.liveSpeedKmh   = Double(max(0, speedKmh))
            st.liveLeanDeg    = leanOn ? (imuLeanDeg ?? (leanGpsDeg ?? 0)) : 0   // IMU is the real body angle
            st.liveDistanceM  = totalDistance_m
            st.liveMaxLeanDeg = leanOn ? maxImuLean_deg : 0   // match the live gauge (IMU), not GPS lean
            st.livePeakG      = maxAccelG
            st.liveElevGainM  = elevationGain_m
            st.liveIsPaused   = isAutoPaused
        }

        // First-5-samples kick: flush early so even a 15 s test ride proves the
        // write path instead of waiting for the 10 s timer to line up.
        sampleCount += 1
        // Flush off the SAMPLER (not just the foreground 10s timer) so batches
        // get stashed to disk in the background, where that timer is suspended.
        // First-5 kick proves the path on a short test ride; then every ~10 s.
        if sampleCount == 5 || sampleCount % 10 == 0 { Task { @MainActor in await self.flush() } }

        pushDebug()
    }

    /// Computes lean angle from GPS using `lean = atan(v² / (r·g))` where
    /// turn radius r is derived from change in bearing over distance traveled.
    /// Direction sign comes from the bearing-change cross product (right turn =
    /// positive, left turn = negative). Returns nil when speed is too low for
    /// stable lean computation or insufficient bearing history.
    ///
    /// Formula consensus per RaceChrono/AiM forums + Hackaday GPS-lean writeup
    /// (deep-research 2026-05-28).
    /// Effective speed (m/s): CoreLocation's Doppler speed when valid (>= 0),
    /// else derived from the position delta since the last fix. CL emits -1 at
    /// walking pace / with sparse fixes, which previously zeroed the HUD and
    /// false-tripped auto-pause.
    private func effectiveSpeedMps(cur: CLLocation?, prev: CLLocation?, dt: TimeInterval) -> Double? {
        if let s = cur?.speed, s >= 0 { return s }
        guard let cur, let prev, dt > 0.2 else { return nil }
        let d = cur.distance(from: prev)
        guard d > 0.3, d < 500 else { return nil }   // ignore GPS jitter + teleports
        return d / dt
    }

    private func gpsLeanAngleDeg(loc: CLLocation?, speedMps: Double, now: Date) -> Double? {
        guard let loc, speedMps > 3.0,            // skip < ~11 km/h
              loc.course >= 0,                    // course is invalid below ~5 km/h
              loc.horizontalAccuracy < 20         // skip noisy fixes
        else { return nil }

        // Maintain a 3-sample FIR window of recent (time, bearing, speed) tuples.
        bearingHistory.append((t: now, bearing: loc.course, speed_mps: speedMps))
        if bearingHistory.count > 3 { bearingHistory.removeFirst(bearingHistory.count - 3) }
        guard bearingHistory.count == 3 else { return nil }

        let first = bearingHistory[0]
        let last  = bearingHistory[2]
        let dt = last.t.timeIntervalSince(first.t)
        guard dt > 0.5 else { return nil }

        // Bearing delta — wrap to [-180, +180] so a 359→1° crossing is +2°, not -358°.
        var dB = last.bearing - first.bearing
        if dB >  180 { dB -= 360 }
        if dB < -180 { dB += 360 }

        // Yaw rate in rad/s
        let yawRate = (dB * .pi / 180.0) / dt
        guard abs(yawRate) > 0.01 else { return 0.0 }   // straight = 0 lean

        // Average speed across the window
        let v = (first.speed_mps + last.speed_mps + bearingHistory[1].speed_mps) / 3.0
        guard v > 1.0 else { return nil }

        // Centripetal accel = v * yawRate (signed). Lean = atan(a_c / g).
        let a_c = v * yawRate
        let leanRad = atan(a_c / 9.81)
        let leanDeg = leanRad * 180.0 / .pi
        return leanDeg.isFinite ? leanDeg : nil
    }

    // MARK: - Persistence

    private func flush() async {
        guard !waypointBuffer.isEmpty else { return }
        let batch = waypointBuffer
        waypointBuffer.removeAll(keepingCapacity: true)
        // DISK FIRST: persist the batch BEFORE the network attempt. The sampler
        // runs in the background (GPS callback) but the upload can be suspended
        // or the app killed mid-flight — RAM was the only copy, so a 64-min ride
        // held 3,849 points in memory and only 10 reached the server (Fabi,
        // 2026-06-07). Stash now → drain later via END / foreground / BG task.
        let stashName = supabase.telemetryBatchBody(waypoints: batch).flatMap {
            TelemetryUploader.shared.stashFailedBatch($0)
        }
        do {
            try await supabase.insertTelemetryBatch(waypoints: batch)
            flushedCount += batch.count
            // Live upload won — drop the disk copy so it isn't sent twice.
            if let stashName { TelemetryUploader.shared.removeStashed(stashName) }
            lastFlushNote = "ok +\(batch.count)"
        } catch {
            // Already safe on disk; do NOT requeue into waypointBuffer (that would
            // double-upload once the stash drains). Leave it for the drainers.
            let ns = error as NSError
            lastFlushNote = "stash \(ns.code) \(ns.domain.replacingOccurrences(of: "NSURLErrorDomain", with: "net"))"
        }
        pushDebug()
    }

    private func writeSummary() async {
        let avgSpeed_mps = speedCount > 0 ? speedSum / Double(speedCount) : 0
        let totalWaypoints = flushedCount + waypointBuffer.count

        var summary: [String: Any] = [
            "phone_telemetry":    true,
            "distance_m":         totalDistance_m,
            "max_speed_kmh":      maxSpeed_mps * 3.6,
            "avg_speed_kmh":      avgSpeed_mps * 3.6,
            "elev_gain_m":        elevationGain_m,
            "elev_loss_m":        elevationLoss_m,
            "max_accel_g":        maxAccelG,
            "waypoints":          totalWaypoints,
            "paused_seconds":     pausedSeconds,
            "zone_seconds":       zoneSeconds.reduce(into: [String: Double]()) { $0["\($1.key)"] = $1.value }
        ]
        // Lean is deliberately absent unless the phone-IMU experiment is switched back on.
        // The phone shifts inside the holder, so its lean is noise; the RaceBox owns lean.
        // Writing 0 here was worse than writing nothing — the ride detail read it as
        // "you never leaned" instead of "not measured".
        if UserDefaults.standard.bool(forKey: "lucidride.leanEnabled") {
            summary["max_lean_deg"]     = maxImuLean_deg
            summary["max_lean_deg_gps"] = maxLeanGps_deg
        }
        if rejectedSpeedSamples > 0 { summary["rejected_speed_samples"] = rejectedSpeedSamples }
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
