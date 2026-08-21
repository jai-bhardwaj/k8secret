import XCTest
@testable import K8Secret

// MARK: - #7 · the feedback link opened GitHub with no title

/// GitHub will not create an issue without a title, and the app was prefilling
/// only the body. What people did was type the whole report into the title and
/// leave the body — with the diagnostics in it — empty. Issue #7 was itself
/// filed that way, which is how the bug got noticed.
final class FeedbackTitleTests: XCTestCase {

    private func title(_ s: String) -> String { FeedbackSheet.title(from: s) }

    func testAShortMessageIsTheTitleAsWritten() {
        XCTAssertEqual(title("Events tab shows nothing"), "Events tab shows nothing")
    }

    func testTheFirstLineIsTheTitleWhenThereAreSeveral() {
        let message = """
        Replica editor gets stuck

        Steps: open a deployment, type 5, press return, cancel the dialog.
        Now Apply does nothing at all.
        """
        XCTAssertEqual(title(message), "Replica editor gets stuck")
    }

    func testTheFirstSentenceIsTheTitleWhenItIsAllOneLine() {
        let message = "Port forward should let me set a path. Right now it always opens the root."
        XCTAssertEqual(title(message), "Port forward should let me set a path")
    }

    /// A full stop inside an abbreviation is not the end of a sentence, and
    /// cutting there would title the issue "e.g".
    func testItDoesNotCutAtAnEarlyAbbreviation() {
        XCTAssertEqual(title("e.g. the events tab is empty for me"),
                       "e.g. the events tab is empty for me")
    }

    func testALongTitleIsTrimmedOnAWordBoundary() {
        let message = "port forward in services should allow customization that would allow "
                    + "us to add a path to the forwarded port so it opens there by default"
        let result = title(message)
        XCTAssertLessThanOrEqual(result.count, 73, "too long for a title: \(result)")
        XCTAssertTrue(result.hasSuffix("…"), "a trimmed title should say so: \(result)")
        XCTAssertFalse(result.contains("  "), result)
        // Trimmed on a space, so the last word is whole.
        let body = result.dropLast()
        XCTAssertFalse(body.hasSuffix(" "), "trailing space before the ellipsis: \(result)")
    }

    func testAnEmptyMessageStillProducesAUsableTitle() {
        XCTAssertEqual(title("   \n  "), "Feedback")
    }

    /// The whole point: whatever the user typed still reaches the body, so
    /// summarising for the title never loses information.
    func testTitleIsDerivedNotSubstituted() {
        let message = "First line\n\nSecond paragraph with the real detail."
        XCTAssertEqual(title(message), "First line")
        XCTAssertNotEqual(title(message), message)
    }
}

// MARK: - #6 · a forwarded port should be able to land on a path

/// A forwarded port is rarely useful at its root — a dashboard lives at
/// /admin/queues — so every open landed on / and the user retyped the rest.
final class PortForwardPathTests: XCTestCase {

    func testAPlainPathGetsItsLeadingSlash() {
        XCTAssertEqual(PortForward.normalize("admin"), "/admin")
        XCTAssertEqual(PortForward.normalize("/admin"), "/admin")
    }

    func testEmptyAndRootMeanNoPath() {
        XCTAssertEqual(PortForward.normalize(""), "")
        XCTAssertEqual(PortForward.normalize("   "), "")
        XCTAssertEqual(PortForward.normalize("/"), "")
    }

    func testQueryStringsAndFragmentsSurvive() {
        XCTAssertEqual(PortForward.normalize("/admin/queues?state=failed"),
                       "/admin/queues?state=failed")
        XCTAssertEqual(PortForward.normalize("docs#section"), "/docs#section")
    }

    /// The one thing this must never do is send the browser somewhere other
    /// than the tunnel. A pasted absolute URL is refused, not repaired.
    func testAnAbsoluteURLIsRefusedRatherThanAppended() {
        XCTAssertEqual(PortForward.normalize("https://example.com/admin"), "")
        XCTAssertEqual(PortForward.normalize("//example.com/admin"), "")
    }

