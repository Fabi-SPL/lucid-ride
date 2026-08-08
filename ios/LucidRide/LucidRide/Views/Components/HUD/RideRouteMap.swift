import SwiftUI
import MapKit

/// Renders a completed ride's GPS track as a MapKit polyline, colored by
/// either HR zone, GPS-derived lean angle, or speed — chosen by the
/// `mode` toggle in the post-ride sheet header.
///
/// Auto-fits the camera to the bounding box of the waypoints. Segments where
/// the recorder was auto-paused render dimmed so the visual story matches
/// the ride: motion = bright, stationary = faded.
struct RideRouteMap: View {
    let waypoints: [TelemetryRow]

    enum ColorMode: String, CaseIterable, Identifiable {
        case hrZone = "HR Zone"
        case lean   = "Lean"
        case speed  = "Speed"
        var id: String { rawValue }
    }

    @State private var mode: ColorMode = .hrZone

    /// Only offer "Lean" when this ride actually carries lean samples. Phone lean is off by
    /// default (the holder moves), so on most rides the mode would paint a uniformly cold
    /// line and read as "you rode the whole thing bolt upright".
    private var hasLean: Bool {
        waypoints.contains { ($0.lean_deg_gps ?? 0) != 0 }
    }
    private var availableModes: [ColorMode] {
        ColorMode.allCases.filter { $0 != .lean || hasLean }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "map")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DS.Colors.textMuted)
                Text("ROUTE")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(DS.Colors.textMuted)
                Spacer()
                Picker("Color by", selection: $mode) {
                    ForEach(availableModes) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
                .onAppear { if mode == .lean && !hasLean { mode = .hrZone } }
            }

            if waypoints.count < 2 {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.05))
                        .frame(height: 200)
                    VStack(spacing: 6) {
                        Image(systemName: "mappin.slash")
                            .font(.system(size: 24))
                            .foregroundStyle(DS.Colors.textFaint)
                        Text("No GPS recorded")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(DS.Colors.textMuted)
                    }
                }
            } else {
                Map(initialPosition: .region(boundingRegion)) {
                    ForEach(segments) { seg in
                        MapPolyline(coordinates: [seg.start, seg.end])
                            .stroke(seg.color.opacity(seg.faded ? 0.25 : 0.95),
                                    style: StrokeStyle(lineWidth: seg.faded ? 2 : 4, lineCap: .round))
                    }
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .allowsHitTesting(false)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.04))
        )
    }

    // MARK: - Segments

    private struct Segment: Identifiable {
        let id: Int
        let start: CLLocationCoordinate2D
        let end:   CLLocationCoordinate2D
        let color: Color
        let faded: Bool
    }

    private var segments: [Segment] {
        // Full rides now arrive complete (2k–6k+ points). Evenly stride down to
        // ~1500 segments so MapKit stays smooth while the whole A→A loop is kept
        // (first + last points always included — the shape spans the entire ride).
        let stride = max(1, waypoints.count / 1500)
        var sampled: [TelemetryRow] = []
        var s = 0
        while s < waypoints.count { sampled.append(waypoints[s]); s += stride }
        if let last = waypoints.last, sampled.last?.recordedAt != last.recordedAt {
            sampled.append(last)
        }

        var out: [Segment] = []
        var i = 0
        var prev: (lat: Double, lon: Double, paused: Bool)?
        for wp in sampled {
            guard let lat = wp.lat, let lon = wp.lon else { continue }
            let paused = wp.is_paused ?? false
            if let p = prev {
                let start = CLLocationCoordinate2D(latitude: p.lat,  longitude: p.lon)
                let end   = CLLocationCoordinate2D(latitude: lat,   longitude: lon)
                let color = colorFor(wp: wp)
                out.append(Segment(id: i, start: start, end: end, color: color, faded: paused || p.paused))
                i += 1
            }
            prev = (lat, lon, paused)
        }
        return out
    }

    private func colorFor(wp: TelemetryRow) -> Color {
        switch mode {
        case .hrZone:
            return zoneColor(wp.zone_index ?? -1)
        case .lean:
            let lean = abs(wp.lean_deg_gps ?? 0)
            if lean < 5  { return DS.Colors.cold }
            if lean < 15 { return DS.Colors.success }
            if lean < 30 { return DS.Colors.warning }
            return DS.Colors.danger
        case .speed:
            let kmh = (wp.speed_mps ?? 0) * 3.6
            if kmh < 30  { return DS.Colors.cold }
            if kmh < 70  { return DS.Colors.success }
            if kmh < 110 { return DS.Colors.warning }
            return DS.Colors.danger
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

    // MARK: - Bounding region

    private var boundingRegion: MKCoordinateRegion {
        let valid = waypoints.compactMap { wp -> CLLocationCoordinate2D? in
            guard let lat = wp.lat, let lon = wp.lon else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        guard !valid.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }
        let lats = valid.map(\.latitude)
        let lons = valid.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude:  (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
        // Add 20% padding so the polyline doesn't kiss the frame edges.
        let span = MKCoordinateSpan(
            latitudeDelta:  max(0.002, (lats.max()! - lats.min()!) * 1.4),
            longitudeDelta: max(0.002, (lons.max()! - lons.min()!) * 1.4)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}
