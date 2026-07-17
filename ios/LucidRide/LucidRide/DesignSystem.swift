import SwiftUI

// ════════════════════════════════════════════════════════════
// LucidRide Design System — Single source of truth for all UI
// Cloned verbatim from LucidHealth, health-engine refs stripped.
// Based on: Lucid brand system + research spec (02-design-system-spec.html)
//
// Rules:
//   - Never use raw Color literals (.gray, .red) — always DS.Colors.*
//   - Never use raw font sizes — always DS.Font.*
//   - Never use raw padding values — always DS.Spacing.*
//   - Every card uses GlassCard or HeroCard modifier
//   - Background is always MeshGradientBackground, never Color.black
// ════════════════════════════════════════════════════════════

enum DS {
    // MARK: - Spacing (8-point grid)
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: - Corner Radius
    enum Radius {
        static let sm: CGFloat = 10
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let pill: CGFloat = 100
    }

    // MARK: - Colors (Forged Metal — LucidRide's own identity, no Lucid violet/teal)
    // Concept: metal heating up. Cold steel at cruise, amber under load,
    // ember at redline. Chrome = the headlight white from the app icon.
    enum Colors {
        // Backgrounds — near-black ink with a faint cool graphite bias
        static let bg = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.039, green: 0.043, blue: 0.051, alpha: 1)    // #0A0B0D ink
                : UIColor(red: 0.949, green: 0.953, blue: 0.961, alpha: 1)    // #F2F3F5 cool paper
        })
        static let surface = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.04)
                : UIColor(white: 1.0, alpha: 0.65)
        })
        static let surfaceElevated = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.07)
                : UIColor(white: 1.0, alpha: 0.80)
        })
        static let surfaceStrong = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.10)
                : UIColor(white: 1.0, alpha: 0.90)
        })

        // Text — chrome/steel neutrals, zero color bias
        static let textPrimary = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.933, green: 0.949, blue: 0.965, alpha: 1)    // #EEF2F6 chrome
                : UIColor(red: 0.086, green: 0.094, blue: 0.110, alpha: 1)    // #16181C
        })
        static let textSecondary = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.545, green: 0.576, blue: 0.612, alpha: 1)    // #8B939C steel
                : UIColor(red: 0.290, green: 0.314, blue: 0.345, alpha: 1)    // #4A5058
        })
        static let textMuted = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.353, green: 0.380, blue: 0.416, alpha: 1)    // #5A616A
                : UIColor(red: 0.431, green: 0.463, blue: 0.498, alpha: 1)    // #6E767F
        })
        static let textFaint = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.227, green: 0.251, blue: 0.282, alpha: 1)    // #3A4048
                : UIColor(red: 0.604, green: 0.631, blue: 0.663, alpha: 1)    // #9AA1A9
        })

        // ── Forged-metal accents ─────────────────────────────
        /// Signature accent — amber, metal under load
        static let amberAccent = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.910, green: 0.541, blue: 0.220, alpha: 1)    // #E88A38
                : UIColor(red: 0.788, green: 0.435, blue: 0.118, alpha: 1)    // #C96F1E
        })
        /// Redline — ember, metal at its limit
        static let ember = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 1.0, green: 0.353, blue: 0.220, alpha: 1)      // #FF5A38
                : UIColor(red: 0.878, green: 0.243, blue: 0.125, alpha: 1)    // #E03E20
        })
        /// Cold steel — cruising, no load
        static let cold = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.718, green: 0.753, blue: 0.788, alpha: 1)    // #B7C0C9
                : UIColor(red: 0.373, green: 0.420, blue: 0.463, alpha: 1)    // #5F6B76
        })
        /// Chrome — the headlight white, primary emphasis
        static let chrome = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.933, green: 0.949, blue: 0.965, alpha: 1)    // #EEF2F6
                : UIColor(red: 0.086, green: 0.094, blue: 0.110, alpha: 1)    // #16181C
        })

        // Legacy names — kept so every old call site lands on the new palette.
        // `violet` renders amber, `teal` renders cold steel. New code uses the
        // forged-metal names above.
        static let violet = amberAccent
        static let teal = cold

        // Semantic (adaptive)
        static let success = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.063, green: 0.725, blue: 0.506, alpha: 1)    // #10b981
                : UIColor(red: 0.020, green: 0.588, blue: 0.412, alpha: 1)    // #059669
        })
        // danger/warning fold into the heat ramp — ember is the danger color
        static let danger = ember
        static let warning = amberAccent

        static let pink = ember
        static let amber = amberAccent

        // Borders (adaptive)
        static let border = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.08)
                : UIColor(white: 0.0, alpha: 0.06)
        })
        static let borderStrong = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.910, green: 0.541, blue: 0.220, alpha: 0.15)
                : UIColor(red: 0.788, green: 0.435, blue: 0.118, alpha: 0.15)
        })
        static let borderViolet = Color(hex: 0xE88A38).opacity(0.18)
        static let borderTeal = Color(hex: 0xB7C0C9).opacity(0.15)

        // Recovery zones
        static func recoveryColor(_ score: Double) -> Color {
            if score >= 67 { return success }
            if score >= 34 { return warning }
            return danger
        }

        static func sleepColor(_ score: Double) -> Color {
            if score >= 70 { return success }
            if score >= 40 { return warning }
            return danger
        }

        static func strainColor(_ score: Double) -> Color {
            if score < 8 { return cold }
            if score < 14 { return amberAccent }
            return ember
        }

        static func bodyStateColor(_ hrv: Double) -> Color {
            // LucidRide: HRV-based body state band on TodayView.
            // Thresholds tuned to motor_racing risk envelope — green = pushing OK,
            // yellow = ride conservatively, red = consider not riding.
            if hrv >= 70 { return success }
            if hrv >= 45 { return warning }
            return danger
        }

        static func zoneColor(_ zone: Int) -> Color {
            // Heat ramp — cold steel → warming → amber → ember. No green:
            // effort reads as temperature, matching the forged-metal identity.
            switch zone {
            case 0: return textMuted
            case 1: return cold
            case 2: return Color(hex: 0xD2A26B)   // warming steel, cold→amber midpoint
            case 3: return amberAccent
            case 4: return ember
            default: return textMuted
            }
        }

        static func leanColor(_ degrees: Double) -> Color {
            // Lean angle thresholds for sport bike on public roads.
            // Below 25° = casual, 25-40° = sporty, 40-50° = aggressive,
            // >50° = race-track territory (or you're crashing).
            let abs = Swift.abs(degrees)
            if abs < 25 { return cold }
            if abs < 40 { return Color(hex: 0xD2A26B) }
            if abs < 50 { return amberAccent }
            return ember
        }

        // Gradient — the heat ramp, amber into ember
        static let brandGradient = LinearGradient(
            colors: [amberAccent, ember],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static let heroGradient = LinearGradient(
            colors: [amberAccent.opacity(0.10), Color.clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        // Status glow halos (used by StatusGlow modifier)
        static let glowViolet  = amberAccent.opacity(0.35)
        static let glowSuccess = success.opacity(0.30)
        static let glowAmber   = amberAccent.opacity(0.30)
        static let glowDanger  = ember.opacity(0.30)

        // Category dots (principle #5) — LucidRide tunes these to ride domains
        static let categoryBody    = chrome      // body state / HRV / strain
        static let categoryRide    = amberAccent // ride telemetry (lean / GPS / IMU)
        static let categoryBike    = cold        // bike / mechanical (fuel, tire, service)
        static let categoryRoute   = Color(hex: 0xD2A26B)  // route / location
        static let categorySession = success     // active session / streaks
    }

    // MARK: - Typography
    // Sized for iPhone 15 Pro (393pt wide). Uses .rounded design.
    // Switch to Font.custom("Outfit", ...) when font is bundled.
    enum Font {
        static let display = SwiftUI.Font.system(size: 28, weight: .heavy, design: .rounded)
        static let title1 = SwiftUI.Font.system(size: 22, weight: .heavy, design: .rounded)
        static let title2 = SwiftUI.Font.system(size: 18, weight: .bold, design: .rounded)
        static let title3 = SwiftUI.Font.system(size: 15, weight: .semibold, design: .rounded)
        static let body = SwiftUI.Font.system(size: 14, weight: .regular)
        static let bodyMed = SwiftUI.Font.system(size: 14, weight: .medium)
        static let caption = SwiftUI.Font.system(size: 12, weight: .regular)
        static let label = SwiftUI.Font.system(size: 10, weight: .bold)
        static let micro = SwiftUI.Font.system(size: 8, weight: .bold)

        // Numeric — sized for 393pt width
        static let heroNumber = SwiftUI.Font.system(size: 44, weight: .heavy, design: .rounded)
        static let bigNumber = SwiftUI.Font.system(size: 24, weight: .bold, design: .rounded)
        static let scoreNumber = SwiftUI.Font.system(size: 20, weight: .heavy, design: .rounded)
        static let statNumber = SwiftUI.Font.system(size: 16, weight: .bold, design: .rounded)
    }

    // MARK: - Animations
    enum Anim {
        static let standard = Animation.spring(duration: 0.3)
        static let bouncy = Animation.bouncy
        static let quick = Animation.easeOut(duration: 0.2)
        static let ringFill = Animation.spring(response: 0.8, dampingFraction: 0.75)
        static let countUp = Animation.spring(response: 0.9, dampingFraction: 0.8)
        static let cardAppear = Animation.spring(response: 0.5, dampingFraction: 0.75)
        /// Gentle 4s breathing loop for live-data anchors (recovery ring steady-state)
        static let breath = Animation.easeInOut(duration: 4.0).repeatForever(autoreverses: true)
        /// Hero ring fill entrance — slower spring, more drama
        static let ringEntrance = Animation.spring(response: 1.2, dampingFraction: 0.75)

        /// Staggered delay for list items
        static func stagger(index: Int) -> Animation {
            cardAppear.delay(Double(index) * 0.08)
        }
    }

    // MARK: - Glow Colors (status halos)
    enum Glow {
        static let violet = DS.Colors.amberAccent.opacity(0.35)
        static let success = DS.Colors.success.opacity(0.30)
        static let amber = DS.Colors.amber.opacity(0.30)
        static let danger = DS.Colors.danger.opacity(0.30)
    }

    // MARK: - Category dot colors (principle #5) — LucidRide
    enum Category {
        case body, ride, bike, route, session

        var color: Color {
            switch self {
            case .body:    return DS.Colors.chrome
            case .ride:    return DS.Colors.amberAccent
            case .bike:    return DS.Colors.cold
            case .route:   return Color(hex: 0xD2A26B)
            case .session: return DS.Colors.success
            }
        }

        var label: String {
            switch self {
            case .body:    return "BODY"
            case .ride:    return "RIDE"
            case .bike:    return "BIKE"
            case .route:   return "ROUTE"
            case .session: return "SESSION"
            }
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}

// MARK: - Background (forged metal — solid ink, one headlight bloom)
//
// The old animated purple mesh is retired. An instrument cluster sits on
// solid near-black; the only light is a faint amber bloom at the top edge
// (the headlight) and a whisper of ember at the bottom. Static — zero
// TimelineView cost, nothing fighting the telemetry for attention.
// Struct keeps its old name so every view's background call still works.

struct MeshGradientBackground: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            DS.Colors.bg.ignoresSafeArea()

            if colorScheme == .dark {
                RadialGradient(
                    colors: [DS.Colors.amberAccent.opacity(0.09), .clear],
                    center: .init(x: 0.5, y: -0.15),
                    startRadius: 0, endRadius: 480
                )
                .ignoresSafeArea()
                RadialGradient(
                    colors: [DS.Colors.ember.opacity(0.04), .clear],
                    center: .init(x: 0.5, y: 1.15),
                    startRadius: 0, endRadius: 420
                )
                .ignoresSafeArea()
                // Brushed-metal hairline along the very top edge
                VStack {
                    LinearGradient(
                        colors: [.clear, DS.Colors.chrome.opacity(0.18), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(height: 1)
                    Spacer()
                }
                .ignoresSafeArea()
            } else {
                RadialGradient(
                    colors: [DS.Colors.amberAccent.opacity(0.07), .clear],
                    center: .init(x: 0.5, y: -0.15),
                    startRadius: 0, endRadius: 480
                )
                .ignoresSafeArea()
            }

            // Dot grid overlay — gives glass cards something to refract.
            DotGridOverlay()
        }
    }
}

// MARK: - Dot Grid Overlay

/// Static dot grid used by MeshGradientBackground. The whole point: glass
/// surfaces need high-frequency content underneath to refract visibly,
/// otherwise they look like flat gray boxes.
struct DotGridOverlay: View {
    @Environment(\.colorScheme) var colorScheme
    var spacing: CGFloat = 24
    var dotSize: CGFloat = 1.5

    var body: some View {
        Canvas { context, size in
            // Neutral steel tint — reads as machined texture, not decoration.
            let color: Color = colorScheme == .dark
                ? Color(hex: 0x8B939C).opacity(0.08)
                : Color(hex: 0x4A5058).opacity(0.10)
            let cols = Int(size.width / spacing) + 2
            let rows = Int(size.height / spacing) + 2
            for row in 0..<rows {
                for col in 0..<cols {
                    let x = CGFloat(col) * spacing
                    let y = CGFloat(row) * spacing
                    let rect = CGRect(
                        x: x - dotSize / 2,
                        y: y - dotSize / 2,
                        width: dotSize,
                        height: dotSize
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(color))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Liquid Glass — 4 Tier System (iOS 26 .glassEffect API)

/// Tier 1 — Subtle: list rows, nested cells (16px radius)
struct GlassSubtle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .glassEffect(.regular, in: .rect(cornerRadius: DS.Radius.md))
    }
}

/// Tier 2 — Default: standard cards (20px radius) with inner shimmer top edge
struct GlassDefault: ViewModifier {
    func body(content: Content) -> some View {
        content
            .glassEffect(
                .regular.tint(DS.Colors.chrome.opacity(0.03)).interactive(),
                in: .rect(cornerRadius: DS.Radius.lg)
            )
            .overlay(alignment: .top) {
                // inner shimmer top edge
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.08), .clear],
                            startPoint: .top, endPoint: .init(x: 0.5, y: 0.15)
                        )
                    )
                    .frame(height: 32)
                    .allowsHitTesting(false)
            }
    }
}

/// Tier 3 — Hero: ONE per page, gradient tint + specular shimmer + halo glow (24px radius)
struct GlassHero: ViewModifier {
    func body(content: Content) -> some View {
        content
            .glassEffect(
                .regular.tint(DS.Colors.amberAccent.opacity(0.05)),
                in: .rect(cornerRadius: DS.Radius.xl)
            )
            .overlay(
                LinearGradient(
                    colors: [DS.Colors.amberAccent.opacity(0.05), Color.clear],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
                .allowsHitTesting(false)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 24, x: 0, y: 8)
    }
}

/// Tier 4 — Pill: chips, tabs, FABs (100px / capsule)
struct GlassPill: ViewModifier {
    func body(content: Content) -> some View {
        content
            .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - Convenience extension for 4 glass tiers
extension View {
    func glassSubtle()  -> some View { modifier(GlassSubtle()) }
    func glassDefault() -> some View { modifier(GlassDefault()) }
    func glassHero()    -> some View { modifier(GlassHero()) }
    func glassPill()    -> some View { modifier(GlassPill()) }

    /// Subtle scale + opacity falloff as a section leaves the viewport.
    /// Keeps cards feeling alive without the "obvious AI animation" tell.
    /// Use only on top-level scroll sections, not on every nested element.
    func scrollSectionTransition() -> some View {
        scrollTransition { content, phase in
            content
                .scaleEffect(phase.isIdentity ? 1.0 : 0.96)
                .opacity(phase.isIdentity ? 1.0 : 0.65)
        }
    }
}

// MARK: - Status Glow Modifier

struct StatusGlowModifier: ViewModifier {
    let color: Color
    var intensity: Double

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.35 * intensity), radius: 20, x: 0, y: 0)
            .shadow(color: color.opacity(0.20 * intensity), radius: 40, x: 0, y: 0)
    }
}

extension View {
    func statusGlow(_ color: Color, intensity: Double = 1.0) -> some View {
        modifier(StatusGlowModifier(color: color, intensity: intensity))
    }
}

// MARK: - Glass Card (Liquid Glass on iOS 26, material fallback on 17-18)

struct GlassCard: ViewModifier {
    var padding: CGFloat = DS.Spacing.md
    var radius: CGFloat = DS.Radius.lg
    var tint: Color = DS.Colors.amberAccent
    var tintOpacity: Double = 0.08

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(tint.opacity(tintOpacity))
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(DS.Colors.border, lineWidth: 0.5)
            )
    }
}

