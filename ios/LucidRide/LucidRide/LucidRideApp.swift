import SwiftUI
import UIKit

extension Notification.Name {
    /// Fired when auth state changes (sign-in, refresh, sign-out).
    static let lucidRideAuthChanged = Notification.Name("lucidRideAuthChanged")
}

/// Locks the app to whichever orientation the user picked in Settings
/// (`lucidride.portraitMode`). This is the authoritative runtime gate — it
/// overrides the Info.plist list, so a mounted phone can't auto-rotate away
/// from the chosen layout. ContentView nudges the actual rotation with
/// `requestGeometryUpdate` whenever the toggle flips.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        UserDefaults.standard.bool(forKey: "lucidride.portraitMode") ? .portrait : .landscape
    }
}

@main
struct LucidRideApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
