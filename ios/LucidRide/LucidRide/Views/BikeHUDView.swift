import SwiftUI

/// Bike Mode HUD — second-screen dashboard for under-TFT phone mount.
///
/// Maximalist Phase A: aurora background pulsing with HR · lean horizon
/// (placeholder sine wave) · 4 stat tiles (real HR + analog speedo + ride
/// score + lap counter) · ECG-style HR waveform · particle bursts on zone
/// changes · optional voice readouts via Bluetooth (Cardo).
///
/// Phase B will replace placeholder lean/speed/distance with RaceBox/IMU
/// + GoPro GPMF + OBDLink data.
struct BikeHUDView: View {
    let activeRide: Ride?
    var onEndRide: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var voice = HUDVoice()

    @State private var liveHR: Double?
    @State private var hrBuffer: [HRSample] = []          // last 60s
    @State private var lastHRZone: Int = -1
    @State private var elapsedSeconds: TimeInterval = 0
    @State private var placeholderLean: Double = 0
    @State private var placeholderSpeed: Double = 0
    @State private var lapCount: Int = 1
    @State private var rideScore: Int = 0
    @State private var hrvAtStart: Double?
    @State private var particleTrigger: Int = 0
    @State private var endingRide = false

    @State private var hrTimer: Timer?
    @State private var elapsedTimer: Timer?
    @State private var lapTimer: Timer?
    @State private var motionTimer: Timer?
    @State private var voiceTimer: Timer?

    private let supabase = SupabaseClient.shared

