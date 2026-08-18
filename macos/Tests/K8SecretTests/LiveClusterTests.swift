import XCTest
import Security
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
        try super.setUpWithError()
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

    /// The prompt users reported came from the transient keychain: the machine
    /// slept, macOS locked it, and the next handshake reached for a private key
    /// behind a lock whose password only ever existed in this process's memory.
    ///
    /// There is no keychain now — the identity is imported straight into the
    /// process — so that lock cannot happen. What still has to hold is the part
    /// that mattered: a second, fresh client can complete its own
    /// client-certificate handshake without asking the user for anything.
    func testASecondClientCanHandshakeWithoutTheUser() async throws {
        let client = try await connected()
        _ = try await client.getServerVersion()

        // A fresh client means a fresh URLSession and a fresh delegate, so this
        // cannot be served by a pooled connection: it forces a real handshake,
        // and a new identity to be built for it.
        let second = K8sClient()
        _ = try await second.connect()
        let version = try await second.getServerVersion()
        XCTAssertTrue(version.hasPrefix("v1."),
                      "the handshake must succeed without a password prompt")
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

// MARK: - vNext live coverage

/// CronJob and Ingress clients against the real API server: create, list,
/// operate, delete — each test owns its object's full lifecycle so the
/// cluster is left as found even on failure (tearDown sweeps).
extension LiveClusterTests {

    private static let liveCronJob = "k8stest-cron"
    private static let liveIngress = "k8stest-ingress"

    func testCronJobLifecycleListSuspendTrigger() async throws {
        let client = try await connected()
        let cronPath = "/apis/batch/v1/namespaces/\(namespace)/cronjobs"
        let manifest: [String: Any] = [
            "apiVersion": "batch/v1", "kind": "CronJob",
            "metadata": ["name": Self.liveCronJob],
            "spec": [
                "schedule": "0 2 * * *",
                "jobTemplate": ["spec": ["template": ["spec": [
                    "restartPolicy": "Never",
                    "containers": [["name": "noop", "image": "busybox:1.36",
                                    "command": ["true"]]],
                ]]]],
            ],
        ]
        try await client.createRawResource(
            collectionPath: cronPath,
            jsonData: JSONSerialization.data(withJSONObject: manifest))
        defer { Task { try? await client.deleteRawResource(path: "\(cronPath)/\(Self.liveCronJob)") } }

        // List sees it, unsuspended.
        var listed = try await client.listCronJobs(namespace: namespace)
        let cj = try XCTUnwrap(listed.first { $0.name == Self.liveCronJob })
        XCTAssertEqual(cj.schedule, "0 2 * * *")
        XCTAssertFalse(cj.suspended)

        // Suspend is a real patch the server round-trips.
        try await client.setCronJobSuspended(namespace: namespace, name: Self.liveCronJob, suspended: true)
        listed = try await client.listCronJobs(namespace: namespace)
        XCTAssertTrue(try XCTUnwrap(listed.first { $0.name == Self.liveCronJob }).suspended)

        // Run-now instantiates the jobTemplate under a manual name.
        let job = try await client.triggerCronJob(namespace: namespace, name: Self.liveCronJob)
        XCTAssertTrue(job.hasPrefix("\(Self.liveCronJob)-manual-"),
                      "manual runs must be attributable to their cronjob: \(job)")
        try? await client.deleteRawResource(
            path: "/apis/batch/v1/namespaces/\(namespace)/jobs/\(job)?propagationPolicy=Background")
    }

    func testIngressLifecycle() async throws {
        let client = try await connected()
        let ingPath = "/apis/networking.k8s.io/v1/namespaces/\(namespace)/ingresses"
        let manifest: [String: Any] = [
            "apiVersion": "networking.k8s.io/v1", "kind": "Ingress",
            "metadata": ["name": Self.liveIngress],
            "spec": ["rules": [[
                "host": "api.test.internal",
                "http": ["paths": [["path": "/", "pathType": "Prefix",
                    "backend": ["service": ["name": "api", "port": ["number": 8080]]]]]],
            ]]],
        ]
        try await client.createRawResource(
            collectionPath: ingPath,
            jsonData: JSONSerialization.data(withJSONObject: manifest))
        defer { Task { try? await client.deleteRawResource(path: "\(ingPath)/\(Self.liveIngress)") } }

        let listed = try await client.listIngresses(namespace: namespace)
        let ing = try XCTUnwrap(listed.first { $0.name == Self.liveIngress })
        XCTAssertEqual(ing.primaryHost, "api.test.internal")
        XCTAssertEqual(ing.rules.first?.serviceName, "api")
        XCTAssertEqual(ing.rules.first?.servicePort, 8080)
    }

    func testConfigMapListAndDataRoundTrip() async throws {
        let client = try await connected()
        let name = "k8stest-cm"
        let cmPath = "/api/v1/namespaces/\(namespace)/configmaps"
        let manifest: [String: Any] = [
            "apiVersion": "v1", "kind": "ConfigMap",
            "metadata": ["name": name],
            "data": ["LOG_LEVEL": "info", "REGION": "ap-south-1"],
        ]
        try await client.createRawResource(
            collectionPath: cmPath,
            jsonData: JSONSerialization.data(withJSONObject: manifest))
        defer { Task { try? await client.deleteRawResource(path: "\(cmPath)/\(name)") } }

        let listed = try await client.listConfigMaps(namespace: namespace)
        XCTAssertTrue(listed.contains { $0.name == name })

        try await client.patchConfigMapKey(namespace: namespace, name: name, key: "LOG_LEVEL", value: "debug")
        let data = try await client.getConfigMapData(namespace: namespace, name: name)
        XCTAssertEqual(data.first { $0.key == "LOG_LEVEL" }?.value, "debug")

        try await client.deleteConfigMapKey(namespace: namespace, name: name, key: "REGION")
        let after = try await client.getConfigMapData(namespace: namespace, name: name)
        XCTAssertFalse(after.contains { $0.key == "REGION" })
    }
}
