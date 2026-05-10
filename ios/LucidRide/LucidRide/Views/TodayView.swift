import SwiftUI

/// Default landing screen.
/// Top-down: greeting toolbar → HRVBand hero → big Start/End Ride button → recent rides list.
struct TodayView: View {
    @State private var hrv: Double?
    @State private var activeRide: Ride?
    @State private var recentRides: [Ride] = []
    @State private var isLoading = false
    @State private var lastError: String?

    private let supabase = SupabaseClient.shared

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12:  return "Morning"
        case 12..<17: return "Afternoon"
        case 17..<22: return "Evening"
        default:       return "Late"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.lg) {
                HRVBand(hrv: hrv)
                    .padding(.top, DS.Spacing.sm)

                StartRideButton(
                    mode: activeRide == nil ? .idle : .active,
                    action: handleRideButton
                )

                if let active = activeRide {
                    activeRideCard(active)
                }

                recentRidesSection

                if let err = lastError {
                    Text(err)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Colors.danger)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DS.Spacing.md)
                }

                Color.clear.frame(height: 80) // tab-bar safe area
            }
            .padding(.horizontal, DS.Spacing.md)
        }
        .scrollIndicators(.hidden)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                TwoToneHeadline(
                    primary: greeting,
                    secondary: " · Lucid Ride",
                    font: .system(size: 17, weight: .heavy, design: .rounded)
                )
            }
        }
        .task { await refresh() }
        .refreshable { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .lucidRideAuthChanged)) { _ in
            Task { await refresh() }
        }
    }

    // MARK: - Active ride card (only shown while ended_at IS NULL)
    @ViewBuilder
    private func activeRideCard(_ ride: Ride) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: 8) {
                AmbientLiveIndicator()
                Text("RIDE IN PROGRESS")
                    .font(DS.Font.label)
                    .tracking(0.8)
                    .foregroundStyle(DS.Colors.danger)
                Spacer()
            }
            HStack(alignment: .firstTextBaseline) {
                Text(ride.durationLabel)
                    .font(DS.Font.bigNumber)
                    .foregroundStyle(DS.Colors.textPrimary)
                    .monospacedDigit()
                Text("· started \(ride.startedAt.formatted(date: .omitted, time: .shortened))")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Colors.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: DS.Spacing.md, tint: DS.Colors.danger)
    }

    // MARK: - Recent rides
    @ViewBuilder
    private var recentRidesSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            SectionHeader(icon: "clock.arrow.circlepath",
                          title: "RECENT RIDES",
                          iconColor: DS.Colors.teal,
                          trailing: recentRides.isEmpty ? nil : "\(recentRides.count)")
            if recentRides.isEmpty && !isLoading {
                EmptyGlassState(
                    icon: "road.lanes",
                    title: "No rides yet",
                    detail: "Hit Start Ride above to log your first one. Schema's ready, telemetry comes later."
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(recentRides.prefix(5)) { ride in
                        NavigationLink {
                            RideDetailView(ride: ride)
                        } label: {
                            RideRow(ride: ride)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Behavior

    private func handleRideButton() async {
        do {
            if let active = activeRide {
                try await supabase.endRide(activityId: active.id)
                activeRide = nil
            } else {
                if let started = try await supabase.startRide() {
                    activeRide = started
                }
            }
            await refresh()
        } catch {
            lastError = "Ride toggle failed: \(error.localizedDescription)"
        }
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let hrvTask    = supabase.fetchLatestHRV()
            async let activeTask = supabase.activeRide()
            async let ridesTask  = supabase.fetchRides(limit: 10)
            let (h, a, r) = try await (hrvTask, activeTask, ridesTask)
            self.hrv         = h
            self.activeRide  = a
            self.recentRides = r
            self.lastError   = nil
        } catch {
            self.lastError = "Refresh failed: \(error.localizedDescription)"
        }
    }
}

/// One-line row used by TodayView (recent rides) and RidesListView.
struct RideRow: View {
    let ride: Ride

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ride.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(DS.Font.bodyMed)
                    .foregroundStyle(DS.Colors.textPrimary)
                HStack(spacing: 8) {
                    Label(ride.durationLabel, systemImage: "clock")
                        .font(DS.Font.caption)
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(DS.Colors.textSecondary)
                    if let hr = ride.hrAvg {
                        Label("\(Int(hr)) avg", systemImage: "heart.fill")
                            .font(DS.Font.caption)
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(DS.Colors.danger.opacity(0.85))
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.Colors.textFaint)
        }
        .padding(DS.Spacing.md)
        .glassCard(padding: 0, tint: DS.Colors.violet)
        .padding(DS.Spacing.xs)
    }
}

/// Small pulsing red dot for "live" / "in progress" indicators.
private struct AmbientLiveIndicator: View {
    @State private var on = false
    var body: some View {
        Circle()
            .fill(DS.Colors.danger)
            .frame(width: 8, height: 8)
            .opacity(on ? 1.0 : 0.4)
            .animation(DS.Anim.breath, value: on)
            .onAppear { on = true }
    }
}
