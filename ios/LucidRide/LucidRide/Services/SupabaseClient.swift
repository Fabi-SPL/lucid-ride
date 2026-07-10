import Foundation

/// Focused Supabase client for LucidRide — direct anon-key access, no user auth.
///
/// As of 2026-05-17 the app reads/writes Supabase **directly with the public
/// anon key**. No email/password is baked into the binary anymore (that was the
/// public-repo credential-leak problem). Scoped RLS policies on the server
/// (`lucidride_anon_*`) let the `anon` role touch exactly Fabi's rows in:
///   - `activities`       — rides tagged `canonical_activity_type='motor_racing'` (SELECT/INSERT/UPDATE)
///   - `realtime_health`  — read-only HR/HRV profile (SELECT)
///
/// The anon key is public by design (it ships in every client). Security comes
/// from the row-scoped server policies, not from hiding the key.
///
/// No dependencies — just URLSession.
final class SupabaseClient {

    static let shared = SupabaseClient()

    let baseURL = "https://db.speed-running-life.com"
    let anonKey = "eyJhbGciOiAiSFMyNTYiLCAidHlwIjogIkpXVCJ9.eyJyb2xlIjogImFub24iLCAiaXNzIjogInN1cGFiYXNlIiwgImlhdCI6IDE3ODM2MjY1NjcsICJleHAiOiA5OTk5OTk5OTk5fQ.60fwzoea_PwWSwr0WVgyUA0Y0r5xZ47KqjZesjvC4nU"
    let userId  = "372210e5-1dda-41b3-b759-5ff72293b8ff"

    // Fail-fast session: 15 s request timeout + no connectivity-waiting, so an
    // offline flush / PATCH errors quickly instead of hanging the ride teardown.
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 30
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    var onLog: ((String) -> Void)?

    /// Always true now — no user session to expire. Kept so SettingsView /
    /// ContentView call sites compile unchanged.
    var isAuthenticated: Bool { true }

    private func log(_ msg: String) {
        let full = "[SB] \(msg)"
        print(full)
        onLog?(full)
    }

    private init() {}

    // MARK: - Request helper (anon key only)

