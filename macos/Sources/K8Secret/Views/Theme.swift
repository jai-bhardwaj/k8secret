import SwiftUI

/// The vNext design system — every color and metric the redesign uses, in one
/// place, derived from the approved prototype (claude.ai artifact "K8Secret
/// vNext", CleanMyMac-inspired canvas revision, frozen 16 Aug 2026).
///
/// The world model: one luminous radial **canvas** fills the whole window —
/// there are no panels and no hairlines. Zones separate by whisper-level
/// washes and light-catch lines; floating surfaces are frosted glass that
/// borrow the canvas hue. The cluster tint paints the entire canvas (rose for
/// prod is unmistakable from across the room). Ocean (blue) is the default.
enum Theme {
    // MARK: - Canvas gradients (the whole-window world)

    /// One radial gradient per (tint × scheme × hero). Stops are verbatim from
    /// the prototype CSS. `hero` is the brighter bottom-glow used on Overview.
    /// Dark stops never collapse to near-black — the darkest corner stays
    /// saturated (the "luminous canvas" rule from the CleanMyMac reference).
    static func canvasStops(tint: ClusterTint, hero: Bool, scheme: ColorScheme) -> [Gradient.Stop] {
        func s(_ pairs: [(UInt32, Double)]) -> [Gradient.Stop] {
            pairs.map { .init(color: Color(hex: $0.0), location: $0.1) }
        }
        switch (tint, scheme, hero) {
        case (.ocean, .dark, false):
            return s([(0x2F6FB4, 0), (0x285D9A, 0.34), (0x1F477A, 0.62), (0x16345C, 0.84), (0x102846, 1)])
        case (.ocean, .dark, true):
            return s([(0x3E96E0, 0), (0x3175C8, 0.30), (0x245695, 0.56), (0x183A66, 0.78), (0x122B4C, 1)])
        case (.ocean, _, false):
            return s([(0xC0D8F2, 0), (0xADC9E8, 0.40), (0x98B6DA, 0.70), (0x88A8CE, 1)])
        case (.ocean, _, true):
            return s([(0xD2E4F8, 0), (0xBAD2F0, 0.34), (0xA2BEE4, 0.64), (0x8FACD6, 1)])
        case (.violet, .dark, false):
            return s([(0x57288A, 0), (0x452073, 0.34), (0x331A58, 0.62), (0x221240, 0.84), (0x180D33, 1)])
        case (.violet, .dark, true):
            return s([(0xB92FD4, 0), (0x7A27BE, 0.30), (0x471D8C, 0.56), (0x271252, 0.78), (0x170C36, 1)])
        case (.violet, _, false):
            return s([(0xD9C4F0, 0), (0xCDB9EA, 0.40), (0xBFAAE2, 0.70), (0xB2A0DB, 1)])
        case (.violet, _, true):
            return s([(0xEFC4F8, 0), (0xDBC0F4, 0.34), (0xC4B0EA, 0.64), (0xB2A0E0, 1)])
        case (.mint, .dark, false):
            return s([(0x2FA98C, 0), (0x269079, 0.34), (0x1C7361, 0.62), (0x14574A, 0.84), (0x0F443A, 1)])
        case (.mint, .dark, true):
            return s([(0x3BD9AD, 0), (0x2FC392, 0.30), (0x219070, 0.56), (0x16624F, 0.78), (0x10473C, 1)])
        case (.mint, _, false):
            return s([(0xBFE9DC, 0), (0xACDCCB, 0.40), (0x97CBB8, 0.70), (0x86BCA8, 1)])
        case (.mint, _, true):
            return s([(0xD2F2E6, 0), (0xBCE5D4, 0.34), (0xA5D4C0, 0.64), (0x90C2AC, 1)])
        case (.amber, .dark, false):
            return s([(0xA66E28, 0), (0x8E5C20, 0.34), (0x6E4619, 0.62), (0x503311, 0.84), (0x3C260D, 1)])
        case (.amber, .dark, true):
            return s([(0xE0A93E, 0), (0xC88931, 0.30), (0x956224, 0.56), (0x664118, 0.78), (0x4C3012, 1)])
        case (.amber, _, false):
            return s([(0xF2DCB8, 0), (0xE8CDA1, 0.40), (0xDABB88, 0.70), (0xCEAC75, 1)])
        case (.amber, _, true):
            return s([(0xF8E6C6, 0), (0xEFD6AC, 0.34), (0xE2C492, 0.64), (0xD4B37C, 1)])
        case (.rose, .dark, false):
            return s([(0xA62E52, 0), (0x8E2745, 0.34), (0x6E1F36, 0.62), (0x501626, 0.84), (0x3C111D, 1)])
        case (.rose, .dark, true):
            return s([(0xE03E70, 0), (0xC83158, 0.30), (0x952441, 0.56), (0x66182C, 0.78), (0x4C1221, 1)])
        case (.rose, _, false):
            return s([(0xF2C0CE, 0), (0xE8ACBD, 0.40), (0xDA96A9, 0.70), (0xCE8598, 1)])
        case (.rose, _, true):
            return s([(0xF8CEDA, 0), (0xEFB8C8, 0.34), (0xE2A0B3, 0.64), (0xD48CA0, 1)])
        }
    }

