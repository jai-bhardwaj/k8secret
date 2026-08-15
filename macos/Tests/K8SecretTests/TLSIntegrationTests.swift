import XCTest
@testable import K8Secret

/// End-to-end tests against a real TLS server, driving the real `K8sClient`.
///
/// The unit tests can't cover the thing that actually mattered most in this
/// codebase: whether a bad certificate is *refused*. That behaviour lives in
/// URLSession's trust evaluation, so proving it needs a real handshake.
///
/// Skipped unless `K8SECRET_TLS_LAB` points at a directory containing `ca.crt`
/// and `other.crt`, with a TLS server on `K8SECRET_TLS_PORT` presenting a
/// certificate signed by `ca.crt`. See `scripts/tls-lab.sh`.
final class TLSIntegrationTests: PromptFreeTestCase {

    private var lab: URL!
    private var port: String!
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let env = ProcessInfo.processInfo.environment
        guard let labPath = env["K8SECRET_TLS_LAB"] else {
            throw XCTSkip("K8SECRET_TLS_LAB not set — skipping TLS integration tests")
        }
        lab = URL(fileURLWithPath: labPath)
        port = env["K8SECRET_TLS_PORT"] ?? "8443"

        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tls-int-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // setUp may have thrown XCTSkip before tempDir was assigned, and these are
        // implicitly-unwrapped, so teardown has to tolerate the skipped case.
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
        unsetenv("KUBECONFIG")
        try super.tearDownWithError()
    }

    /// Write a kubeconfig pointing at the test server and make it the active one.
    private func useKubeconfig(caFile: String?, insecure: Bool = false) throws {
        var clusterLines = ["    server: https://localhost:\(port!)"]
        if let caFile {
            let data = try Data(contentsOf: lab.appendingPathComponent(caFile))
            clusterLines.append("    certificate-authority-data: \(data.base64EncodedString())")
        }
        if insecure {
            clusterLines.append("    insecure-skip-tls-verify: true")
        }

        let yaml = """
        apiVersion: v1
        kind: Config
        current-context: test
        clusters:
        - cluster:
        \(clusterLines.joined(separator: "\n"))
          name: test-cluster
        contexts:
        - context:
            cluster: test-cluster
            user: test-user
            namespace: payments
          name: test
        users:
        - name: test-user
          user:
            token: test-token
        """

        let path = tempDir.appendingPathComponent("config-\(UUID().uuidString).yaml")
        try yaml.write(to: path, atomically: true, encoding: .utf8)
        setenv("KUBECONFIG", path.path, 1)
    }

    // MARK: - The regression that matters

    func testRefusesAServerSignedByAnUnrelatedCA() async throws {
        // THE regression test for this branch. The old delegate evaluated the chain,
        // saw it fail, and called completionHandler(.useCredential, ...) anyway —
        // so this exact scenario silently succeeded and every secret was readable
        // by whoever held the other CA's key.
        try useKubeconfig(caFile: "other.crt")

        do {
            _ = try await K8sClient().connect()
            XCTFail("connected to a server whose certificate does not chain to the configured CA")
        } catch {
            // Any refusal is correct; assert it's a transport failure, not a 4xx.
            if case K8sError.requestFailed(let code, _) = error {
                XCTFail("expected the handshake to be refused, got HTTP \(code)")
            }
        }
    }

    func testConnectsWhenTheCertificateChainsToTheConfiguredCA() async throws {
        try useKubeconfig(caFile: "ca.crt")

        let context = try await K8sClient().connect()
        XCTAssertEqual(context, "test")
    }

    func testInsecureSkipTLSVerifyStillWorksAsAnExplicitOptIn() async throws {
        // A deliberate per-cluster opt-out the user wrote themselves. Failing closed
        // must not break it.
        try useKubeconfig(caFile: nil, insecure: true)

        let context = try await K8sClient().connect()
        XCTAssertEqual(context, "test")
    }

    func testRefusesWhenNoCAIsConfiguredAndTheCertIsSelfSigned() async throws {
        // No CA and no opt-out: the system trust store can't validate this server,
        // so the connection must be refused rather than falling through.
        try useKubeconfig(caFile: nil)

        do {
            _ = try await K8sClient().connect()
            XCTFail("connected to an untrusted server with no CA configured")
        } catch {
            // expected
        }
    }

    // MARK: - Real requests over the verified channel

    func testListsNamespacesOverTLS() async throws {
        try useKubeconfig(caFile: "ca.crt")
        let client = K8sClient()
        _ = try await client.connect()

        let namespaces = try await client.listNamespaces()
        XCTAssertEqual(namespaces.map(\.name).sorted(), ["default", "payments"])
    }

    func testReadsAndDecodesSecretDataWithItsResourceVersion() async throws {
        try useKubeconfig(caFile: "ca.crt")
        let client = K8sClient()
        _ = try await client.connect()

        let result = try await client.getSecretData(namespace: "payments", name: "app-config")

        XCTAssertEqual(result.resourceVersion, "424242")
        let values = Dictionary(uniqueKeysWithValues: result.items.map { ($0.key, $0.value) })
        XCTAssertEqual(values["DATABASE_URL"], "postgres://user:pass@db/prod")
        XCTAssertEqual(values["API_KEY"], "sk-live-abc123")
    }

    func testSecretWriteIsASingleConditionalMergePatch() async throws {
        try useKubeconfig(caFile: "ca.crt")
        let client = K8sClient()
        _ = try await client.connect()

        // Three staged changes used to mean three sequential PATCHes. The server
        // log is asserted separately by the harness; here we prove the call shape
        // succeeds and carries everything at once.
        try await client.applySecretChanges(
            namespace: "payments",
            name: "app-config",
            upserts: ["API_KEY": "sk-live-rotated", "NEW_KEY": "hello"],
            removals: ["DATABASE_URL"],
            resourceVersion: "424242"
        )
    }

    func testServerVersionOverTLS() async throws {
        try useKubeconfig(caFile: "ca.crt")
        let client = K8sClient()
        _ = try await client.connect()

        let version = try await client.getServerVersion()
        XCTAssertEqual(version, "v1.29")
    }
}
