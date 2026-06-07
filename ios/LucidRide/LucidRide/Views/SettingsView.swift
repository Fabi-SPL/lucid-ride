import SwiftUI

/// Modal sheet from the main app. Shows auth status, build info, sign-out.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var authedEmail: String = ""
    @State private var isAuthed = false

    /// Master brightness for the home-screen 3D bike. Read live by
    /// `BikeSceneView` via the same `@AppStorage` key, so dragging this
    /// updates the bike in real time behind the settings sheet.
    @AppStorage("lucidride.bikeBrightness") private var bikeBrightness: Double = 0.5

    /// Flip the whole HUD 180° — for when the phone lies flat and iOS can't
    /// auto-rotate (gravity is on the z-axis), so it reads upside down.
    @AppStorage("lucidride.flipDashboard") private var flipDashboard = false
    /// Lean lateral axis. true = phone long-edge ACROSS the bike (landscape on
    /// the tank); false = long-edge ALONG the bike (portrait).
    @AppStorage("lucidride.leanLateralY") private var leanLateralY = true

    private let supabase = SupabaseClient.shared
    @ObservedObject private var spotify = SpotifyController.shared

    var body: some View {
        ZStack(alignment: .top) {
            DS.Colors.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.top, 12)
                    .padding(.horizontal, 22)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        displaySection
                        mountSection
                        musicSection
                        accountSection
                        buildSection
                        aboutSection
                        creditsSection
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
    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("DISPLAY", icon: "sun.max")
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Bike brightness")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.textMuted)
                    Spacer()
                    Text("\(Int(bikeBrightness * 100))%")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(DS.Colors.textPrimary)
                        .monospacedDigit()
                }
                HStack(spacing: 10) {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(DS.Colors.textFaint)
                    Slider(value: $bikeBrightness, in: 0.0...1.0)
                        .tint(DS.Colors.violet)
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(DS.Colors.textFaint)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04))
            )
            Text("Drag while you can see the bike — it updates live. Drives HDR + key + ambient together as one knob.")
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(DS.Colors.textMuted)
                .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var mountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("MOUNT", icon: "iphone.gen3")
            VStack(spacing: 0) {
                Toggle(isOn: $flipDashboard) {
                    Text("Flip dashboard 180°")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.textPrimary)
                }
                .tint(DS.Colors.violet)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Divider().background(DS.Colors.border).padding(.horizontal, 14)

                Toggle(isOn: $leanLateralY) {
                    Text("Phone mounted sideways (landscape)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.textPrimary)
                }
                .tint(DS.Colors.violet)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(
                RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04))
            )
            Text("Flip if the HUD reads upside-down on the tank. Turn ON \u{201C}sideways\u{201D} when the phone's long edge runs across the bike — keeps the lean angle correct.")
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(DS.Colors.textMuted)
                .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var musicSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("MUSIC", icon: "music.note")
            VStack(alignment: .leading, spacing: 0) {
                if spotify.isConnected {
                    infoRow("Spotify", value: "Connected", color: DS.Colors.success)
                    Divider().background(DS.Colors.border).padding(.horizontal, 14)
                    Button { spotify.disconnect() } label: {
                        HStack {
                            Text("Disconnect")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(DS.Colors.danger)
                            Spacer()
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(DS.Colors.danger.opacity(0.7))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button { spotify.connect() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "music.note")
                                .font(.system(size: 13, weight: .bold))
                            Text("Connect Spotify")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(DS.Colors.textFaint)
                        }
                        .foregroundStyle(DS.Colors.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04))
            )
            Text("Control playback from the ride screen with glove-sized buttons. Needs Spotify Premium + the Spotify app open on this phone.")
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(DS.Colors.textMuted)
                .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("DATA", icon: "externaldrive.connected.to.line.below")
            VStack(alignment: .leading, spacing: 0) {
                infoRow("Source", value: "Supabase (direct)")
                Divider().background(DS.Colors.border).padding(.horizontal, 14)
                infoRow("Mode", value: "anon key · scoped", color: DS.Colors.success)
            }
            .background(
                RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04))
            )
            Text("No login needed — reads HR + rides directly via row-scoped policies. No credentials stored in the app.")
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(DS.Colors.textMuted)
                .padding(.horizontal, 4)
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
            Text("Lucid Ride is a bike telemetry + biometric pipeline. Phase A: live HR / HRV / body state via the linked health backend, plus phone-side GPS, IMU, distance, and zone-time on every ride. Phase B: RaceBox GPS/IMU, GoPro GPMF, OBD adapter — wires up as hardware lands.")
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
    private var creditsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("CREDITS", icon: "scribble.variable")
            VStack(alignment: .leading, spacing: 8) {
                Text("3D bike model")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(DS.Colors.textMuted)
                Text("\"Motorcycle [Ducati Super Sports]\" by Noah (@Noaah on Sketchfab) — CC BY 4.0")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(DS.Colors.textSecondary)
                Text("HDR studio lighting")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(DS.Colors.textMuted)
                    .padding(.top, 4)
                Text("\"Studio Small 04\" HDRI by Sergej Majboroda — Polyhaven CC0")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(DS.Colors.textSecondary)
            }
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