    /// The canvas as a view: the prototype's `radial-gradient(110% 90% at 42%
    /// 108%)` — a glow rising from below-left of bottom-center. Draw it on the
    /// window root behind everything, ignoring safe areas.
    struct CanvasBackground: View {
        var tint: ClusterTint
        var hero: Bool
        @Environment(\.colorScheme) private var scheme

        var body: some View {
            GeometryReader { geo in
                EllipticalGradient(
                    stops: Theme.canvasStops(tint: tint, hero: hero, scheme: scheme),
                    center: UnitPoint(x: 0.42, y: hero ? 1.04 : 1.08),
                    startRadiusFraction: 0,
                    endRadiusFraction: hero ? 0.95 : 1.10
                )
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .ignoresSafeArea()
            .animation(easeOut, value: tint)
        }
    }

    // MARK: - Ink & text on canvas

    /// Text on the canvas. Dark canvas: white; light canvas: deep ink.
    static let text = dynamic(light: 0x241640, dark: 0xFFFFFF)
    static let text2 = dynamicA(light: 0x241640, lightA: 0.75, dark: 0xFFFFFF, darkA: 0.72)
    static let text3 = dynamicA(light: 0x241640, lightA: 0.47, dark: 0xFFFFFF, darkA: 0.44)

    // MARK: - Surfaces (translucent washes on the canvas — no opaque panels)

    /// Window ground behind the canvas (only visible before the canvas draws).
    static let ground = dynamic(light: 0xB2A0DB, dark: 0x102846)
    /// Panes are transparent — the canvas is the surface.
    static let panel = Color.clear
    /// Cards and pills sit slightly above the canvas: a white veil.
    static let raised = dynamicA(light: 0xFFFFFF, lightA: 0.32, dark: 0xFFFFFF, darkA: 0.06)
    /// Wells (inputs, code, chips) recess: darker in light, faint white in dark.
    static let inset = dynamicA(light: 0x3A2A5E, lightA: 0.063, dark: 0xFFFFFF, darkA: 0.04)
    /// Soft edges where an edge is unavoidable (cards use shadow depth instead).
    static let line = dynamicA(light: 0xFFFFFF, lightA: 0.40, dark: 0xFFFFFF, darkA: 0.08)
    static let lineStrong = dynamicA(light: 0xFFFFFF, lightA: 0.60, dark: 0xFFFFFF, darkA: 0.15)

    // MARK: - Accent

    static let accent = dynamic(light: 0xA32BC9, dark: 0xE24BE0)
    static let accentText = Color.white
    /// Selection ring around pills/rows (ink in light, white in dark).
    static let selRing = dynamicA(light: 0x3A2A5E, lightA: 0.22, dark: 0xFFFFFF, darkA: 0.15)
    /// Row selection fill.
    static let selRow = dynamicA(light: 0x0E9C85, lightA: 0.15, dark: 0x3ECFB2, darkA: 0.08)

