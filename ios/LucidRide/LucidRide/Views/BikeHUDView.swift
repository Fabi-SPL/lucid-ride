import SwiftUI

/// Bike Mode HUD — multi-page swipeable cluster that locks to landscape on
/// entry. Three pages designed for under-TFT phone mount:
///
///   1. Body — heart rate hero + ECG waveform + small HRV/elapsed/score rail
///   2. Ride — lean horizon hero + lap/elapsed/score cells
///   3. Cluster — two large analog dials (HR + lean)
///
/// Voice readouts toggle in header. Particle bursts on HR-zone changes
/// across all pages (overlay). Aurora background shared across pages.
struct BikeHUDView: View {
    let activeRide: Ride?
    var onEndRide: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var state = HUDState()
    @StateObject private var voice = HUDVoice()

    @State private var pageIndex: Int = 0
    @State private var endingRide = false
    @State private var voiceTimer: Timer?

    var body: some View {
        ZStack {
            AuroraBackground(pulseBPM: state.liveHR)
            ParticleBurst(trigger: state.particleTrigger,
                          color: HUDState.zoneColor(for: state.liveHR))

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                TabView(selection: $pageIndex) {
                    HUDPageBody(state: state).tag(0)
                    HUDPageRide(state: state).tag(1)
                    HUDPageCluster(state: state).tag(2)
                    HUDPageBike(state: state).tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .frame(maxHeight: .infinity)

                if state.hrIsStale {
                    staleBanner
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { onEnter() }
        .onDisappear { onExit() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(DS.Colors.textFaint)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                liveDot
                Text("LUCID RIDE")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(DS.Colors.textMuted)
                Text("·")
                    .foregroundStyle(DS.Colors.textFaint)
                Text(pageName.uppercased())
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(HUDState.zoneColor(for: state.liveHR))
            }

            Spacer()

            Button {
                voice.toggle()
                if voice.enabled { voice.say("Bike mode armed.") }
            } label: {
                Image(systemName: voice.enabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(voice.enabled ? DS.Colors.violet : DS.Colors.textFaint)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(voice.enabled ? 0.10 : 0.04)))
            }
            .buttonStyle(.plain)

            if activeRide != nil {
                Button {
                    Task { await endRide() }
                } label: {
                    Text(endingRide ? "ENDING…" : "END")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(DS.Colors.danger.opacity(endingRide ? 0.45 : 0.85)))
                }
                .buttonStyle(.plain)
                .disabled(endingRide)
            }
        }
    }

    private var liveDot: some View {
        Circle()
            .fill(state.liveHR == nil ? DS.Colors.textFaint : DS.Colors.success)
            .frame(width: 7, height: 7)
            .opacity(state.liveHR == nil ? 0.4 : 1)
            .animation(DS.Anim.breath, value: state.liveHR != nil)
    }

    private var pageName: String {
        switch pageIndex {
        case 0: return "Body"
        case 1: return "Ride"
        case 2: return "Cluster"
        case 3: return "Bike"
        default: return ""
        }
    }

    /// Bottom-edge banner shown when no fresh HR samples have arrived in
    /// the last 60s — usually means LucidBridge isn't running. Tap to dismiss.
    private var staleBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(DS.Colors.amber)
            Text("HR stale — open LucidBridge to start streaming")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(DS.Colors.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DS.Colors.amber.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DS.Colors.amber.opacity(0.35), lineWidth: 0.5)
        )
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
    }

    // MARK: - Lifecycle

    private func onEnter() {
        UIApplication.shared.isIdleTimerDisabled = true
        forceLandscape()
        state.start(activeRide: activeRide)
        startVoiceTimer()
    }

    private func onExit() {
        UIApplication.shared.isIdleTimerDisabled = false
        state.stop()
        voice.stop()
        voiceTimer?.invalidate()
        voiceTimer = nil
        restorePortrait()
    }

    private func forceLandscape() {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { _ in }
    }

    private func restorePortrait() {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
    }

    private func startVoiceTimer() {
        voiceTimer = Timer.scheduledTimer(withTimeInterval: 90, repeats: true) { _ in
            Task { @MainActor in
                guard voice.enabled else { return }
                let mins = Int(state.elapsedSeconds) / 60
                if let hr = state.liveHR {
                    voice.say("Heart rate \(Int(hr)). \(HUDState.zoneLabel(for: hr).lowercased()) zone. \(mins) minutes elapsed.")
                } else {
                    voice.say("\(mins) minutes elapsed.")
                }
            }
        }
    }

    private func endRide() async {
        endingRide = true
        if voice.enabled { voice.say("Ending ride.") }
        await onEndRide()
        endingRide = false
        dismiss()
    }
}
