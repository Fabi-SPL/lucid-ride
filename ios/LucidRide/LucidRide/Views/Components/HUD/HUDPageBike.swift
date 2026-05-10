import SwiftUI

/// HUD Page 4 — Bike. The 3D bike IS the menu: tap any part to drill into
/// its data. Headlight = body state (real). Wheels / tank / fairings =
/// telemetry placeholders rendered with full data slots ready for Phase B.
struct HUDPageBike: View {
    @ObservedObject var state: HUDState
    @State private var selectedPart: BikePart?
    @State private var hintVisible = true

    var body: some View {
        ZStack {
            BikeSceneView(
                leanDegrees: state.placeholderLean,
                pulseBPM: state.liveHR,
                accentColor: HUDState.zoneColor(for: state.liveHR),
                onPartTap: { part in
                    hintVisible = false
                    selectedPart = part
                }
            )

            VStack {
                Spacer()
                if hintVisible {
                    tapHint
                        .padding(.bottom, 14)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .sheet(item: $selectedPart) { part in
            BikePartSheet(part: part, state: state)
        }
        .task {
            // Auto-fade the tap hint after 6 seconds
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            withAnimation(DS.Anim.standard) { hintVisible = false }
        }
    }

    private var tapHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(DS.Colors.violet)
            Text("Tap any part of the bike for its data")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(DS.Colors.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(Color.white.opacity(0.06))
        )
        .overlay(
            Capsule().stroke(DS.Colors.violet.opacity(0.30), lineWidth: 0.5)
        )
    }
}