    // MARK: - Metric hues (data kinds, not states)

    static let cpu = dynamic(light: 0x2B6FD8, dark: 0x6AA6FF)
    static let memory = dynamic(light: 0x7C5CE0, dark: 0xA78BFA)

    // MARK: - Semantic

    static let ok = dynamic(light: 0x1F9D5B, dark: 0x34C77B)
    static let warn = dynamic(light: 0xB27E19, dark: 0xE5A93D)
    static let bad = dynamic(light: 0xC6423B, dark: 0xE5564F)

    /// Soft backgrounds behind pills and badges: the hue at chip opacity.
    static func soft(_ color: Color) -> Color { color.opacity(0.14) }

    // MARK: - Module identity hues (the sidebar + wash system)

    /// Every destination has a hue: it colors the dimensional icon's selected
    /// pill and the canvas wash while that module is open.
    static func moduleHue(_ key: String, scheme: ColorScheme) -> Color {
        let dark: [String: UInt32] = [
            "overview": 0x3ECFB2, "deployments": 0x6AA6FF, "pods": 0x43E0B8,
            "cronjobs": 0xF5A83D, "services": 0xA78BFA, "ingresses": 0x4FC3F7,
            "secrets": 0xF26D8D, "configmaps": 0x8BD450, "events": 0xFF8A65,
        ]
        let light: [String: UInt32] = [
            "overview": 0x2BB8A3, "deployments": 0x3D7EE8, "pods": 0x1FA98C,
            "cronjobs": 0xD98A2B, "services": 0x7C5CE0, "ingresses": 0x2E9BD6,
            "secrets": 0xD6567E, "configmaps": 0x6BA32E, "events": 0xE06B4D,
        ]
        let table = scheme == .dark ? dark : light
        return Color(hex: table[key] ?? (scheme == .dark ? 0xFFFFFF : 0x241640))
    }

    // MARK: - Glass recipes

    /// Luminous popover glass (dialogs, palette, menus, toasts): frosted
    /// material lifted by a white veil so the panel reads *brighter* than the
    /// world behind it, with a lit top edge. Matches the prototype's
    /// `--pop` + blur(64) saturate(1.85) brightness(1.35).
    struct PopGlass: ViewModifier {
        var radius: CGFloat = 22
        @Environment(\.colorScheme) private var scheme
        func body(content: Content) -> some View {
            content
                .background {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .fill(Color.white.opacity(scheme == .dark ? 0.11 : 0.55))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .strokeBorder(Color.white.opacity(scheme == .dark ? 0.18 : 0.45), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.30), radius: 30, y: 16)
                }
        }
    }

