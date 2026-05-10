import SwiftUI

/// Particle effect overlay. Fires a radial burst of colored dots on every
/// `trigger` value change. Used by the HUD to celebrate HR-zone changes,
/// max-lean events, or other "you just did a thing" moments.
///
/// Particles fall to gravity and fade out. Self-cleaning — empties the
/// array when no particles remain alive.
struct ParticleBurst: View {
    let trigger: Int
    var origin: CGPoint = .zero       // .zero = use canvas center
    var color: Color = DS.Colors.violet
    var count: Int = 28

    @State private var particles: [Particle] = []
    @State private var lastTrigger = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Particle: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        var vx: CGFloat
        var vy: CGFloat
        var life: Double
        var color: Color
        var size: CGFloat
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 : 1.0 / 30.0)) { ctx in
            Canvas { canvas, size in
                for p in particles {
                    let r = p.size * p.life
                    let rect = CGRect(x: p.x - r, y: p.y - r, width: r*2, height: r*2)
                    canvas.opacity = p.life
                    canvas.fill(Path(ellipseIn: rect), with: .color(p.color))
                }
            }
            .onChange(of: ctx.date) { _, _ in
                tick()
            }
            .onChange(of: trigger, initial: false) { _, new in
                guard !reduceMotion, new != lastTrigger else { return }
                lastTrigger = new
                spawn()
            }
        }
        .allowsHitTesting(false)
    }

    private func spawn() {
        let cx = origin == .zero ? UIScreen.main.bounds.width / 2 : origin.x
        let cy = origin == .zero ? UIScreen.main.bounds.height / 2 : origin.y
        let palette: [Color] = [color, DS.Colors.teal, DS.Colors.success, color.opacity(0.7)]
        for _ in 0..<count {
            let angle = Double.random(in: 0..<2 * .pi)
            let speed = Double.random(in: 90...260)
            let dt = 1.0 / 30.0
            particles.append(Particle(
                x: cx,
                y: cy,
                vx: CGFloat(cos(angle) * speed * dt),
                vy: CGFloat(sin(angle) * speed * dt),
                life: 1.0,
                color: palette.randomElement() ?? color,
                size: CGFloat(Double.random(in: 3...6))
            ))
        }
    }

    private func tick() {
        guard !particles.isEmpty else { return }
        particles = particles.compactMap { p in
            var n = p
            n.x += p.vx
            n.y += p.vy
            n.vy += 0.5            // gravity
            n.vx *= 0.98           // air drag
            n.life -= 0.035
            return n.life > 0 ? n : nil
        }
    }
}
