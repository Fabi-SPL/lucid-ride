import Foundation

/// Per-ride roll-up of RaceBox samples, from the `ride_tracker_summary` view.
///
/// The phone and the box record complementary halves of a ride: the phone owns GPS,
/// speed, route and HR; the box owns lean, lean rate and G. The box has no clock of
/// its own, so nothing linked the two until the tracker started stamping a real epoch
/// into each log (LRD4) — the server then binds every sample to the activity whose
/// time window contains it. This is the read side of that binding.
struct TrackerSummary: Codable, Equatable {
    let activityId:     String
    let samples:        Int
    let maxLeanDeg:     Double?
    let leanLeftDeg:    Double?     // most negative lean seen (left side)
    let leanRightDeg:   Double?     // most positive lean seen (right side)
    let maxG:           Double?
    let maxLeanRateDps: Double?
    let firstAt:        Date?
    let lastAt:         Date?

    enum CodingKeys: String, CodingKey {
        case activityId     = "activity_id"
        case samples
        case maxLeanDeg     = "max_lean_deg"
        case leanLeftDeg    = "lean_left_deg"
        case leanRightDeg   = "lean_right_deg"
        case maxG           = "max_g"
        case maxLeanRateDps = "max_lean_rate_dps"
        case firstAt        = "first_at"
        case lastAt         = "last_at"
    }

    /// A handful of samples is a connection blip, not a ride worth showing lean for.
    var isMeaningful: Bool { samples >= 60 }
}

/// A stretch of RaceBox data with no matching phone ride — the days the box went out
/// alone. Grouped server-side by 10-minute gaps in `tracker_sessions`.
struct TrackerSession: Codable, Equatable, Identifiable {
    let device:     String
    let grp:        Int
    let startedAt:  Date
    let endedAt:    Date
    let samples:    Int
    let maxLeanDeg: Double?
    let maxG:       Double?

    var id: String { "\(device)-\(grp)" }
    var durationSeconds: TimeInterval { endedAt.timeIntervalSince(startedAt) }

    enum CodingKeys: String, CodingKey {
        case device, grp, samples
        case startedAt  = "started_at"
        case endedAt    = "ended_at"
        case maxLeanDeg = "max_lean_deg"
        case maxG       = "max_g"
    }
}

/// One history list, both sources. Before this the two halves lived in different places —
/// phone rides in Supabase, box rides as .bin files on a laptop — so no screen ever showed
/// the whole picture.
enum TimelineItem: Identifiable {
    case ride(Ride)
    case boxOnly(TrackerSession)

    var id: String {
        switch self {
        case .ride(let r):    return "ride-\(r.id)"
        case .boxOnly(let s): return "box-\(s.id)"
        }
    }

    var date: Date {
        switch self {
        case .ride(let r):    return r.startedAt
        case .boxOnly(let s): return s.startedAt
        }
    }
}