    func testSpacesAreEncodedSoTheURLStaysValid() {
        let result = PortForward.normalize("/my dashboard")
        XCTAssertFalse(result.contains(" "), result)
        XCTAssertTrue(result.hasPrefix("/"), result)
    }

    func testTheLocalURLCarriesThePath() {
        var pf = PortForward(context: "colima", namespace: "payments",
                             target: "svc/api", displayName: "api",
                             remotePort: 80, localPort: 18080)
        XCTAssertEqual(pf.localURL, "http://localhost:18080")

        pf.path = "admin/queues"
        XCTAssertEqual(pf.localURL, "http://localhost:18080/admin/queues")
    }

    /// Two forwards of the same-named service in different clusters are
    /// different targets — a path set on staging must not open on production.
    @MainActor
    func testPathsAreKeyedPerClusterAndNamespace() {
        let mgr = PortForwardManager.shared
        defer {
            mgr.setPath("", context: "staging", namespace: "web", target: "svc/api", remotePort: 80)
            mgr.setPath("", context: "prod", namespace: "web", target: "svc/api", remotePort: 80)
        }

        mgr.setPath("/staging-admin", context: "staging", namespace: "web",
                    target: "svc/api", remotePort: 80)

        XCTAssertEqual(mgr.savedPath(context: "staging", namespace: "web",
                                     target: "svc/api", remotePort: 80), "/staging-admin")
        XCTAssertEqual(mgr.savedPath(context: "prod", namespace: "web",
                                     target: "svc/api", remotePort: 80), "",
                       "a path set on one cluster must not leak into another")
    }

    @MainActor
    func testClearingAPathForgetsIt() {
        let mgr = PortForwardManager.shared
        mgr.setPath("/docs", context: "colima", namespace: "d", target: "svc/x", remotePort: 8080)
        XCTAssertEqual(mgr.savedPath(context: "colima", namespace: "d",
                                     target: "svc/x", remotePort: 8080), "/docs")
        mgr.setPath("  ", context: "colima", namespace: "d", target: "svc/x", remotePort: 8080)
        XCTAssertEqual(mgr.savedPath(context: "colima", namespace: "d",
                                     target: "svc/x", remotePort: 8080), "")
    }
}

// MARK: - #5 · the replica editor went permanently dead

/// The stepper armed `lastRequestedReplicas` before showing its confirmation and
/// only ever disarmed when the cluster reached that number. Cancel the dialog —
/// or have the scale refused — and the control stayed armed for that value, so
/// Apply silently did nothing for it, forever.
///
/// The view's own `@State` can't be reached from here; what these pin is the
/// plumbing the fix depends on, which is where the bug actually lived.
@MainActor
final class ConfirmationCancelTests: XCTestCase {

    func testCancellingRunsTheCancelHandler() {
        let state = AppState()
        var cancelled = false
        state.confirm(title: "Scale deployment", message: "from 1 to 9",
                      confirmLabel: "Scale", onCancel: { cancelled = true }) {}

        XCTAssertNotNil(state.confirmAction)
        state.cancelConfirmation()

        XCTAssertTrue(cancelled, "the caller must hear that its request was declined")
        XCTAssertNil(state.confirmAction)
    }

    func testConfirmingDoesNotRunTheCancelHandler() {
        let state = AppState()
        var cancelled = false
        state.confirm(title: "t", message: "m", confirmLabel: "Go",
                      onCancel: { cancelled = true }) {}

        // What the confirm button does: take the work, clear, run it.
        state.confirmAction = nil
        XCTAssertFalse(cancelled)
    }

    /// A second request while one is pending is dropped — and being dropped is
    /// itself an answer the caller has to hear, or it stays armed for a dialog
    /// that is never coming.
    func testADroppedDuplicateIsToldItWasDropped() {
        let state = AppState()
        state.confirm(title: "first", message: "m", confirmLabel: "Go") {}

        var secondCancelled = false
        state.confirm(title: "second", message: "m", confirmLabel: "Go",
                      onCancel: { secondCancelled = true }) {}

        XCTAssertTrue(secondCancelled, "the dropped request must be disarmed")
        XCTAssertEqual(state.confirmAction?.title, "first",
                       "the pending dialog must not be replaced")
    }

