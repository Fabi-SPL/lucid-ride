import AppIntents
import Foundation

/// One-press ride toggle, designed for the iPhone 15 Pro Action Button.
/// User assigns this in Settings → Action Button → App Shortcut → LucidRide.
///
/// Behavior: if a ride is active → end it; otherwise → start one. The intent
/// hits Supabase directly so it works even when the app is in the background
/// (the activity row gets opened/closed regardless). On next foreground, the
/// recorder picks up the active ride via `refreshActiveRide()` and attaches
/// a fresh telemetry recorder from "now."
///
/// For the in-app feedback story, the intent posts
/// `Notification.Name.lucidRideToggledViaIntent` so ContentView can react if
/// the user happens to have the app open when they press the Action Button.
struct ToggleRideIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Ride"
    static var description = IntentDescription("Start a new ride, or end the current one. Designed for the Action Button.")

    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let supabase = SupabaseClient.shared
        let active = try? await supabase.activeRide()

        if let active {
            try? await supabase.endRide(activityId: active.id)
            NotificationCenter.default.post(name: .lucidRideToggledViaIntent,
                                           object: nil,
                                           userInfo: ["action": "ended", "id": active.id])
            return .result(dialog: "Ride ended.")
        } else {
            let ride = try? await supabase.startRide()
            NotificationCenter.default.post(name: .lucidRideToggledViaIntent,
                                           object: nil,
                                           userInfo: ["action": "started", "id": ride?.id ?? ""])
            return .result(dialog: "Ride started.")
        }
    }
}

/// Registers `ToggleRideIntent` as an App Shortcut so it appears in
/// Settings → Action Button → App Shortcut picker.
struct LucidRideShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleRideIntent(),
            phrases: [
                "Toggle ride in \(.applicationName)",
                "Start ride in \(.applicationName)",
                "End ride in \(.applicationName)"
            ],
            shortTitle: "Toggle Ride",
            systemImageName: "figure.outdoor.cycle"
        )
    }
}

extension Notification.Name {
    static let lucidRideToggledViaIntent = Notification.Name("lucidRideToggledViaIntent")
}
