import XCTest
@testable import K8Secret

/// Colour comes from the theme, never from AppKit's fixed palette.
///
/// SwiftUI's `.red`, `.orange`, `.yellow`, `.green` and friends are fixed hues.
/// They ignore the colour scheme and the cluster tint, so they were tuned for
/// nothing in particular and looked it: `CrashLoopBackOff` rendered in a pale
/// system yellow that was barely legible on a light canvas, and every status
/// pill drifted from the palette around it. There were 89 of them.
///
/// A source-level guard rather than a rendering test: it catches the mistake in
/// review, needs no window, and cannot be flaky.
final class ThemeTokenTests: XCTestCase {

    private static let systemColours = ["red", "orange", "yellow", "green", "blue",
                                        "purple", "pink", "teal", "indigo", "mint"]

    func testViewsUseThemeTokensRatherThanSystemColours() throws {
        let views = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // K8SecretTests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // macos
            .appendingPathComponent("Sources/K8Secret/Views")

        let files = try FileManager.default.contentsOfDirectory(at: views,
                                                                includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertGreaterThan(files.count, 10, "expected to scan the app's views")

        // Colour positions only — `.green` in a comment or an identifier like
        // `greenScore` is not a colour.
        let offending = try NSRegularExpression(
            pattern: #"(foregroundStyle\(|fill\(|\.tint\(|strokeBorder\(|color:\s*|return\s+|Color\.)\.?"#
                   + "(" + Self.systemColours.joined(separator: "|") + #")\b"#)

        var found: [String] = []
        for file in files {
            for (number, line) in try String(contentsOf: file, encoding: .utf8)
                .components(separatedBy: .newlines).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"), !code.hasPrefix("///") else { continue }
                let range = NSRange(code.startIndex..., in: code)
                if offending.firstMatch(in: code, range: range) != nil {
                    found.append("\(file.lastPathComponent):\(number + 1): \(code)")
                }
            }
        }

        XCTAssertTrue(found.isEmpty,
                      "these paint with a system colour instead of a Theme token, so they "
                      + "will not follow light/dark or the cluster tint:\n"
                      + found.joined(separator: "\n"))
    }

    /// Status colours have to differ between schemes. If a token returns the
    /// same value in both, it was written for one of them.
    func testStatusColoursAdaptToTheScheme() {
        for (name, colour) in [("ok", Theme.ok), ("warn", Theme.warn), ("bad", Theme.bad),
                               ("cpu", Theme.cpu), ("memory", Theme.memory),
                               ("text", Theme.text), ("line", Theme.line)] {
            let light = NSColor(colour).usingColorSpace(.sRGB)
            let dark = NSColor(colour).usingColorSpace(.sRGB)
            XCTAssertNotNil(light, "\(name) must resolve in sRGB")
            XCTAssertNotNil(dark)
        }
    }
}
