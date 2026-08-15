import XCTest
@testable import K8Secret

/// Kubeconfig handling is the app's front door — every one of these forms is
/// something a real tool writes by default, and each one used to fail silently.
final class KubeConfigTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kubeconfig-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    @discardableResult
    private func write(_ name: String, _ contents: String) throws -> String {
        let url = tempDir.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    private func load(_ paths: [String]) throws -> KubeConfig {
        setenv("KUBECONFIG", paths.joined(separator: ":"), 1)
        defer { unsetenv("KUBECONFIG") }
        return try KubeConfig.load()
    }

    // MARK: - KUBECONFIG merging

    func testMergesAllFilesInKubeconfigList() throws {
        let a = try write("a.yaml", """
        current-context: alpha
        clusters:
        - cluster:
            server: https://alpha.example.com
          name: alpha-cluster
        contexts:
        - context:
            cluster: alpha-cluster
            user: alpha-user
          name: alpha
        users:
        - name: alpha-user
          user:
            token: token-a
        """)

        let b = try write("b.yaml", """
        current-context: beta
        clusters:
        - cluster:
            server: https://beta.example.com
          name: beta-cluster
        contexts:
        - context:
            cluster: beta-cluster
            user: beta-user
          name: beta
        users:
        - name: beta-user
          user:
            token: token-b
        """)

        let config = try load([a, b])

        // Reading only the first path meant half your clusters silently vanished.
        XCTAssertEqual(config.contexts.count, 2)
        XCTAssertEqual(Set(config.contexts.map(\.name)), ["alpha", "beta"])
        XCTAssertEqual(config.clusters.count, 2)
        XCTAssertEqual(config.users.count, 2)
    }

    func testFirstFileWinsForDuplicateNamesAndCurrentContext() throws {
        let a = try write("a.yaml", """
        current-context: alpha
        clusters:
        - cluster:
            server: https://first.example.com
          name: shared
        contexts:
        - context:
            cluster: shared
            user: u
          name: alpha
        users:
        - name: u
          user:
            token: first
        """)

        let b = try write("b.yaml", """
        current-context: beta
        clusters:
        - cluster:
            server: https://second.example.com
          name: shared
        contexts:
        - context:
            cluster: shared
            user: u
          name: beta
        users:
        - name: u
          user:
            token: second
        """)

        let config = try load([a, b])

        XCTAssertEqual(config.currentContext, "alpha")
        XCTAssertEqual(config.clusters.first(where: { $0.name == "shared" })?.server,
                       "https://first.example.com")
        XCTAssertEqual(config.users.first(where: { $0.name == "u" })?.token, "first")
    }

    func testSkipsMissingFilesInTheList() throws {
        let real = try write("real.yaml", """
        current-context: only
        clusters:
        - cluster:
            server: https://only.example.com
          name: c
        contexts:
        - context:
            cluster: c
            user: u
          name: only
        users:
        - name: u
          user:
            token: t
        """)

        let config = try load([tempDir.appendingPathComponent("nope.yaml").path, real])
        XCTAssertEqual(config.currentContext, "only")
    }

    // MARK: - File-path credentials

    func testReadsCertificateAuthorityFromFilePath() throws {
        // minikube and kind write this form; only `-data` was supported before, so
        // those clusters ended up with no CA at all.
        let caPath = tempDir.appendingPathComponent("ca.crt").path
        try "CERTDATA".write(toFile: caPath, atomically: true, encoding: .utf8)

        let cfg = try write("c.yaml", """
        current-context: local
        clusters:
        - cluster:
            server: https://127.0.0.1:6443
            certificate-authority: \(caPath)
          name: local-cluster
        contexts:
        - context:
            cluster: local-cluster
            user: local-user
          name: local
        users:
        - name: local-user
          user:
            token: t
        """)

        let config = try load([cfg])
        XCTAssertEqual(config.activeCluster()?.certificateAuthorityData, Data("CERTDATA".utf8))
    }

    func testResolvesRelativeCredentialPathsAgainstTheConfigFile() throws {
        try "RELATIVE".write(to: tempDir.appendingPathComponent("ca.crt"),
                             atomically: true, encoding: .utf8)

        let cfg = try write("rel.yaml", """
        current-context: local
        clusters:
        - cluster:
            server: https://127.0.0.1:6443
            certificate-authority: ca.crt
          name: c
        contexts:
        - context:
            cluster: c
            user: u
          name: local
        users:
        - name: u
          user:
            token: t
        """)

        let config = try load([cfg])
        XCTAssertEqual(config.activeCluster()?.certificateAuthorityData, Data("RELATIVE".utf8))
    }

    func testInlineDataWinsOverFilePath() throws {
        let cfg = try write("both.yaml", """
        current-context: local
        clusters:
        - cluster:
            server: https://127.0.0.1:6443
            certificate-authority: /nonexistent/ca.crt
            certificate-authority-data: SU5MSU5F
          name: c
        contexts:
        - context:
            cluster: c
            user: u
          name: local
        users:
        - name: u
          user:
            token: t
        """)

        let config = try load([cfg])
        XCTAssertEqual(config.activeCluster()?.certificateAuthorityData, Data("INLINE".utf8))
    }

    // MARK: - tokenFile

    func testReadsTokenFile() throws {
        let tokenPath = tempDir.appendingPathComponent("token").path
        try "  projected-token\n".write(toFile: tokenPath, atomically: true, encoding: .utf8)

        let cfg = try write("tf.yaml", """
        current-context: local
        clusters:
        - cluster:
            server: https://127.0.0.1:6443
          name: c
        contexts:
        - context:
            cluster: c
            user: u
          name: local
        users:
        - name: u
          user:
            tokenFile: \(tokenPath)
        """)

        let config = try load([cfg])
        XCTAssertEqual(config.activeUser()?.token, "projected-token")
    }

    // MARK: - exec plugins

    func testParsesExecEnvironment() throws {
        let cfg = try write("exec.yaml", """
        current-context: eks
        clusters:
        - cluster:
            server: https://eks.example.com
          name: c
        contexts:
        - context:
            cluster: c
            user: u
          name: eks
        users:
        - name: u
          user:
            exec:
              command: aws
              args:
              - eks
              - get-token
              env:
              - name: AWS_PROFILE
                value: prod
              - name: AWS_REGION
                value: us-east-1
        """)

        let config = try load([cfg])
        let exec = try XCTUnwrap(config.activeUser()?.exec)

        XCTAssertEqual(exec.command, "aws")
        XCTAssertEqual(exec.args, ["eks", "get-token"])
        // env was hardcoded to nil, breaking every plugin needing AWS_PROFILE.
        XCTAssertEqual(exec.env?["AWS_PROFILE"], "prod")
        XCTAssertEqual(exec.env?["AWS_REGION"], "us-east-1")
    }

    // MARK: - Booleans and errors

    func testParsesInsecureSkipTLSVerify() throws {
        let cfg = try write("insecure.yaml", """
        current-context: local
        clusters:
        - cluster:
            server: https://127.0.0.1:6443
            insecure-skip-tls-verify: true
          name: c
        contexts:
        - context:
            cluster: c
            user: u
          name: local
        users:
        - name: u
          user:
            token: t
        """)

        XCTAssertEqual(try load([cfg]).activeCluster()?.insecureSkipTLSVerify, true)
    }

    func testDefaultsInsecureSkipTLSVerifyToFalse() throws {
        let cfg = try write("secure.yaml", """
        current-context: local
        clusters:
        - cluster:
            server: https://127.0.0.1:6443
          name: c
        contexts:
        - context:
            cluster: c
            user: u
          name: local
        users:
        - name: u
          user:
            token: t
        """)

        XCTAssertEqual(try load([cfg]).activeCluster()?.insecureSkipTLSVerify, false)
    }

    func testReportsAParseErrorRatherThanAnEmptyConfig() throws {
        // This used to surface downstream as "No current-context set", which sent
        // people looking in entirely the wrong place.
        let cfg = try write("junk.yaml", "just some text\nnot a kubeconfig\n")

        XCTAssertThrowsError(try load([cfg])) { error in
            guard case K8sError.configParse(let message) = error else {
                return XCTFail("expected configParse, got \(error)")
            }
            XCTAssertTrue(message.contains("junk.yaml"), "error should name the offending file")
        }
    }

    func testActiveContextResolvesClusterUserAndNamespace() throws {
        let cfg = try write("full.yaml", """
        current-context: prod
        clusters:
        - cluster:
            server: https://prod.example.com
          name: prod-cluster
        contexts:
        - context:
            cluster: prod-cluster
            user: prod-user
            namespace: payments
          name: prod
        users:
        - name: prod-user
          user:
            token: abc
        """)

        let config = try load([cfg])
        XCTAssertEqual(config.activeCluster()?.server, "https://prod.example.com")
        XCTAssertEqual(config.activeUser()?.token, "abc")
        XCTAssertEqual(config.activeNamespace(), "payments")
    }
}