struct HeroCard: ViewModifier {
    var color: Color = DS.Colors.amberAccent

    func body(content: Content) -> some View {
        content
            .padding(DS.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .fill(LinearGradient(
                        colors: [color.opacity(0.10), Color.clear],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .stroke(color.opacity(0.15), lineWidth: 0.5)
            )
    }
}

/// Specular shimmer overlay — diagonal light sweep across the hero card every
/// 6 seconds. Per Lucid Design Bundle Tier 3 hero spec. Respects reduce-motion.
struct SpecularShimmer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            EmptyView()
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let phase = (context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 6.0)) / 6.0
                GeometryReader { geo in
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: Color.white.opacity(0.08), location: 0.48),
                            .init(color: Color.white.opacity(0.16), location: 0.50),
                            .init(color: Color.white.opacity(0.08), location: 0.52),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: geo.size.width * 0.45)
                    .offset(x: -geo.size.width + (geo.size.width * 2.45 * CGFloat(phase)))
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
                .opacity(0.55)
            }
        }
    }
}

extension View {
    func glassCard(
        padding: CGFloat = DS.Spacing.md,
        elevated: Bool = false,
        tint: Color? = nil
    ) -> some View {
        modifier(GlassCard(
            padding: padding,
            tint: tint ?? DS.Colors.amberAccent,
            tintOpacity: tint != nil ? 0.08 : 0.04
        ))
    }

