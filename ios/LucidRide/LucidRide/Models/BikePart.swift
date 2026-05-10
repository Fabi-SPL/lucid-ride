import SwiftUI

/// Tappable bike part — corresponds to a named SCNNode in BikeSceneView
/// and routes to a BikePartSheet panel showing relevant telemetry.
///
/// The bike IS the menu: tap any part → its data panel appears.
enum BikePart: String, CaseIterable, Identifiable {
    case headlight
    case tank
    case tailFairing
    case frontFairing
    case frontWheel
    case rearWheel

    var id: String { rawValue }
    var nodeName: String { rawValue }

    var displayName: String {
        switch self {
        case .headlight:    return "Body State"
        case .tank:         return "Fuel & Range"
        case .tailFairing:  return "Distance"
        case .frontFairing: return "Engine"
        case .frontWheel:   return "Front Tire"
        case .rearWheel:    return "Rear Tire"
        }
    }

    var subtitle: String {
        switch self {
        case .headlight:    return "Live HR · HRV · zone"
        case .tank:         return "Fuel level · estimated range"
        case .tailFairing:  return "GPS · trip distance · elapsed"
        case .frontFairing: return "Speed · RPM · gear · throttle"
        case .frontWheel:   return "PSI · temp · wear"
        case .rearWheel:    return "PSI · temp · chain · wear"
        }
    }

    var icon: String {
        switch self {
        case .headlight:    return "heart.fill"
        case .tank:         return "fuelpump.fill"
        case .tailFairing:  return "map.fill"
        case .frontFairing: return "speedometer"
        case .frontWheel:   return "tire"
        case .rearWheel:    return "tire"
        }
    }

    var accentColor: Color {
        switch self {
        case .headlight:    return DS.Colors.danger
        case .tank:         return DS.Colors.amber
        case .tailFairing:  return Color(hex: 0xA78BFA)
        case .frontFairing: return DS.Colors.violet
        case .frontWheel:   return DS.Colors.teal
        case .rearWheel:    return DS.Colors.teal
        }
    }

    /// True only for parts where Phase A has real data wired up. Currently
    /// only the headlight (Body State) reads from realtime_health.
    var hasLiveData: Bool {
        switch self {
        case .headlight: return true
        default:         return false
        }
    }
}
