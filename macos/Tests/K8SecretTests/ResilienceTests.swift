import XCTest
@testable import K8Secret

/// Retry policy. Getting this wrong in either direction is costly: retrying a
/// permanent error just delays the message, and *not* retrying a throttle means
/// poll loops keep hammering an API server that already asked them to slow down.
final class RetryPolicyTests: XCTestCase {

    func testRetriesOnThrottling() {
        XCTAssertNotNil(K8sClient.retryDelay(for: .requestFailed(429, "too many requests"), attempt: 0))
    }

    func testRetriesOnServerErrors() {
        for code in [500, 502, 503, 504] {
            XCTAssertNotNil(K8sClient.retryDelay(for: .requestFailed(code, "boom"), attempt: 0),
                            "HTTP \(code) should be retried")
        }
    }

    func testRetriesOnNetworkErrors() {
        XCTAssertNotNil(K8sClient.retryDelay(for: .networkError("connection lost"), attempt: 0))
    }

    func testDoesNotRetryClientErrors() {
        // These will fail identically forever; retrying only delays the message.
        for code in [400, 401, 403, 404, 409, 422] {
            XCTAssertNil(K8sClient.retryDelay(for: .requestFailed(code, "nope"), attempt: 0),
                         "HTTP \(code) should not be retried")
        }
    }

    func testDoesNotRetryConfigurationErrors() {
        XCTAssertNil(K8sClient.retryDelay(for: .noConfig, attempt: 0))
        XCTAssertNil(K8sClient.retryDelay(for: .noContext, attempt: 0))
        XCTAssertNil(K8sClient.retryDelay(for: .authFailed("bad token"), attempt: 0))
        XCTAssertNil(K8sClient.retryDelay(for: .configParse("bad yaml"), attempt: 0))
    }

    func testBackoffGrowsWithAttempts() {
        let first = K8sClient.retryDelay(for: .networkError("x"), attempt: 0) ?? 0
        let later = K8sClient.retryDelay(for: .networkError("x"), attempt: 3) ?? 0
        XCTAssertGreaterThan(later, first)
    }

    func testBackoffIsCapped() {
        // Without a ceiling, exponential growth reaches absurd delays.
        for attempt in 0...12 {
            let delay = K8sClient.retryDelay(for: .networkError("x"), attempt: attempt) ?? 0
            XCTAssertLessThanOrEqual(delay, 16, "attempt \(attempt) delay \(delay) exceeded the cap")
        }
    }

    func testJitterVariesTheDelay() {
        // Identical delays would make parallel pollers retry in lockstep and
        // recreate the spike that caused the throttling in the first place.
        let samples = Set((0..<40).map { _ in K8sClient.retryDelay(for: .networkError("x"), attempt: 2) ?? 0 })
        XCTAssertGreaterThan(samples.count, 1, "backoff should be jittered")
    }

    func testHonoursServerRetryAfterHint() {
        XCTAssertEqual(K8sClient.retryAfterSeconds(in: "Too many requests, retry after 5"), 5)
        XCTAssertEqual(K8sClient.retryAfterSeconds(in: "please Retry After 3 seconds"), 3)
        XCTAssertNil(K8sClient.retryAfterSeconds(in: "no hint here"))
    }

    func testServerHintRaisesTheDelay() {
        let delay = K8sClient.retryDelay(for: .requestFailed(429, "retry after 7"), attempt: 0) ?? 0
        XCTAssertGreaterThanOrEqual(delay, 7, "a server-supplied hint should not be undercut")
    }
}

/// The log window renders continuously while lines arrive, so its bookkeeping has
/// to stay correct and cheap as the buffer churns.
@MainActor
final class LogBufferTests: XCTestCase {

    private func makeState() -> LogStreamState {
        LogStreamState(id: LogStreamID(context: "c", namespace: "n", pod: "p", container: ""))
    }

    func testCountsLevelsIncrementally() {
        let s = makeState()
        s.appendLine("ERROR something broke")
        s.appendLine("ERROR again")
        s.appendLine("INFO all good")

        XCTAssertEqual(s.levelCounts[.error], 2)
        XCTAssertEqual(s.levelCounts[.info], 1)
        XCTAssertNil(s.levelCounts[.debug])
    }

    func testTracksActivePodsWithoutRescanning() {
        let s = makeState()
        s.appendLine("a", podName: "pod-b")
        s.appendLine("b", podName: "pod-a")
        s.appendLine("c", podName: "pod-a")

        XCTAssertEqual(s.activePods, ["pod-a", "pod-b"])
    }

    func testBufferIsCappedAndReportsWhatItDropped() {
        let s = makeState()
        for i in 0..<12_000 { s.appendLine("INFO line \(i)") }

        XCTAssertLessThanOrEqual(s.lines.count, 11_000, "buffer must stay bounded")
        XCTAssertGreaterThan(s.droppedLines, 0, "truncation should be reported, not silent")
        // Total accounted for: what's held plus what was dropped.
        XCTAssertEqual(s.lines.count + s.droppedLines, 12_000)
    }

