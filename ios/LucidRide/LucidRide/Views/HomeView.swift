import SwiftUI

/// Garage — the app's resting state. Opens straight to your last ride, your
/// month + lifetime stats, and a scrollable history. No 3D bike, no tap-a-part
/// paradigm: the payoff (what that ride actually was) is the whole point.
///
/// Every row — the hero and each history entry — opens the full ride breakdown
/// (`PostRideSummarySheet`) via `onOpenRide`. Portrait, scrollable, one big
/// START pinned at the bottom.
struct HomeView: View {
    @ObservedObject var state: HUDState
    var starting: Bool
    var onStart: () -> Void
    var onSettings: () -> Void
    var onOpenRide: (String) -> Void

    @StateObject private var model = GarageModel()

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                topBar
                if state.hrIsStale { staleBanner }

                ScrollView {
                    VStack(spacing: 0) {
                        if model.loading && model.rides.isEmpty {
                            loadingState
                        } else if let last = model.lastRide {
                            lastRideHero(last)
                            monthSection
                            lifetimeLine
                            historySection
                        } else {
                            emptyState
                        }
                        Color.clear.frame(height: 130)   // clear the START bar
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 4)
                }
                .scrollIndicators(.hidden)
                .refreshable { await model.load() }
            }
            startBar
        }
        .task { await model.load() }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(state.liveHR == nil ? DS.Colors.textFaint : DS.Colors.success)
                .frame(width: 7, height: 7)
                .opacity(state.liveHR == nil ? 0.4 : 1)
                .shadow(color: state.liveHR == nil ? .clear : DS.Colors.success, radius: 5)
            Text("LUCID RIDE")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(DS.Colors.textMuted)
            Text("·").foregroundStyle(DS.Colors.textFaint)
            Text(state.liveHR == nil ? "STANDBY" : HUDState.zoneLabel(for: state.liveHR).uppercased())
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(state.liveHR == nil ? DS.Colors.textMuted : HUDState.zoneColor(for: state.liveHR))

            Spacer()

            Button(action: onSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DS.Colors.textFaint)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.05)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var staleBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(DS.Colors.amber)
            Text("HR stale — open LucidBridge to start streaming")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(DS.Colors.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DS.Colors.amber.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(DS.Colors.amber.opacity(0.35), lineWidth: 0.5))
        .padding(.horizontal, 18)
        .padding(.bottom, 4)
    }

    // MARK: - Last ride hero

    @ViewBuilder
    private func lastRideHero(_ ride: Ride) -> some View {
        let km = (ride.metadata?.distanceM ?? 0) / 1000
        let top = ride.metadata?.maxSpeedKmh ?? 0
        let avg = ride.metadata?.avgSpeedKmh ?? 0
        let elev = ride.metadata?.elevGainM ?? 0

        Button { onOpenRide(ride.id) } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text("LAST RIDE")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(1.3)
                        .foregroundStyle(DS.Colors.violet)
                    Text("· " + ride.startedAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(DS.Colors.textMuted)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DS.Colors.textFaint)
                }

                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    numeric(ride.durationLabel, size: 40, color: DS.Colors.textPrimary)
                    numeric(km > 0 ? String(format: "%.1f km", km) : "— km", size: 30, color: DS.Colors.textSecondary)
                }
                .padding(.top, 10)

                if !model.lastRoutePoints.isEmpty {
                    MiniRouteShape(points: model.lastRoutePoints)
                        .stroke(
                            LinearGradient(colors: [DS.Colors.teal, DS.Colors.violet], startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                        )
                        .frame(height: 52)
                        .padding(.vertical, 12)
                } else {
                    Color.clear.frame(height: 14)
                }

                HStack(spacing: 0) {
                    heroStat("TOP SPEED", top > 1 ? String(format: "%.0f", top) : "—", "km/h")
                    heroDivider
                    heroStat("AVG", avg > 1 ? String(format: "%.0f", avg) : "—", "km/h")
                    heroDivider
                    heroStat("ELEVATION", elev > 1 ? String(format: "%.0f", elev) : "—", "m")
                }
            }
            .padding(17)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(colors: [DS.Colors.violet.opacity(0.16), DS.Colors.teal.opacity(0.05)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.ultraThinMaterial))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(DS.Colors.borderViolet, lineWidth: 0.5))
            .shadow(color: DS.Colors.violet.opacity(0.22), radius: 22, x: 0, y: 10)
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }

    private func numeric(_ s: String, size: CGFloat, color: Color) -> some View {
        Text(s)
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .foregroundStyle(color)
            .monospacedDigit()
            .kerning(-0.5)
    }

    private var heroDivider: some View {
        Rectangle().fill(DS.Colors.border).frame(width: 0.5, height: 30).padding(.horizontal, 14)
    }

    private func heroStat(_ key: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(DS.Colors.textPrimary)
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Colors.textMuted)
            }
            Text(key)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(DS.Colors.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - This month

    private var monthSection: some View {
        let m = model.rollup(monthOnly: true)
        return VStack(alignment: .leading, spacing: 0) {
            sectionHeader("THIS MONTH")
            HStack(spacing: 9) {
                statTile("\(m.count)", "", "RIDES", DS.Colors.violet)
                statTile(String(format: "%.0f", m.km), "km", "DISTANCE", DS.Colors.textPrimary)
                statTile(model.hmLabel(m.seconds), "", "TIME", DS.Colors.teal)
            }
        }
    }

    private func statTile(_ value: String, _ unit: String, _ key: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(color)
                    .monospacedDigit()
                    .kerning(-0.5)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.Colors.textSecondary)
                }
            }
            Text(key)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(DS.Colors.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 13)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(DS.Colors.border, lineWidth: 0.5))
    }

    // MARK: - Lifetime line

    private var lifetimeLine: some View {
        let a = model.rollup(monthOnly: false)
        return HStack(spacing: 6) {
            Image(systemName: "infinity")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(DS.Colors.amber)
            (
                Text("Lifetime ")
                    .foregroundStyle(DS.Colors.textSecondary)
                + Text(String(format: "%.0f km", a.km)).foregroundStyle(DS.Colors.textPrimary).fontWeight(.heavy)
                + Text(" · ").foregroundStyle(DS.Colors.textFaint)
                + Text("\(a.count) rides").foregroundStyle(DS.Colors.textPrimary).fontWeight(.heavy)
                + Text(" · ").foregroundStyle(DS.Colors.textFaint)
                + Text(model.hmLabel(a.seconds)).foregroundStyle(DS.Colors.textPrimary).fontWeight(.heavy)
                + Text(a.topKmh > 1 ? " · top \(Int(a.topKmh))" : "").foregroundStyle(DS.Colors.textPrimary).fontWeight(.heavy)
            )
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DS.Colors.border, lineWidth: 0.5))
        .padding(.top, 10)
    }

    // MARK: - History

    private var historySection: some View {
        VStack(spacing: 8) {
            sectionHeader("RIDE HISTORY", trailing: "\(model.completed.count) TOTAL")
            ForEach(model.completed) { ride in
                historyRow(ride)
            }
        }
    }

    private func historyRow(_ ride: Ride) -> some View {
        let km = (ride.metadata?.distanceM ?? 0) / 1000
        let effort = HUDState.effortLabel(from: ride.metadata?.zoneSeconds ?? [:])
        return Button { onOpenRide(ride.id) } label: {
            HStack(spacing: 13) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(ride.startedAt.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(DS.Colors.textPrimary)
                    Text(ride.startedAt.formatted(.dateTime.month(.abbreviated).day()).uppercased())
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(DS.Colors.textMuted)
                }
                .frame(width: 48, alignment: .leading)

                Text(effort.emoji).font(.system(size: 15))

                Text(effort.label)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(0.4)
                    .foregroundStyle(effort.color)

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(km > 0 ? String(format: "%.1f km", km) : "— km")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(DS.Colors.textPrimary)
                        .monospacedDigit()
                    Text(ride.durationLabel)
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(DS.Colors.textMuted)
                        .monospacedDigit()
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DS.Colors.textFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(DS.Colors.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared bits

    private func sectionHeader(_ title: String, trailing: String? = nil) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(DS.Colors.textMuted)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(DS.Colors.textFaint)
            }
        }
        .padding(.top, 22)
        .padding(.bottom, 11)
    }

    private var loadingState: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .tint(DS.Colors.violet)
            .frame(maxWidth: .infinity)
            .frame(height: 260)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(DS.Colors.textFaint)
            Text("No rides yet")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(DS.Colors.textPrimary)
            Text("Hit START and your first ride lands here — distance, speed, route, heart-rate zones, all of it.")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(DS.Colors.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 70)
    }

    private var startBar: some View {
        Button(action: onStart) {
            HStack(spacing: 9) {
                Image(systemName: starting ? "hourglass" : "play.fill")
                    .font(.system(size: 15, weight: .heavy))
                Text(starting ? "STARTING…" : "START RIDE")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .tracking(0.5)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(
                Capsule().fill(LinearGradient(colors: [DS.Colors.violet, Color(hex: 0x7C5CD6)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                    .opacity(starting ? 0.5 : 1)
            )
            .shadow(color: DS.Colors.violet.opacity(0.5), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(starting)
        .padding(.horizontal, 18)
        .padding(.bottom, 24)
        .background(
            LinearGradient(colors: [.clear, DS.Colors.bg.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                .frame(height: 120)
                .allowsHitTesting(false),
            alignment: .bottom
        )
    }
}

// MARK: - Garage data model

@MainActor
final class GarageModel: ObservableObject {
    @Published var rides: [Ride] = []
    @Published var lastRideWaypoints: [TelemetryRow] = []
    @Published var loading = true

    private let supabase = SupabaseClient.shared

    /// Completed rides, most-recent first (fetchRides already orders desc).
    var completed: [Ride] { rides.filter { $0.endedAt != nil } }
    var lastRide: Ride? { completed.first }

    func load() async {
        loading = true
        rides = (try? await supabase.fetchRides(limit: 200)) ?? []
        if let last = lastRide {
            lastRideWaypoints = (try? await supabase.fetchRideTelemetry(activityId: last.id, limit: 800)) ?? []
        } else {
            lastRideWaypoints = []
        }
        loading = false
    }

    /// (count, distance km, seconds, top km/h) over all completed rides, or just
    /// the current calendar month when `monthOnly`.
    func rollup(monthOnly: Bool) -> (count: Int, km: Double, seconds: Double, topKmh: Double) {
        let cal = Calendar.current
        let now = Date()
        let rows = completed.filter { r in
            monthOnly ? cal.isDate(r.startedAt, equalTo: now, toGranularity: .month) : true
        }
        let km = rows.reduce(0.0) { $0 + (($1.metadata?.distanceM ?? 0) / 1000) }
        let seconds = rows.reduce(0.0) { $0 + $1.durationSeconds }
        let topKmh = rows.reduce(0.0) { max($0, $1.metadata?.maxSpeedKmh ?? 0) }
        return (rows.count, km, seconds, topKmh)
    }

    func hmLabel(_ seconds: Double) -> String {
        let t = Int(seconds)
        let h = t / 3600
        let m = (t % 3600) / 60
        if h == 0 { return "\(m)m" }
        return "\(h)h \(m)m"
    }

    /// Normalized (0…1, y-down, north-up) last-ride track for the hero mini-map.
    /// Downsampled to keep the Path light; empty when there's no usable GPS.
    var lastRoutePoints: [CGPoint] {
        let coords = lastRideWaypoints.compactMap { wp -> (Double, Double)? in
            guard let la = wp.lat, let lo = wp.lon, !(wp.is_paused ?? false) else { return nil }
            return (la, lo)
        }
        guard coords.count >= 2 else { return [] }
        let lats = coords.map(\.0), lons = coords.map(\.1)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!
        let spanLat = max(1e-7, maxLat - minLat)
        let spanLon = max(1e-7, maxLon - minLon)
        let step = max(1, coords.count / 160)
        var out: [CGPoint] = []
        var i = 0
        while i < coords.count {
            let (la, lo) = coords[i]
            out.append(CGPoint(x: (lo - minLon) / spanLon, y: 1 - (la - minLat) / spanLat))
            i += step
        }
        return out
    }
}

// MARK: - Mini route shape

/// Strokes a normalized (0…1) point list to fit its frame. Aspect is stretched
/// to fill — it's a glanceable signature of the ride, not a survey map.
struct MiniRouteShape: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard points.count >= 2 else { return p }
        let pad: CGFloat = 3
        let w = rect.width - pad * 2
        let h = rect.height - pad * 2
        for (i, pt) in points.enumerated() {
            let x = pad + pt.x * w
            let y = pad + pt.y * h
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        return p
    }
}
