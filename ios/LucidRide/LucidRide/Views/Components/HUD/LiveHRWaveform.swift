import SwiftUI

/// Scrolling ECG-style heart-rate waveform across the bottom of the HUD.
/// Last `windowSeconds` of HR samples drawn left-to-right, animating left
/// as new samples arrive. Soft area fill below the line for visual weight.
///
/// Re-renders at 30 fps via TimelineView so the time axis advances even
/// between sample arrivals.
struct LiveHRWaveform: View {
    let samples: [HRSample]
    let windowSeconds: TimeInterval = 60
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 : 1.0 / 30.0)) { ctx in
            let now = ctx.date
            let cutoff = now.addingTimeInterval(-windowSeconds)
            let relevant = samples
                .filter { $0.recordedAt >= cutoff && $0.heartRate != nil }
                .sorted { $0.recordedAt < $1.recordedAt }

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let hrMin = 50.0
                let hrMax = 180.0

                ZStack(alignment: .leading) {
                    // Faint horizontal grid every 30 BPM
                    Canvas { c, size in
                        for hr in stride(from: 60.0, through: 180.0, by: 30.0) {
                            let normY = (hr - hrMin) / (hrMax - hrMin)
                            let y = h * (1 - normY)
                            var line = Path()
                            line.move(to: CGPoint(x: 0, y: y))
                            line.addLine(to: CGPoint(x: w, y: y))
                            c.stroke(line, with: .color(DS.Colors.textFaint.opacity(0.10)), lineWidth: 0.5)
                            c.draw(Text("\(Int(hr))")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundStyle(DS.Colors.textFaint.opacity(0.4)),
                                at: CGPoint(x: 14, y: y - 6),
                                anchor: .leading)
                        }
                    }
                    .allowsHitTesting(false)

                    if relevant.isEmpty {
                        Text("connecting to body data…")
                            .font(DS.Font.label)
                            .tracking(1.0)
                            .foregroundStyle(DS.Colors.textFaint)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Canvas { c, size in
                            var line = Path()
                            for (i, s) in relevant.enumerated() {
                                guard let hr = s.heartRate else { continue }
                                let age = now.timeIntervalSince(s.recordedAt)
                                let x = w * (1 - age / windowSeconds)
                                let normY = max(0, min(1, (hr - hrMin) / (hrMax - hrMin)))
                                let y = h * (1 - normY)
                                if i == 0 { line.move(to: CGPoint(x: x, y: y)) }
                                else { line.addLine(to: CGPoint(x: x, y: y)) }
                            }
                            // Area fill below the line
                            var fill = line
                            fill.addLine(to: CGPoint(x: w, y: h))
                            fill.addLine(to: CGPoint(x: 0, y: h))
                            fill.closeSubpath()
                            c.fill(fill, with: .linearGradient(
                                Gradient(colors: [DS.Colors.danger.opacity(0.22), DS.Colors.danger.opacity(0.0)]),
                                startPoint: CGPoint(x: 0, y: 0),
                                endPoint: CGPoint(x: 0, y: h)
                            ))
                            c.stroke(line, with: .color(DS.Colors.danger), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))

                            // Bright pulsing dot at the leading edge (newest sample)
                            if let last = relevant.last, let hr = last.heartRate {
                                let age = now.timeIntervalSince(last.recordedAt)
                                let x = w * (1 - age / windowSeconds)
                                let normY = max(0, min(1, (hr - hrMin) / (hrMax - hrMin)))
                                let y = h * (1 - normY)
                                let dotR: CGFloat = 4
                                c.fill(Path(ellipseIn: CGRect(x: x - dotR, y: y - dotR, width: dotR*2, height: dotR*2)),
                                       with: .color(DS.Colors.danger))
                                c.fill(Path(ellipseIn: CGRect(x: x - dotR*2, y: y - dotR*2, width: dotR*4, height: dotR*4)),
                                       with: .color(DS.Colors.danger.opacity(0.25)))
                            }
                        }
                    }
                }
            }
        }
    }
}
