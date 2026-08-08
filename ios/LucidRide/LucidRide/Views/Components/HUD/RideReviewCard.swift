import SwiftUI

/// The Review card. Sits directly under the hero so it's read before the tiles —
/// the sentences are the point, the numbers are the evidence.
///
/// Renders nothing at all when the ride had nothing worth saying. An empty card
/// with "no insights available" would be worse than no card.
struct RideReviewCard: View {
    let insights: [RideReview.Insight]

    var body: some View {
        if insights.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 5) {
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DS.Colors.textMuted)
                    Text("THE READ")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(DS.Colors.textMuted)
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(insights) { i in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: i.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(tint(i.tone))
                                .frame(width: 18, alignment: .center)
                                .padding(.top, 1)
                            Text(i.text)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(DS.Colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(DS.Colors.amberAccent.opacity(0.16), lineWidth: 0.5)
            )
        }
    }

    private func tint(_ tone: RideReview.Insight.Tone) -> Color {
        switch tone {
        case .win:     return DS.Colors.amberAccent
        case .note:    return DS.Colors.ember
        case .neutral: return DS.Colors.textMuted
        }
    }
}
