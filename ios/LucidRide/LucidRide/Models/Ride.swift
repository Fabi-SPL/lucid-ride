import Foundation

/// Ride row mapped from the existing Supabase `activities` table where
/// `canonical_activity_type = 'motor_racing'`. The activities table is the
/// rides table — see lucid-ride/CLAUDE.md "Common Mistake #4".
///
/// Fields below are a subset of the full activities schema (lucid Health uses
/// the same table for non-ride activities). LucidRide reads/writes only what
/// it needs.
struct Ride: Codable, Identifiable, Equatable {
    let id: String
    let userId: String?
    let canonicalActivityType: String?
    let activityType: String?
    let startedAt: Date
    let endedAt: Date?
    let hrAvg: Double?
    let hrPeak: Double?
    let hrMin: Double?
    let hrvAvg: Double?
    let strainContribution: Double?
    let source: String?
    let metadata: RideMetadata?

    enum CodingKeys: String, CodingKey {
        case id
        case userId                = "user_id"
        case canonicalActivityType = "canonical_activity_type"
        case activityType          = "activity_type"
        case startedAt             = "started_at"
        case endedAt               = "ended_at"
        case hrAvg                 = "hr_avg"
        case hrPeak                = "hr_peak"
        case hrMin                 = "hr_min"
        case hrvAvg                = "hrv_avg"
        case strainContribution    = "strain_contribution"
        case source
        case metadata
    }

    var isActive: Bool { endedAt == nil }

    /// Duration in seconds — uses ended_at if set, otherwise time-since-started.
    var durationSeconds: TimeInterval {
        let end = endedAt ?? Date()
        return end.timeIntervalSince(startedAt)
    }

    /// Human-readable duration: "32m" / "1h 12m" / "2h"
    var durationLabel: String {
        let total = Int(durationSeconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h == 0 { return "\(m)m" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }
}

/// Free-form jsonb on `activities.metadata`. LucidRide stamps app + version + bike;
/// future telemetry fields (lean_max, distance_km, route_id) go here too.
struct RideMetadata: Codable, Equatable {
    let app:       String?
    let version:   String?
    let bike:      String?
    let leanMax:   Double?
    let distanceKm: Double?
    let routeId:   String?

    enum CodingKeys: String, CodingKey {
        case app, version, bike
        case leanMax    = "lean_max"
        case distanceKm = "distance_km"
        case routeId    = "route_id"
    }
}
