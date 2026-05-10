import SwiftUI

/// Big morphing pill button. Idle = "Start Ride" (violet fill), Active = "End Ride" (danger fill).
/// Tap fires haptic + the provided action. Disables itself for 600ms post-tap to prevent double-fires.
struct StartRideButton: View {
    enum Mode { case idle, active }

    let mode: Mode
    let action: () async -> Void
    @State private var isWorking = false

    private var label: String {
        switch mode {
        case .idle:   return "Start Ride"
        case .active: return "End Ride"
        }
    }

    private var symbol: String {
        switch mode {
        case .idle:   return "play.circle.fill"
        case .active: return "stop.circle.fill"
        }
    }

    private var tint: Color {
        switch mode {
        case .idle:   return DS.Colors.violet
        case .active: return DS.Colors.danger
        }
    }

    var body: some View {
        Button {
            guard !isWorking else { return }
            isWorking = true
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            Task {
                await action()
                try? await Task.sleep(nanoseconds: 600_000_000)
                isWorking = false
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                Text(label)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .kerning(-0.2)
                if isWorking {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.pill, style: .continuous)
                    .fill(tint.opacity(isWorking ? 0.55 : 0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.pill, style: .continuous)
                    .stroke(tint.opacity(0.35), lineWidth: 0.5)
            )
            .shadow(color: tint.opacity(0.30), radius: 18, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .animation(DS.Anim.standard, value: mode)
        .animation(DS.Anim.standard, value: isWorking)
    }
}

#Preview {
    ZStack {
        MeshGradientBackground()
        VStack(spacing: 24) {
            StartRideButton(mode: .idle) {}
            StartRideButton(mode: .active) {}
        }
        .padding()
    }
}
