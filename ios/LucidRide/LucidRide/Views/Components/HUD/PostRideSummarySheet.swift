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
    @State private var tracker: TrackerSummary?
    @State private var review: [RideReview.Insight] = []

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
                                .tint(DS.Colors.amberAccent)
                                .frame(height: 200)
                        } else if let ride {
                            RideRouteMap(waypoints: waypoints)
                            heroSection(ride: ride)
                            RideReviewCard(insights: review)
                            statGrid(ride: ride)
                            zoneDisclosure(ride: ride)
                            if !hrSamples.isEmpty { hrSparkline }
                            imuSection(ride: ride, tracker: tracker)
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
        let dist_km = distanceKm

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
                Image(systemName: effort.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(effort.color)
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
        let topSpd = topSpeedKmh > 1 ? String(format: "%.0f", topSpeedKmh) : "—"
        let elev = m?.elevGainM.map { String(format: "%.0f", $0) } ?? "—"
        let avgHR = avgHRValue.map { String(format: "%.0f", $0) } ?? "—"

        LazyVGrid(columns: cols, spacing: 1) {
            statCell(value: dur,        unit: "Duration",   icon: "clock.fill",            tint: DS.Colors.textPrimary)
            statCell(value: topSpd,     unit: "km/h top",   icon: "gauge.with.dots.needle.bottom.50percent", tint: DS.Colors.amberAccent)
            statCell(value: elev,       unit: "m elev",     icon: "mountain.2.fill",       tint: DS.Colors.cold)
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
                        zoneRow(index: 0, label: "Warm-Up",   secs: zs["0"] ?? 0, total: total, color: DS.Colors.cold)
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
        case 0: return DS.Colors.cold
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
                            colors: [DS.Colors.cold.opacity(0.25), DS.Colors.warning.opacity(0.40), DS.Colors.danger.opacity(0.55)],
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

    /// Lean comes from the RaceBox when it was along for the ride. The phone's own IMU is a
    /// fallback only if the (default-off) experiment is switched on — a phone that rotates
    /// inside its holder cannot measure how far the bike is over.
    @ViewBuilder
    private func imuSection(ride: Ride, tracker: TrackerSummary? = nil) -> some View {
        let leanOn = UserDefaults.standard.bool(forKey: "lucidride.leanEnabled")
        let phoneLean = ride.metadata?.maxLeanDeg ?? 0
        let boxLean = (tracker?.isMeaningful == true) ? (tracker?.maxLeanDeg ?? 0) : 0
        let accel = ride.metadata?.maxAccelG ?? 0
        let lean = boxLean > 0 ? boxLean : phoneLean
        let showLean = boxLean > 0 || (leanOn && phoneLean >= 1)
        if !showLean && accel < 0.05 {
            EmptyView()
        } else {
            HStack(spacing: 10) {
                if showLean {
                    imuTile(value: String(format: "%.0f°", lean),
                            label: boxLean > 0 ? "MAX LEAN · BOX" : "MAX LEAN",
                            icon: "arrow.left.and.right.righttriangle.left.righttriangle.right.fill",
                            tint: DS.Colors.amberAccent)
                }
                if accel >= 0.05 {
                    imuTile(value: String(format: "%.2fG", accel),
                            label: "PEAK ACCEL",
                            icon: "speedometer",
                            tint: DS.Colors.warning)
                }
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

    // MARK: - Waypoint-derived fallbacks
    //
    // The recorder's metadata summary can be empty/zeroed (e.g. a ride that was
    // ended twice wrote a blank summary over the real data). The waypoints are
    // the source of truth, so recompute hero stats from them when metadata is
    // missing.

    private var distanceKm: Double {
        if let d = ride?.metadata?.distanceM, d > 1 { return d / 1000 }
        return waypointDistanceM() / 1000
    }
    private var topSpeedKmh: Double {
        if let s = ride?.metadata?.maxSpeedKmh, s > 1 { return s }
        return (waypoints.compactMap { $0.speed_mps }.max() ?? 0) * 3.6
    }
    private var avgHRValue: Double? {
        if let h = ride?.hrAvg, h > 0 { return h }
        let hrs = waypoints.compactMap { $0.heart_rate }
        return hrs.isEmpty ? nil : Double(hrs.reduce(0, +)) / Double(hrs.count)
    }
    private func waypointDistanceM() -> Double {
        guard waypoints.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<waypoints.count {
            guard let la = waypoints[i-1].lat, let lo = waypoints[i-1].lon,
                  let lb = waypoints[i].lat,   let lob = waypoints[i].lon else { continue }
            let d = haversineM(la, lo, lb, lob)
            if d > 0.5 && d < 500 { total += d }
        }
        return total
    }
    private func haversineM(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let R = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat/2) * sin(dLat/2) + cos(lat1 * .pi/180) * cos(lat2 * .pi/180) * sin(dLon/2) * sin(dLon/2)
        return R * 2 * atan2(sqrt(a), sqrt(1 - a))
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
            // The Review compares this ride against every earlier one, so the
            // history and the box roll-ups come along in the same round trip.
            async let hist = supabase.fetchRides(limit: 200)
            async let trk  = supabase.fetchTrackerSummaries()
            hrSamples          = (try? await hr) ?? []
            waypoints          = (try? await wp) ?? []
            let history        = (try? await hist) ?? []
            let trackerHistory = (try? await trk) ?? [:]
            tracker            = trackerHistory[activityId]
            // Built once here, not in `body` — each Insight carries a fresh UUID,
            // so recomputing per render would churn the ForEach identities.
            review = RideReview.insights(
                ride: r,
                tracker: tracker,
                trackerHistory: trackerHistory,
                waypoints: waypoints,
                history: history
            )
        }
        loading = false
    }
}
