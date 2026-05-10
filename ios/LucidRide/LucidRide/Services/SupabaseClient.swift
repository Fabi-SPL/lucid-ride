import Foundation

/// Focused Supabase client for LucidRide — auth + activities (motor_racing) + realtime_health JOINs only.
///
/// Cloned conceptually from LucidHealth's SupabaseClient (which is 2200 lines and covers
/// food, recovery, sleep, BLE telemetry — all of which we don't need here). LucidRide
/// shares the same Supabase project, anon key, and user_id, but only touches:
///   - `activities`           — rides tagged `canonical_activity_type = 'motor_racing'`
///   - `realtime_health`      — read-only JOIN by ride window (HRV/HR profile)
///
/// No dependencies — just URLSession.
final class SupabaseClient {

    static let shared = SupabaseClient()

    // CI replaces these at build time via sed injection (see .github/workflows/build-lucidride.yml)
    static let prefilledEmail:    String = "BUILD_EMAIL"
    static let prefilledPassword: String = "BUILD_PASSWORD"

    let baseURL = "https://db.speed-running-life.com"
    let anonKey = "eyJhbGciOiAiSFMyNTYiLCAidHlwIjogIkpXVCJ9.eyJyb2xlIjogImFub24iLCAiaXNzIjogInN1cGFiYXNlIiwgImlhdCI6IDE3NDEyOTQ4MDAsICJleHAiOiA5OTk5OTk5OTk5fQ.y3KAL0j_RC9hlzrNVkgZXPxifyRZX3cF_d7-iuE4kA8"
    let userId  = "372210e5-1dda-41b3-b759-5ff72293b8ff"

    internal var accessToken: String?
    private  var tokenExpiry: Date?
    private  let session = URLSession.shared

    var onLog: ((String) -> Void)?

    private func log(_ msg: String) {
        let full = "[SB] \(msg)"
        print(full)
        onLog?(full)
    }

    // UserDefaults — sandboxed per app bundle. Per-app keys keep sibling-app
    // login states from shadowing each other.
    private var email: String {
        UserDefaults.standard.string(forKey: "lucidride_email") ?? ""
    }
    private var password: String {
        UserDefaults.standard.string(forKey: "lucidride_password") ?? ""
    }

    var isAuthenticated: Bool {
        accessToken != nil && (tokenExpiry.map { Date() < $0 } ?? false)
    }

    private init() {}

    // MARK: - Auth

    /// Idempotent sign-in. Returns immediately if a valid token exists; otherwise
    /// prefills credentials from CI-injected static constants on first run, then
    /// posts to /auth/v1/token?grant_type=password.
    func signInIfNeeded() async {
        if isAuthenticated { return }

        // First-run prefill — copy CI-baked credentials into UserDefaults if empty
        if (UserDefaults.standard.string(forKey: "lucidride_email") ?? "").isEmpty {
            UserDefaults.standard.set(Self.prefilledEmail,    forKey: "lucidride_email")
            UserDefaults.standard.set(Self.prefilledPassword, forKey: "lucidride_password")
        }

        guard !email.isEmpty, !password.isEmpty,
              email != "BUILD_EMAIL", password != "BUILD_PASSWORD" else {
            log("signInIfNeeded skipped — no credentials baked in")
            return
        }

        let url = URL(string: "\(baseURL)/auth/v1/token?grant_type=password")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(anonKey,           forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["email": email, "password": password])

        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                log("auth failed: \((resp as? HTTPURLResponse)?.statusCode ?? -1)")
                return
            }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            self.accessToken = json?["access_token"] as? String
            let expiresIn   = (json?["expires_in"] as? Double) ?? 3600
            self.tokenExpiry = Date().addingTimeInterval(expiresIn - 60) // refresh 1m early
            log("authenticated until \(tokenExpiry!.formatted())")
        } catch {
            log("auth error: \(error)")
        }
    }

    func signOut() {
        accessToken = nil
        tokenExpiry = nil
        UserDefaults.standard.removeObject(forKey: "lucidride_email")
        UserDefaults.standard.removeObject(forKey: "lucidride_password")
    }

    // MARK: - Request helper

    private func authedRequest(path: String, method: String = "GET", body: Any? = nil, queryItems: [URLQueryItem] = []) async -> URLRequest? {
        await signInIfNeeded()
        guard let token = accessToken else { return nil }

        var components = URLComponents(string: "\(baseURL)\(path)")!
        if !queryItems.isEmpty { components.queryItems = queryItems }
        guard let url = components.url else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(anonKey,            forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)",  forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return req
    }

    // MARK: - Activities (motor_racing tagging)

    /// Fetch the most recent N motor_racing activities, newest first.
    func fetchRides(limit: Int = 50) async throws -> [Ride] {
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "user_id",                  value: "eq.\(userId)"),
            URLQueryItem(name: "canonical_activity_type",  value: "eq.motor_racing"),
            URLQueryItem(name: "order",                    value: "started_at.desc"),
            URLQueryItem(name: "limit",                    value: "\(limit)")
        ]
        guard let req = await authedRequest(path: "/rest/v1/activities", queryItems: queryItems) else {
            throw NSError(domain: "lucidride", code: 401)
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
        guard var req = await authedRequest(path: "/rest/v1/activities", method: "POST", body: body) else {
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
    /// Caller is responsible for refreshing the rides list.
    func endRide(activityId: String) async throws {
        let nowISO = ISO8601DateFormatter.lucid.string(from: Date())
        let queryItems = [URLQueryItem(name: "id", value: "eq.\(activityId)")]
        guard let req = await authedRequest(
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
        guard let req = await authedRequest(path: "/rest/v1/activities", queryItems: queryItems) else {
            return nil
        }
        let (data, _) = try await session.data(for: req)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601withFractional
        return (try? decoder.decode([Ride].self, from: data))?.first
    }

    // MARK: - realtime_health (window query)

    /// Fetch HR samples from the realtime_health table within a time window.
    /// Used to render the post-ride HR profile chart on RideDetailView.
    func fetchHRWindow(start: Date, end: Date) async throws -> [HRSample] {
        let startISO = ISO8601DateFormatter.lucid.string(from: start)
        let endISO   = ISO8601DateFormatter.lucid.string(from: end)
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "select",    value: "ts,hr,hrv_rmssd"),
            URLQueryItem(name: "user_id",   value: "eq.\(userId)"),
            URLQueryItem(name: "ts",        value: "gte.\(startISO)"),
            URLQueryItem(name: "ts",        value: "lte.\(endISO)"),
            URLQueryItem(name: "order",     value: "ts.asc"),
            URLQueryItem(name: "limit",     value: "10000")
        ]
        guard let req = await authedRequest(path: "/rest/v1/realtime_health", queryItems: queryItems) else {
            return []
        }
        let (data, _) = try await session.data(for: req)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601withFractional
        return (try? decoder.decode([HRSample].self, from: data)) ?? []
    }

    /// Latest HRV reading from realtime_health — drives the body-state band on TodayView.
    func fetchLatestHRV() async throws -> Double? {
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "select",  value: "hrv_rmssd"),
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "hrv_rmssd", value: "not.is.null"),
            URLQueryItem(name: "order",   value: "ts.desc"),
            URLQueryItem(name: "limit",   value: "1")
        ]
        guard let req = await authedRequest(path: "/rest/v1/realtime_health", queryItems: queryItems) else {
            return nil
        }
        let (data, _) = try await session.data(for: req)
        let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        return (arr?.first?["hrv_rmssd"] as? Double)
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
