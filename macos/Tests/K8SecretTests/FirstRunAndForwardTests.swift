import XCTest
@testable import K8Secret

/// What a fresh install lands on.
///
/// Opening the app showed two side-by-side placeholders — "Select a Namespace"
/// next to "Select a Deployment" — even when the kubeconfig said exactly which
/// namespace the current context works in. That field was parsed and then never
/// read, so the first impression of the app was an empty window asking the user
/// to go find their own data.
@MainActor
final class InitialNamespaceTests: XCTestCase {

    private func namespaces(_ names: [String]) -> [K8sNamespace] {
        names.map { K8sNamespace(id: $0, name: $0, status: "Active") }
    }

    func testPrefersTheNamespaceNamedByTheContext() {
        let s = AppState()
        s.namespaces = namespaces(["default", "kube-system", "payments"])

        XCTAssertEqual(s.initialNamespaceChoice(preferred: "payments")?.name, "payments")
    }

    func testFallsBackToDefaultWhenTheContextNamesNone() {
        let s = AppState()
        s.namespaces = namespaces(["kube-system", "default", "payments"])

        XCTAssertEqual(s.initialNamespaceChoice(preferred: nil)?.name, "default")
    }

    func testFallsBackToDefaultWhenTheNamedNamespaceIsGone() {
        // A context can name a namespace that has since been deleted.
        let s = AppState()
        s.namespaces = namespaces(["default", "kube-system"])

        XCTAssertEqual(s.initialNamespaceChoice(preferred: "deleted-ns")?.name, "default")
    }

    func testFallsBackToTheFirstNamespaceWhenThereIsNoDefault() {
        let s = AppState()
        s.namespaces = namespaces(["alpha", "beta"])

        XCTAssertEqual(s.initialNamespaceChoice(preferred: nil)?.name, "alpha")
    }

    func testChoosesNothingWhenThereAreNoNamespaces() {
        let s = AppState()
        XCTAssertNil(s.initialNamespaceChoice(preferred: "payments"))
    }

    func testNeverOverridesAnExistingSelection() {
        // Only ever runs on a fresh connect; it must not yank the user elsewhere.
        let s = AppState()
        s.namespaces = namespaces(["default", "payments"])
        s.selectedNamespace = s.namespaces.first { $0.name == "payments" }

        XCTAssertFalse(s.shouldSelectInitialNamespace)
    }

    func testSelectsWhenNothingIsChosenYet() {
        let s = AppState()
        s.namespaces = namespaces(["default"])
        XCTAssertTrue(s.shouldSelectInitialNamespace)
    }
}

/// Port forwarding, which is the app's most side-effecting feature: it spawns a
/// process and opens a browser.
@MainActor
final class PortForwardIdentityTests: XCTestCase {

    private func forward(context: String, namespace: String, target: String, port: Int) -> PortForward {
        PortForward(context: context, namespace: namespace, target: target,
                    displayName: target, remotePort: port, localPort: 18080)
    }

    func testForwardsInDifferentClustersAreNotTheSameForward() {
        // `svc/api` exists in almost every cluster. Matching on name and port alone
        // meant a second window could show — and open — the other cluster's tunnel.
        let staging = forward(context: "staging", namespace: "payments", target: "svc/api", port: 80)
        let production = forward(context: "prod", namespace: "payments", target: "svc/api", port: 80)

        XCTAssertFalse(staging.matches(production))
    }

    func testForwardsInDifferentNamespacesAreNotTheSameForward() {
        let a = forward(context: "prod", namespace: "payments", target: "svc/api", port: 80)
        let b = forward(context: "prod", namespace: "billing", target: "svc/api", port: 80)

        XCTAssertFalse(a.matches(b))
    }

    func testSameTargetInSamePlaceIsTheSameForward() {
        let a = forward(context: "prod", namespace: "payments", target: "svc/api", port: 80)
        let b = forward(context: "prod", namespace: "payments", target: "svc/api", port: 80)

        XCTAssertTrue(a.matches(b))
    }

    func testDifferentPortsOnTheSameServiceAreDistinct() {
        let http = forward(context: "prod", namespace: "payments", target: "svc/api", port: 80)
        let metrics = forward(context: "prod", namespace: "payments", target: "svc/api", port: 9090)

        XCTAssertFalse(http.matches(metrics))
    }

    func testBrowserOpensOnceEvenThoughKubectlAnnouncesReadinessTwice() {
        // kubectl prints a readiness line per address family:
        //   Forwarding from 127.0.0.1:18080 -> 80
        //   Forwarding from [::1]:18080 -> 80
        // The stdout handler runs per chunk, so both were treated as "ready" and
        // each opened a tab — the two-tabs bug.
        var fwd = forward(context: "prod", namespace: "payments", target: "svc/api", port: 80)
        var opened = 0

        for _ in 0..<2 where !fwd.hasOpenedBrowser {
            fwd.hasOpenedBrowser = true
            opened += 1
        }

        XCTAssertEqual(opened, 1, "exactly one browser tab per forward")
    }

    func testLocalURLPointsAtTheLocalPort() {
        let fwd = forward(context: "prod", namespace: "payments", target: "svc/api", port: 80)
        XCTAssertEqual(fwd.localURL, "http://localhost:18080")
    }
}