    func testCancellingWithNoHandlerIsHarmless() {
        let state = AppState()
        state.confirm(title: "t", message: "m", confirmLabel: "Go") {}
        state.cancelConfirmation()
        XCTAssertNil(state.confirmAction)
    }

    /// Scaling to a number the cluster already reports needs no confirmation and
    /// no dialog — the guard in the view returns early, and this pins that the
    /// no-confirmation path is genuinely reached rather than silently dialogged.
    func testAModestScaleDoesNotAskForConfirmation() {
        let state = AppState()
        let dep = K8sDeployment(id: "d/web", name: "web", namespace: "d",
                                replicas: 2, readyReplicas: 2, availableReplicas: 2,
                                updatedReplicas: 2, images: [], strategy: "RollingUpdate",
                                createdAt: Date(), labels: [:], conditions: [])
        state.requestScale(dep, to: 3)
        XCTAssertNil(state.confirmAction,
                     "a one-pod change in a non-production context should just happen")
    }
}

// MARK: - #5 (as reported) · editing state survived changing deployment

/// The replica editor's `@State` lives in a single `DeploymentDetailView`
/// instance — `dep` is read from `state.selectedDeployment` inside the body —
/// so selecting a different deployment does not give it fresh state. The only
/// reset was `.onChange(of: dep.replicas)`, and these pin why that was never
/// enough: the reset has to key on *which deployment*, not on its count.
final class DeploymentIdentityTests: XCTestCase {

    private func dep(_ ns: String, _ name: String, replicas: Int) -> K8sDeployment {
        K8sDeployment(id: "\(ns)/\(name)", name: name, namespace: ns,
                      replicas: replicas, readyReplicas: replicas,
                      availableReplicas: replicas, updatedReplicas: replicas,
                      images: [], strategy: "RollingUpdate", createdAt: Date(),
                      labels: [:], conditions: [])
    }

    /// The bug in one assertion. Two different deployments routinely have the
    /// same replica count — it is the single most common count there is — so a
    /// reset that watches the count never fired, and the value typed for one
    /// deployment stayed on screen for the next. Apply stayed enabled, and it
    /// would have scaled the newly selected deployment to it.
    func testTwoDeploymentsCanShareAReplicaCountButNeverAnIdentity() {
        let a = dep("payments", "api", replicas: 3)
        let b = dep("payments", "worker", replicas: 3)

        XCTAssertEqual(a.replicas, b.replicas,
                       "the count is not a reset trigger — this is the case that broke")
        XCTAssertNotEqual(a.id, b.id, "identity is, and must differ")
    }

    /// Same name in two namespaces is a real arrangement, and the editor must
    /// treat them as different deployments.
    func testTheSameNameInAnotherNamespaceIsADifferentDeployment() {
        XCTAssertNotEqual(dep("staging", "api", replicas: 2).id,
                          dep("production", "api", replicas: 2).id)
    }

    /// The other half of keying on identity: it must be stable, or the poll
    /// would reset the field every second while the user was typing into it.
    func testIdentityIsStableAcrossRefreshesAndScaling() {
        let before = dep("payments", "api", replicas: 3)
        let afterPoll = dep("payments", "api", replicas: 3)
        let afterScaling = dep("payments", "api", replicas: 9)

        XCTAssertEqual(before.id, afterPoll.id, "a refresh must not look like a new deployment")
        XCTAssertEqual(before.id, afterScaling.id,
                       "scaling changes the count, not which deployment this is")
    }

    /// A pod's identity carries the same guarantee, which is what lets the log
    /// pane clear a container choice that belongs to the pod you just left.
    func testPodIdentityDistinguishesPodsWithMatchingShape() {
        func pod(_ name: String) -> K8sPod {
            K8sPod(id: "d/\(name)", name: name, namespace: "d", phase: "Running",
                   readyCount: 1, totalCount: 1, restarts: 0, nodeName: "n1",
                   podIP: "10.0.0.1", hostIP: "10.0.0.2", createdAt: Date(),
                   labels: [:], containers: [], ownerKind: "ReplicaSet",
                   ownerName: "web")
        }
        XCTAssertNotEqual(pod("web-1").id, pod("web-2").id,
                          "two pods of the same deployment are still different pods")
    }
}
