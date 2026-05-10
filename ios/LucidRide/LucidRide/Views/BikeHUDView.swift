import SwiftUI

/// Bike Mode HUD — second-screen dashboard designed to be glanced at while the
/// phone is mounted under the bike's TFT cluster (X-Grip / Quad Lock).
///
/// Pure-black background for max contrast in sunlight, huge numerals, minimal
/// chrome, polls realtime_health every 3s for live HR. Phase A: HR is real,
/// lean angle / distance / speed are placeholders rendered in muted color
/// with a "PLACEHOLDER" pin to signal "telemetry not yet wired".
///
/// Layout swaps between landscape (4 tiles in a row) and portrait (2x2 grid)
/// via GeometryReader — the user can mount the phone in either orientation.
struct BikeHUDView: View {
    let activeRide: Ride?
    var onEndRide: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var liveHR: Double?
    @State private var lastHRRecordedAt: Date?
    @State private var elapsedSeconds: TimeInterval = 0
    @State private var elapsedTimer: Timer?
    @State private var hrTimer: Timer?
    @State private var endingRide = false

    private let supabase = SupabaseClient.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                GeometryReader { geo in
                    let isLandscape = geo.size.width > geo.size.height
                    ScrollView(.vertical, showsIndicators: false) {
                        if isLandscape {
                            HStack(spacing: 14) {
                                hrTile
                                leanTile
                                elapsedTile
                                speedTile
                            }
                            .padding(.horizontal, 16)
                        } else {
                            VStack(spacing: 14) {
                                HStack(spacing: 14) { hrTile; leanTile }
                                HStack(spacing: 14) { elapsedTile; speedTile }
                                distanceTile
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .onAppear {
            startTimers()
            UIApplication.shared.isIdleTimerDisabled = true   // keep screen on while mounted
        }
        .onDisappear {
            stopTimers()
            UIApplication.shared.isIdleTimerDisabled = false
        }
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
                liveDot
                Text("LUCID RIDE · BIKE MODE")
                    .font(DS.Font.label)
                    .tracking(1.2)
                    .foregroundStyle(DS.Colors.textMuted)
            }

            Spacer()

            if activeRide != nil {
                Button {
                    Task { await endRide() }
                } label: {
                    Text(endingRide ? "ENDING…" : "END RIDE")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(DS.Colors.danger.opacity(endingRide ? 0.45 : 0.80)))
                }
                .buttonStyle(.plain)
                .disabled(endingRide)
            }
        }
    }

    private var liveDot: some View {
        let dotColor: Color = liveHR == nil ? DS.Colors.textFaint : DS.Colors.success
        return Circle()
            .fill(dotColor)
            .frame(width: 8, height: 8)
            .opacity(liveHR == nil ? 0.4 : 1.0)
            .animation(DS.Anim.breath, value: liveHR != nil)
    }

    // MARK: - Tiles

    private var hrTile: some View {
        bigTile(
            label: "HEART RATE",
            value: liveHR.map { "\(Int($0))" } ?? "—",
            unit: "BPM",
            color: hrColor,
            icon: "heart.fill",
            placeholder: false
        )
    }

    private var leanTile: some View {
        bigTile(
            label: "LEAN",
            value: "0",
            unit: "°",
            color: DS.Colors.teal,
            icon: "skew",
            placeholder: true
        )
    }

    private var elapsedTile: some View {
        bigTile(
            label: "ELAPSED",
            value: elapsedLabel,
            unit: "M:S",
            color: DS.Colors.violet,
            icon: "clock.fill",
            placeholder: activeRide == nil
        )
    }

    private var speedTile: some View {
        bigTile(
            label: "SPEED",
            value: "—",
            unit: "KM/H",
            color: DS.Colors.amber,
            icon: "speedometer",
            placeholder: true
        )
    }

    private var distanceTile: some View {
        bigTile(
            label: "DISTANCE",
            value: "—",
            unit: "KM",
            color: Color(hex: 0xA78BFA),
            icon: "map.fill",
            placeholder: true
        )
    }

    @ViewBuilder
    private func bigTile(label: String, value: String, unit: String, color: Color, icon: String, placeholder: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color.opacity(0.8))
                Text(label)
                    .font(DS.Font.label)
                    .tracking(1.0)
                    .foregroundStyle(DS.Colors.textMuted)
                Spacer(minLength: 4)
                if placeholder {
                    Text("PENDING")
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(DS.Colors.amber.opacity(0.7))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .overlay(
                            Capsule()
                                .stroke(DS.Colors.amber.opacity(0.45), lineWidth: 0.5)
                        )
                }
            }
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 84, weight: .heavy, design: .rounded))
                    .foregroundStyle(placeholder ? color.opacity(0.45) : color)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                Text(unit)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(DS.Colors.textMuted)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(color.opacity(placeholder ? 0.15 : 0.30), lineWidth: 0.5)
        )
        .shadow(color: placeholder ? .clear : color.opacity(0.20), radius: 24, x: 0, y: 0)
    }

    // MARK: - Computed

    private var elapsedLabel: String {
        let total = Int(elapsedSeconds)
        let m = total / 60
        let s = total % 60
        if m >= 60 {
            let h = m / 60
            let mm = m % 60
            return String(format: "%d:%02d", h, mm)
        }
        return String(format: "%d:%02d", m, s)
    }

    private var hrColor: Color {
        guard let hr = liveHR else { return DS.Colors.textMuted }
        if hr < 110 { return DS.Colors.teal }
        if hr < 140 { return DS.Colors.success }
        if hr < 165 { return DS.Colors.warning }
        return DS.Colors.danger
    }

    // MARK: - Behavior

    private func startTimers() {
        if let started = activeRide?.startedAt {
            elapsedSeconds = Date().timeIntervalSince(started)
        }
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if let started = activeRide?.startedAt {
                elapsedSeconds = Date().timeIntervalSince(started)
            }
        }
        Task { await refreshHR() }
        hrTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            Task { await refreshHR() }
        }
    }

    private func stopTimers() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        hrTimer?.invalidate()
        hrTimer = nil
    }

    private func refreshHR() async {
        guard let sample = try? await supabase.fetchLatestHR(), let hr = sample.heartRate else { return }
        await MainActor.run {
            withAnimation(.easeOut(duration: 0.4)) {
                self.liveHR = hr
                self.lastHRRecordedAt = sample.recordedAt
            }
        }
    }

    private func endRide() async {
        endingRide = true
        await onEndRide()
        endingRide = false
        dismiss()
    }
}
