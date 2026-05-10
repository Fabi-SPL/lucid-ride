import SwiftUI

/// Skeleton tile for telemetry that the hardware doesn't capture yet.
/// Shows up as a muted, dashed-stroke card with icon + label + the future-state copy.
/// All four (lean, GPS, segments, body-state correlation) use this shape until
/// RaceBox / GoPro / OBDLink / ride_telemetry land.
struct PlaceholderTile: View {
    let icon: String
    let title: String
    let detail: String
    var height: CGFloat = 140

    @State private var shimmer = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Colors.textFaint)
                Text(title.uppercased())
                    .font(DS.Font.label)
                    .tracking(0.8)
                    .foregroundStyle(DS.Colors.textMuted)
                Spacer()
                GlassStatusPill(icon: "hourglass", text: "Hardware pending", color: DS.Colors.amber)
            }

            // Skeleton bars — three muted rectangles that shimmer subtly
            VStack(alignment: .leading, spacing: 6) {
                ForEach([1.0, 0.7, 0.45], id: \.self) { width in
                    Capsule()
                        .fill(DS.Colors.textFaint.opacity(0.18))
                        .frame(maxWidth: .infinity)
                        .frame(height: 8)
                        .scaleEffect(x: width, anchor: .leading)
                }
            }
            .padding(.vertical, 4)

            Text(detail)
                .font(DS.Font.caption)
                .foregroundStyle(DS.Colors.textMuted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: height)
        .padding(DS.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
                .foregroundStyle(DS.Colors.border)
        )
        .opacity(shimmer ? 1.0 : 0.92)
        .animation(DS.Anim.breath, value: shimmer)
        .onAppear { shimmer = true }
    }
}

#Preview {
    ZStack {
        MeshGradientBackground()
        VStack(spacing: 12) {
            PlaceholderTile(
                icon: "skew",
                title: "Lean angle",
                detail: "RaceBox Mini S + IMU fusion arrives once telemetry hardware is wired."
            )
            PlaceholderTile(
                icon: "map",
                title: "GPS track",
                detail: "Route drawing wires up after the GPMF ingest pipeline ships."
            )
        }
        .padding()
    }
}
