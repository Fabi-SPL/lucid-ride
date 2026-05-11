import SwiftUI

/// Black warehouse / studio backdrop for the cinematic bike scene.
///
/// Replaces AuroraBackground (which pulsed violet on HR) with a dark
/// industrial gradient: near-black at edges, slight warm grey in the upper
/// centre suggesting overhead pendant lights, fading to pure black at the
/// floor. The grey-and-amber centre catches the eye and reads as a real
/// physical space (warehouse with hanging lights) rather than abstract UI.
///
/// No animation by default — the bike itself is the moving subject. Subtle
/// breathing-grey halo at top centre uses TimelineView so the space feels
/// alive without distracting from the bike.
struct StudioBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            // Gentle breathing on the overhead light pool.
            let pulse = 0.85 + 0.15 * (sin(t * 0.4) * 0.5 + 0.5)

            ZStack {
                Color.black.ignoresSafeArea()

                // Vertical gradient — deep grey at top (skylight feel), pure
                // black at bottom (polished floor catches the bike).
                LinearGradient(
                    colors: [
                        Color(white: 0.08),
                        Color(white: 0.04),
                        Color(white: 0.015),
                        Color.black
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                // Off-centre warm pool — the "overhead pendant light."
                RadialGradient(
                    colors: [
                        Color(red: 0.16, green: 0.13, blue: 0.10).opacity(pulse * 0.65),
                        Color(red: 0.05, green: 0.04, blue: 0.04).opacity(0.0)
                    ],
                    center: UnitPoint(x: 0.35, y: 0.18),
                    startRadius: 20,
                    endRadius: 520
                )
                .blendMode(.plusLighter)
                .ignoresSafeArea()

                // Subtle cool counterpoint on the opposite side — cinematic
                // warm/cool separation. Reads as a second practical light.
                RadialGradient(
                    colors: [
                        Color(red: 0.08, green: 0.11, blue: 0.18).opacity(0.40),
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.78, y: 0.30),
                    startRadius: 10,
                    endRadius: 440
                )
                .blendMode(.plusLighter)
                .ignoresSafeArea()

                // Vignette — pulls the corners further into black so the
                // bike pops in the centre.
                RadialGradient(
                    colors: [Color.clear, Color.black.opacity(0.55)],
                    center: .center,
                    startRadius: 240,
                    endRadius: 720
                )
                .blendMode(.multiply)
                .ignoresSafeArea()
            }
        }
    }
}
