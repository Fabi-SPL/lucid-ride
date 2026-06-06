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
/// Landscape only (the app is orientation-locked to landscape).
struct RideActiveHUD: View {
    @ObservedObject var state: HUDState
    let ending: Bool
    var onEnd: () -> Void
    var onSettings: () -> Void

    private var zoneColor: Color { HUDState.zoneColor(for: state.liveHR) }
    private var leanColor: Color { DS.Colors.leanColor(state.liveLeanDeg) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            heroRow
            Spacer(minLength: 0)
            statStrip
            if !state.liveDebug.isEmpty {
                Text(state.liveDebug)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(DS.Colors.textFaint)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
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

            Spacer()

            Button(action: onSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DS.Colors.textFaint)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.04)))
            }
            .buttonStyle(.plain)

            endButton
        }
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

    // MARK: - Hero row (speed · lean · HR)

    private var heroRow: some View {
        HStack(alignment: .center, spacing: 0) {
            speedCluster
                .frame(maxWidth: .infinity)
            leanGauge
                .frame(width: 150)
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
            stripDivider
            hudStat(icon: "arrow.left.and.right",
                    value: "\(Int(state.liveMaxLeanDeg.rounded()))°",
                    unit: "MAX LEAN", color: DS.Colors.teal)
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
}

/// Applies `.monospacedDigit()` conditionally (so timer columns don't jitter
/// while count-up stats still animate via numericText).
private struct MaybeMono: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.monospacedDigit() } else { content }
    }
}
