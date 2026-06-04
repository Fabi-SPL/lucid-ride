import SwiftUI

/// Lucid Ride — the bike IS the app.
///
/// Full-screen 3D bike. Tap any part for that part's telemetry. No tabs,
/// no nested views, no Today screen. The headlight pulses with live HR.
/// One pill at the bottom for START / END RIDE. One gear in the corner
/// for sign-in / version / sign-out.
struct ContentView: View {
    @StateObject private var state = HUDState()

    @State private var selectedPart: BikePart?
    @State private var showSettings = false
    @State private var activeRide: Ride?
    @State private var hintVisible = true
    @State private var endingRide = false
    @State private var startingRide = false
    @State private var partPositions: [BikePart: CGPoint] = [:]
    @State private var recorder: RideTelemetryRecorder?
    @State private var postRideActivityId: String?

    private let supabase = SupabaseClient.shared

    var body: some View {
        ZStack {
            StudioBackground()
                .ignoresSafeArea()

            if let ride = activeRide {
                // Active ride → glanceable telemetry HUD (no 3D bike: saves
                // battery and is far more readable in a mount).
                RideActiveHUD(
                    state: state,
                    ending: endingRide,
                    onEnd: { Task { await endRide(ride) } },
                    onSettings: { showSettings = true }
                )
                .transition(.opacity)
            } else {
                bikeHome
                    .transition(.opacity)
            }
        }
        .animation(DS.Anim.standard, value: activeRide?.id)
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .sheet(item: $selectedPart) { part in
            BikePartSheet(part: part, state: state)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(item: Binding(
            get: { postRideActivityId.map(IdentifiableString.init) },
            set: { postRideActivityId = $0?.value }
        )) { idWrapper in
            PostRideSummarySheet(activityId: idWrapper.value)
        }
        .onAppear { onEnter() }
        .onDisappear { onExit() }
        .onReceive(NotificationCenter.default.publisher(for: .lucidRideAuthChanged)) { _ in
            Task { await refreshActiveRide() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lucidRideToggledViaIntent)) { note in
            // Action Button fired ToggleRideIntent. We don't redo the network
            // work (the intent already did it) — we just sync our local state
            // with whatever happened.
            Task { await refreshActiveRide() }
            if let info = note.userInfo,
               let action = info["action"] as? String,
               action == "ended",
               let id = info["id"] as? String, !id.isEmpty {
                Task {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    postRideActivityId = id
                }
            }
        }
    }

    // MARK: - Bike home (idle / no active ride)

    @ViewBuilder
    private var bikeHome: some View {
        ZStack {
            BikeSceneView(
                leanDegrees: state.placeholderLean,
                pulseBPM: state.liveHR,
                accentColor: HUDState.zoneColor(for: state.liveHR),
                onPartTap: { part in
                    hintVisible = false
                    selectedPart = part
                },
                onPartScreenPositions: { positions in
                    partPositions = positions
                }
            )
            .ignoresSafeArea()

            // Floating part markers — small glass pills with an icon + chevron
            // anchored to each bike-part's projected screen position. They orbit
            // with the bike (driven by SCN render-loop projection) so the user
            // always sees what's tappable.
            partMarkersLayer
                .allowsHitTesting(false)

            ParticleBurst(
                trigger: state.particleTrigger,
                color: HUDState.zoneColor(for: state.liveHR)
            )
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomStack
            }
        }
    }

    // MARK: - Part markers (floating arrows + icons)

