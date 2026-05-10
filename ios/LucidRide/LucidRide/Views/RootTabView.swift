import SwiftUI

/// Root nav with shared mesh background and floating pill tab bar.
/// Mirrors LucidHealth's RootTabView pattern — single mesh, opacity-swap tabs,
/// no NavigationStack rerender on tab change.
///
/// 3 tabs (Phase A): Today / Rides / Settings.
/// Insights tab deferred to Phase B once telemetry hardware lands.
struct RootTabView: View {
    @State private var selectedTab: AppTab = .today

    var body: some View {
        ZStack(alignment: .bottom) {
            MeshGradientBackground()
                .ignoresSafeArea()

            ZStack {
                ForEach(AppTab.allCases, id: \.rawValue) { tab in
                    NavigationStack {
                        tabContent(tab)
                    }
                    .opacity(selectedTab == tab ? 1 : 0)
                    .allowsHitTesting(selectedTab == tab)
                }
            }
            .ignoresSafeArea()

            PillTabBar(selectedTab: $selectedTab)
        }
        .ignoresSafeArea(.keyboard)
    }

    @ViewBuilder
    private func tabContent(_ tab: AppTab) -> some View {
        switch tab {
        case .today:    TodayView()
        case .rides:    RidesListView()
        case .settings: SettingsView()
        }
    }
}
