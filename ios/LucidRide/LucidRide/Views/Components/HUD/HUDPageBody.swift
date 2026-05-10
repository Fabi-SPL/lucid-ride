import SwiftUI

/// HUD Page 1 — Body. Heart-rate-centric. Big number, zone label, live ECG
/// waveform. Optimized for landscape.
struct HUDPageBody: View {
    @ObservedObject var state: HUDState

    private var hr: Double? { state.liveHR }
    private var hrColor: Color { HUDState.zoneColor(for: hr) }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                // Big HR (left, hero)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(hrColor.opacity(0.85))
                        Text("HEART RATE")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(DS.Colors.textMuted)
                    }
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(hr.map { "\(Int($0))" } ?? "—")
                            .font(.system(size: 88, weight: .heavy, design: .rounded))
                            .foregroundStyle(hrColor)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text("BPM")
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(DS.Colors.textMuted)
                    }
                    Text(HUDState.zoneLabel(for: hr))
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(1.0)
                        .foregroundStyle(hrColor.opacity(0.85))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Right rail — HRV / score / elapsed (compact, monospaced)
                VStack(alignment: .trailing, spacing: 8) {
                    railStat(label: "HRV", value: state.hrvAtStart.map { "\(Int($0))" } ?? "—",
                             unit: "ms", color: DS.Colors.violet)
                    railStat(label: "ELAPSED", value: state.elapsedLabel,
                             unit: "", color: DS.Colors.teal)
                    railStat(label: "SCORE", value: "\(state.rideScore)",
                             unit: "/100", color: scoreColor)
                }
                .frame(width: 140)
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)

            // Waveform — full width, anchors the page
            LiveHRWaveform(samples: state.hrBuffer)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 18)
                .padding(.bottom, 14)
        }
    }

    @ViewBuilder
    private func railStat(label: String, value: String, unit: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(DS.Colors.textMuted)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(color)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(DS.Colors.textMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var scoreColor: Color {
        if state.rideScore >= 80 { return DS.Colors.success }
        if state.rideScore >= 60 { return DS.Colors.teal }
        if state.rideScore >= 40 { return DS.Colors.warning }
        return DS.Colors.danger
    }
}
