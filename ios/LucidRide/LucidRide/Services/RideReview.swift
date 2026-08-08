import Foundation

/// The Review: what a ride actually *was*, in sentences.
///
/// Every other surface in this app reports numbers. A number on its own says
/// nothing — 118 km/h is a personal best or an ordinary Tuesday depending on the
/// forty rides behind it, and only the app knows which. This turns the stored
/// history into two or three plain statements about the ride you just finished.
///
/// Rules that keep it honest:
///   • Every line needs a comparison, a ratio, or something to do about it.
///     A line that only restates a tile gets deleted, not reworded.
///   • One line per family, so three speed facts can't crowd out the lean one.
///   • Silence beats filler. An unremarkable ride gets one line, or none.
///   • No coaching voice, no exclamation marks.
///
/// The rules were tuned against the real 114-ride history rather than invented:
/// an early draft told him "heart rate never really lifted" on almost every
/// ride, which is simply what riding a motorcycle does to a heart rate, and it
/// warned about missing box data on rides from months before he owned the box.
enum RideReview {

    struct Insight: Identifiable {
        enum Tone { case win, neutral, note }
        /// At most one insight per family survives ranking.
        enum Family { case speed, distance, lean, effort, terrain, logistics, coverage }

        let id = UUID()
        let icon:   String
        let text:   String
        let tone:   Tone
        let family: Family
        let weight: Int
    }

    private static let families: [Insight.Family] =
        [.speed, .distance, .lean, .effort, .terrain, .logistics, .coverage]

    /// Build the ride's review. `history` should be every stored ride including
    /// this one; anything started later is ignored, so re-opening an old ride
    /// still reads the way it did on the day.
    static func insights(
        ride: Ride,
        tracker: TrackerSummary?,
        trackerHistory: [String: TrackerSummary] = [:],
        waypoints: [TelemetryRow] = [],
        history: [Ride] = []
    ) -> [Insight] {

        // Newest first — several rules want "the last ten".
        let prior = history
            .filter { $0.id != ride.id && $0.startedAt < ride.startedAt && $0.endedAt != nil }
            .sorted { $0.startedAt > $1.startedAt }

        var all: [Insight] = []
        all += speed(ride, prior, waypoints)
        all += distance(ride, prior)
        all += lean(tracker, trackerHistory, prior)
        all += effort(ride, prior)
        all += terrain(ride, prior)
        all += logistics(ride, prior)
        all += coverage(ride, tracker, trackerHistory, prior)

        let bestPerFamily = families.compactMap { f in
            all.filter { $0.family == f }.max { $0.weight < $1.weight }
        }
        return Array(bestPerFamily.sorted { $0.weight > $1.weight }.prefix(3))
    }

    // MARK: - Speed

    private static func speed(_ ride: Ride, _ prior: [Ride], _ waypoints: [TelemetryRow]) -> [Insight] {
        let top = ride.metadata?.maxSpeedKmh ?? 0
        guard top > 1 else { return [] }
        var out: [Insight] = []

        let priorTops = prior.compactMap { $0.metadata?.maxSpeedKmh }.filter { $0 > 1 }
        if let best = priorTops.max() {
            if top > best {
                out.append(.init(
                    icon: "flag.checkered",
                    text: (top - best) >= 1
                        ? "\(num(top)) km/h — your fastest yet, by \(num(top - best))."
                        : "\(num(top)) km/h — a new best, just.",
                    tone: .win, family: .speed, weight: 100))
            } else if top >= best * 0.97 {
                out.append(.init(
                    icon: "gauge.with.dots.needle.bottom.50percent",
                    text: "\(num(top)) km/h, \(num(best - top)) off your best.",
                    tone: .neutral, family: .speed, weight: 45))
            }
        }

        // Against the recent norm rather than the all-time peak, which one
        // exceptional ride can put out of reach for a whole season.
        let recentTops = prior.prefix(10).compactMap { $0.metadata?.maxSpeedKmh }.filter { $0 > 1 }
        if recentTops.count >= 5, let med = median(recentTops), top >= med + 8 {
            out.append(.init(
                icon: "bolt.horizontal",
                text: "\(num(top)) km/h — quicker than you've been in ten rides.",
                tone: .neutral, family: .speed, weight: 50))
        }

        // A high average is harder to move than a top speed: it means the ride flowed.
        if let avg = ride.metadata?.avgSpeedKmh, avg > 5 {
            let priorAvgs = prior.compactMap { $0.metadata?.avgSpeedKmh }.filter { $0 > 5 }
            if priorAvgs.count >= 3, let bestAvg = priorAvgs.max(), avg > bestAvg {
                out.append(.init(
                    icon: "wind",
                    text: "\(num(avg)) km/h average — the cleanest run you've had. Barely stopped.",
                    tone: .win, family: .speed, weight: 65))
            }
        }

        // Falls back to the raw track when the ride's summary is blank.
        let moving = waypoints.filter { ($0.is_paused ?? false) == false }
        if moving.count >= 120 {
            let fast = moving.filter { (($0.speed_mps ?? 0) * 3.6) >= 80 }
            let frac = Double(fast.count) / Double(moving.count)
            if frac >= 0.35 {
                out.append(.init(
                    icon: "arrow.right.to.line",
                    text: "\(pct(frac)) of the ride sat above 80 km/h. Open roads, not town.",
                    tone: .neutral, family: .speed, weight: 55))
            }
        }
        return out
    }

