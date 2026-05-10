import SwiftUI

/// Circular gauge with a tick-marked outer ring, fill arc that grows with
/// the value, and the digital readout in the center. Phase A: value is a
/// placeholder slow sweep (0 → max → 0). Phase B: live OBD speed.
struct BigAnalogSpeedo: View {
    let value: Double
    let max: Double
    let label: String
    let unit: String
    var color: Color = DS.Colors.amber
    var placeholder: Bool = false

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let lineWidth = size * 0.05

            ZStack {
                // Outer track
                Circle()
                    .trim(from: 0.0, to: 0.78)
                    .stroke(color.opacity(0.12), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(126))

                // Fill arc — 0…78% of full circle (rules out the bottom 22% so
                // the dial reads as a speedometer, not a clock).
                Circle()
                    .trim(from: 0.0, to: 0.78 * min(1, value / max))
                    .stroke(
                        AngularGradient(colors: [color.opacity(0.7), color], center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(126))
                    .animation(.easeOut(duration: 0.5), value: value)

                // Tick marks every (max / 10)
                ForEach(0..<11, id: \.self) { i in
                    let t = Double(i) / 10.0
                    let angle = 126 + (0.78 * 360 * t) // start at 126°, sweep 280.8°
                    Rectangle()
                        .fill(color.opacity(0.45))
                        .frame(width: 1, height: lineWidth * 1.4)
                        .offset(y: -size * 0.42)
                        .rotationEffect(.degrees(angle))
                }

                // Center digital readout
                VStack(spacing: 2) {
                    Text("\(Int(value))")
                        .font(.system(size: size * 0.32, weight: .heavy, design: .rounded))
                        .foregroundStyle(placeholder ? color.opacity(0.45) : color)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(unit)
                        .font(.system(size: size * 0.07, weight: .heavy, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(DS.Colors.textMuted)
                    Text(label)
                        .font(.system(size: size * 0.055, weight: .heavy, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(DS.Colors.textFaint)
                        .padding(.top, 2)
                    if placeholder {
                        Text("PENDING")
                            .font(.system(size: size * 0.045, weight: .heavy, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(DS.Colors.amber.opacity(0.65))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .overlay(Capsule().stroke(DS.Colors.amber.opacity(0.4), lineWidth: 0.5))
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
