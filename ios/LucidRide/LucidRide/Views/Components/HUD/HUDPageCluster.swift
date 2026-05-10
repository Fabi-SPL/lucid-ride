import SwiftUI

/// HUD Page 3 — Cluster. Two big analog dials side by side: HR (left, BPM)
/// and Lean (right, degrees). The "this is a real instrument cluster" page.
struct HUDPageCluster: View {
    @ObservedObject var state: HUDState

    var body: some View {
        HStack(spacing: 24) {
            BigAnalogSpeedo(
                value: state.liveHR ?? 0,
                max: 200,
                label: "HEART RATE",
                unit: "BPM",
                color: HUDState.zoneColor(for: state.liveHR),
                placeholder: state.liveHR == nil
            )
            .padding(8)

            BigAnalogSpeedo(
                value: abs(state.placeholderLean),
                max: 60,
                label: "LEAN",
                unit: "°",
                color: leanColor,
                placeholder: true
            )
            .padding(8)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxHeight: .infinity)
    }

    private var leanColor: Color {
        let abs = Swift.abs(state.placeholderLean)
        if abs < 25 { return DS.Colors.teal }
        if abs < 40 { return DS.Colors.success }
        if abs < 50 { return DS.Colors.warning }
        return DS.Colors.danger
    }
}
