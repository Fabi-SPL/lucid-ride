import SwiftUI

/// HUD Page 4 — Bike. 3D motorcycle that leans with the lean angle.
/// SceneKit-rendered, brand-colored, runs at 60fps.
struct HUDPageBike: View {
    @ObservedObject var state: HUDState

    var body: some View {
        ZStack {
            BikeSceneView(
                leanDegrees: state.placeholderLean,
                pulseBPM: state.liveHR,
                accentColor: HUDState.zoneColor(for: state.liveHR)
            )
            .padding(.bottom, 40)

            VStack {
                Spacer()
                HStack(spacing: 14) {
                    miniStat(label: "LEAN",
                             value: "\(Int(state.placeholderLean))°",
                             color: leanColor,
                             pending: true)
                    miniStat(label: "HR",
                             value: state.liveHR.map { "\(Int($0))" } ?? "—",
                             color: HUDState.zoneColor(for: state.liveHR),
                             pending: false)
                    miniStat(label: "SCORE",
                             value: "\(state.rideScore)",
                             color: scoreColor,
                             pending: false)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
            }
        }
    }

    @ViewBuilder
    private func miniStat(label: String, value: String, color: Color, pending: Bool) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(DS.Colors.textMuted)
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(pending ? color.opacity(0.55) : color)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(color.opacity(0.25), lineWidth: 0.5)
        )
    }

    private var leanColor: Color {
        let abs = Swift.abs(state.placeholderLean)
        if abs < 25 { return DS.Colors.teal }
        if abs < 40 { return DS.Colors.success }
        if abs < 50 { return DS.Colors.warning }
        return DS.Colors.danger
    }

    private var scoreColor: Color {
        if state.rideScore >= 80 { return DS.Colors.success }
        if state.rideScore >= 60 { return DS.Colors.teal }
        if state.rideScore >= 40 { return DS.Colors.warning }
        return DS.Colors.danger
    }
}
