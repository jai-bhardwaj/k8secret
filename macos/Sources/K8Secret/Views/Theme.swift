import SwiftUI

/// The vNext design system — every color and metric the redesign uses, in one
/// place, derived from the approved prototype (claude.ai artifact "K8Secret
/// vNext", frozen 16 Aug 2026).
///
/// Three families, deliberately separate:
///
/// - **Accent** is the app's identity (phosphor mint). It is spent only on
///   selection, focus, primary actions, and progress — never on data.
/// - **Metric hues** color-code data by *kind*: blue is always CPU, violet is
///   always memory, everywhere in the app. Rows stay scannable because the hue
///   answers "what is this number" before the number is read.
/// - **Semantic** (ok/warn/bad) encodes *state*, and is never used decoratively,
///   so color = something needs attention stays true.
///
/// Everything adapts to light/dark through the asset-free dynamic initializer,
/// so the palette lives in code next to its rationale.
enum Theme {
    // MARK: - Accent

    static let accent = dynamic(light: 0x0E9C85, dark: 0x3ECFB2)
    static let accentText = dynamic(light: 0xFFFFFF, dark: 0x08110E)

    // MARK: - Metric hues (data kinds, not states)

    static let cpu = dynamic(light: 0x2B6FD8, dark: 0x6AA6FF)
    static let memory = dynamic(light: 0x7C5CE0, dark: 0xA78BFA)

    // MARK: - Semantic

    static let ok = dynamic(light: 0x1F9D5B, dark: 0x34C77B)
    static let warn = dynamic(light: 0xB27E19, dark: 0xE5A93D)
    static let bad = dynamic(light: 0xC6423B, dark: 0xE5564F)

    /// Soft backgrounds behind pills and badges: the hue at chip opacity.
    static func soft(_ color: Color) -> Color { color.opacity(0.14) }

    // MARK: - Per-context cluster tints

    /// The choices offered in Settings for color-coding a cluster context.
    /// Amber and rose are named for their intended use so the picker teaches
    /// the habit: staging gets a warning color, prod gets an alarming one.
    enum ClusterTint: String, CaseIterable, Identifiable, Codable {
        case mint, ocean, violet, amber, rose
        var id: String { rawValue }

        var color: Color {
            switch self {
            case .mint: return Theme.accent
            case .ocean: return Theme.cpu
            case .violet: return Theme.memory
            case .amber: return Theme.warn
            case .rose: return Theme.bad
            }
        }

        var label: String {
            switch self {
            case .mint: return "Default"
            case .ocean: return "Ocean"
            case .violet: return "Violet"
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
    /// Slight overshoot, reserved for pops: dialogs, toasts, switch thumbs.
    static let spring = Animation.spring(response: 0.32, dampingFraction: 0.78)

    // MARK: - Plumbing

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}
