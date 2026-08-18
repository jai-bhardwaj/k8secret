import XCTest
@testable import K8Secret

/// The app must not touch a keychain.
///
/// It used to: a client-certificate identity was imported into a throwaway
/// file-based keychain, because macOS was believed to build a `SecIdentity`
/// only from a keychain-resident key. It doesn't — `SecPKCS12Import` with no
/// destination keychain returns an identity that signs a handshake perfectly
/// well — and that keychain was the source of every password prompt this app
/// ever showed a user: macOS locks it on sleep, and the password it then asks
/// for was random and only ever existed in the process's memory.
///
/// This used to be guarded at runtime, by refusing user interaction during
/// tests so a regression failed instead of hanging on a dialog. Guarding the
/// source is stronger: a reintroduction fails here, before anything runs, and
/// it needs no deprecated API of its own to do it.
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

        var offenders: [String] = []
        var scanned = 0
        for case let url as URL in enumerator where url.pathExtension == "swift" {
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
                      "keychain APIs are back in the app:\n" + offenders.joined(separator: "\n"))
    }
}
