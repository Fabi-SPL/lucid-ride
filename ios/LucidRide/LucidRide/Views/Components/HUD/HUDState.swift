import Foundation
import SwiftUI

/// Shared live state for the Bike HUD — owned by BikeHUDView, observed by
/// each HUD page. Centralizes the HR poll, elapsed timer, lap counter,
/// placeholder motion, ride score, and zone-change particle trigger.
///
/// Pages just read; only this object writes.
@MainActor
final class HUDState: ObservableObject {
    @Published var liveHR: Double?
    @Published var hrBuffer: [HRSample] = []
    @Published var hrvAtStart: Double?

    @Published var elapsedSeconds: TimeInterval = 0
    @Published var lapCount: Int = 1
    @Published var rideScore: Int = 0

    @Published var placeholderLean: Double = 0           // Phase B → real IMU
    @Published var particleTrigger: Int = 0              // bumps on zone change
    @Published var lastSampleAge: TimeInterval = .infinity  // seconds since latest realtime_health row

    private(set) var lastZone: Int = -1
    private(set) var rideStartedAt: Date?

    /// True when no fresh HR sample has arrived in the last 60 seconds.
    /// Pages can render a "Open LucidBridge for live data" hint when stale.
    var hrIsStale: Bool { lastSampleAge > 60 }

    private var hrTimer: Timer?
    private var elapsedTimer: Timer?
    private var lapTimer: Timer?
    private var motionTimer: Timer?

    private let supabase = SupabaseClient.shared

    func start(activeRide: Ride?) {
        rideStartedAt = activeRide?.startedAt
        if let started = rideStartedAt {
            elapsedSeconds = Date().timeIntervalSince(started)
            lapCount = max(1, 1 + Int(elapsedSeconds) / 300)
        }

        Task { await prefetch() }
        Task { await refreshHR() }

        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if let started = self.rideStartedAt {
                    self.elapsedSeconds = Date().timeIntervalSince(started)
                }
                self.recomputeRideScore()
            }
        }
        hrTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { await self?.refreshHR() }
        }
        lapTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.lapCount += 1
                self.particleTrigger += 1
            }
        }
        motionTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let t = Date().timeIntervalSinceReferenceDate
                self.placeholderLean = sin(t * 0.30) * 28 + sin(t * 0.91) * 6
            }
        }
    }

    func stop() {
        [hrTimer, elapsedTimer, lapTimer, motionTimer].forEach { $0?.invalidate() }
        hrTimer = nil; elapsedTimer = nil; lapTimer = nil; motionTimer = nil
    }

    private func prefetch() async {
        let end = Date()
        let start = end.addingTimeInterval(-120)
        if let samples = try? await supabase.fetchHRWindow(start: start, end: end) {
            await MainActor.run { hrBuffer = samples }
        }
        if let hrv = try? await supabase.fetchLatestHRV() {
            await MainActor.run { hrvAtStart = hrv }
        }
    }

    private func refreshHR() async {
        guard let s = try? await supabase.fetchLatestHR(), let hr = s.heartRate else { return }
        await MainActor.run {
            withAnimation(.easeOut(duration: 0.4)) { self.liveHR = hr }
            if !self.hrBuffer.contains(where: { $0.recordedAt == s.recordedAt }) {
                self.hrBuffer.append(s)
            }
            let cutoff = Date().addingTimeInterval(-90)
            self.hrBuffer.removeAll { $0.recordedAt < cutoff }
            self.lastSampleAge = Date().timeIntervalSince(s.recordedAt)
            let zone = Self.zoneIndex(for: hr)
            if zone != self.lastZone, self.lastZone != -1 {
                self.particleTrigger += 1
            }
            self.lastZone = zone
        }
    }

    private func recomputeRideScore() {
        let body = min(35.0, max(0.0, (hrvAtStart ?? 50) / 100.0 * 35.0))
        let time = min(25.0, max(0.0, elapsedSeconds / 3600.0 * 25.0))
        rideScore = Int(body + time + 25.0 + 15.0)
    }

    // MARK: - Helpers

    static func zoneIndex(for hr: Double) -> Int {
        if hr < 110 { return 0 }
        if hr < 140 { return 1 }
        if hr < 165 { return 2 }
        return 3
    }

    static func zoneColor(for hr: Double?) -> Color {
        guard let hr else { return DS.Colors.textMuted }
        if hr < 110 { return DS.Colors.teal }
        if hr < 140 { return DS.Colors.success }
        if hr < 165 { return DS.Colors.warning }
        return DS.Colors.danger
    }

    static func zoneLabel(for hr: Double?) -> String {
        guard let hr else { return "—" }
        if hr < 110 { return "WARM-UP" }
        if hr < 140 { return "AEROBIC" }
        if hr < 165 { return "THRESHOLD" }
        return "REDLINE"
    }

    var elapsedLabel: String {
        let total = Int(elapsedSeconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
