import SwiftUI

/// Single-ride detail. Real HR profile from realtime_health JOIN; everything else placeholder.
struct RideDetailView: View {
    let ride: Ride

    @State private var samples: [HRSample] = []
    @State private var isLoadingHR = false
    @State private var hrError: String?

    private let supabase = SupabaseClient.shared

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.md) {
                rideHeroCard
                HRChart(samples: samples, rideStart: ride.startedAt, rideEnd: ride.endedAt)
                placeholderGrid
                Color.clear.frame(height: 80)
            }
            .padding(.horizontal, DS.Spacing.md)
        }
        .scrollIndicators(.hidden)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                TwoToneHeadline(
                    primary: ride.startedAt.formatted(date: .abbreviated, time: .omitted),
                    secondary: " · " + ride.startedAt.formatted(date: .omitted, time: .shortened),
                    font: .system(size: 17, weight: .heavy, design: .rounded)
                )
            }
        }
        .task { await loadHR() }
    }

    // MARK: - Ride hero card

    @ViewBuilder
    private var rideHeroCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack {
                Text("RIDE")
                    .font(DS.Font.label)
                    .tracking(0.8)
                    .foregroundStyle(DS.Colors.textMuted)
                Spacer()
                if ride.isActive {
                    GlassStatusPill(icon: "circle.fill", text: "In progress", color: DS.Colors.danger)
                } else if let src = ride.source {
                    GlassStatusPill(icon: "tag.fill", text: src, color: DS.Colors.violet)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: DS.Spacing.lg) {
                heroStat(label: "Duration", value: ride.durationLabel, color: DS.Colors.violet)
                Divider().frame(height: 36).background(DS.Colors.border)
                heroStat(label: "Avg HR",
                         value: ride.hrAvg.map { "\(Int($0))" } ?? "—",
                         color: DS.Colors.danger)
                Divider().frame(height: 36).background(DS.Colors.border)
                heroStat(label: "Peak",
                         value: ride.hrPeak.map { "\(Int($0))" } ?? "—",
                         color: DS.Colors.warning)
            }
        }
        .heroCard()
    }

    @ViewBuilder
    private func heroStat(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(DS.Font.bigNumber)
                .foregroundStyle(color)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(DS.Font.micro)
                .tracking(0.7)
                .foregroundStyle(DS.Colors.textMuted)
        }
    }

    // MARK: - Placeholder telemetry tiles

    @ViewBuilder
    private var placeholderGrid: some View {
        VStack(spacing: 8) {
            SectionHeader(icon: "antenna.radiowaves.left.and.right",
                          title: "TELEMETRY (PHASE B)",
                          iconColor: DS.Colors.amber,
                          trailing: "Hardware pending")

            PlaceholderTile(
                icon: "skew",
                title: "Lean angle",
                detail: "Wires up once a 25Hz IMU source (RaceBox Mini S or iPhone CoreMotion fallback) is connected."
            )
            PlaceholderTile(
                icon: "map",
                title: "GPS track",
                detail: "Route drawing arrives with the GoPro GPMF ingest pipeline (Edge Function watches a synced folder)."
            )
            PlaceholderTile(
                icon: "rectangle.split.3x1",
                title: "Ride segments",
                detail: "Corner-detection algorithm materializes a ride_segments table at upload time."
            )
            PlaceholderTile(
                icon: "waveform.and.person.filled",
                title: "Body-state correlation",
                detail: "Morning HRV → max-lean per ride scatter. Activates once a few rides have full telemetry stacks."
            )
        }
    }

    // MARK: - Behavior

    private func loadHR() async {
        isLoadingHR = true
        defer { isLoadingHR = false }
        let end = ride.endedAt ?? Date()
        do {
            self.samples = try await supabase.fetchHRWindow(start: ride.startedAt, end: end)
            self.hrError = nil
        } catch {
            self.hrError = error.localizedDescription
        }
    }
}
