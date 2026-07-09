import SwiftUI

/// Lucid Ride — shell.
///
/// Two states, one screen:
///   • Idle → `HomeView` (the Garage): last ride, month + lifetime stats,
///     scrollable history, one big START. Portrait.
///   • Riding → `RideActiveHUD`: glanceable telemetry, mount-locked orientation.
///
/// The 3D bike / tap-a-part paradigm is gone (2026-07-10). Any ride — the hero
/// or a history row — opens the full breakdown via `PostRideSummarySheet`.
struct ContentView: View {
    @StateObject private var state = HUDState()

    @State private var showSettings = false
    @State private var activeRide: Ride?
    @State private var endingRide = false
    @State private var startingRide = false
    @State private var recorder: RideTelemetryRecorder?
    @State private var postRideActivityId: String?

    /// Flip the HUD 180° — for a flat-on-tank mount iOS can't auto-rotate.
    /// Applies to the riding HUD only; the Garage stays upright.
    @AppStorage("lucidride.flipDashboard") private var flipDashboard = false

    /// Portrait vs landscape for the *riding* HUD. The Garage home is always
    /// portrait. Default false = landscape HUD (original mount behavior).
    @AppStorage("lucidride.portraitMode") private var portraitMode = false

    private let supabase = SupabaseClient.shared

    var body: some View {
        ZStack {
            MeshGradientBackground()
                .ignoresSafeArea()

            if let ride = activeRide {
                RideActiveHUD(
                    state: state,
                    ending: endingRide,
                    onEnd: { Task { await endRide(ride) } },
                    onSettings: { showSettings = true }
                )
                .rotationEffect(.degrees(flipDashboard ? 180 : 0))
                .transition(.opacity)
            } else {
                HomeView(
                    state: state,
                    starting: startingRide,
                    onStart: { Task { await startRide() } },
                    onSettings: { showSettings = true },
                    onOpenRide: { id in postRideActivityId = id }
                )
                .transition(.opacity)
            }
        }
        .animation(DS.Anim.standard, value: activeRide?.id)
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
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
        .onChange(of: portraitMode) { _, _ in applyOrientation() }
        .onChange(of: activeRide?.id) { _, _ in applyOrientation() }
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

    // MARK: - Lifecycle

    private func onEnter() {
        UIApplication.shared.isIdleTimerDisabled = true
        applyOrientation()
        Task {
            await refreshActiveRide()
            state.start(activeRide: activeRide)
        }
    }

    private func onExit() {
        UIApplication.shared.isIdleTimerDisabled = false
        state.stop()
    }

    /// Idle → portrait (the Garage list). Riding → the Settings toggle decides.
    /// Keeps `lucidride.rideActive` in sync so the AppDelegate gate agrees.
    private func applyOrientation() {
        let riding = activeRide != nil
        UserDefaults.standard.set(riding, forKey: "lucidride.rideActive")
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        let mask: UIInterfaceOrientationMask = !riding
            ? .portrait
            : (portraitMode ? .portrait : .landscape)
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    // MARK: - Ride control

    private func refreshActiveRide() async {
        activeRide = try? await supabase.activeRide()
        applyOrientation()
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
                applyOrientation()
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
        applyOrientation()
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        // Mark ended FIRST (tiny, fast PATCH) so a force-quit during the slower
        // flush/summary/HealthKit teardown can't leave the ride stuck "active".
        // Then do the heavier teardown.
        Task {
            try? await supabase.endRide(activityId: completedId)
            await rec?.stop()
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