    /// Flyout / structural glass (the sidebar's floating panel): a neutral
    /// dark veil in dark mode so the canvas tint shows through the frost.
    struct FloatGlass: ViewModifier {
        var radius: CGFloat = 16
        @Environment(\.colorScheme) private var scheme
        func body(content: Content) -> some View {
            content
                .background {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .fill(scheme == .dark
                                      ? Color(hex: 0x150E20).opacity(0.45)
                                      : Color.white.opacity(0.45))
                        )
                        .shadow(color: .black.opacity(0.28), radius: 24, y: 10)
                }
        }
    }

    // MARK: - Buttons

    /// The primary action: a white pill with ink text (CleanMyMac's grammar).
    /// Never a gradient, never a colored glow.
    struct PrimaryPill: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: 12.5, weight: .bold))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(Color(hex: 0x231646))
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background(Capsule().fill(.white))
                .shadow(color: .black.opacity(0.32), radius: 9, y: 4)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(Theme.spring, value: configuration.isPressed)
        }
    }

    /// Destructive actions: red voice on a soft red wash — never a filled
    /// red slab (the prototype's Stop-button grammar).
    struct DangerPill: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(Theme.bad)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Capsule().fill(Theme.bad.opacity(0.14)))
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(Theme.spring, value: configuration.isPressed)
        }
    }

    /// Secondary actions: translucent wash pill.
    struct SoftPill: ButtonStyle {
        @Environment(\.colorScheme) private var scheme
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Capsule().fill(Theme.raised))
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(Theme.spring, value: configuration.isPressed)
        }
    }

    // MARK: - Per-context cluster tints

    /// Settings offers these for color-coding a cluster context; the choice
    /// paints the *entire canvas*. Ocean is the app default. Amber and rose
    /// are named for their intended use so the picker teaches the habit.
    enum ClusterTint: String, CaseIterable, Identifiable, Codable {
        case ocean, violet, mint, amber, rose
        var id: String { rawValue }

        /// The default canvas for contexts with no explicit choice.
        static let `default`: ClusterTint = .ocean

        /// The swatch/dot color representing this tint.
        var color: Color {
            switch self {
            case .ocean: return Color(hex: 0x5B9BE0)
            case .violet: return Color(hex: 0x9B6CE8)
            case .mint: return Color(hex: 0x3ECFB2)
            case .amber: return Color(hex: 0xE0A93E)
            case .rose: return Color(hex: 0xE05C7E)
            }
        }

        var label: String {
            switch self {
            case .ocean: return "Ocean — default"
            case .violet: return "Violet"
            case .mint: return "Mint"
            case .amber: return "Amber — good for staging"
            case .rose: return "Rose — good for prod"
            }
        }
    }

    // MARK: - Metrics thresholds

    /// Color for a usage-vs-request percentage: quiet while healthy, amber
    /// above 60, red above 85. The number carries the value; the color carries
    /// whether to care.
    static func pressure(_ percent: Int) -> Color {
        percent > 85 ? bad : (percent > 60 ? warn : ok)
    }

    // MARK: - Motion (extends Motion.swift's vocabulary)

    /// Expo-out: fast start, soft landing. The default for everything.
    static let easeOut = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.26)
    /// Slight overshoot, reserved for movement only — never colors or veils
    /// (a spring on a fill overshoots the alpha and reads as a flash).
    static let spring = Animation.spring(response: 0.32, dampingFraction: 0.78)

    /// The app's actual appearance, from AppKit's authority. Exists because
    /// SwiftUI's colorScheme environment misreports inside the toast's
    /// transition subtree on Sonoma (observed: .light in a provably dark
    /// window), and dynamic NSColors misresolve in the same place.
    static var currentScheme: ColorScheme {
        NSApplication.shared.effectiveAppearance
            .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }

    // MARK: - Scheme-resolved variants

    /// For views that render inside detached compositing layers (a `.shadow`,
    /// a snapshot, a transition): AppKit resolves dynamic NSColors there
    /// against the *system default* appearance, not the window's. These
    /// resolve through SwiftUI's own environment instead.
    static func raised(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x2A2140) : Color(hex: 0xF4EFFB)
    }
    static func lineStrong(_ scheme: ColorScheme) -> Color {
        Color.white.opacity(scheme == .dark ? 0.15 : 0.60)
    }
    static func ok(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x34C77B) : Color(hex: 0x1F9D5B)
    }
    static func bad(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xE5564F) : Color(hex: 0xC6423B)
    }
    static func text(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white : Color(hex: 0x241640)
    }

    // MARK: - Plumbing

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        dynamicA(light: light, lightA: 1, dark: dark, darkA: 1)
    }

    private static func dynamicA(light: UInt32, lightA: CGFloat, dark: UInt32, darkA: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: isDark ? darkA : lightA
            )
        })
    }
}

extension View {
    /// Luminous popover glass — dialogs, palette, menus, toasts.
    func popGlass(radius: CGFloat = 22) -> some View {
        modifier(Theme.PopGlass(radius: radius))
    }
    /// Structural glass — the sidebar flyout and kin.
    func floatGlass(radius: CGFloat = 16) -> some View {
        modifier(Theme.FloatGlass(radius: radius))
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
