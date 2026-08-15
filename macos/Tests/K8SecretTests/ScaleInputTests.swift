import XCTest
@testable import K8Secret

/// Scaling is the app's most consequential everyday action, and now that the
/// count can be typed the failure modes changed: a typo is a scheduling decision.
@MainActor
final class ScaleInputTests: XCTestCase {

    private func deployment(replicas: Int) -> K8sDeployment {
        K8sDeployment(
            id: "ns/api", name: "api", namespace: "ns",
            replicas: replicas, readyReplicas: replicas,
            availableReplicas: replicas, updatedReplicas: replicas,
            images: ["nginx:alpine"], strategy: "RollingUpdate",
            createdAt: Date(), labels: [:], conditions: []
        )
    }

    private func state(context: String = "staging") -> AppState {
        let s = AppState()
        s.context = context
        return s
    }

    // MARK: - What asks first

    func testScalingToZeroAsks() {
        let s = state()
        s.requestScale(deployment(replicas: 3), to: 0)

        let action = s.confirmAction
        XCTAssertNotNil(action)
        XCTAssertTrue(action?.destructive == true)
        XCTAssertEqual(action?.confirmLabel, "Stop")
    }

    func testALargeIncreaseAsks() {
        // 2 -> 100 is the case that motivated the typed field; it is also what
        // "2" with an extra keystroke looks like.
        let s = state()
        s.requestScale(deployment(replicas: 2), to: 100)

        let message = s.confirmAction?.message
        XCTAssertNotNil(s.confirmAction, "a jump of 98 pods should confirm")
        XCTAssertEqual(message?.contains("98 more pods"), true, "say what it costs: \(message ?? "nil")")
    }

    func testASmallIncreaseDoesNotAsk() {
        // Nudging 2 -> 3 is routine; prompting on it trains people to dismiss.
        let s = state()
        s.requestScale(deployment(replicas: 2), to: 3)
        XCTAssertNil(s.confirmAction)
    }

    func testScalingDownDoesNotAskUnlessItReachesZero() {
        let s = state()
        s.requestScale(deployment(replicas: 10), to: 4)
        XCTAssertNil(s.confirmAction, "reducing capacity is reversible and not a big jump")
    }

    func testAnyScaleOnProductionAsks() {
        let s = state(context: "prod-us-east-1")
        s.requestScale(deployment(replicas: 2), to: 3)

        XCTAssertNotNil(s.confirmAction)
        XCTAssertEqual(s.confirmAction?.message.contains("looks like production"), true)
    }

    func testTheBoundaryOfALargeJump() {
        // +4 goes through, +5 asks. Pinning it so the threshold can't drift
        // unnoticed.
        let below = state()
        below.requestScale(deployment(replicas: 1), to: 5)
        XCTAssertNil(below.confirmAction)

        let atThreshold = state()
        atThreshold.requestScale(deployment(replicas: 1), to: 6)
        XCTAssertNotNil(atThreshold.confirmAction)
    }

    func testStoppingNamesTheDeployment() {
        let s = state()
        s.requestScale(deployment(replicas: 4), to: 0)

        XCTAssertEqual(s.confirmAction?.title, "Stop api?")
        XCTAssertEqual(s.confirmAction?.message.contains("stop serving traffic"), true)
    }

    func testScalingAnAlreadyStoppedDeploymentUpIsNotTreatedAsShutdown() {
        // 0 -> 3 is a start, not a stop, and shouldn't be flagged destructive.
        let s = state()
        s.requestScale(deployment(replicas: 0), to: 3)
        XCTAssertNil(s.confirmAction, "starting a stopped deployment is routine")
    }
}
