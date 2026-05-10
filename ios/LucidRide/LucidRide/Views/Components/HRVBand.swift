import SwiftUI

/// Hero body-state band on TodayView. Big number, color-coded label, one-line copy.
/// Pulses gently when band is `.green` (signals "live data flowing").
struct HRVBand: View {
    let hrv: Double?
    @State private var pulse = false

    private var band: BodyStateBand { BodyStateBand(hrv: hrv) }

    private var color: Color {
        switch band {
        case .green:   return DS.Colors.success
        case .yellow:  return DS.Colors.warning
        case .red:     return DS.Colors.danger
        case .unknown: return DS.Colors.textMuted
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("BODY STATE")
                        .font(DS.Font.label)
                        .tracking(0.8)
                        .foregroundStyle(DS.Colors.textMuted)
                    Text(band.label)
                        .font(DS.Font.title1)
                        .foregroundStyle(color)
                }
                Spacer()
                if let hrv {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(hrv))")
                            .font(DS.Font.heroNumber)
                            .foregroundStyle(DS.Colors.textPrimary)
                            .monospacedDigit()
                        Text("HRV · ms")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Colors.textMuted)
                    }
                } else {
                    Text("—")
                        .font(DS.Font.heroNumber)
                        .foregroundStyle(DS.Colors.textFaint)
                }
            }

            // Color band gauge
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(color.opacity(0.12))
                    Capsule()
                        .fill(LinearGradient(
                            colors: [color.opacity(0.85), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: geo.size.width * fillFraction)
                }
            }
            .frame(height: 8)
            .scaleEffect(y: pulse && band == .green ? 1.4 : 1.0, anchor: .center)
            .animation(DS.Anim.breath, value: pulse)

            Text(band.copy)
                .font(DS.Font.body)
                .foregroundStyle(DS.Colors.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .heroCard(color: color)
        .statusGlow(color, intensity: band == .green ? 1.0 : 0.5)
        .onAppear { pulse = true }
    }

    /// Map HRV to a 0…1 fill fraction. 30ms = 0.0, 90ms = 1.0.
    private var fillFraction: Double {
        guard let h = hrv else { return 0.0 }
        let clamped = max(30, min(90, h))
        return (clamped - 30) / 60
    }
}

#Preview {
    ZStack {
        MeshGradientBackground()
        VStack(spacing: 16) {
            HRVBand(hrv: 78)
            HRVBand(hrv: 52)
            HRVBand(hrv: 32)
            HRVBand(hrv: nil)
        }
        .padding()
    }
}
