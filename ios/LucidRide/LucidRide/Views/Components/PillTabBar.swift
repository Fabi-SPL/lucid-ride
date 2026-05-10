import SwiftUI

/// Floating glass-pill tab bar — principle #8.
/// 3 tabs: Today / Rides / Settings.
enum AppTab: Int, CaseIterable {
    case today, rides, settings

    var icon: String {
        switch self {
        case .today:    return "sun.max.fill"
        case .rides:    return "road.lanes"
        case .settings: return "gearshape.fill"
        }
    }

    var label: String {
        switch self {
        case .today:    return "Today"
        case .rides:    return "Rides"
        case .settings: return "Settings"
        }
    }
}

struct PillTabBar: View {
    @Binding var selectedTab: AppTab
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases, id: \.rawValue) { tab in
                Button {
                    withAnimation(DS.Anim.standard) { selectedTab = tab }
                } label: {
                    tabItem(tab)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: selectedTab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(height: 56)
        .glassEffect(.regular, in: .capsule)
        .overlay(
            Capsule().stroke(DS.Colors.border, lineWidth: 0.5)
        )
        .padding(.horizontal, 32)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func tabItem(_ tab: AppTab) -> some View {
        let isActive = selectedTab == tab

        ZStack {
            if isActive {
                Capsule()
                    .fill(DS.Colors.violet.opacity(0.18))
                    .matchedGeometryEffect(id: "tabIndicator", in: indicator)
            }

            HStack(spacing: isActive ? 5 : 0) {
                Image(systemName: tab.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isActive ? DS.Colors.violet : DS.Colors.textMuted)

                if isActive {
                    Text(tab.label)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.violet)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }
            .padding(.horizontal, isActive ? 12 : 10)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
    }
}

#Preview {
    ZStack(alignment: .bottom) {
        MeshGradientBackground()
        PillTabBar(selectedTab: .constant(.today))
    }
}
