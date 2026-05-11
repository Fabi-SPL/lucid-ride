import SwiftUI

/// Floating marker that hovers above a bike part, showing its icon + a
/// downward chevron pointing at the part. Driven by per-frame SCN projection
/// from `BikeSceneView`, so it orbits naturally with the bike.
///
/// Style: glass pill, SF Symbol icon, accent ring keyed to the part's colour.
/// "Live" parts get a soft pulsing halo so the headlight reads as "this one
/// is the real-data tile" without crowding the screen with labels.
struct PartMarker: View {
    let part: BikePart
    let isLive: Bool

    @State private var pulse = false

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                // Subtle ambient halo
                if isLive {
                    Circle()
                        .fill(part.accentColor.opacity(0.35))
                        .frame(width: 36, height: 36)
                        .blur(radius: 8)
                        .scaleEffect(pulse ? 1.20 : 0.95)
                        .opacity(pulse ? 0.75 : 0.45)
                }

                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle().stroke(part.accentColor.opacity(0.65), lineWidth: 1.0)
                    )

                Image(systemName: part.icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(part.accentColor)
            }

            // Downward chevron — the "arrow" pointing at the bike part.
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(part.accentColor.opacity(0.85))
                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
        }
        .onAppear {
            if isLive {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
    }
}
