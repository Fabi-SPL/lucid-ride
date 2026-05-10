import SwiftUI

/// HUD Page 2 — Ride. Lean horizon hero + 3 smaller stats (Lap / Elapsed / Score).
/// Designed to glance-read while riding: lean = top priority, lap/elapsed/score
/// secondary.
struct HUDPageRide: View {
    @ObservedObject var state: HUDState

    var body: some View {
        VStack(spacing: 8) {
            // Lean horizon — hero at top
            LeanHorizonView(leanDegrees: state.placeholderLean)
                .frame(height: 110)
                .padding(.horizontal, 14)
                .padding(.top, 8)

            // 3 compact stat cells, equal width
            HStack(spacing: 10) {
                statCell(
                    icon: "flag.checkered",
                    label: "LAP",
                    value: "\(state.lapCount)",
                    sub: "best —",
                    color: DS.Colors.success
                )
                statCell(
                    icon: "clock.fill",
                    label: "ELAPSED",
                    value: state.elapsedLabel,
                    sub: state.rideStartedAt.map { "since \($0.formatted(date: .omitted, time: .shortened))" } ?? "no active ride",
                    color: DS.Colors.teal
                )
                statCell(
                    icon: "star.fill",
                    label: "SCORE",
                    value: "\(state.rideScore)",
                    sub: "/ 100",
                    color: scoreColor
                )
            }
            .padding(.horizontal, 14)
            .frame(maxHeight: .infinity)
            .padding(.bottom, 14)
        }
    }

    @ViewBuilder
    private func statCell(icon: String, label: String, value: String, sub: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(color.opacity(0.85))
                Text(label)
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(DS.Colors.textMuted)
            }
            Text(value)
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(sub)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(DS.Colors.textFaint)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(color.opacity(0.30), lineWidth: 0.6)
        )
        .shadow(color: color.opacity(0.15), radius: 16, x: 0, y: 0)
    }

    private var scoreColor: Color {
        if state.rideScore >= 80 { return DS.Colors.success }
        if state.rideScore >= 60 { return DS.Colors.teal }
        if state.rideScore >= 40 { return DS.Colors.warning }
        return DS.Colors.danger
    }
}
