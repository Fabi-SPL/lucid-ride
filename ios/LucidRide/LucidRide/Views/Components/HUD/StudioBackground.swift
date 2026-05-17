import SwiftUI

/// Clean photographer's seamless backdrop for the bike scene.
///
/// The earlier "warehouse with warm/cool pendant pools + heavy vignette"
/// version read as muddy and wonky. This is the opposite: a calm neutral
/// charcoal sweep, like a real product-shoot cyclorama. Lighter at the
/// horizon (where the floor meets the wall), gently darker toward the
/// edges. No colour casts, no animation, no heavy vignette — the bike and
/// its lighting are the subject; the background just gets out of the way.
struct StudioBackground: View {
    var body: some View {
        ZStack {
            // Base neutral sweep — soft charcoal up top fading to deep
            // (not pure) black at the bottom. The mid "horizon" band is the
            // lightest part, like a seamless paper backdrop catching light.
            LinearGradient(
                stops: [
                    .init(color: Color(white: 0.10), location: 0.00),
                    .init(color: Color(white: 0.13), location: 0.42),  // horizon glow
                    .init(color: Color(white: 0.06), location: 0.72),
                    .init(color: Color(white: 0.03), location: 1.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Soft central key bloom — a single, neutral, very subtle pool
            // behind where the bike sits. Gives depth without colour or drama.
            RadialGradient(
                colors: [
                    Color(white: 0.20).opacity(0.55),
                    Color.clear
                ],
                center: UnitPoint(x: 0.5, y: 0.42),
                startRadius: 40,
                endRadius: 560
            )
            .blendMode(.plusLighter)
            .ignoresSafeArea()

            // Very light edge falloff — just enough to seat the bike in the
            // frame. Far gentler than the previous 0.55-black vignette.
            RadialGradient(
                colors: [Color.clear, Color.black.opacity(0.28)],
                center: .center,
                startRadius: 320,
                endRadius: 820
            )
            .blendMode(.multiply)
            .ignoresSafeArea()
        }
    }
}
