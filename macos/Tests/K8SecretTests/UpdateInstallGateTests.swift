import XCTest
@testable import K8Secret

/// The three checks standing between a remote JSON file and code execution on the
/// user's machine.
///
/// Before these existed, the updater took a URL out of a manifest, downloaded it
/// with no scheme or host check, mounted it with checksum verification disabled,
/// copied it into /Applications, stripped quarantine and ad-hoc signed it. Anyone
/// who could influence the manifest or the download got arbitrary code execution —
/// with the app dismantling Gatekeeper on the payload's behalf.
final class UpdateInstallGateTests: XCTestCase {

    private let validDigest = "5c20a811b5f7851f91d4a23afe0bc524e214265d446b05e33ace890c3bbc4fba"

    private func release(
        url: String = "https://github.com/jai-bhardwaj/k8secret/releases/download/v0.5.6/K8Secret-0.5.6.dmg",
        sha256: String? = nil
    ) -> AppRelease {
        AppRelease(version: "9.9.9", url: url, notes: "", minOS: nil, date: nil,
                   sha256: sha256 ?? validDigest)
    }

    // MARK: - What is allowed

    func testAllowsAProperlySignedRelease() {
        guard case .allowed(let url, let digest) = UpdateChecker.decide(release()) else {
            return XCTFail("a well-formed release should be installable")
        }
        XCTAssertEqual(url.host, "github.com")
        XCTAssertEqual(digest, validDigest)
    }

    func testAllowsTheRedirectHostGitHubUsesForAssets() {
        let r = release(url: "https://objects.githubusercontent.com/foo/K8Secret.dmg")
        guard case .allowed = UpdateChecker.decide(r) else {
            return XCTFail("GitHub's asset redirect host must be accepted")
        }
    }

    func testDigestComparisonIsCaseInsensitive() {
        guard case .allowed(_, let digest) = UpdateChecker.decide(release(sha256: validDigest.uppercased())) else {
            return XCTFail("an uppercase digest is still a digest")
        }
        XCTAssertEqual(digest, validDigest)
    }

    func testTolerantOfSurroundingWhitespaceInTheDigest() {
        guard case .allowed = UpdateChecker.decide(release(sha256: "  \(validDigest)\n")) else {
            return XCTFail("whitespace around the digest should not refuse the update")
        }
    }

    // MARK: - What is refused

    func testRefusesPlainHTTP() {
        // With NSAllowsArbitraryLoads set, as it was, this would have been fetched.
        let r = release(url: "http://github.com/jai-bhardwaj/k8secret/releases/download/v1/a.dmg")
        assertRefused(r, because: "trusted HTTPS")
    }

    func testRefusesAnUntrustedHost() {
        assertRefused(release(url: "https://evil.example.com/K8Secret.dmg"), because: "trusted HTTPS")
    }

    func testRefusesALookalikeHost() {
        // Substring matching would accept this; membership does not.
        assertRefused(release(url: "https://github.com.evil.example.com/a.dmg"), because: "trusted HTTPS")
    }

    func testRefusesAFileURL() {
        assertRefused(release(url: "file:///tmp/K8Secret.dmg"), because: "trusted HTTPS")
    }

    func testRefusesAManifestWithNoChecksum() {
        let r = AppRelease(version: "9.9.9", url: release().url, notes: "", minOS: nil, date: nil, sha256: nil)
        assertRefused(r, because: "no sha256")
    }

    func testRefusesAMalformedChecksum() {
        assertRefused(release(sha256: "deadbeef"), because: "no sha256")                    // too short
        assertRefused(release(sha256: String(repeating: "z", count: 64)), because: "no sha256") // not hex
    }

    func testRefusesAnUnparseableURL() {
        assertRefused(release(url: ""), because: "not a valid URL")
    }

    private func assertRefused(_ release: AppRelease, because fragment: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        switch UpdateChecker.decide(release) {
        case .allowed:
            XCTFail("update should have been refused", file: file, line: line)
        case .refused(let reason):
            XCTAssertTrue(reason.localizedCaseInsensitiveContains(fragment),
                          "unexpected refusal reason: \(reason)", file: file, line: line)
        }
    }

    // MARK: - Digest of an actual file

    func testDigestMatchesShasum() throws {
        // Same value `shasum -a 256` produces for an empty file.
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("digest-\(UUID().uuidString).bin")
        try Data().write(to: path)
        defer { try? FileManager.default.removeItem(at: path) }

        XCTAssertEqual(try UpdateChecker.sha256Hex(ofFileAt: path),
                       "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    func testDigestChangesWithASingleFlippedByte() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        let a = dir.appendingPathComponent("a-\(UUID().uuidString).bin")
        let b = dir.appendingPathComponent("b-\(UUID().uuidString).bin")
        try Data(repeating: 0x41, count: 4096).write(to: a)
        var tampered = Data(repeating: 0x41, count: 4096)
        tampered[2048] = 0x42
        try tampered.write(to: b)
        defer {
            try? FileManager.default.removeItem(at: a)
            try? FileManager.default.removeItem(at: b)
        }

        XCTAssertNotEqual(try UpdateChecker.sha256Hex(ofFileAt: a),
                          try UpdateChecker.sha256Hex(ofFileAt: b))
    }

    func testDigestHandlesAFileLargerThanOneChunk() throws {
        // Hashing is streamed in 1 MiB chunks; make sure the loop is right.
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("big-\(UUID().uuidString).bin")
        try Data(repeating: 0x5A, count: (1 << 20) + 12345).write(to: path)
        defer { try? FileManager.default.removeItem(at: path) }

        let digest = try UpdateChecker.sha256Hex(ofFileAt: path)
        XCTAssertEqual(digest.count, 64)
        XCTAssertTrue(digest.allSatisfy(\.isHexDigit))
    }
}
