import SwiftUI

/// Pure-black canvas with a subtle violet mesh cloud that pulses at the
/// current heart rate. Replaces a flat black background — adds ambient life
/// without distraction. Beat-synced via TimelineView.
struct AuroraBackground: View {
    let pulseBPM: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pulseInterval: Double {
        guard let bpm = pulseBPM, bpm > 30 else { return 1.0 }
        return 60.0 / bpm
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            // Heart-beat envelope: 1.0 at peak, 0.55 at trough
            let phase = (t.truncatingRemainder(dividingBy: pulseInterval)) / pulseInterval
            let beat = pow(sin(phase * .pi), 3.0) // sharp spike, slow decay
            let intensity = 0.55 + 0.45 * beat

            // Ambient drift, decoupled from the beat
            let driftX = Float(sin(t * 0.05) * 0.08)
            let driftY = Float(cos(t * 0.04) * 0.06)

            ZStack {
                Color.black.ignoresSafeArea()

                MeshGradient(
                    width: 3, height: 3,
                    points: [
                        [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                        [0.0, 0.5], [0.5 + driftX, 0.5 + driftY], [1.0, 0.5],
                        [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
                    ],
                    colors: [
                        Color.black, Color(hex: 0x0A0612), Color.black,
                        Color(hex: 0x0A0612),
                        DS.Colors.violet.opacity(0.18 * intensity),
                        Color(hex: 0x0A0612),
                        Color.black, Color(hex: 0x0A0612), Color.black
                    ]
                )
                .ignoresSafeArea()
                .blur(radius: 24)
                .blendMode(.plusLighter)
                .opacity(0.85)

                // Second slow cloud — teal, opposite drift, much subtler
                MeshGradient(
                    width: 2, height: 2,
                    points: [
                        [0.10, 0.20],
                        [0.85 - driftX * 2, 0.20],
                        [0.20 + driftX * 2, 0.85],
                        [0.85, 0.85]
                    ],
                    colors: [
                        Color.clear,
                        DS.Colors.teal.opacity(0.06 * intensity),
                        DS.Colors.teal.opacity(0.05 * intensity),
                        Color.clear
                    ]
                )
                .ignoresSafeArea()
                .blur(radius: 32)
                .blendMode(.plusLighter)
            }
        }
    }
}
