import XCTest
import AppKit
@testable import K8Secret

/// Status colours must stay readable on every canvas the app can paint.
///
/// There are five cluster tints and two schemes, so any one of these colours
/// has to work against ten different backgrounds — and the failure mode is
/// specific: a status that shares its canvas's hue disappears into it. An amber
/// warning on the amber cluster rendered as a pale olive that could not be read
/// at all, and green on mint did the same. Judging that by eye is how it got
/// shipped; this measures it.
///
/// 4.5:1 is WCAG AA for body text. The tokens sat between 2.9 and 3.6 in light
/// mode before they were chosen against this test.
final class ContrastTests: XCTestCase {

    /// The hardest point of each canvas — the extreme stop, not the average.
    private let lightCanvases: [UInt32] = [0xC0D8F2, 0xD9C4F0, 0xBFE9DC, 0xF2DCB8, 0xF2C0CE]
    private let darkCanvases: [UInt32] = [0x102846, 0x180D33, 0x0F443A, 0x3C260D, 0x3C111D]

    private func luminance(_ colour: NSColor) -> Double {
        let srgb = colour.usingColorSpace(.sRGB)!
        func channel(_ v: CGFloat) -> Double {
            let d = Double(v)
            return d <= 0.03928 ? d / 12.92 : pow((d + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(srgb.redComponent)
             + 0.7152 * channel(srgb.greenComponent)
             + 0.0722 * channel(srgb.blueComponent)
    }

    private func contrast(_ a: NSColor, _ b: NSColor) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    private func colour(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    func testStatusColoursAreReadableOnEveryCanvas() {
        // Mirrors Theme's values. Deliberately duplicated: SwiftUI resolves a
        // dynamic colour against the environment, and a test has no window to
        // resolve one in, so the numbers are asserted directly.
        let tokens: [(String, light: UInt32, dark: UInt32)] = [
            ("ok",     light: 0x0A5233, dark: 0x7CEFB4),
            ("warn",   light: 0x6B4708, dark: 0xF7CE78),
            ("bad",    light: 0x8E2119, dark: 0xFF9089),
            ("cpu",    light: 0x14458F, dark: 0x93C0FF),
            ("memory", light: 0x4A2E9E, dark: 0xC3B0FF),
        ]

        for token in tokens {
            for canvas in lightCanvases {
                let ratio = contrast(colour(token.light), colour(canvas))
                XCTAssertGreaterThanOrEqual(
                    ratio, 4.5,
                    String(format: "%@ is %.2f:1 on light canvas %06X — unreadable",
                           token.0, ratio, canvas))
            }
            for canvas in darkCanvases {
                let ratio = contrast(colour(token.dark), colour(canvas))
                XCTAssertGreaterThanOrEqual(
                    ratio, 4.5,
                    String(format: "%@ is %.2f:1 on dark canvas %06X — unreadable",
                           token.0, ratio, canvas))
            }
        }
    }
}
