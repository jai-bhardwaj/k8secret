import XCTest
@testable import K8Secret

/// How the UI behaves while data is arriving.
///
/// These are the states a user actually sees: first load, a refresh over content
/// that is already on screen, and a live stream that has stopped. Getting them
/// wrong doesn't crash anything — it just makes the app feel broken, which is why
/// none of it was caught before.
@MainActor
final class RefreshStateTests: XCTestCase {

    private func pod(_ name: String, phase: String = "Running") -> K8sPod {
        K8sPod(
            id: "ns/\(name)", name: name, namespace: "ns", phase: phase,
            readyCount: 1, totalCount: 1, restarts: 0, nodeName: "node",
            podIP: "10.0.0.1", hostIP: "10.0.0.2", createdAt: Date(),
            labels: [:], containers: [], ownerKind: "ReplicaSet", ownerName: "rs"
        )
    }

    // MARK: - First load vs refresh

    func testFirstLoadTakesOverTheView() {
        let s = AppState()
        s.selectedResourceType = .pods
        s.loadingPods = true

        XCTAssertTrue(s.isInitialLoad, "with nothing to show, the spinner should own the view")
        XCTAssertFalse(s.isRefreshing)
    }

    func testRefreshOverExistingContentDoesNotTakeOverTheView() {
        // The defect: every refresh replaced the list with a full-screen spinner
        // and rebuilt it, losing scroll position and flashing the rows.
        let s = AppState()
        s.selectedResourceType = .pods
        s.pods = [pod("api-1")]
        s.loadingPods = true

        XCTAssertFalse(s.isInitialLoad, "content is on screen; it must stay")
        XCTAssertTrue(s.isRefreshing, "the refresh should still be visible somewhere")
    }

    func testIdleShowsNeitherIndicator() {
        let s = AppState()
        s.selectedResourceType = .pods
        s.pods = [pod("api-1")]

        XCTAssertFalse(s.isInitialLoad)
        XCTAssertFalse(s.isRefreshing)
    }

    func testStatesTrackTheSelectedResourceType() {
        let s = AppState()
        s.deployments = [
            K8sDeployment(id: "ns/api", name: "api", namespace: "ns", replicas: 1,
                          readyReplicas: 1, availableReplicas: 1, updatedReplicas: 1,
                          images: [], strategy: "RollingUpdate", createdAt: Date(),
                          labels: [:], conditions: [])
        ]
        s.loadingDeployments = true
        s.loadingSecrets = true

        s.selectedResourceType = .deployments
        XCTAssertTrue(s.isRefreshing, "deployments have content, so this is a refresh")

        s.selectedResourceType = .secrets
        XCTAssertTrue(s.isInitialLoad, "secrets have none, so this is a first load")
    }

    // MARK: - Liveness

    func testWatchEventMarksDataFresh() {
        let s = AppState()
        s.liveUpdatesInterrupted = true

        s.apply(.added(pod("api-1")))

        XCTAssertNotNil(s.lastUpdated)
        XCTAssertFalse(s.liveUpdatesInterrupted, "a delivered event means the stream recovered")
    }

    func testFreshnessStampMovesForwardOnEachEvent() throws {
        let s = AppState()
        s.apply(.added(pod("api-1")))
        let first = try XCTUnwrap(s.lastUpdated)

        s.apply(.modified(pod("api-1", phase: "Pending")))
        let second = try XCTUnwrap(s.lastUpdated)

        XCTAssertGreaterThanOrEqual(second, first)
    }

    func testBookmarkStillCountsAsLiveness() {
        // A bookmark carries no data but does prove the stream is alive; treating
        // it as silence would show "stale" on a quiet namespace.
        let s = AppState()
        s.apply(.bookmark("12345"))
        XCTAssertNotNil(s.lastUpdated)
    }

    // MARK: - Selection is not disturbed by updates

    func testUpdatingTheSelectedPodKeepsItSelected() {
        // Selection handlers are keyed on id now. A status change rewrites the
        // selected value, and reacting to that as a new selection wiped the log
        // pane and refetched events while the user was reading them.
        let s = AppState()
        s.apply(.added(pod("api-1", phase: "Pending")))
        s.selectedPod = s.pods.first
        let idBefore = s.selectedPod?.id

        s.apply(.modified(pod("api-1", phase: "Running")))

        XCTAssertEqual(s.selectedPod?.id, idBefore, "identity is unchanged")
        XCTAssertEqual(s.selectedPod?.phase, "Running", "but the value is current")
    }

    func testDeletingTheSelectedPodClearsSelection() {
        let s = AppState()
        s.apply(.added(pod("api-1")))
        s.selectedPod = s.pods.first

        s.apply(.deleted(pod("api-1")))
        XCTAssertNil(s.selectedPod, "the detail pane must not show a pod that is gone")
    }
}
