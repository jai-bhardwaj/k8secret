import XCTest
@testable import K8Secret

/// The updater decides whether to replace the running app, so its version
/// comparison and its manifest contract are both security-relevant.
final class UpdateCheckerTests: XCTestCase {

    // MARK: - Version comparison

    func testDetectsNewerVersion() {
        XCTAssertTrue(UpdateChecker.isNewer("0.6.0", than: "0.5.2"))
        XCTAssertTrue(UpdateChecker.isNewer("1.0.0", than: "0.9.9"))
        XCTAssertTrue(UpdateChecker.isNewer("0.5.3", than: "0.5.2"))
    }

    func testDoesNotDowngrade() {
        XCTAssertFalse(UpdateChecker.isNewer("0.5.1", than: "0.5.2"))
        XCTAssertFalse(UpdateChecker.isNewer("0.5.2", than: "0.5.2"))
        XCTAssertFalse(UpdateChecker.isNewer("0.9.9", than: "1.0.0"))
    }

    func testComparesNumericallyNotLexically() {
        // "0.5.10" sorts before "0.5.2" as a string; it must not.
        XCTAssertTrue(UpdateChecker.isNewer("0.5.10", than: "0.5.2"))
        XCTAssertFalse(UpdateChecker.isNewer("0.5.2", than: "0.5.10"))
    }

    func testHandlesDifferentComponentCounts() {
        XCTAssertTrue(UpdateChecker.isNewer("0.6", than: "0.5.9"))
        XCTAssertFalse(UpdateChecker.isNewer("0.5", than: "0.5.0"))
    }

    func testPrereleaseIsNotNewerThanItsRelease() {
        XCTAssertFalse(UpdateChecker.isNewer("1.0.0-rc1", than: "1.0.0"))
        XCTAssertTrue(UpdateChecker.isNewer("1.0.1-rc1", than: "1.0.0"))
    }

    func testNonNumericComponentDoesNotShiftTheRest() {
        // Regression: compactMap used to drop "x" entirely, so "1.x.5" compared as
        // 1.5 and could present a bogus release as an upgrade.
        XCTAssertFalse(UpdateChecker.isNewer("1.x.5", than: "1.4.0"))
    }

    // MARK: - Manifest contract

    func testManifestDecodesChecksum() throws {
        let json = """
        {
          "version": "0.6.0",
          "url": "https://github.com/jai-bhardwaj/k8secret/releases/download/v0.6.0/K8Secret-0.6.0.dmg",
          "notes": "Test",
          "minOS": "14.0",
          "date": "2026-08-15",
          "sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        }
        """
        let release = try JSONDecoder().decode(AppRelease.self, from: Data(json.utf8))
        XCTAssertEqual(release.sha256?.count, 64)
        XCTAssertEqual(release.version, "0.6.0")
    }

    func testManifestWithoutChecksumStillDecodesButHasNoDigest() throws {
        // Older manifests must not crash the check; the install path is what
        // refuses them.
        let json = """
        { "version": "0.5.2", "url": "https://github.com/x/y/releases/download/v1/a.dmg", "notes": "" }
        """
        let release = try JSONDecoder().decode(AppRelease.self, from: Data(json.utf8))
        XCTAssertNil(release.sha256)
    }

    /// Repo-root `release/latest.json` — the manifest actually served to users.
    private static var shippedManifestURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // K8SecretTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // macos
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("release/latest.json")
    }

    func testShippedManifestCarriesAChecksumField() throws {
        // Guards the release pipeline: publish.sh must keep writing sha256, or the
        // updater will refuse every future release.
        let data = try Data(contentsOf: Self.shippedManifestURL)
        let release = try JSONDecoder().decode(AppRelease.self, from: data)

        let digest = try XCTUnwrap(release.sha256, "release/latest.json must publish a sha256")
        XCTAssertEqual(digest.count, 64)
        XCTAssertTrue(
            digest.allSatisfy(\.isHexDigit),
            "sha256 must be hex"
        )
    }

    func testShippedManifestURLIsOnATrustedHost() throws {
        let release = try JSONDecoder().decode(
            AppRelease.self,
            from: try Data(contentsOf: Self.shippedManifestURL)
        )
        let url = try XCTUnwrap(URL(string: release.url))

        XCTAssertEqual(url.scheme, "https")
        XCTAssertTrue(AppConstants.releaseDownloadHosts.contains(try XCTUnwrap(url.host)))
    }
}