    @ViewBuilder
    private var partMarkersLayer: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(BikePart.allCases) { part in
                    if let p = partPositions[part] {
                        PartMarker(part: part, isLive: part.hasLiveData)
                            .position(x: p.x, y: p.y - 28)   // hover 28pt above part centre
                            .opacity(opacityForPosition(p, in: geo.size))
                            .animation(.easeOut(duration: 0.15), value: p)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }

    /// Fade markers near screen edges so they don't fight the UI chrome.
    private func opacityForPosition(_ p: CGPoint, in size: CGSize) -> Double {
        let edge: CGFloat = 60
        let leftFade  = min(1, max(0, p.x / edge))
        let rightFade = min(1, max(0, (size.width - p.x) / edge))
        let topFade   = min(1, max(0, (p.y - 50) / edge))           // top bar is ~50pt tall
        let botFade   = min(1, max(0, (size.height - 80 - p.y) / edge)) // bottom row is ~80pt
        return min(min(leftFade, rightFade), min(topFade, botFade))
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            liveDot
            Text("LUCID RIDE")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(DS.Colors.textMuted)
            Text("·")
                .foregroundStyle(DS.Colors.textFaint)
            Text(zoneLabelText)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(HUDState.zoneColor(for: state.liveHR))

            Spacer()

            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DS.Colors.textFaint)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.04)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
    }

    private var liveDot: some View {
        Circle()
            .fill(state.liveHR == nil ? DS.Colors.textFaint : DS.Colors.success)
            .frame(width: 7, height: 7)
            .opacity(state.liveHR == nil ? 0.4 : 1)
            .animation(DS.Anim.breath, value: state.liveHR != nil)
    }

    private var zoneLabelText: String {
        guard state.liveHR != nil else { return "STANDBY" }
        return HUDState.zoneLabel(for: state.liveHR).uppercased()
    }

    // MARK: - Bottom stack (hint + stale banner + ride button)

    private var bottomStack: some View {
        VStack(spacing: 10) {
            if hintVisible {
                tapHint
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if state.hrIsStale {
                staleBanner
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            rideActionRow
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
    }

    private var tapHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(DS.Colors.violet)
            Text("Tap any part of the bike for its data")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(DS.Colors.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().stroke(DS.Colors.violet.opacity(0.30), lineWidth: 0.5))
    }

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
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DS.Colors.amber.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DS.Colors.amber.opacity(0.35), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var rideActionRow: some View {
        HStack {
            Spacer()
            if let ride = activeRide {
                Button {
                    Task { await endRide(ride) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: endingRide ? "hourglass" : "stop.fill")
                        Text(endingRide ? "ENDING…" : "END RIDE · \(state.elapsedLabel)")
                    }
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(DS.Colors.danger.opacity(endingRide ? 0.45 : 0.85)))
                }
                .buttonStyle(.plain)
                .disabled(endingRide)
            } else {
                Button {
                    Task { await startRide() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: startingRide ? "hourglass" : "play.fill")
                        Text(startingRide ? "STARTING…" : "START RIDE")
                    }
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(DS.Colors.violet.opacity(startingRide ? 0.45 : 0.85)))
                }
                .buttonStyle(.plain)
                .disabled(startingRide)
            }
        }
    }

    // MARK: - Lifecycle

    private func onEnter() {
        UIApplication.shared.isIdleTimerDisabled = true
        forceLandscape()
        Task {
            await refreshActiveRide()
            state.start(activeRide: activeRide)
        }
        // Auto-fade the tap hint after 6 seconds
        Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            await MainActor.run {
                withAnimation(DS.Anim.standard) { hintVisible = false }
            }
        }
    }

    private func onExit() {
        UIApplication.shared.isIdleTimerDisabled = false
        state.stop()
    }

    private func forceLandscape() {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { _ in }
    }

    // MARK: - Ride control

    private func refreshActiveRide() async {
        activeRide = try? await supabase.activeRide()
        // If the app launched into an in-flight ride (e.g., crash-restart), attach
        // a fresh recorder from "now" so we at least capture the remainder.
        if let ride = activeRide, recorder == nil {
            let rec = RideTelemetryRecorder(activityId: ride.id, userId: supabase.userId, state: state)
            rec.start()
            recorder = rec
        }
    }

    private func startRide() async {
        startingRide = true
        defer { startingRide = false }
        do {
            if let ride = try await supabase.startRide() {
                activeRide = ride
                state.start(activeRide: ride)
                // Spin up the phone-side recorder (GPS + IMU + HR + zone time).
                let rec = RideTelemetryRecorder(activityId: ride.id, userId: supabase.userId, state: state)
                rec.start()
                recorder = rec
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func endRide(_ ride: Ride) async {
        // Optimistic end — clear the UI IMMEDIATELY so the screen can never
        // freeze on "ENDING…" no matter how slow/offline the network or
        // HealthKit is. Teardown runs in the background; the recorder stashes
        // any failed batch to disk and the BGProcessingTask retries it later.
        let rec = recorder
        let completedId = ride.id
        recorder = nil
        activeRide = nil
        endingRide = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        // Flush + summary + HealthKit finish + ended_at PATCH, off the UI path.
        Task {
            await rec?.stop()
            try? await supabase.endRide(activityId: completedId)
        }
        // Pop the post-ride sheet shortly after.
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            postRideActivityId = completedId
        }
    }
}

/// Thin Identifiable wrapper so `.sheet(item:)` can take a plain String.
private struct IdentifiableString: Identifiable {
    let value: String
    var id: String { value }
    init(_ v: String) { self.value = v }
}
