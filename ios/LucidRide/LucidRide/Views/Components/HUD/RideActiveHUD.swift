import SwiftUI

/// Full-screen glanceable HUD shown while a ride is active.
///
/// Replaces the 3D bike home screen the moment `activeRide != nil`. Built for
/// a 1-second glance in a phone mount: SPEED is the hero, a live lean gauge
/// sits center as the signature visual, HR + zone on the right. A bottom strip
/// carries the secondary stats (distance, elapsed, peak lean, peak G, elev).
///
/// All values are read live from `HUDState`, which the `RideTelemetryRecorder`
/// updates every second (speed / lean / distance / peak G / elev gain) plus the
/// 3 s HR poll. Tearing the SceneKit bike down during a ride also saves a
/// meaningful chunk of battery on a long ride.
///
/// Adapts to the dashboard orientation chosen in Settings
/// (`lucidride.portraitMode`): landscape = wide glance layout; portrait = tall
/// layout with big, reachable music controls for gloved hands.
struct RideActiveHUD: View {
    @ObservedObject var state: HUDState
    @ObservedObject private var spotify = SpotifyController.shared
    @AppStorage("lucidride.portraitMode") private var portraitMode = false
    /// Phone-IMU lean. Default OFF (useless on a free-rotating mount → RaceBox
    /// owns lean). Hides the lean gauge + MAX LEAN stat when off.
    @AppStorage("lucidride.leanEnabled") private var leanEnabled = false
    let ending: Bool
    var onEnd: () -> Void
    var onSettings: () -> Void

    private var zoneColor: Color { HUDState.zoneColor(for: state.liveHR) }
    private var leanColor: Color { DS.Colors.leanColor(state.liveLeanDeg) }

    var body: some View {
        Group {
            if portraitMode { portraitBody } else { landscapeBody }
        }
    }

    // MARK: - Landscape layout (wide glance)

