import SwiftUI

/// Aircraft-style attitude indicator across the top of the HUD.
/// A horizontal line that rotates by the current lean angle, with degree
/// tick marks and a center indicator. Color shifts cyan → green → amber → red
/// as lean increases.
///
/// Phase A: leanDegrees is a placeholder driven by a slow sine wave to give
/// the HUD ambient motion. Phase B: real value from RaceBox / iPhone IMU.
struct LeanHorizonView: View {
    let leanDegrees: Double

    private var leanColor: Color {
        let abs = Swift.abs(leanDegrees)
        if abs < 25 { return DS.Colors.teal }
        if abs < 40 { return DS.Colors.success }
        if abs < 50 { return DS.Colors.warning }
        return DS.Colors.danger
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let cx = w / 2
            let cy = h / 2

            ZStack {
                // Tick marks at every 15° (linearly mapped to width)
                ForEach([-45, -30, -15, 0, 15, 30, 45], id: \.self) { deg in
                    let x = cx + CGFloat(deg) * (w * 0.014)
                    VStack(spacing: 3) {
                        Rectangle()
                            .fill(DS.Colors.textFaint.opacity(deg == 0 ? 0.6 : 0.25))
                            .frame(width: 1, height: deg == 0 ? 14 : 8)
                        Text("\(abs(deg))°")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(DS.Colors.textFaint.opacity(deg == 0 ? 0.7 : 0.35))
                    }
                    .position(x: x, y: cy + 12)
                }

                // The horizon line itself — rotates with the lean
                Path { p in
                    p.move(to: CGPoint(x: 0, y: cy))
                    p.addLine(to: CGPoint(x: w, y: cy))
                }
                .stroke(LinearGradient(
                    colors: [Color.clear, leanColor.opacity(0.3), leanColor, leanColor.opacity(0.3), Color.clear],
                    startPoint: .leading, endPoint: .trailing
                ), lineWidth: 2)
                .rotationEffect(.degrees(leanDegrees), anchor: .center)
                .animation(.easeOut(duration: 0.18), value: leanDegrees)

                // Static center indicator — little triangle pointing down at the line
                Image(systemName: "triangle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(DS.Colors.violet)
                    .rotationEffect(.degrees(180))
                    .position(x: cx, y: cy - 18)

                // Live degrees readout, top-right
                HStack(spacing: 4) {
                    Text("\(Int(leanDegrees))")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("° LEAN")
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(DS.Colors.textMuted)
                }
                .foregroundStyle(leanColor)
                .position(x: w - 50, y: 14)
            }
        }
    }
}