    func heroCard(color: Color = DS.Colors.amberAccent) -> some View {
        modifier(HeroCard(color: color))
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    var icon: String = ""
    let title: String
    var iconColor: Color = DS.Colors.amberAccent
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            if !icon.isEmpty {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(iconColor)
            }
            Text(title)
                .font(DS.Font.label)
                .foregroundStyle(DS.Colors.textMuted)
                .tracking(0.8)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(iconColor)
            }
        }
    }
}

// MARK: - Stat Pill

struct StatPill: View {
    let icon: String
    let value: String
    var unit: String = ""
    var color: Color = DS.Colors.textSecondary

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color.opacity(0.7))
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 9))
                    .foregroundStyle(color.opacity(0.6))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.08))
        .overlay(
            Capsule().stroke(color.opacity(0.15), lineWidth: 0.5)
        )
        .clipShape(Capsule())
    }
}

// MARK: - Score Ring (Recovery / Sleep / Strain hero display)

struct ScoreRing: View {
    let score: Double
    var maxScore: Double = 100
    var size: CGFloat = 56
    var lineWidth: CGFloat = 4
    var color: Color = DS.Colors.success
    var label: String? = nil

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(color.opacity(0.12), lineWidth: lineWidth)

            // Progress
            Circle()
                .trim(from: 0, to: min(score / maxScore, 1.0))
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(DS.Anim.ringFill, value: score)