    private var landscapeBody: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            heroRow
            Spacer(minLength: 0)
            statStrip
            musicStrip
            debugLine
        }
        .padding(.horizontal, 26)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    // MARK: - Portrait layout (tall, glove-friendly)

    private var portraitBody: some View {
        VStack(spacing: 0) {
            portraitTopBar
            Spacer(minLength: 6)
            speedCluster
            Spacer(minLength: 12)
            if leanEnabled {
                HStack(alignment: .center, spacing: 18) {
                    leanGauge
                    hrCluster
                }
            } else {
                hrCluster
            }
            Spacer(minLength: 12)
            portraitStatGrid
            Spacer(minLength: 14)
            musicStrip
            debugLine
            Spacer(minLength: 14)
            endButtonWide
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 22)
    }

    @ViewBuilder
    private var debugLine: some View {
        if !state.liveDebug.isEmpty {
            Text(state.liveDebug)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(DS.Colors.textFaint)
                .padding(.top, 4)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            statusLeading
            Spacer()
            settingsButton
            endButton
        }
    }

    /// Portrait keeps the status chips + gear up top, but moves END to a big
    /// full-width button at the very bottom (out of the way of music taps).
    private var portraitTopBar: some View {
        HStack(spacing: 10) {
            statusLeading
            Spacer()
            settingsButton
        }
    }

    @ViewBuilder
    private var statusLeading: some View {
        Circle()
            .fill(state.liveHR == nil ? DS.Colors.textFaint : DS.Colors.success)
            .frame(width: 7, height: 7)
            .opacity(state.liveHR == nil ? 0.4 : 1)
            .animation(DS.Anim.breath, value: state.liveHR != nil)

        Text("LUCID RIDE")
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .tracking(1.2)
            .foregroundStyle(DS.Colors.textMuted)

        if state.liveIsPaused {
            pausedBadge
        } else {
            Text("·").foregroundStyle(DS.Colors.textFaint)
            Text(HUDState.zoneLabel(for: state.liveHR).uppercased())
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(zoneColor)
        }
    }

    private var settingsButton: some View {
        Button(action: onSettings) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DS.Colors.textFaint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.04)))
        }
        .buttonStyle(.plain)
    }

    private var pausedBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "pause.fill")
                .font(.system(size: 8, weight: .black))
            Text("AUTO-PAUSED")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1.0)
        }
        .foregroundStyle(DS.Colors.amber)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(DS.Colors.amber.opacity(0.12)))
        .overlay(Capsule().stroke(DS.Colors.amber.opacity(0.30), lineWidth: 0.5))
    }

    private var endButton: some View {
        Button(action: onEnd) {
            HStack(spacing: 8) {
                Image(systemName: ending ? "hourglass" : "stop.fill")
                    .font(.system(size: 11, weight: .black))
                Text(ending ? "ENDING…" : "END · \(state.elapsedLabel)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Capsule().fill(DS.Colors.danger.opacity(ending ? 0.45 : 0.85)))
        }
        .buttonStyle(.plain)
        .disabled(ending)
    }

    /// Portrait END — full-width, anchored at the bottom of the tall layout.
    private var endButtonWide: some View {
        Button(action: onEnd) {
            HStack(spacing: 8) {
                Image(systemName: ending ? "hourglass" : "stop.fill")
                    .font(.system(size: 14, weight: .black))
                Text(ending ? "ENDING…" : "END · \(state.elapsedLabel)")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Capsule().fill(DS.Colors.danger.opacity(ending ? 0.45 : 0.85)))
        }
        .buttonStyle(.plain)
        .disabled(ending)
    }

    // MARK: - Hero row (speed · lean · HR)

    private var heroRow: some View {
        HStack(alignment: .center, spacing: 0) {
            speedCluster
                .frame(maxWidth: .infinity)
            if leanEnabled {
                leanGauge
                    .frame(width: 150)
            }
            hrCluster
                .frame(maxWidth: .infinity)
        }
    }

    private var speedCluster: some View {
        VStack(spacing: 0) {
            Text("\(Int(state.liveSpeedKmh.rounded()))")
                .font(.system(size: 112, weight: .heavy, design: .rounded))
                .foregroundStyle(state.liveIsPaused ? DS.Colors.textMuted : DS.Colors.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: state.liveSpeedKmh)
            Text("KM/H")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .tracking(3.0)
                .foregroundStyle(DS.Colors.textMuted)
                .offset(y: -8)
        }
    }

    private var hrCluster: some View {
        VStack(spacing: 2) {
            Text(state.liveHR.map { "\(Int($0))" } ?? "—")
                .font(.system(size: 68, weight: .heavy, design: .rounded))
                .foregroundStyle(zoneColor)
                .monospacedDigit()
                .contentTransition(.numericText())
                .shadow(color: zoneColor.opacity(state.liveHR == nil ? 0 : 0.35), radius: 18)
            Text("BPM")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(2.4)
                .foregroundStyle(DS.Colors.textMuted)
            zonePips
                .padding(.top, 6)
        }
    }

    /// Four-segment zone indicator — fills up to the current HR zone.
    private var zonePips: some View {
        let current = state.liveHR.map { HUDState.zoneIndex(for: $0) } ?? -1
        return HStack(spacing: 4) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(i <= current ? HUDState.zoneColor(for: zoneThreshold(i)) : DS.Colors.textFaint.opacity(0.25))
                    .frame(width: 18, height: 4)
            }
        }
    }

    /// Representative HR for each zone bucket so the pip lights its own color.
    private func zoneThreshold(_ zone: Int) -> Double {
        switch zone {
        case 0: return 100
        case 1: return 125
        case 2: return 150
        default: return 175
        }
    }

    // MARK: - Lean gauge (artificial-horizon style)

    private var leanGauge: some View {
        let deg = state.liveLeanDeg
        let visualDeg = max(-55, min(55, deg))
        return VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(DS.Colors.border, lineWidth: 1)
                    .frame(width: 116, height: 116)

                // Fixed top reference notch
                Capsule()
                    .fill(DS.Colors.textFaint)
                    .frame(width: 2, height: 9)
                    .offset(y: -58)

                // Tilting horizon bar — banks with your lean.
                Capsule()
                    .fill(leanColor)
                    .frame(width: 92, height: 5)
                    .shadow(color: leanColor.opacity(0.5), radius: 6)
                    .rotationEffect(.degrees(visualDeg))
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: visualDeg)

                // Center hub
                Circle()
                    .fill(DS.Colors.textPrimary)
                    .frame(width: 7, height: 7)
            }

            HStack(spacing: 4) {
                Text("\(Int(abs(deg).rounded()))°")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(leanColor)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(leanDirection(deg))
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(DS.Colors.textMuted)
            }
            VStack(spacing: 2) {
                Text("LEAN")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(2.0)
                    .foregroundStyle(DS.Colors.textFaint)
                Text("TAP TO ZERO")
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(DS.Colors.violet.opacity(0.75))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            state.leanZeroRequested = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    private func leanDirection(_ deg: Double) -> String {
        if abs(deg) < 3 { return "LEVEL" }
        return deg > 0 ? "RIGHT" : "LEFT"
    }

    // MARK: - Bottom stat strip

    private var statStrip: some View {
        HStack(spacing: 0) {
            hudStat(icon: "point.topleft.down.curvedto.point.bottomright.up",
                    value: String(format: "%.1f", state.liveDistanceM / 1000),
                    unit: "KM", color: DS.Colors.categoryRoute)
            stripDivider
            hudStat(icon: "timer",
                    value: state.elapsedLabel,
                    unit: "TIME", color: DS.Colors.violet, mono: true)
            if leanEnabled {
                stripDivider
                hudStat(icon: "arrow.left.and.right",
                        value: "\(Int(state.liveMaxLeanDeg.rounded()))°",
                        unit: "MAX LEAN", color: DS.Colors.teal)
            }
            stripDivider
            hudStat(icon: "bolt.fill",
                    value: String(format: "%.1fg", state.livePeakG),
                    unit: "PEAK G", color: DS.Colors.amber)
            stripDivider
            hudStat(icon: "mountain.2.fill",
                    value: "+\(Int(state.liveElevGainM.rounded()))",
                    unit: "ELEV M", color: DS.Colors.categoryRoute)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(DS.Colors.border, lineWidth: 0.5)
        )
    }

    /// Portrait is narrow, so the 5 stats reflow into a 3-column grid instead of
    /// one cramped row.
    private var portraitStatGrid: some View {
        let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: cols, spacing: 14) {
            hudStat(icon: "point.topleft.down.curvedto.point.bottomright.up",
                    value: String(format: "%.1f", state.liveDistanceM / 1000),
                    unit: "KM", color: DS.Colors.categoryRoute)
            hudStat(icon: "timer",
                    value: state.elapsedLabel,
                    unit: "TIME", color: DS.Colors.violet, mono: true)
            if leanEnabled {
                hudStat(icon: "arrow.left.and.right",
                        value: "\(Int(state.liveMaxLeanDeg.rounded()))°",
                        unit: "MAX LEAN", color: DS.Colors.teal)
            }
            hudStat(icon: "bolt.fill",
                    value: String(format: "%.1fg", state.livePeakG),
                    unit: "PEAK G", color: DS.Colors.amber)
            hudStat(icon: "mountain.2.fill",
                    value: "+\(Int(state.liveElevGainM.rounded()))",
                    unit: "ELEV M", color: DS.Colors.categoryRoute)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(DS.Colors.border, lineWidth: 0.5)
        )
    }

    private var stripDivider: some View {
        Rectangle()
            .fill(DS.Colors.border)
            .frame(width: 0.5, height: 30)
    }

    private func hudStat(icon: String, value: String, unit: String, color: Color, mono: Bool = false) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(color.opacity(0.85))
                Text(value)
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .foregroundStyle(DS.Colors.textPrimary)
                    .modifier(MaybeMono(on: mono))
                    .contentTransition(.numericText())
            }
            Text(unit)
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(DS.Colors.textFaint)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Spotify music strip (glove-friendly controls)

    @ViewBuilder
    private var musicStrip: some View {
        if spotify.isConnected {
            connectedMusic
                .task {
                    while !Task.isCancelled {
                        await spotify.refreshNowPlaying()
                        try? await Task.sleep(nanoseconds: 8_000_000_000)
                    }
                }
        } else {
            Button(action: onSettings) {
                HStack(spacing: 6) {
                    Image(systemName: "music.note").font(.system(size: 10, weight: .bold))
                    Text("CONNECT SPOTIFY")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(1.2)
                }
                .foregroundStyle(DS.Colors.textFaint)
                .padding(.top, 8)
            }
            .buttonStyle(.plain)
        }
    }

    /// Portrait stacks the track label over three full-width buttons (huge glove
    /// targets); landscape keeps the compact label-left / buttons-right row.
    @ViewBuilder
    private var connectedMusic: some View {
        if portraitMode {
            VStack(spacing: 12) {
                trackLabel(centered: true)
                HStack(spacing: 12) {
                    musicButtonWide("backward.fill", size: 22) { spotify.previous() }
                    musicButtonWide(spotify.isPlaying ? "pause.fill" : "play.fill", size: 28, prominent: true) { spotify.togglePlayPause() }
                    musicButtonWide("forward.fill", size: 22) { spotify.next() }
                }
            }
            .padding(.top, 4)
        } else {
            HStack(spacing: 14) {
                trackLabel(centered: false)
                HStack(spacing: 10) {
                    musicButton("backward.fill", size: 17) { spotify.previous() }
                    musicButton(spotify.isPlaying ? "pause.fill" : "play.fill", size: 20, prominent: true) { spotify.togglePlayPause() }
                    musicButton("forward.fill", size: 17) { spotify.next() }
                }
            }
            .padding(.top, 10)
        }
    }

    private func trackLabel(centered: Bool) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: 1) {
            Text(spotify.trackTitle ?? "—")
                .font(.system(size: centered ? 13 : 12, weight: .heavy, design: .rounded))
                .foregroundStyle(DS.Colors.textPrimary)
                .lineLimit(1)
            Text(spotify.statusNote.isEmpty ? (spotify.artistName ?? "Spotify") : spotify.statusNote)
                .font(.system(size: centered ? 10 : 9, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.textFaint)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
    }

    private func musicButton(_ icon: String, size: CGFloat, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: size, weight: .black))
                .foregroundStyle(prominent ? .black : DS.Colors.textPrimary)
                .frame(width: prominent ? 60 : 52, height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(prominent ? Color(red: 0.114, green: 0.725, blue: 0.329) : Color.white.opacity(0.07))
                )
                .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Portrait music button — fills its third of the row and stands 64pt tall
    /// for a confident gloved tap.
    private func musicButtonWide(_ icon: String, size: CGFloat, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: size, weight: .black))
                .foregroundStyle(prominent ? .black : DS.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(prominent ? Color(red: 0.114, green: 0.725, blue: 0.329) : Color.white.opacity(0.07))
                )
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Applies `.monospacedDigit()` conditionally (so timer columns don't jitter
/// while count-up stats still animate via numericText).
private struct MaybeMono: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.monospacedDigit() } else { content }
    }
}