    var body: some View {
        ZStack {
            AuroraBackground(pulseBPM: liveHR)
            ParticleBurst(trigger: particleTrigger, color: zoneColor(for: liveHR))

            GeometryReader { geo in
                let isLandscape = geo.size.width > geo.size.height
                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 18)
                        .padding(.top, 10)
                        .padding(.bottom, 6)

                    LeanHorizonView(leanDegrees: placeholderLean)
                        .frame(height: isLandscape ? 70 : 80)
                        .padding(.horizontal, 8)

                    if isLandscape { landscapeBody } else { portraitBody }

                    LiveHRWaveform(samples: hrBuffer)
                        .frame(height: isLandscape ? 90 : 110)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 14)
                }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .onAppear { onEnter() }
        .onDisappear { onExit() }
    }

    // MARK: - Layouts

    @ViewBuilder
    private var landscapeBody: some View {
        HStack(spacing: 14) {
            hrTile
            BigAnalogSpeedo(value: placeholderSpeed, max: 200,
                            label: "SPEED", unit: "KM/H", placeholder: true)
                .padding(8)
            scoreTile
            lapTile
        }
        .padding(.horizontal, 14)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var portraitBody: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                hrTile
                BigAnalogSpeedo(value: placeholderSpeed, max: 200,
                                label: "SPEED", unit: "KM/H", placeholder: true)
                    .padding(6)
            }
            HStack(spacing: 12) {
                scoreTile
                lapTile
            }
        }
        .padding(.horizontal, 14)
        .frame(maxHeight: .infinity)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(DS.Colors.textFaint)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                Circle()
                    .fill(liveHR == nil ? DS.Colors.textFaint : DS.Colors.success)
                    .frame(width: 7, height: 7)
                    .opacity(liveHR == nil ? 0.45 : 1)
                    .animation(DS.Anim.breath, value: liveHR != nil)
                Text("LUCID RIDE · BIKE MODE")
                    .font(DS.Font.label)
                    .tracking(1.2)
                    .foregroundStyle(DS.Colors.textMuted)
            }

            Spacer()

            Button {
                voice.toggle()
                if voice.enabled { voice.say("Bike mode armed.") }
            } label: {
                Image(systemName: voice.enabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(voice.enabled ? DS.Colors.violet : DS.Colors.textFaint)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(voice.enabled ? 0.10 : 0.04)))
            }
            .buttonStyle(.plain)

            if activeRide != nil {
                Button {
                    Task { await endRide() }
                } label: {
                    Text(endingRide ? "ENDING…" : "END")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(DS.Colors.danger.opacity(endingRide ? 0.45 : 0.85)))
                }
                .buttonStyle(.plain)
                .disabled(endingRide)
            }
        }
    }

    // MARK: - Tiles

    private var hrTile: some View {
        TileFrame(color: hrColor) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(hrColor.opacity(0.85))
                    Text("HEART RATE")
                        .font(DS.Font.label)
                        .tracking(1.0)
                        .foregroundStyle(DS.Colors.textMuted)
                }
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(liveHR.map { "\(Int($0))" } ?? "—")
                        .font(.system(size: 64, weight: .heavy, design: .rounded))
                        .foregroundStyle(hrColor)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("BPM")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(DS.Colors.textMuted)
                }
                Text(zoneLabel(for: liveHR))
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(hrColor.opacity(0.85))
            }
        }
    }

    private var scoreTile: some View {
        TileFrame(color: scoreColor) {
            VStack(alignment: .leading, spacing: 6) {
                Text("RIDE SCORE")
                    .font(DS.Font.label)
                    .tracking(1.0)
                    .foregroundStyle(DS.Colors.textMuted)
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text("\(rideScore)")
                        .font(.system(size: 64, weight: .heavy, design: .rounded))
                        .foregroundStyle(scoreColor)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("/100")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(DS.Colors.textMuted)
                }
                Text("BODY · TIME · SMOOTH")
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(DS.Colors.textFaint)
            }
        }
    }

    private var lapTile: some View {
        TileFrame(color: DS.Colors.success) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DS.Colors.success.opacity(0.85))
                    Text("LAP")
                        .font(DS.Font.label)
                        .tracking(1.0)
                        .foregroundStyle(DS.Colors.textMuted)
                }
                Text("\(lapCount)")
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .foregroundStyle(DS.Colors.success)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("\(elapsedLabel)  · BEST —")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(DS.Colors.textFaint)
            }
        }
    }

    // MARK: - Computed

    private var elapsedLabel: String {
        let total = Int(elapsedSeconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private var hrColor: Color { zoneColor(for: liveHR) }

    private var scoreColor: Color {
        if rideScore >= 80 { return DS.Colors.success }
        if rideScore >= 60 { return DS.Colors.teal }
        if rideScore >= 40 { return DS.Colors.warning }
        return DS.Colors.danger
    }

    private func zoneColor(for hr: Double?) -> Color {
        guard let hr else { return DS.Colors.textMuted }
        if hr < 110 { return DS.Colors.teal }
        if hr < 140 { return DS.Colors.success }
        if hr < 165 { return DS.Colors.warning }
        return DS.Colors.danger
    }

    private func zoneLabel(for hr: Double?) -> String {
        guard let hr else { return "—" }
        if hr < 110 { return "WARM-UP ZONE" }
        if hr < 140 { return "AEROBIC ZONE" }
        if hr < 165 { return "THRESHOLD" }
        return "REDLINE"
    }

    private func zoneIndex(for hr: Double?) -> Int {
        guard let hr else { return -1 }
        if hr < 110 { return 0 }
        if hr < 140 { return 1 }
        if hr < 165 { return 2 }
        return 3
    }

    // MARK: - Lifecycle

    private func onEnter() {
        UIApplication.shared.isIdleTimerDisabled = true
        if let started = activeRide?.startedAt {
            elapsedSeconds = Date().timeIntervalSince(started)
            // Pretend lap counter increments every 5 minutes since started_at
            lapCount = max(1, 1 + Int(elapsedSeconds) / 300)
        }
        Task { await prefetchHRWindow() }
        Task { await refreshHR() }
        startTimers()
    }

    private func onExit() {
        UIApplication.shared.isIdleTimerDisabled = false
        stopTimers()
        voice.stop()
    }

    private func startTimers() {
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                if let started = activeRide?.startedAt {
                    elapsedSeconds = Date().timeIntervalSince(started)
                }
                updateRideScore()
            }
        }
        hrTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            Task { await refreshHR() }
        }
        lapTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task { @MainActor in
                lapCount += 1
                particleTrigger += 1
                if voice.enabled { voice.say("Lap \(lapCount).") }
            }
        }
        // Placeholder lean + speed motion — slow sine waves so the dial / horizon
        // feel alive even before real telemetry hardware lands.
        motionTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            Task { @MainActor in
                let t = Date().timeIntervalSinceReferenceDate
                placeholderLean = sin(t * 0.30) * 28 + sin(t * 0.91) * 6
                placeholderSpeed = 60 + sin(t * 0.18) * 35 + sin(t * 0.71) * 8
            }
        }
        voiceTimer = Timer.scheduledTimer(withTimeInterval: 90, repeats: true) { _ in
            Task { @MainActor in
                guard voice.enabled else { return }
                let hr = liveHR.map { Int($0) }
                let mins = Int(elapsedSeconds) / 60
                if let hr {
                    voice.say("Heart rate \(hr). \(zoneLabel(for: liveHR).lowercased()). \(mins) minutes elapsed.")
                } else {
                    voice.say("\(mins) minutes elapsed.")
                }
            }
        }
    }

    private func stopTimers() {
        [elapsedTimer, hrTimer, lapTimer, motionTimer, voiceTimer].forEach { $0?.invalidate() }
        elapsedTimer = nil; hrTimer = nil; lapTimer = nil; motionTimer = nil; voiceTimer = nil
    }

    // MARK: - Data

    private func prefetchHRWindow() async {
        // Pull last 2 minutes of HR samples so the waveform draws immediately
        // on entry instead of empty-state until the first poll.
        let end = Date()
        let start = end.addingTimeInterval(-120)
        if let samples = try? await supabase.fetchHRWindow(start: start, end: end) {
            await MainActor.run {
                hrBuffer = samples
                if let hrv = try? await supabase.fetchLatestHRV() {
                    self.hrvAtStart = hrv
                }
            }
        }
        // HRV (separate await to avoid nested try? in task)
        if hrvAtStart == nil, let hrv = try? await supabase.fetchLatestHRV() {
            await MainActor.run { self.hrvAtStart = hrv }
        }
    }

    private func refreshHR() async {
        guard let sample = try? await supabase.fetchLatestHR(), let hr = sample.heartRate else { return }
        await MainActor.run {
            withAnimation(.easeOut(duration: 0.4)) { liveHR = hr }
            // Append to buffer, dedupe by recordedAt, keep last 90s
            if !hrBuffer.contains(where: { $0.recordedAt == sample.recordedAt }) {
                hrBuffer.append(sample)
            }
            let cutoff = Date().addingTimeInterval(-90)
            hrBuffer.removeAll { $0.recordedAt < cutoff }
            // Zone change detection — particle burst + voice
            let zone = zoneIndex(for: hr)
            if zone != lastHRZone, lastHRZone != -1 {
                particleTrigger += 1
                if voice.enabled {
                    voice.say(zone > lastHRZone ? "Climbing into \(zoneLabel(for: hr).lowercased())." : "Easing into \(zoneLabel(for: hr).lowercased()).")
                }
            }
            lastHRZone = zone
        }
    }

    private func updateRideScore() {
        // Phase A formula:
        //   bodyComponent  = clamp(hrv / 100 * 35, 0, 35)   — body-state alignment
        //   timeComponent  = clamp(elapsed/3600 * 25, 0, 25) — first hour caps
        //   smoothPlaceholder = 25 (constant — replace with HR variance score later)
        //   aggrPlaceholder   = 15 (constant — replace with lean variance later)
        let body = min(35.0, max(0.0, (hrvAtStart ?? 50) / 100.0 * 35.0))
        let time = min(25.0, max(0.0, elapsedSeconds / 3600.0 * 25.0))
        let smooth = 25.0
        let aggr = 15.0
        rideScore = Int(body + time + smooth + aggr)
    }

    private func endRide() async {
        endingRide = true
        if voice.enabled { voice.say("Ending ride.") }
        await onEndRide()
        endingRide = false
        dismiss()
    }
}

// MARK: - Tile chrome

/// Glass-tinted card frame used by the four HUD tiles. Soft glow in the
/// tile color, dashed-stroke border so they read as instrument cells.
private struct TileFrame<Content: View>: View {
    let color: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(color.opacity(0.32), lineWidth: 0.6)
            )
            .shadow(color: color.opacity(0.18), radius: 22, x: 0, y: 0)
    }
}