            // Center text
            VStack(spacing: 0) {
                Text("\(Int(score))")
                    .font(.system(size: size * 0.32, weight: .heavy, design: .rounded))
                    .foregroundStyle(color)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let label {
                    Text(label)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(DS.Colors.textMuted)
                        .textCase(.uppercase)
                        .tracking(0.5)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Info Row (icon + label + value)

struct InfoRow: View {
    let icon: String
    let label: String
    let value: String
    var color: Color = DS.Colors.textSecondary

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color.opacity(0.7))
                .frame(width: 24)
            Text(label)
                .font(DS.Font.caption)
                .foregroundStyle(DS.Colors.textMuted)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.textPrimary)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.xs)
    }
}

// MARK: - Alert Banner

struct AlertBanner: View {
    let icon: String
    let message: String
    var color: Color = DS.Colors.warning

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
            Text(message)
                .font(DS.Font.caption)
                .foregroundStyle(DS.Colors.textPrimary)
                .lineLimit(3)
            Spacer()
        }
        .glassCard(padding: 12, tint: color)
        .padding(.horizontal)
    }
}

// MARK: - Glass Status Pill

struct GlassStatusPill: View {
    let icon: String
    let text: String
    var color: Color = DS.Colors.amberAccent

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.10))
        .overlay(
            Capsule()
                .stroke(color.opacity(0.18), lineWidth: 0.5)
        )
        .clipShape(Capsule())
    }
}

