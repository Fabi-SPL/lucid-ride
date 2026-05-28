import ActivityKit
import WidgetKit
import SwiftUI

/// Live Activity for the active ride — shows on the Lock Screen and in the
/// Dynamic Island while a ride is in progress. Updates pushed from the main
/// app via `activity.update(using:)` at ~1 Hz.
///
/// Glanceable values: speed (km/h), HR, lean angle, elapsed time. No taps
/// required, no app open. Designed for phone-on-RAM-mount usage.
struct RideLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { context in
            LockScreenView(state: context.state, startedAt: context.attributes.startedAt)
                .activityBackgroundTint(Color.black.opacity(0.6))
                .activitySystemActionForegroundColor(Color.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded — shown when user long-presses or taps the island.
                DynamicIslandExpandedRegion(.leading) {
                    expandedLeading(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    expandedTrailing(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    expandedBottom(state: context.state, startedAt: context.attributes.startedAt)
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.circle.fill" : "figure.outdoor.cycle")
                    .foregroundStyle(zoneColor(context.state.zoneIndex))
            } compactTrailing: {
                Text("\(context.state.speedKmh)")
                    .monospacedDigit()
                    .foregroundStyle(.white)
            } minimal: {
                Image(systemName: "figure.outdoor.cycle")
                    .foregroundStyle(zoneColor(context.state.zoneIndex))
            }
        }
    }

    // MARK: - Dynamic Island expanded

    @ViewBuilder
    private func expandedLeading(state: RideActivityAttributes.ContentState) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(state.speedKmh)")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text("KM/H")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    @ViewBuilder
    private func expandedTrailing(state: RideActivityAttributes.ContentState) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(zoneColor(state.zoneIndex))
                Text(state.heartRate > 0 ? "\(state.heartRate)" : "—")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            Text("BPM · Z\(state.zoneIndex >= 0 ? state.zoneIndex + 1 : 0)")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    @ViewBuilder
    private func expandedBottom(state: RideActivityAttributes.ContentState, startedAt: Date) -> some View {
        HStack(spacing: 14) {
            Label {
                Text(elapsedLabel(state.elapsedSeconds))
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .monospacedDigit()
            } icon: {
                Image(systemName: "clock.fill")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(.white.opacity(0.85))

            Label {
                Text(distanceLabel(state.distanceMeters))
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .monospacedDigit()
            } icon: {
                Image(systemName: "ruler")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(.white.opacity(0.85))

            Label {
                Text("\(abs(state.leanDeg))°")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .monospacedDigit()
            } icon: {
                Image(systemName: state.leanDeg < 0 ? "arrow.left" : "arrow.right")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(.white.opacity(0.85))

            Spacer()
            if state.isPaused {
                Text("⏸ AUTO-PAUSED")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    // MARK: - Lock Screen

    private struct LockScreenView: View {
        let state: RideActivityAttributes.ContentState
        let startedAt: Date

        var body: some View {
            HStack(alignment: .center, spacing: 16) {
                // Left — speed hero
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(state.speedKmh)")
                            .font(.system(size: 42, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text("km/h")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .tracking(1.0)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    HStack(spacing: 10) {
                        Label(elapsedLabel(state.elapsedSeconds), systemImage: "clock.fill")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(0.80))
                            .monospacedDigit()
                        Label(distanceLabel(state.distanceMeters), systemImage: "ruler")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(0.80))
                            .monospacedDigit()
                    }
                }

                Spacer()

                // Right — HR + lean
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(RideLiveActivity.zoneColor(state.zoneIndex))
                        Text(state.heartRate > 0 ? "\(state.heartRate)" : "—")
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                    if state.leanDeg != 0 {
                        HStack(spacing: 4) {
                            Image(systemName: state.leanDeg < 0 ? "arrow.left" : "arrow.right")
                                .font(.system(size: 9, weight: .bold))
                            Text("\(abs(state.leanDeg))° lean")
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                        }
                        .foregroundStyle(.white.opacity(0.80))
                    } else if state.isPaused {
                        Text("⏸ paused")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .tracking(0.6)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Helpers

    static func zoneColor(_ idx: Int) -> Color {
        switch idx {
        case 0: return Color(red: 79/255, green: 209/255, blue: 197/255)   // teal
        case 1: return Color(red: 16/255, green: 185/255, blue: 129/255)   // success
        case 2: return Color(red: 245/255, green: 158/255, blue: 11/255)   // warning
        case 3: return Color(red: 239/255, green: 68/255, blue: 68/255)    // danger
        default: return .white.opacity(0.45)
        }
    }

    private func zoneColor(_ idx: Int) -> Color { Self.zoneColor(idx) }
}

private func elapsedLabel(_ total: Int) -> String {
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
    return String(format: "%d:%02d", m, s)
}

private func distanceLabel(_ meters: Int) -> String {
    if meters < 1000 { return "\(meters) m" }
    return String(format: "%.1f km", Double(meters) / 1000.0)
}
