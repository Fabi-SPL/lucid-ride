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
    let anonKey = "eyJhbGciOiAiSFMyNTYiLCAidHlwIjogIkpXVCJ9.eyJyb2xlIjogImFub24iLCAiaXNzIjogInN1cGFiYXNlIiwgImlhdCI6IDE3NDEyOTQ4MDAsICJleHAiOiA5OTk5OTk5OTk5fQ.y3KAL0j_RC9hlzrNVkgZXPxifyRZX3cF_d7-iuE4kA8"
    let userId  = "372210e5-1dda-41b3-b759-5ff72293b8ff"

    private let session = URLSession.shared

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

    /// Returns the active (ended_at IS NULL) motor_racing activity, or nil if none.
    func activeRide() async throws -> Ride? {
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "user_id",                  value: "eq.\(userId)"),
            URLQueryItem(name: "canonical_activity_type",  value: "eq.motor_racing"),
            URLQueryItem(name: "ended_at",                 value: "is.null"),
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
    func fetchLatestHR() async throws -> HRSample? {
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "select",     value: "recorded_at,heart_rate,hrv_rmssd"),
            URLQueryItem(name: "user_id",    value: "eq.\(userId)"),
            URLQueryItem(name: "heart_rate", value: "not.is.null"),
            URLQueryItem(name: "order",      value: "recorded_at.desc"),
            URLQueryItem(name: "limit",      value: "1")
        ]
        guard let req = anonRequest(path: "/rest/v1/realtime_health", queryItems: queryItems) else {
            return nil
        }
        let (data, _) = try await session.data(for: req)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601withFractional
        return (try? decoder.decode([HRSample].self, from: data))?.first
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
