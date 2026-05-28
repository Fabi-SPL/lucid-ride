import SwiftUI
import Charts

/// Auto-opens after END RIDE. Pulls the freshly-finalized ride metadata from
/// Supabase and shows the most insight-dense post-ride view possible without
/// feeling cluttered. ADHD-scannable: hero stat + 4-grid + zone bar behind
/// disclosure + HR sparkline. Steals patterns from WHOOP, Polar Flow, Apple
/// Fitness, Strava (full provenance in deep-research report 2026-05-28).
struct PostRideSummarySheet: View {
    let activityId: String

    @Environment(\.dismiss) private var dismiss
    @State private var ride: Ride?
    @State private var loading = true
    @State private var showZones = false
    @State private var hrSamples: [HRSample] = []
    @State private var waypoints: [TelemetryRow] = []

    private let supabase = SupabaseClient.shared

    var body: some View {
        ZStack(alignment: .top) {
            DS.Colors.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.top, 12)
                    .padding(.horizontal, 22)

                ScrollView {
                    VStack(spacing: 18) {
                        if loading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(DS.Colors.violet)
                                .frame(height: 200)
                        } else if let ride {
                            RideRouteMap(waypoints: waypoints)
                            heroSection(ride: ride)
                            statGrid(ride: ride)
                            zoneDisclosure(ride: ride)
                            if !hrSamples.isEmpty { hrSparkline }
                            imuSection(ride: ride)
                            Color.clear.frame(height: 40)
                        } else {
                            emptyState
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                }
                .scrollIndicators(.hidden)
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(DS.Colors.bg)
        .task { await refresh() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("RIDE COMPLETE")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(DS.Colors.textMuted)
                Text(ride?.startedAt.formatted(.dateTime.weekday(.wide).hour().minute()) ?? "—")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.textSecondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(DS.Colors.textFaint)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Hero (distance + effort badge)

    @ViewBuilder
    private func heroSection(ride: Ride) -> some View {
        let zs = ride.metadata?.zoneSeconds ?? [:]
        let effort = HUDState.effortLabel(from: zs)
        let dist_km = (ride.metadata?.distanceM ?? 0) / 1000.0

        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 0) {
                Text(String(format: "%.1f", dist_km))
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .foregroundStyle(DS.Colors.textPrimary)
                    .monospacedDigit()
                Text("km")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(DS.Colors.textMuted)
                    .offset(y: -4)
            }

            Spacer()

            // Effort pill — semantic label from zone breakdown
            HStack(spacing: 6) {
                Text(effort.emoji)
                    .font(.system(size: 16))
                Text(effort.label.uppercased())
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(effort.color)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(effort.color.opacity(0.12))
            )
            .overlay(
                Capsule().stroke(effort.color.opacity(0.25), lineWidth: 0.5)
            )
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.04))
        )
    }

    // MARK: - Stat grid (4 cells)

    @ViewBuilder
    private func statGrid(ride: Ride) -> some View {
        let cols = [GridItem(.flexible(), spacing: 1), GridItem(.flexible(), spacing: 1)]
        let m = ride.metadata
        let dur = ride.durationLabel
        let topSpd = m?.maxSpeedKmh.map { String(format: "%.0f", $0) } ?? "—"
        let elev = m?.elevGainM.map { String(format: "%.0f", $0) } ?? "—"
        let avgHR = ride.hrAvg.map { String(format: "%.0f", $0) } ?? "—"

        LazyVGrid(columns: cols, spacing: 1) {
            statCell(value: dur,        unit: "Duration",   icon: "clock.fill",            tint: DS.Colors.textPrimary)
            statCell(value: topSpd,     unit: "km/h top",   icon: "gauge.with.dots.needle.bottom.50percent", tint: DS.Colors.violet)
            statCell(value: elev,       unit: "m elev",     icon: "mountain.2.fill",       tint: DS.Colors.teal)
            statCell(value: avgHR,      unit: "bpm avg",    icon: "heart.fill",            tint: DS.Colors.danger)
        }
        .background(Color.white.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func statCell(value: String, unit: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint.opacity(0.75))
                Text(unit.uppercased())
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(DS.Colors.textMuted)
            }
            Text(value)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.03))
    }

    // MARK: - Zone breakdown (progressive disclosure)

    @ViewBuilder
    private func zoneDisclosure(ride: Ride) -> some View {
        let zs = ride.metadata?.zoneSeconds ?? [:]
        let total = zs.values.reduce(0, +)

        if total < 1.0 {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { showZones.toggle() }
                } label: {
                    HStack {
                        Image(systemName: "heart.text.square.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(DS.Colors.textMuted)
                        Text("HEART RATE ZONES")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(DS.Colors.textMuted)
                        Spacer()
                        Image(systemName: showZones ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(DS.Colors.textFaint)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                // Always-visible compact stacked bar
                zoneStackedBar(zs: zs, total: total)
                    .frame(height: 12)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)

                if showZones {
                    Divider().background(DS.Colors.border).padding(.horizontal, 14)
                    VStack(spacing: 6) {
                        zoneRow(index: 0, label: "Warm-Up",   secs: zs["0"] ?? 0, total: total, color: DS.Colors.teal)
                        zoneRow(index: 1, label: "Aerobic",   secs: zs["1"] ?? 0, total: total, color: DS.Colors.success)
                        zoneRow(index: 2, label: "Threshold", secs: zs["2"] ?? 0, total: total, color: DS.Colors.warning)
                        zoneRow(index: 3, label: "Redline",   secs: zs["3"] ?? 0, total: total, color: DS.Colors.danger)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04))
            )
        }
    }

    @ViewBuilder
    private func zoneStackedBar(zs: [String: Double], total: Double) -> some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    let secs = zs["\(i)"] ?? 0
                    let frac = total > 0 ? CGFloat(secs / total) : 0
                    RoundedRectangle(cornerRadius: 3)
                        .fill(zoneColor(i))
                        .frame(width: max(0, geo.size.width * frac - 2))
                }
            }
        }
    }

    @ViewBuilder
    private func zoneRow(index: Int, label: String, secs: Double, total: Double, color: Color) -> some View {
        let mins = Int(secs / 60)
        let secsRem = Int(secs) % 60
        let pct = total > 0 ? Int((secs / total) * 100) : 0
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.textSecondary)
            Spacer()
            Text(String(format: "%d:%02d", mins, secsRem))
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
            Text("\(pct)%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.textMuted)
                .frame(width: 36, alignment: .trailing)
                .monospacedDigit()
        }
    }

    private func zoneColor(_ i: Int) -> Color {
        switch i {
        case 0: return DS.Colors.teal
        case 1: return DS.Colors.success
        case 2: return DS.Colors.warning
        case 3: return DS.Colors.danger
        default: return DS.Colors.textFaint
        }
    }

    // MARK: - HR sparkline

    @ViewBuilder
    private var hrSparkline: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DS.Colors.textMuted)
                Text("HR OVER RIDE")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(DS.Colors.textMuted)
            }

            Chart(Array(hrSamples.enumerated()), id: \.offset) { idx, s in
                if let hr = s.heartRate {
                    AreaMark(
                        x: .value("t", idx),
                        y: .value("bpm", hr)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        .linearGradient(
                            colors: [DS.Colors.teal.opacity(0.25), DS.Colors.warning.opacity(0.40), DS.Colors.danger.opacity(0.55)],
                            startPoint: .bottom, endPoint: .top
                        )
                    )
                    LineMark(
                        x: .value("t", idx),
                        y: .value("bpm", hr)
                    )
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .foregroundStyle(DS.Colors.danger.opacity(0.85))
                }
            }
            .frame(height: 70)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04))
        )
    }

    // MARK: - IMU summary

    @ViewBuilder
    private func imuSection(ride: Ride) -> some View {
        let lean = ride.metadata?.maxLeanDeg ?? 0
        let accel = ride.metadata?.maxAccelG ?? 0
        if lean < 1 && accel < 0.05 {
            EmptyView()
        } else {
            HStack(spacing: 10) {
                imuTile(value: String(format: "%.0f°", lean),
                        label: "MAX LEAN",
                        icon: "arrow.left.and.right.righttriangle.left.righttriangle.right.fill",
                        tint: DS.Colors.violet)
                imuTile(value: String(format: "%.2fG", accel),
                        label: "PEAK ACCEL",
                        icon: "speedometer",
                        tint: DS.Colors.warning)
            }
        }
    }

    @ViewBuilder
    private func imuTile(value: String, label: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint.opacity(0.75))
                Text(label)
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(DS.Colors.textMuted)
            }
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04))
        )
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 30))
                .foregroundStyle(DS.Colors.textFaint)
            Text("No telemetry recorded for this ride")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.textMuted)
        }
        .frame(height: 200)
    }

    // MARK: - Data

    private func refresh() async {
        loading = true
        if let r = try? await supabase.fetchRideById(activityId) {
            ride = r
            let started = r.startedAt
            let ended = r.endedAt ?? Date()
            // Parallel fetch — HR samples + waypoints — so the sheet finishes
            // loading faster on bad cell connections.
            async let hr   = supabase.fetchHRWindow(start: started, end: ended)
            async let wp   = supabase.fetchRideTelemetry(activityId: activityId)
            hrSamples = (try? await hr) ?? []
            waypoints = (try? await wp) ?? []
        }
        loading = false
    }
}