// MARK: - Metric Tile

struct MetricTile: View {
    let label: String
    let value: String
    var unit: String = ""
    var color: Color = DS.Colors.amberAccent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(DS.Font.micro)
                .foregroundStyle(DS.Colors.textMuted)
                .tracking(0.7)

            Text(value)
                .font(DS.Font.title2)
                .foregroundStyle(color)
                .monospacedDigit()

            if !unit.isEmpty {
                Text(unit)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Colors.textSecondary)
                    .lineLimit(2)
            }
        }
        // .leading = horizontal-leading + vertical-CENTER. With minHeight 108 the
        // tiles stay row-consistent, but short content (e.g. SDNN/42/ms) no longer
        // pins to the top with a 48pt dead zone below — vertically centered now.
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
        .padding(DS.Spacing.md)
        .glassCard(padding: 0, tint: color)
    }
}

// MARK: - Empty Glass State

struct EmptyGlassState: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(DS.Colors.textFaint)
            Text(title)
                .font(DS.Font.bodyMed)
                .foregroundStyle(DS.Colors.textPrimary)
            Text(detail)
                .font(DS.Font.caption)
                .foregroundStyle(DS.Colors.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.xl)
        .glassCard(padding: DS.Spacing.md)
    }
}

// MARK: - Two-Tone Headline

/// Two-tone typographic headline per Lucid Design Bundle principle 1.
/// Bold primary half locks the eye in 0.3s, muted secondary half adds context
/// without competing. Same font, same size, different weight + color.
struct TwoToneHeadline: View {
    let primary: String
    let secondary: String
    var font: SwiftUI.Font = DS.Font.display

    var body: some View {
        (
            Text(primary)
                .fontWeight(.heavy)
                .foregroundStyle(DS.Colors.textPrimary)
            + Text(secondary.hasPrefix(" ") ? "" : " ")
                .foregroundStyle(DS.Colors.textPrimary)
            + Text(secondary)
                .fontWeight(.regular)
                .foregroundStyle(DS.Colors.textMuted)
        )
        .font(font)
        .kerning(-0.5)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Glass Action Button Style

struct GlassActionButtonStyle: ButtonStyle {
    var tint: Color = DS.Colors.amberAccent
    var filled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(filled ? Color.white : tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Group {
                    if filled {
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .fill(tint.opacity(configuration.isPressed ? 0.52 : 0.70))
                    } else {
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .fill(tint.opacity(configuration.isPressed ? 0.18 : 0.10))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(tint.opacity(0.18), lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
