import XCTest
@testable import K8Secret

/// The keychain is confined to one file, and to macOS 14.
///
/// On macOS 15 and later `kSecImportToMemoryOnly` keeps a client-certificate
/// identity in process memory, and no keychain is involved at all. macOS 14 has
/// no such option, and both alternatives there are wrong: leaving the item in
/// the login keychain makes the next launch prompt for a password — this app is
/// ad-hoc signed, so every build is a different application to macOS — and
/// deleting it immediately invalidates the identity it backs, which is exactly
/// how 0.6.15 broke every client-certificate handshake on macOS 14.
///
/// So `TransientKeychain` stays: a keychain created for this process, randomly
/// named and keyed, never in the search list, deleted on quit. This test keeps
/// it there and nowhere else, so the rest of the app cannot start reaching for
/// the user's keychain again.
final class NoKeychainTests: XCTestCase {

    func testNoSourceFileUsesTheDeprecatedKeychainAPIs() throws {
        let sources = URL(fileURLWithPath: #filePath)      // …/Tests/K8SecretTests/this
            .deletingLastPathComponent()                    // …/Tests/K8SecretTests
            .deletingLastPathComponent()                    // …/Tests
            .deletingLastPathComponent()                    // …/macos
            .appendingPathComponent("Sources")

        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil),
            "cannot walk \(sources.path)")

        // The one file allowed to speak SecKeychain, and the one call site
        // allowed to name a destination keychain for an import.
        let allowed = ["TransientKeychain.swift", "K8sClient.swift", "K8SecretApp.swift"]

        var offenders: [String] = []
        var scanned = 0
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            if allowed.contains(url.lastPathComponent) { scanned += 1; continue }
            scanned += 1
            let text = try String(contentsOf: url, encoding: .utf8)
            for line in text.components(separatedBy: .newlines) {
                // Comments explain why the keychain is gone; they are not uses.
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"), !code.hasPrefix("///") else { continue }
                if code.contains("SecKeychain") || code.contains("kSecImportExportKeychain") {
                    offenders.append("\(url.lastPathComponent): \(code)")
                }
            }
        }

        XCTAssertGreaterThan(scanned, 10, "expected to scan the app's sources")
        XCTAssertTrue(offenders.isEmpty,
                      "keychain APIs have spread beyond \(allowed.joined(separator: ", ")):\n"
                      + offenders.joined(separator: "\n"))
    }
}
