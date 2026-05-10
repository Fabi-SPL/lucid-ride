import SwiftUI

/// Minimal settings — auth status, build info, sign out.
/// More to come in Phase B (bike picker, default route, telemetry source picker).
struct SettingsView: View {
    @State private var authedEmail: String = ""
    @State private var isAuthed = false

    private let supabase = SupabaseClient.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {

                accountSection
                buildSection
                aboutSection

                Color.clear.frame(height: 80)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.top, DS.Spacing.md)
        }
        .scrollIndicators(.hidden)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                TwoToneHeadline(
                    primary: "Settings",
                    secondary: " · Lucid Ride",
                    font: .system(size: 17, weight: .heavy, design: .rounded)
                )
            }
        }
        .task { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .lucidRideAuthChanged)) { _ in
            refresh()
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            SectionHeader(icon: "person.circle", title: "ACCOUNT")

            VStack(alignment: .leading, spacing: 0) {
                InfoRow(icon: "envelope",
                        label: "Email",
                        value: authedEmail.isEmpty ? "not signed in" : authedEmail)
                InfoRow(icon: "checkmark.shield",
                        label: "Status",
                        value: isAuthed ? "authenticated" : "—",
                        color: isAuthed ? DS.Colors.success : DS.Colors.textMuted)
            }
            .padding(.vertical, DS.Spacing.sm)
            .glassCard(padding: 0)

            if isAuthed {
                Button {
                    supabase.signOut()
                    refresh()
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(GlassActionButtonStyle(tint: DS.Colors.danger))
            }
        }
    }

    @ViewBuilder
    private var buildSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            SectionHeader(icon: "hammer", title: "BUILD")
            VStack(alignment: .leading, spacing: 0) {
                InfoRow(icon: "tag",      label: "Version",  value: BuildInfo.codeVersion)
                InfoRow(icon: "number",   label: "Commit",   value: String(BuildInfo.commitHash.prefix(7)))
                InfoRow(icon: "calendar", label: "Built",    value: BuildInfo.buildDate)
                InfoRow(icon: "iphone",   label: "App",      value: BuildInfo.appName)
            }
            .padding(.vertical, DS.Spacing.sm)
            .glassCard(padding: 0)
        }
    }

    @ViewBuilder
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            SectionHeader(icon: "info.circle", title: "ABOUT")
            VStack(alignment: .leading, spacing: 8) {
                Text("Lucid Ride is a bike telemetry + biometric pipeline. Phase A: HR profile (real, from the linked health backend) + placeholder telemetry tiles. Phase B: RaceBox GPS/IMU, GoPro GPMF, OBD adapter, and voice debrief — wires up as hardware lands.")
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Colors.textSecondary)
                    .lineLimit(nil)
            }
            .padding(DS.Spacing.md)
            .glassCard(padding: 0)
        }
    }

    private func refresh() {
        self.authedEmail = UserDefaults.standard.string(forKey: "lucidride_email") ?? ""
        self.isAuthed    = supabase.isAuthenticated
    }
}