    // MARK: - Distance

    private static func distance(_ ride: Ride, _ prior: [Ride]) -> [Insight] {
        let km = (ride.metadata?.distanceM ?? 0) / 1000
        let priorKm = prior.compactMap { $0.metadata?.distanceM }.map { $0 / 1000 }.filter { $0 > 1 }
        guard km > 1, priorKm.count >= 3 else { return [] }

        let recent = Array(priorKm.prefix(10))
        if let best = priorKm.max(), km > best {
            return [.init(icon: "ruler",
                          text: "\(num(km)) km — the longest you've ridden.",
                          tone: .win, family: .distance, weight: 95)]
        }
        guard recent.count >= 5, let recentBest = recent.max(), let med = median(recent) else { return [] }
        if km > recentBest {
            return [.init(icon: "ruler",
                          text: "\(num(km)) km, the longest of your last \(recent.count + 1).",
                          tone: .win, family: .distance, weight: 45)]
        }
        if km >= med * 1.35 {
            return [.init(icon: "arrow.up.right",
                          text: "\(num(km)) km against your usual \(num(med)). A long way round.",
                          tone: .neutral, family: .distance, weight: 35)]
        }
        if km <= med * 0.6 {
            return [.init(icon: "arrow.down.right",
                          text: "\(num(km)) km — short, next to your usual \(num(med)).",
                          tone: .neutral, family: .distance, weight: 22)]
        }
        return []
    }

    // MARK: - Lean (RaceBox only — the phone can't measure this)

    private static func lean(
        _ tracker: TrackerSummary?,
        _ trackerHistory: [String: TrackerSummary],
        _ prior: [Ride]
    ) -> [Insight] {
        guard let t = tracker, t.isMeaningful else { return [] }
        var out: [Insight] = []

        let left  = abs(t.leanLeftDeg  ?? 0)
        let right = abs(t.leanRightDeg ?? 0)
        let maxLean = t.maxLeanDeg ?? max(left, right)

        // Asymmetry is the one thing telemetry knows that you cannot feel.
        if max(left, right) >= 15 {
            let gap = abs(left - right)
            if gap >= 5 {
                let deeper    = right > left ? "right" : "left"
                let shallower = right > left ? "left"  : "right"
                out.append(.init(
                    icon: "arrow.triangle.swap",
                    text: "You go \(deg(gap)) deeper into \(deeper)-handers than \(shallower). The \(shallower) side has room.",
                    tone: .note, family: .lean, weight: 85))
            } else if gap <= 2 {
                out.append(.init(
                    icon: "equal.circle",
                    text: "Left and right within \(deg(max(gap, 1))) of each other. Evenly ridden.",
                    tone: .win, family: .lean, weight: 40))
            }
        }

        let priorLeans = prior.compactMap { trackerHistory[$0.id] }
            .filter { $0.isMeaningful }
            .compactMap { $0.maxLeanDeg }
        if maxLean > 5, priorLeans.count >= 2, let bestLean = priorLeans.max(), maxLean > bestLean {
            out.append(.init(
                icon: "angle",
                text: "\(deg(maxLean)) — the furthest over you've been across \(priorLeans.count + 1) logged rides.",
                tone: .win, family: .lean, weight: 90))
        }
        return out
    }

    // MARK: - Effort
    //
    // Only the loud end of the heart-rate story is worth a line. Riding a
    // motorcycle keeps you in zone 1 almost by definition, so "this was a
    // cruise" would print on nearly every ride and mean nothing.

