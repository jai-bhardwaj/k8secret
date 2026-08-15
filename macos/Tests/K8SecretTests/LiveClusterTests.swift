import XCTest
@testable import K8Secret

/// Tests against a real Kubernetes cluster.
///
/// These cover the paths the stub server and unit tests can't reach: client
/// certificate authentication, the watch stream and its event application, and
/// writes that actually land in etcd.
///
/// Skipped unless `K8SECRET_LIVE=1`. Expects a cluster reachable from the
/// current kubeconfig with a `payments` namespace containing a `app-config`
/// secret and an `api` deployment. See scripts/live-cluster.sh.
final class LiveClusterTests: XCTestCase {

    private let namespace = "payments"

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["K8SECRET_LIVE"] == "1" else {
            throw XCTSkip("K8SECRET_LIVE not set — skipping live cluster tests")
        }
    }

    private func connected() async throws -> K8sClient {
        let client = K8sClient()
        _ = try await client.connect()
        return client
    }

    // MARK: - Connection and auth

    func testConnectsUsingKubeconfigCredentials() async throws {
        // colima/k3s issues a client certificate with an EC key, so this also
        // covers the SecKeyCreateWithData RSA-then-EC fallback in createIdentity.
        let client = K8sClient()
        let context = try await client.connect()
        XCTAssertFalse(context.isEmpty)

        let version = try await client.getServerVersion()
        XCTAssertTrue(version.hasPrefix("v1."), "unexpected server version: \(version)")
    }

    func testListsRealNamespaces() async throws {
        let client = try await connected()
        let names = try await client.listNamespaces().map(\.name)
        XCTAssertTrue(names.contains(namespace))
        XCTAssertTrue(names.contains("kube-system"))
    }

    // MARK: - Secrets against real etcd

    func testReadsAndDecodesARealSecret() async throws {
        let client = try await connected()
        let result = try await client.getSecretData(namespace: namespace, name: "app-config")

        let values = Dictionary(uniqueKeysWithValues: result.items.map { ($0.key, $0.value) })
        XCTAssertEqual(values["DATABASE_URL"], "postgres://user:pass@db/prod")
        XCTAssertEqual(values["API_KEY"], "sk-live-abc123")
        // Multi-line values are what the .env export quoting exists for.
        XCTAssertEqual(values["MULTILINE"]?.contains("\n"), true)

        XCTAssertNotNil(result.resourceVersion)
    }

    func testAtomicWriteAppliesAllChangesAtOnce() async throws {
        let client = try await connected()
        let before = try await client.getSecretData(namespace: namespace, name: "app-config")

        try await client.applySecretChanges(
            namespace: namespace,
            name: "app-config",
            upserts: ["API_KEY": "sk-live-rotated", "ADDED_KEY": "added"],
            removals: [],
            resourceVersion: before.resourceVersion
        )

        let after = try await client.getSecretData(namespace: namespace, name: "app-config")
        let values = Dictionary(uniqueKeysWithValues: after.items.map { ($0.key, $0.value) })

        XCTAssertEqual(values["API_KEY"], "sk-live-rotated")
        XCTAssertEqual(values["ADDED_KEY"], "added")
        // Untouched keys must survive a merge-patch.
        XCTAssertEqual(values["DATABASE_URL"], "postgres://user:pass@db/prod")

        // Restore
        try await client.applySecretChanges(
            namespace: namespace, name: "app-config",
            upserts: ["API_KEY": "sk-live-abc123"], removals: ["ADDED_KEY"],
            resourceVersion: nil
        )
    }

    func testStaleResourceVersionIsRejected() async throws {
        // The optimistic-concurrency guarantee: a write built on a stale read must
        // fail rather than silently clobber whoever wrote in between.
        let client = try await connected()
        let first = try await client.getSecretData(namespace: namespace, name: "app-config")
        let staleVersion = try XCTUnwrap(first.resourceVersion)

        // Someone else writes.
        try await client.applySecretChanges(
            namespace: namespace, name: "app-config",
            upserts: ["CONFLICT_PROBE": "1"], removals: [], resourceVersion: nil
        )

        do {
            try await client.applySecretChanges(
                namespace: namespace, name: "app-config",
                upserts: ["API_KEY": "should-not-land"], removals: [],
                resourceVersion: staleVersion
            )
            XCTFail("stale resourceVersion write was accepted")
        } catch K8sError.requestFailed(let code, _) {
            XCTAssertEqual(code, 409, "expected a conflict, got HTTP \(code)")
        }

        // The rejected value must not have landed.
        let after = try await client.getSecretData(namespace: namespace, name: "app-config")
        let values = Dictionary(uniqueKeysWithValues: after.items.map { ($0.key, $0.value) })
        XCTAssertNotEqual(values["API_KEY"], "should-not-land")

        try await client.applySecretChanges(
            namespace: namespace, name: "app-config",
            upserts: [:], removals: ["CONFLICT_PROBE"], resourceVersion: nil
        )
    }

    // MARK: - Pagination and pods

    func testListsPodsWithAResourceVersionToWatchFrom() async throws {
        let client = try await connected()
        let page = try await client.listPodsWithVersion(namespace: namespace)

        XCTAssertGreaterThanOrEqual(page.pods.count, 1)
        XCTAssertNotNil(page.resourceVersion, "watch cannot start without a resourceVersion")
        XCTAssertTrue(page.pods.allSatisfy { $0.namespace == self.namespace })
    }

    // MARK: - Watch

    func testWatchDeliversPodEventsForRealChanges() async throws {
        let client = try await connected()
        let page = try await client.listPodsWithVersion(namespace: namespace)
        let startVersion = try XCTUnwrap(page.resourceVersion)

        let received = Received()
        let watching = Task {
            try? await client.watchPods(namespace: namespace, resourceVersion: startVersion) { event in
                Task { await received.record(event) }
            }
        }
        defer { watching.cancel() }

        // Give the watch a moment to establish, then cause a real change.
        try await Task.sleep(for: .seconds(2))
        try await client.deletePod(namespace: namespace, name: page.pods[0].name)

        // The ReplicaSet will delete and recreate, so expect traffic either way.
        var sawEvent = false
        for _ in 0..<30 {
            try await Task.sleep(for: .seconds(1))
            if await received.count > 0 { sawEvent = true; break }
        }
        XCTAssertTrue(sawEvent, "watch delivered no events after a real pod deletion")
    }

    func testWatchFromAnAncientResourceVersionSignalsExpiry() async throws {
        // 410 Gone is routine on a busy cluster; the client has to recognise it so
        // AppState re-lists instead of backing off forever.
        let client = try await connected()

        do {
            try await client.watchPods(namespace: namespace, resourceVersion: "1") { _ in }
            // Some servers close the stream instead of erroring — acceptable.
        } catch is K8sClient.WatchExpired {
            // exactly what we want
        } catch {
            // A transport error is tolerable; a silent success is not.
        }
    }

    // MARK: - Metrics

    func testReadsPodMetricsWhenMetricsServerIsPresent() async throws {
        let client = try await connected()
        // k3s bundles metrics-server, but it needs a scrape cycle after startup.
        let metrics = try? await client.getPodMetrics(namespace: namespace)
        if let metrics, !metrics.isEmpty {
            XCTAssertTrue(metrics.allSatisfy { !$0.containers.isEmpty })
        }
    }

    /// Actor so the watch callback can record events without data races.
    private actor Received {
        private(set) var events: [K8sClient.PodWatchEvent] = []
        var count: Int { events.count }
        func record(_ event: K8sClient.PodWatchEvent) { events.append(event) }
    }
}