    func testLevelCountsStayConsistentAfterTrimming() {
        let s = makeState()
        for i in 0..<12_000 { s.appendLine("ERROR line \(i)") }

        // Counts are decremented as lines age out, so they describe the buffer.
        XCTAssertEqual(s.levelCounts[.error], s.lines.count)
    }

    func testUnfilteredViewReturnsTheBufferUntouched() {
        let s = makeState()
        for i in 0..<100 { s.appendLine("INFO line \(i)") }
        XCTAssertEqual(s.filteredLines.count, 100)
    }

    func testFiltersByLevel() {
        let s = makeState()
        s.appendLine("ERROR bad")
        s.appendLine("INFO fine")
        s.levelFilter = .error

        XCTAssertEqual(s.filteredLines.count, 1)
        XCTAssertTrue(s.filteredLines[0].text.contains("bad"))
    }

    func testFiltersBySearchTextCaseInsensitively() {
        let s = makeState()
        s.appendLine("INFO connected to database")
        s.appendLine("INFO serving traffic")
        s.search = "DATABASE"

        XCTAssertEqual(s.filteredLines.count, 1)
    }

    func testClearResetsAllBookkeeping() {
        let s = makeState()
        for i in 0..<12_000 { s.appendLine("ERROR line \(i)", podName: "p") }
        s.clear()

        XCTAssertTrue(s.lines.isEmpty)
        XCTAssertTrue(s.levelCounts.isEmpty)
        XCTAssertTrue(s.activePods.isEmpty)
        XCTAssertEqual(s.droppedLines, 0)
    }
}

/// Watch events mutate the pod list in place. Getting this wrong shows the user a
/// list that disagrees with their cluster, which is worse than showing a stale one.
@MainActor
final class PodWatchTests: XCTestCase {

    private func pod(_ name: String, phase: String = "Running") -> K8sPod {
        K8sPod(
            id: "ns/\(name)", name: name, namespace: "ns", phase: phase,
            readyCount: 1, totalCount: 1, restarts: 0, nodeName: "node",
            podIP: "10.0.0.1", hostIP: "10.0.0.2", createdAt: Date(),
            labels: [:], containers: [], ownerKind: "ReplicaSet", ownerName: "rs"
        )
    }

    func testAddedInsertsANewPod() {
        let s = AppState()
        s.apply(.added(pod("api-1")))
        XCTAssertEqual(s.pods.map(\.name), ["api-1"])
    }

    func testAddedForAKnownPodUpdatesRatherThanDuplicating() {
        // The server replays ADDED for existing objects when a watch restarts.
        let s = AppState()
        s.apply(.added(pod("api-1", phase: "Pending")))
        s.apply(.added(pod("api-1", phase: "Running")))

        XCTAssertEqual(s.pods.count, 1)
        XCTAssertEqual(s.pods.first?.phase, "Running")
    }

    func testModifiedUpdatesInPlace() {
        let s = AppState()
        s.apply(.added(pod("api-1", phase: "Pending")))
        s.apply(.modified(pod("api-1", phase: "Running")))

        XCTAssertEqual(s.pods.count, 1)
        XCTAssertEqual(s.pods.first?.phase, "Running")
    }

    func testDeletedRemovesThePod() {
        let s = AppState()
        s.apply(.added(pod("api-1")))
        s.apply(.added(pod("api-2")))
        s.apply(.deleted(pod("api-1")))

        XCTAssertEqual(s.pods.map(\.name), ["api-2"])
    }

    func testSelectionFollowsUpdates() {
        let s = AppState()
        s.apply(.added(pod("api-1", phase: "Pending")))
        s.selectedPod = s.pods.first

        s.apply(.modified(pod("api-1", phase: "Running")))
        XCTAssertEqual(s.selectedPod?.phase, "Running")
    }

    func testSelectionClearsWhenTheSelectedPodIsDeleted() {
        // Scaled down or evicted — the detail pane must not keep showing a pod
        // that no longer exists.
        let s = AppState()
        s.apply(.added(pod("api-1")))
        s.selectedPod = s.pods.first

        s.apply(.deleted(pod("api-1")))
        XCTAssertNil(s.selectedPod)
    }

    func testSelectionSurvivesUnrelatedChanges() {
        let s = AppState()
        s.apply(.added(pod("api-1")))
        s.apply(.added(pod("api-2")))
        s.selectedPod = s.pods.first(where: { $0.name == "api-1" })

        s.apply(.deleted(pod("api-2")))
        XCTAssertEqual(s.selectedPod?.name, "api-1")
    }

    func testBookmarkDoesNotChangeTheList() {
        let s = AppState()
        s.apply(.added(pod("api-1")))
        s.apply(.bookmark("12345"))

        XCTAssertEqual(s.pods.count, 1)
    }

    func testDeletingAnUnknownPodIsHarmless() {
        let s = AppState()
        s.apply(.added(pod("api-1")))
        s.apply(.deleted(pod("ghost")))

        XCTAssertEqual(s.pods.map(\.name), ["api-1"])
    }
}