    private func anonRequest(path: String,
                             method: String = "GET",
                             body: Any? = nil,
                             queryItems: [URLQueryItem] = []) -> URLRequest? {
        var components = URLComponents(string: "\(baseURL)\(path)")!
        if !queryItems.isEmpty { components.queryItems = queryItems }
        guard let url = components.url else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(anonKey,            forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return req
    }

    // MARK: - Auth shims (no-ops — kept for call-site compatibility)

    func signInIfNeeded() async { /* no auth needed — direct anon access */ }
    func signOut() { /* nothing to sign out of */ }

    // MARK: - Activities (motor_racing tagging)

    func fetchRides(limit: Int = 50) async throws -> [Ride] {
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "user_id",                  value: "eq.\(userId)"),
            URLQueryItem(name: "canonical_activity_type",  value: "eq.motor_racing"),
            URLQueryItem(name: "order",                    value: "started_at.desc"),
            URLQueryItem(name: "limit",                    value: "\(limit)")
        ]
        guard let req = anonRequest(path: "/rest/v1/activities", queryItems: queryItems) else {
            throw NSError(domain: "lucidride", code: 400)
        }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            log("fetchRides failed: \((resp as? HTTPURLResponse)?.statusCode ?? -1)")
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601withFractional
        return (try? decoder.decode([Ride].self, from: data)) ?? []
    }

    /// Start a ride — inserts a motor_racing activity row with `started_at = now()`,
    /// `ended_at = null`, source 'tap'. Returns the inserted row.
    func startRide() async throws -> Ride? {
        let nowISO = ISO8601DateFormatter.lucid.string(from: Date())
        let body: [String: Any] = [
            "user_id": userId,
            "canonical_activity_type": "motor_racing",
            "activity_type": "motorcycle",
            "started_at": nowISO,
            "source": "tap",
            "metadata": ["app": "LucidRide", "version": BuildInfo.codeVersion, "bike": "RS125"]
        ]
        guard var req = anonRequest(path: "/rest/v1/activities", method: "POST", body: body) else {
            return nil
        }
        req.setValue("return=representation", forHTTPHeaderField: "Prefer")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            log("startRide failed: \((resp as? HTTPURLResponse)?.statusCode ?? -1)")
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601withFractional
        return (try? decoder.decode([Ride].self, from: data))?.first
    }

    /// End the active ride — sets `ended_at = now()` on the activity row.
    func endRide(activityId: String) async throws {
        let nowISO = ISO8601DateFormatter.lucid.string(from: Date())
        let queryItems = [URLQueryItem(name: "id", value: "eq.\(activityId)")]
        guard let req = anonRequest(
            path: "/rest/v1/activities",
            method: "PATCH",
            body: ["ended_at": nowISO],
            queryItems: queryItems
        ) else { return }
        let (_, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            log("endRide failed: \(http.statusCode)")
        }
    }

    /// Fetch a single ride by activity ID — used by PostRideSummarySheet to
    /// re-read the metadata after finalizeRideTelemetry PATCH lands.
    func fetchRideById(_ activityId: String) async throws -> Ride? {
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "id",      value: "eq.\(activityId)"),
            URLQueryItem(name: "limit",   value: "1")
        ]
        guard let req = anonRequest(path: "/rest/v1/activities", queryItems: queryItems) else {
            return nil
        }
        let (data, _) = try await session.data(for: req)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601withFractional
        return (try? decoder.decode([Ride].self, from: data))?.first
    }

    /// Returns the active (ended_at IS NULL) ride STARTED BY THIS APP, or nil.
    ///
    /// Critically filters `source=eq.tap`: the shared `activities` table also
    /// holds Lucid's auto-detected motor_racing rows (75+ of them vs the user's
    /// handful of taps). Without this filter the app resurrected an auto-detected
    /// ride as "active" on every launch and could never be ended. Also ignores
    /// anything older than 8 h so a stale un-ended ride can't zombie back.
    func activeRide() async throws -> Ride? {
        let cutoff = ISO8601DateFormatter.lucid.string(from: Date().addingTimeInterval(-8 * 3600))
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "user_id",                  value: "eq.\(userId)"),
            URLQueryItem(name: "canonical_activity_type",  value: "eq.motor_racing"),
            URLQueryItem(name: "source",                   value: "eq.tap"),
            URLQueryItem(name: "ended_at",                 value: "is.null"),
            URLQueryItem(name: "started_at",               value: "gte.\(cutoff)"),
            URLQueryItem(name: "order",                    value: "started_at.desc"),
            URLQueryItem(name: "limit",                    value: "1")
        ]
        guard let req = anonRequest(path: "/rest/v1/activities", queryItems: queryItems) else {
            return nil
        }
        let (data, _) = try await session.data(for: req)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601withFractional
        return (try? decoder.decode([Ride].self, from: data))?.first
    }

    // MARK: - realtime_health (window query)

    func fetchHRWindow(start: Date, end: Date) async throws -> [HRSample] {
        let startISO = ISO8601DateFormatter.lucid.string(from: start)
        let endISO   = ISO8601DateFormatter.lucid.string(from: end)
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "select",       value: "recorded_at,heart_rate,hrv_rmssd"),
            URLQueryItem(name: "user_id",      value: "eq.\(userId)"),
            URLQueryItem(name: "recorded_at",  value: "gte.\(startISO)"),
            URLQueryItem(name: "recorded_at",  value: "lte.\(endISO)"),
            URLQueryItem(name: "heart_rate",   value: "not.is.null"),
            URLQueryItem(name: "order",        value: "recorded_at.asc"),
            URLQueryItem(name: "limit",        value: "10000")
        ]
        guard let req = anonRequest(path: "/rest/v1/realtime_health", queryItems: queryItems) else {
            return []
        }
        let (data, _) = try await session.data(for: req)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601withFractional
        return (try? decoder.decode([HRSample].self, from: data)) ?? []
    }

    func fetchLatestHRV() async throws -> Double? {
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "select",    value: "hrv_rmssd"),
            URLQueryItem(name: "user_id",   value: "eq.\(userId)"),
            URLQueryItem(name: "hrv_rmssd", value: "not.is.null"),
            URLQueryItem(name: "order",     value: "recorded_at.desc"),
            URLQueryItem(name: "limit",     value: "1")
        ]
        guard let req = anonRequest(path: "/rest/v1/realtime_health", queryItems: queryItems) else {
            return nil
        }
        let (data, _) = try await session.data(for: req)
        let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        return (arr?.first?["hrv_rmssd"] as? Double)
    }

    /// Latest HR reading from realtime_health — polled every few seconds by HUDState.
    /// FRESHNESS GUARD: only accept a reading from the last 120 s. If the Whoop
    /// pipeline stops streaming (BLE drop / LucidHealth not running), the table
    /// goes stale and the newest row is just whatever was last seen — e.g. a
    /// resting 74 bpm from before the ride. Without this, that stale value gets
    /// shown AND recorded as "live" for the whole ride (Fabi 2026-06-08: HR
    /// frozen at 74 across 5,390 waypoints). Stale → no row → nil → HUD shows
    /// "—" and the recorder writes no HR, instead of a fake flatline.
    func fetchLatestHR() async throws -> HRSample? {
        let freshISO = ISO8601DateFormatter.lucid.string(from: Date().addingTimeInterval(-120))
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "select",      value: "recorded_at,heart_rate,hrv_rmssd"),
            URLQueryItem(name: "user_id",     value: "eq.\(userId)"),
            URLQueryItem(name: "heart_rate",  value: "not.is.null"),
            URLQueryItem(name: "recorded_at", value: "gte.\(freshISO)"),
            URLQueryItem(name: "order",       value: "recorded_at.desc"),
            URLQueryItem(name: "limit",       value: "1")
        ]
        guard let req = anonRequest(path: "/rest/v1/realtime_health", queryItems: queryItems) else {
            return nil
        }
        let (data, _) = try await session.data(for: req)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601withFractional
        return (try? decoder.decode([HRSample].self, from: data))?.first
    }

    // MARK: - Ride telemetry persistence

    /// Builds the JSON-ready body for a batch insert. Exposed so
    /// `TelemetryUploader` can stash a failed batch to disk and retry it
    /// later via BGProcessingTask without re-encoding from Waypoint structs.
    func telemetryBatchBody(waypoints: [Waypoint]) -> [[String: Any]]? {
        guard !waypoints.isEmpty else { return nil }
        return waypoints.map { wp in
            return waypointDict(wp)
        }
    }

    private func waypointDict(_ wp: Waypoint) -> [String: Any] {
        var dict: [String: Any] = [
            "user_id":     wp.userId,
            "activity_id": wp.activityId,
            "recorded_at": ISO8601DateFormatter.lucidFractional.string(from: wp.recordedAt)
        ]
        if let v = finite(wp.lat)          { dict["lat"]          = v }
        if let v = finite(wp.lon)          { dict["lon"]          = v }
        if let v = finite(wp.altitude_m)   { dict["altitude_m"]   = v }
        if let v = finite(wp.baro_alt_m)   { dict["baro_alt_m"]   = v }
        if let v = finite(wp.speed_mps)    { dict["speed_mps"]    = v }
        if let v = finite(wp.course_deg)   { dict["course_deg"]   = v }
        if let v = finite(wp.h_acc_m)      { dict["h_acc_m"]      = v }
        if let v = finite(wp.v_acc_m)      { dict["v_acc_m"]      = v }
        if let v = wp.heart_rate           { dict["heart_rate"]   = v }
        if let v = wp.zone_index           { dict["zone_index"]   = v }
        if let v = finite(wp.pitch_rad)    { dict["pitch_rad"]    = v }
        if let v = finite(wp.roll_rad)     { dict["roll_rad"]     = v }
        if let v = finite(wp.yaw_rad)      { dict["yaw_rad"]      = v }
        if let v = finite(wp.user_accel_x) { dict["user_accel_x"] = v }
        if let v = finite(wp.user_accel_y) { dict["user_accel_y"] = v }
        if let v = finite(wp.user_accel_z) { dict["user_accel_z"] = v }
        if let v = finite(wp.lean_deg_gps) { dict["lean_deg_gps"] = v }
        if let v = finite(wp.compass_deg)  { dict["compass_deg"]  = v }
        dict["is_paused"] = wp.is_paused
        return dict
    }

    /// Batch-insert phone-side waypoints into `ride_telemetry`.
    /// Called periodically by `RideTelemetryRecorder` (every 30 s).
    ///
    /// Every numeric field is run through `finite(_:)` because the IMU emits
    /// NaN/inf during sensor warm-up and `JSONSerialization` throws on those
    /// — a single NaN in any field would otherwise nuke the entire batch.
    func insertTelemetryBatch(waypoints: [Waypoint]) async throws {
        guard !waypoints.isEmpty else { return }
        let body = waypoints.map { waypointDict($0) }
        guard let req = anonRequest(path: "/rest/v1/ride_telemetry", method: "POST", body: body) else {
            throw NSError(domain: "lucidride", code: 400)
        }
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let snippet = String(data: data, encoding: .utf8)?.prefix(300) ?? ""
            log("insertTelemetryBatch failed: \(http.statusCode) — \(snippet)")
            throw NSError(domain: "lucidride", code: http.statusCode)
        }
    }

    /// Returns the value only if it's a real finite number; nil for NaN, +/-inf, or nil input.
    /// IMU/GPS occasionally emit NaN before sensor warm-up — those poison JSON encoding.
    private func finite(_ v: Double?) -> Double? {
        guard let v, v.isFinite else { return nil }
        return v
    }

    /// Patches the active activity row with phone-telemetry summary + HR aggregates.
    /// Summary lives inside `metadata` JSONB (merged with existing keys) to avoid
    /// schema migrations; HR aggregates use the existing `hr_avg/hr_peak/hr_min`
    /// columns.
    func finalizeRideTelemetry(activityId: String,
                               summary: [String: Any],
                               hrAvg: Double?,
                               hrMax: Double?,
                               hrMin: Double?) async throws {
        let existing = (try? await fetchActivityMetadata(activityId: activityId)) ?? [:]
        var merged: [String: Any] = existing
        for (k, v) in summary { merged[k] = v }

        var body: [String: Any] = ["metadata": merged]
        if let v = hrAvg { body["hr_avg"]  = Int(v.rounded()) }
        if let v = hrMax { body["hr_peak"] = Int(v.rounded()) }
        if let v = hrMin { body["hr_min"]  = Int(v.rounded()) }

        let queryItems = [URLQueryItem(name: "id", value: "eq.\(activityId)")]
        guard let req = anonRequest(path: "/rest/v1/activities",
                                    method: "PATCH",
                                    body: body,
                                    queryItems: queryItems) else {
            throw NSError(domain: "lucidride", code: 400)
        }
        let (_, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            log("finalizeRideTelemetry failed: \(http.statusCode)")
            throw NSError(domain: "lucidride", code: http.statusCode)
        }
    }

    private func fetchActivityMetadata(activityId: String) async throws -> [String: Any]? {
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "select", value: "metadata"),
            URLQueryItem(name: "id",     value: "eq.\(activityId)")
        ]
        guard let req = anonRequest(path: "/rest/v1/activities", queryItems: queryItems) else {
            return nil
        }
        let (data, _) = try await session.data(for: req)
        let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        return arr?.first?["metadata"] as? [String: Any]
    }

    /// Fetch the waypoints for a completed ride, ordered ascending by time.
    /// Used by PostRideSummarySheet to render the route map + lean overlay.
    /// Selects only the fields needed for visualization to keep payload small.
    func fetchRideTelemetry(activityId: String, limit: Int = 5000) async throws -> [TelemetryRow] {
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "select",      value: "recorded_at,lat,lon,speed_mps,heart_rate,zone_index,lean_deg_gps,is_paused"),
            URLQueryItem(name: "activity_id", value: "eq.\(activityId)"),
            URLQueryItem(name: "lat",         value: "not.is.null"),
            URLQueryItem(name: "lon",         value: "not.is.null"),
            URLQueryItem(name: "order",       value: "recorded_at.asc"),
            URLQueryItem(name: "limit",       value: "\(limit)")
        ]
        guard let req = anonRequest(path: "/rest/v1/ride_telemetry", queryItems: queryItems) else {
            return []
        }
        let (data, _) = try await session.data(for: req)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601withFractional
        return (try? decoder.decode([TelemetryRow].self, from: data)) ?? []
    }
}

/// Decode-only projection of a `ride_telemetry` row for post-ride visualization.
/// The full Waypoint struct in RideTelemetryRecorder is encode-only (snake_case
/// JSON-dict construction); this is the read-side counterpart with proper Codable.
struct TelemetryRow: Decodable, Identifiable {
    let recordedAt: Date
    let lat: Double?
    let lon: Double?
    let speed_mps: Double?
    let heart_rate: Int?
    let zone_index: Int?
    let lean_deg_gps: Double?
    let is_paused: Bool?

    var id: Date { recordedAt }

    enum CodingKeys: String, CodingKey {
        case recordedAt = "recorded_at"
        case lat, lon
        case speed_mps, heart_rate, zone_index, lean_deg_gps, is_paused
    }
}

// MARK: - Date formatter helpers

extension JSONDecoder.DateDecodingStrategy {
    /// ISO 8601 with optional fractional seconds (Supabase mixes both formats).
    static var iso8601withFractional: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let d = ISO8601DateFormatter.lucidFractional.date(from: str) { return d }
            if let d = ISO8601DateFormatter.lucid.date(from: str) { return d }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(str)")
        }
    }
}

extension ISO8601DateFormatter {
    static let lucid: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    static let lucidFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
