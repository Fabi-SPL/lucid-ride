import SwiftUI

/// Modal sheet from the main app. Shows auth status, build info, sign-out.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var authedEmail: String = ""
    @State private var isAuthed = false

    private let supabase = SupabaseClient.shared

    var body: some View {
        ZStack(alignment: .top) {
            DS.Colors.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.top, 12)
                    .padding(.horizontal, 22)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        accountSection
                        buildSection
                        aboutSection
                        Color.clear.frame(height: 40)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                }
                .scrollIndicators(.hidden)
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(DS.Colors.bg)
        .task { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .lucidRideAuthChanged)) { _ in
            refresh()
        }
    }

    private var header: some View {
        HStack {
            Text("SETTINGS")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(DS.Colors.textPrimary)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(DS.Colors.textFaint)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("ACCOUNT", icon: "person.circle")
            VStack(alignment: .leading, spacing: 0) {
                infoRow("Email", value: authedEmail.isEmpty ? "not signed in" : authedEmail)
                Divider().background(DS.Colors.border).padding(.horizontal, 14)
                infoRow("Status",
                        value: isAuthed ? "authenticated" : "—",
                        color: isAuthed ? DS.Colors.success : DS.Colors.textMuted)
            }
            .background(
                RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04))
            )

            if isAuthed {
                Button {
                    supabase.signOut()
                    refresh()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Sign out")
                    }
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(DS.Colors.danger.opacity(0.85)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var buildSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("BUILD", icon: "hammer")
            VStack(alignment: .leading, spacing: 0) {
                infoRow("Version", value: BuildInfo.codeVersion)
                Divider().background(DS.Colors.border).padding(.horizontal, 14)
                infoRow("Commit", value: String(BuildInfo.commitHash.prefix(7)))
                Divider().background(DS.Colors.border).padding(.horizontal, 14)
                infoRow("Built", value: BuildInfo.buildDate)
                Divider().background(DS.Colors.border).padding(.horizontal, 14)
                infoRow("App", value: BuildInfo.appName)
            }
            .background(
                RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04))
            )
        }
    }

    @ViewBuilder
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("ABOUT", icon: "info.circle")
            Text("Lucid Ride is a bike telemetry + biometric pipeline. Phase A: live HR / HRV / body state via the linked health backend, plus placeholder slots on every other bike part. Phase B: RaceBox GPS/IMU, GoPro GPMF, OBD adapter, and voice debrief — wires up as hardware lands.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(DS.Colors.textSecondary)
                .lineLimit(nil)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04))
                )
        }
    }

    @ViewBuilder
    private func sectionLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(DS.Colors.textMuted)
            Text(title)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(DS.Colors.textMuted)
        }
    }

    @ViewBuilder
    private func infoRow(_ label: String, value: String, color: Color = DS.Colors.textPrimary) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.textMuted)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func refresh() {
        self.authedEmail = UserDefaults.standard.string(forKey: "lucidride_email") ?? ""
        self.isAuthed    = supabase.isAuthenticated
    }
}
