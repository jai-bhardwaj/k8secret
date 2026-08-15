import XCTest
@testable import K8Secret

/// Secrets routinely hold PEM keys, JSON blobs and passwords full of shell
/// metacharacters. An export that doesn't survive a round-trip through `.env` is
/// worse than no export at all, because the corruption is silent.
final class SecretExportTests: XCTestCase {

    func testSimpleValueIsNotQuoted() {
        XCTAssertEqual(AppState.envQuoted("hunter2"), "hunter2")
        XCTAssertEqual(AppState.envQuoted("postgres"), "postgres")
    }

    func testValueWithSpacesIsQuoted() {
        XCTAssertEqual(AppState.envQuoted("hello world"), "\"hello world\"")
    }

    func testEmptyValueIsQuoted() {
        // Bare `KEY=` is ambiguous across .env parsers; `KEY=""` is not.
        XCTAssertEqual(AppState.envQuoted(""), "\"\"")
    }

    func testNewlinesAreEscapedNotEmitted() {
        // A raw newline would end the line and turn the rest of a PEM key into
        // garbage keys — the single most damaging case for this app's users.
        let pem = "-----BEGIN KEY-----\nabc\n-----END KEY-----"
        let quoted = AppState.envQuoted(pem)

        XCTAssertFalse(quoted.contains("\n"), "export must stay on one line")
        XCTAssertEqual(quoted, "\"-----BEGIN KEY-----\\nabc\\n-----END KEY-----\"")
    }

    func testQuotesAndBackslashesAreEscaped() {
        XCTAssertEqual(AppState.envQuoted("say \"hi\""), "\"say \\\"hi\\\"\"")
        XCTAssertEqual(AppState.envQuoted("C:\\path"), "\"C:\\\\path\"")
    }

    func testDollarIsEscapedSoShellsDoNotInterpolate() {
        // `KEY="$HOME"` would expand when sourced; the literal must be preserved.
        XCTAssertEqual(AppState.envQuoted("$HOME"), "\"\\$HOME\"")
    }

    func testValueWithHashIsQuoted() {
        // Unquoted, everything after ` #` is a comment to most .env parsers.
        XCTAssertEqual(AppState.envQuoted("abc #def"), "\"abc #def\"")
    }
}
