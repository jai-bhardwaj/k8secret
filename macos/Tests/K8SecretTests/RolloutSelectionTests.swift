import XCTest
@testable import K8Secret

/// Selection ownership while a rollout is being watched.
///
/// Scaling a deployment starts a poll that runs for up to three minutes, pinned
/// to the deployment that was scaled. Nothing stopped that poll from writing to
/// `selectedDeployment` after the user had moved on, so clicking a different
/// deployment mid-rollout yanked them back to the one that was scaling.
///
/// Live because the rollout poll only reaches its assignment after a real
/// `getDeployment` returns. Skipped unless `K8SECRET_LIVE=1`; expects the
/// `payments` namespace with an `api` deployment. See LiveClusterTests.
@MainActor
final class RolloutSelectionTests: PromptFreeTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        guard ProcessInfo.processInfo.environment["K8SECRET_LIVE"] == "1" else {
            throw XCTSkip("K8SECRET_LIVE not set — skipping live rollout tests")
        }
    }

    /// Only identity matters in these tests — the question is which deployment
    /// owns the selection and the banner, not what its status says.
    private func deployment(named name: String) -> K8sDeployment {
        K8sDeployment(
            id: "payments/\(name)", name: name, namespace: "payments",
            replicas: 1, readyReplicas: 1, availableReplicas: 1, updatedReplicas: 1,
            images: [], strategy: "RollingUpdate", createdAt: Date(),
            labels: [:], conditions: []
        )
    }

    /// The deployment the user has moved on to.
    private func otherDeployment() -> K8sDeployment { deployment(named: "other") }

    private func connectedState() async throws -> AppState {
        let s = AppState()
        await s.connect()
        s.selectedNamespace = K8sNamespace(id: "payments", name: "payments", status: "Active")
        return s
    }

    func testRolloutPollDoesNotStealSelection() async throws {
        let s = try await connectedState()

        // Watch a rollout of payments/api, exactly as scaling it does.
        s.startRolloutPolling(deploymentId: "payments/api")

        // The user clicks a different deployment while it is still rolling out.
        let other = otherDeployment()
        s.selectedDeployment = other

        // The poll sleeps 3s before its first tick, then fetches. Wait past that
        // so at least one tick has had the chance to write.
        try await Task.sleep(for: .seconds(6))

        XCTAssertEqual(
            s.selectedDeployment?.id, other.id,
            "rollout poll for payments/api overwrote a selection the user had moved off"
        )

        s.stopRolloutPolling()
    }

    /// The banner belongs to the deployment being rolled out, not to whatever is
    /// on screen. The poll keeps running once the user clicks away — the rollout
    /// is still happening and its completion is still worth reporting — but the
    /// banner goes with the deployment it describes.
    func testRolloutBannerFollowsTheDeploymentNotTheScreen() async throws {
        let s = try await connectedState()

        s.startRolloutPolling(deploymentId: "payments/api")
        XCTAssertTrue(s.rollingOut)

        // On the rolling-out deployment: banner belongs on screen.
        s.selectedDeployment = deployment(named: "api")
        XCTAssertTrue(s.showsRolloutBanner)

        // Clicked away: the rollout continues, but this pane isn't about it.
        s.selectedDeployment = otherDeployment()
        XCTAssertTrue(s.rollingOut, "the rollout itself is still in flight")
        XCTAssertFalse(
            s.showsRolloutBanner,
            "banner claimed a deployment the user is no longer looking at"
        )

        // And it stays gone as ticks land.
        try await Task.sleep(for: .seconds(6))
        XCTAssertFalse(s.showsRolloutBanner)

        s.stopRolloutPolling()
    }

    // MARK: - The same race in the shared loaders

    /// `loadEvents` backs all three detail panes, so a late reply lands wherever
    /// the user happens to be. Started for `api`, answered while `other` is
    /// selected: the events must not be adopted.
    func testEventsFetchedForOneResourceDoNotLandOnAnother() async throws {
        let s = try await connectedState()

        s.selectedDeployment = deployment(named: "other")
        s.events = []

        // Fetch events for `api` while `other` is what's on screen.
        await s.loadEvents(for: "Deployment", name: "api")

        XCTAssertTrue(
            s.events.isEmpty,
            "events for api were written while other was selected"
        )
    }

    /// The guard is only useful if it still lets the normal case through.
    func testEventsLandWhenTheResourceIsStillSelected() async throws {
        let s = try await connectedState()

        s.selectedDeployment = deployment(named: "api")
        await s.loadEvents(for: "Deployment", name: "api")

        // Whether `api` currently has events is up to the cluster; what matters
        // is that the guard admitted the reply rather than dropping it.
        XCTAssertTrue(
            s.isStillSelected(kind: "Deployment", name: "api", namespace: "payments"),
            "guard rejected the resource that is actually selected"
        )
    }

    /// Namespace-scoped loads race too: switch namespace mid-list and the slower
    /// reply used to repopulate the list for the namespace you just left.
    func testListLoadDoesNotWriteAfterNamespaceChanged() async throws {
        let s = try await connectedState()
        s.selectedResourceType = .deployments
        s.deployments = []

        // The race has three orderings and only one proves anything:
        //   (a) switch before the load captures its namespace — it lists
        //       `default`, returns nothing, proves nothing;
        //   (b) switch while the reply is in flight — the guard must drop it;
        //   (c) reply lands before the switch — a legitimate write,
        //       indistinguishable from the bug after the fact.
        // (c) is why this test flaked: on a fast local cluster the reply can
        // beat a fixed sleep. Detect it — deployments already populated at the
        // moment of the switch — and retry until an attempt is conclusive.
        var conclusive = false
        for _ in 0..<8 where !conclusive {
            s.selectedNamespace = K8sNamespace(id: "p", name: "payments", status: "Active")
            s.deployments = []
            let load = Task { await s.loadResourcesForCurrentType(restartWatch: false) }
            try await Task.sleep(for: .milliseconds(2))
            let repliedEarly = !s.deployments.isEmpty
            s.selectedNamespace = K8sNamespace(id: "default", name: "default", status: "Active")
            await load.value
            if repliedEarly { continue }        // case (c): inconclusive, go again
            conclusive = true
            XCTAssertTrue(
                s.deployments.isEmpty,
                "payments deployments were written after the user moved to default"
            )
        }
        XCTAssertTrue(conclusive, "8 attempts and the reply always beat the switch — raise the sleep")
    }
}
