import SwiftUI

extension Notification.Name {
    /// Fired when auth state changes (sign-in, refresh, sign-out).
    static let lucidRideAuthChanged = Notification.Name("lucidRideAuthChanged")
}

@main
struct LucidRideApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var authRefreshTimer: Timer?

    init() {
        // Register the BGProcessingTask handler before scene launch — required
        // by iOS for the system to deliver background tasks to this app.
        TelemetryUploader.shared.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    await SupabaseClient.shared.signInIfNeeded()
                    NotificationCenter.default.post(name: .lucidRideAuthChanged, object: nil)
                    // Flush any pending telemetry batches stashed by the last
                    // session that ended with poor connectivity.
                    await TelemetryUploader.shared.flushPendingNow()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    handleScenePhase(newPhase)
                }
        }
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            // Re-run sign-in on every foreground transition. Cheap when token is
            // still valid, refreshes when expired.
            Task {
                await SupabaseClient.shared.signInIfNeeded()
                NotificationCenter.default.post(name: .lucidRideAuthChanged, object: nil)
            }
            startAuthRefreshTimer()
        case .background, .inactive:
            stopAuthRefreshTimer()
        @unknown default:
            break
        }
    }

    private func startAuthRefreshTimer() {
        stopAuthRefreshTimer()
        authRefreshTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in
            Task {
                await SupabaseClient.shared.signInIfNeeded()
                NotificationCenter.default.post(name: .lucidRideAuthChanged, object: nil)
            }
        }
    }

    private func stopAuthRefreshTimer() {
        authRefreshTimer?.invalidate()
        authRefreshTimer = nil
    }
}
