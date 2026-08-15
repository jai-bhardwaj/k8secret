import XCTest
@testable import K8Secret

/// Confirmations must survive being triggered twice.
///
/// The replica field commits on Return *and* on losing focus — and pressing
/// Return moves focus to the confirmation dialog, so a single edit fired both.
/// The second request overwrote the pending dialog, so the user saw a
/// confirmation appear twice and whichever one they answered acted on a request
/// they had not read. Any double-firing control reaches this same code, so the
/// guard belongs here rather than in one view.
@MainActor
final class ConfirmationDedupeTests: XCTestCase {

    private func state() -> AppState {
        let s = AppState()
        s.context = "staging"
        return s
    }

    func testASecondConfirmationDoesNotReplaceAPendingOne() {
        let s = state()
        s.confirm(title: "First", message: "first", confirmLabel: "Do it") {}
        s.confirm(title: "Second", message: "second", confirmLabel: "Do it") {}

        XCTAssertEqual(s.confirmAction?.title, "First",
                       "the request the user initiated is the one that should be showing")
    }

    func testAnsweringOneRestoresTheAbilityToAsk() {
        let s = state()
        s.confirm(title: "First", message: "first", confirmLabel: "Do it") {}
        s.confirmAction = nil   // user answered or cancelled

        s.confirm(title: "Second", message: "second", confirmLabel: "Do it") {}
        XCTAssertEqual(s.confirmAction?.title, "Second")
    }

    func testDoubleSubmittingAScaleAsksOnce() {
        // What actually happened: Return committed, the dialog took focus, the
        // blur handler committed the same edit again.
        let s = state()
        let dep = K8sDeployment(
            id: "ns/api", name: "api", namespace: "ns", replicas: 2,
            readyReplicas: 2, availableReplicas: 2, updatedReplicas: 2,
            images: [], strategy: "RollingUpdate", createdAt: Date(),
            labels: [:], conditions: []
        )

        s.requestScale(dep, to: 100)
        let first = s.confirmAction
        s.requestScale(dep, to: 100)

        XCTAssertNotNil(first)
        XCTAssertEqual(s.confirmAction?.id, first?.id, "the same dialog, not a replacement")
    }

    func testDoubleDeleteRequestAsksOnce() {
        // The guard is app-wide, so any confirmed action benefits.
        let s = state()
        s.confirm(title: "Delete pod", message: "gone forever", confirmLabel: "Delete") {}
        let first = s.confirmAction
        s.confirm(title: "Delete pod", message: "gone forever", confirmLabel: "Delete") {}

        XCTAssertEqual(s.confirmAction?.id, first?.id)
    }
}