    private static func effort(_ ride: Ride, _ prior: [Ride]) -> [Insight] {
        var out: [Insight] = []

        let zs = ride.metadata?.zoneSeconds ?? [:]
        let total = zs.values.reduce(0, +)
        if total > 300 {
            let redline = (zs["3"] ?? 0) / total
            if redline >= 0.15 {
                out.append(.init(
                    icon: "bolt.heart",
                    text: "\(pct(redline)) of it at redline. Your body worked as hard as the bike did.",
                    tone: .note, family: .effort, weight: 60))
            }
        }

        if let peak = ride.hrPeak, peak > 60 {
            let priorPeaks = prior.compactMap { $0.hrPeak }.filter { $0 > 60 }
            if priorPeaks.count >= 4, let med = median(priorPeaks), peak >= med + 12 {
                out.append(.init(
                    icon: "heart.circle",
                    text: "Peak \(Int(peak)) bpm, \(Int(peak - med)) over your usual. Something got your attention.",
                    tone: .note, family: .effort, weight: 50))
            }
        }
        return out
    }

    // MARK: - Terrain

    private static func terrain(_ ride: Ride, _ prior: [Ride]) -> [Insight] {
        guard let gain = ride.metadata?.elevGainM, gain > 150 else { return [] }
        let priorGains = prior.prefix(10).compactMap { $0.metadata?.elevGainM }
        guard priorGains.count >= 3, let best = priorGains.max(), gain > best else { return [] }
        return [.init(
            icon: "mountain.2",
            text: "\(Int(gain)) m of climbing — the hilliest of your last \(priorGains.count + 1) rides.",
            tone: .neutral, family: .terrain, weight: 50)]
    }

    // MARK: - Logistics

    private static func logistics(_ ride: Ride, _ prior: [Ride]) -> [Insight] {
        var out: [Insight] = []

        if let last = prior.first {
            let cal = Calendar.current
            let days = cal.dateComponents([.day],
                                          from: cal.startOfDay(for: last.startedAt),
                                          to:   cal.startOfDay(for: ride.startedAt)).day ?? 0
            if days == 0 {
                out.append(.init(icon: "arrow.2.squarepath",
                                 text: "Second time out today.",
                                 tone: .win, family: .logistics, weight: 48))
            } else if days >= 7 {
                out.append(.init(icon: "calendar",
                                 text: "First ride in \(days) days.",
                                 tone: .neutral, family: .logistics, weight: 42))
            }
        }

        let dur = ride.durationSeconds
        if let paused = ride.metadata?.pausedSeconds, dur > 600, paused / dur >= 0.25 {
            out.append(.init(
                icon: "pause.circle",
                text: "\(pct(paused / dur)) of the clock was spent stopped. Lights and traffic, not riding.",
                tone: .note, family: .logistics, weight: 38))
        }
        return out
    }

    // MARK: - Coverage (did the box actually catch the ride?)

    private static func coverage(
        _ ride: Ride,
        _ tracker: TrackerSummary?,
        _ trackerHistory: [String: TrackerSummary],
        _ prior: [Ride]
    ) -> [Insight] {
        let dur = ride.durationSeconds
        guard dur > 600 else { return [] }

        guard let t = tracker, t.isMeaningful else {
            // Only worth saying when he normally brings the box. Without this
            // gate it prints on every ride he ever recorded, box or not.
            let cutoff = ride.startedAt.addingTimeInterval(-14 * 86_400)
            let usesBox = prior.contains {
                $0.startedAt >= cutoff && (trackerHistory[$0.id]?.isMeaningful ?? false)
            }
            guard usesBox else { return [] }
            return [.init(icon: "cpu",
                          text: "No box data on this one — lean and G are blank.",
                          tone: .note, family: .coverage, weight: 40)]
        }

        guard let first = t.firstAt, let last = t.lastAt else { return [] }
        let covered = last.timeIntervalSince(first)
        guard covered / dur < 0.5 else { return [] }
        return [.init(
            icon: "exclamationmark.triangle",
            text: "The box only caught \(mins(covered)) of \(mins(dur)) — check the mount or the hotspot.",
            tone: .note, family: .coverage, weight: 75)]
    }

    // MARK: - Helpers

    private static func median(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        return s[s.count / 2]
    }
    private static func num(_ v: Double) -> String { String(format: "%.0f", v.rounded()) }
    private static func deg(_ v: Double) -> String { String(format: "%.0f°", v.rounded()) }
    private static func pct(_ f: Double) -> String { "\(Int(f * 100))%" }
    private static func mins(_ seconds: TimeInterval) -> String {
        let m = max(1, Int((seconds / 60).rounded()))
        return m < 60 ? "\(m) min" : "\(m / 60)h \(m % 60)m"
    }
}
