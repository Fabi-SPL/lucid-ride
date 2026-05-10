import Foundation
import SwiftUI

/// Single HR/HRV sample from the `realtime_health` table.
/// Used for the HR profile chart on RideDetailView.
struct HRSample: Codable, Identifiable {
    let ts: Date
    let hr: Double?
    let hrvRmssd: Double?

    enum CodingKeys: String, CodingKey {
        case ts
        case hr
        case hrvRmssd = "hrv_rmssd"
    }

    var id: TimeInterval { ts.timeIntervalSince1970 }
}

/// Snapshot of "should I be on a bike right now?" derived from latest HRV.
/// Three bands: green (push it), yellow (ride conservatively), red (consider not).
/// Thresholds match `DS.Colors.bodyStateColor(_:)`.
enum BodyStateBand: String {
    case green, yellow, red, unknown

    init(hrv: Double?) {
        guard let h = hrv else { self = .unknown; return }
        if h >= 70      { self = .green }
        else if h >= 45 { self = .yellow }
        else            { self = .red }
    }

    var label: String {
        switch self {
        case .green:   return "Cleared"
        case .yellow:  return "Conservative"
        case .red:     return "Reconsider"
        case .unknown: return "—"
        }
    }

    var copy: String {
        switch self {
        case .green:   return "Body's recovered. Push the corners if you want to."
        case .yellow:  return "Ride for the joy, not the pace. Keep margins."
        case .red:     return "Low recovery. Today's ride is the one to skip."
        case .unknown: return "Connect WHOOP via LucidBridge to see body state."
        }
    }
}
