import SwiftUI
import UIKit

extension Notification.Name {
    /// Fired when auth state changes (sign-in, refresh, sign-out).
    static let lucidRideAuthChanged = Notification.Name("lucidRideAuthChanged")
}

/// Authoritative runtime orientation gate — overrides the Info.plist list so a
/// mounted phone can't auto-rotate away from the chosen layout. Two states:
///   • Not riding (Garage home) → always portrait (scrollable list).
///   • Riding → the Settings `lucidride.portraitMode` toggle decides.
/// ContentView keeps `lucidride.rideActive` in sync and nudges the actual
/// rotation with `requestGeometryUpdate` on every transition.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        let riding = UserDefaults.standard.bool(forKey: "lucidride.rideActive")
        guard riding else { return .portrait }
        return UserDefaults.standard.bool(forKey: "lucidride.portraitMode") ? .portrait : .landscape
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
