import SwiftUI

/// Full scroll of every motor_racing activity, newest first. Tap → RideDetailView.
struct RidesListView: View {
    @State private var rides: [Ride] = []
    @State private var isLoading = false
    @State private var lastError: String?

    private let supabase = SupabaseClient.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if rides.isEmpty && !isLoading {
                    EmptyGlassState(
                        icon: "road.lanes",
                        title: "No rides logged",
                        detail: "Start a ride from the Today tab. Past motor_racing activities (the existing 634 days of them) show here once the auth handshake completes."
                    )
                    .padding(.top, DS.Spacing.xxl)
                }

                ForEach(rides) { ride in
                    NavigationLink {
                        RideDetailView(ride: ride)
                    } label: {
                        RideRow(ride: ride)
                    }
                    .buttonStyle(.plain)
                }

                if let err = lastError {
                    Text(err)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Colors.danger)
                        .padding(.top, DS.Spacing.md)
                }

                Color.clear.frame(height: 80)
            }
            .padding(.horizontal, DS.Spacing.md)
        }
        .scrollIndicators(.hidden)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                TwoToneHeadline(
                    primary: "Rides",
                    secondary: " · all time",
                    font: .system(size: 17, weight: .heavy, design: .rounded)
                )
            }
        }
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            self.rides = try await supabase.fetchRides(limit: 200)
            self.lastError = nil
        } catch {
            self.lastError = "Couldn't load rides: \(error.localizedDescription)"
        }
    }
}
