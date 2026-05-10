import SwiftUI

/// Slide-up sheet shown when a bike part is tapped. Renders the relevant
/// telemetry section for that part — real data when wired (headlight = HR),
/// "Hardware pending" placeholder for the rest until Phase B.
struct BikePartSheet: View {
    let part: BikePart
    @ObservedObject var state: HUDState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            DS.Colors.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                handle
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        if part.hasLiveData {
                            liveContent
                        } else {
                            pendingContent
                        }
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 12)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(DS.Colors.bg)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: part.icon)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(part.accentColor)
                .frame(width: 56, height: 56)
                .background(
                    Circle().fill(part.accentColor.opacity(0.14))
                )
                .overlay(
                    Circle().stroke(part.accentColor.opacity(0.30), lineWidth: 0.6)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(part.displayName.uppercased())
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(DS.Colors.textMuted)
                Text(part.subtitle)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.textPrimary)
                    .lineLimit(2)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(DS.Colors.textFaint)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
        }
    }

    private var handle: some View {
        Capsule()
            .fill(DS.Colors.textFaint.opacity(0.4))
            .frame(width: 38, height: 4)
    }

    // MARK: - Live (Body State / headlight only — real data)

    @ViewBuilder
    private var liveContent: some View {
        let band = BodyStateBand(hrv: state.hrvAtStart)

        VStack(alignment: .leading, spacing: 10) {
            heroRow(
                value: state.liveHR.map { "\(Int($0))" } ?? "—",
                unit: "BPM",
                color: HUDState.zoneColor(for: state.liveHR),
                label: HUDState.zoneLabel(for: state.liveHR)
            )

            sectionDivider

            metricGrid(items: [
                ("HRV (latest)", state.hrvAtStart.map { "\(Int($0)) ms" } ?? "—", DS.Colors.violet),
                ("Body state", band.label, DS.Colors.bodyStateColor(state.hrvAtStart ?? 0)),
                ("Last sample", lastSampleLabel, DS.Colors.textSecondary),
                ("Stream", state.hrIsStale ? "stale" : "live",
                    state.hrIsStale ? DS.Colors.warning : DS.Colors.success)
            ])

            sectionDivider

            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("BAND COPY")
                Text(band.copy)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.textSecondary)
                    .lineLimit(nil)
            }
        }
    }

    private var lastSampleLabel: String {
        let age = state.lastSampleAge
        if !age.isFinite { return "—" }
        if age < 10 { return "just now" }
        if age < 60 { return "\(Int(age))s ago" }
        if age < 3600 { return "\(Int(age / 60))m ago" }
        return "\(Int(age / 3600))h ago"
    }

    // MARK: - Pending (placeholder Phase B parts)

    @ViewBuilder
    private var pendingContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            heroRow(value: "—", unit: pendingUnit, color: part.accentColor.opacity(0.55), label: "HARDWARE PENDING")

            sectionDivider

            metricGrid(items: pendingMetrics)

            sectionDivider

            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("ARRIVES IN PHASE B")
                Text(pendingDescription)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.textSecondary)
                    .lineLimit(nil)
            }

            // Subtle outlined card noting the sensor source
            HStack(spacing: 10) {
                Image(systemName: "sensor.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(part.accentColor)
                Text(pendingSource)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.textPrimary)
                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(part.accentColor.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(part.accentColor.opacity(0.25), lineWidth: 0.5)
            )
        }
    }

    private var pendingUnit: String {
        switch part {
        case .tank:         return "L"
        case .tailFairing:  return "KM"
        case .frontFairing: return "RPM"
        case .frontWheel,
             .rearWheel:    return "PSI"
        default:            return ""
        }
    }

    private var pendingMetrics: [(String, String, Color)] {
        switch part {
        case .tank:
            return [("Fuel level", "—", DS.Colors.amber),
                    ("Estimated range", "—", DS.Colors.amber),
                    ("Last refuel", "—", DS.Colors.textMuted),
                    ("Avg consumption", "—", DS.Colors.textMuted)]
        case .tailFairing:
            return [("Trip distance", "—", DS.Colors.violet),
                    ("Total ride time", state.elapsedLabel, DS.Colors.teal),
                    ("Avg speed", "—", DS.Colors.textMuted),
                    ("Lap count", "\(state.lapCount)", DS.Colors.success)]
        case .frontFairing:
            return [("Speed", "—", DS.Colors.violet),
                    ("RPM", "—", DS.Colors.danger),
                    ("Gear", "—", DS.Colors.amber),
                    ("Throttle", "—", DS.Colors.warning)]
        case .frontWheel:
            return [("Pressure", "—", DS.Colors.teal),
                    ("Temperature", "—", DS.Colors.warning),
                    ("Tread wear", "—", DS.Colors.textMuted),
                    ("Compound", "—", DS.Colors.textMuted)]
        case .rearWheel:
            return [("Pressure", "—", DS.Colors.teal),
                    ("Temperature", "—", DS.Colors.warning),
                    ("Tread wear", "—", DS.Colors.textMuted),
                    ("Chain tension", "—", DS.Colors.textMuted)]
        case .headlight: return []
        }
    }

    private var pendingDescription: String {
        switch part {
        case .tank:         return "Fuel level + range arrive once OBD adapter (OBDLink MX+) is connected to the bike's ECU."
        case .tailFairing:  return "Distance + map track wire up after the GPS pipeline (RaceBox Mini S + GoPro GPMF) ships."
        case .frontFairing: return "Speed, RPM, and gear come from OBD. Throttle position is read off the same bus."
        case .frontWheel:   return "TPMS sensors (third-party Bluetooth pressure caps) feed PSI + temp. Tread wear is computed from km elapsed since reset."
        case .rearWheel:    return "Same TPMS source. Chain tension is a planned manual log entry every 500 km."
        case .headlight:    return ""
        }
    }

    private var pendingSource: String {
        switch part {
        case .tank:         return "Source: OBD adapter via Bluetooth"
        case .tailFairing:  return "Source: RaceBox Mini S + GoPro GPMF"
        case .frontFairing: return "Source: OBD adapter (SwiftOBD2 lib)"
        case .frontWheel,
             .rearWheel:    return "Source: TPMS Bluetooth pressure caps"
        case .headlight:    return ""
        }
    }

    // MARK: - Reusable building blocks

    @ViewBuilder
    private func heroRow(value: String, unit: String, color: Color, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .foregroundStyle(color)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(unit)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(DS.Colors.textMuted)
            }
            Text(label)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(color.opacity(0.85))
        }
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(DS.Colors.border)
            .frame(height: 0.5)
            .padding(.vertical, 4)
    }

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .tracking(1.0)
            .foregroundStyle(DS.Colors.textMuted)
    }

    @ViewBuilder
    private func metricGrid(items: [(String, String, Color)]) -> some View {
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(items, id: \.0) { (label, value, color) in
                VStack(alignment: .leading, spacing: 4) {
                    Text(label.uppercased())
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(1.0)
                        .foregroundStyle(DS.Colors.textMuted)
                    Text(value)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(color)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(color.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(color.opacity(0.20), lineWidth: 0.5)
                )
            }
        }
    }
}
