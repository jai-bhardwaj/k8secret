import XCTest
@testable import K8Secret

/// What a fresh install lands on.
///
/// Two rules, and the order matters. A kubeconfig context that names a
/// namespace wins, because that is the user's own `kubectl` setting stated
/// deliberately. Everything else opens on all namespaces: landing in `default`
/// was a guess dressed as a decision, and on most clusters `default` is the one
/// namespace with nothing in it — so the app's first screen showed an empty
/// cluster and the scope responsible sat in the titlebar corner.
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

    func testOpensOnAllNamespacesWhenTheContextNamesNone() {
        // `default` exists here and is deliberately not chosen: it is almost
        // always empty, and picking it is what made the app look broken on a
        // cluster that was working perfectly well.
        let s = AppState()
        s.namespaces = namespaces(["kube-system", "default", "payments"])

        XCTAssertNil(s.initialNamespaceChoice(preferred: nil),
                     "no namespace named by the context means every namespace")
    }

    func testOpensOnAllNamespacesWhenTheNamedNamespaceIsGone() {
        // A context can name a namespace that has since been deleted. Showing
        // the whole cluster is honest; silently substituting `default` is not.
        let s = AppState()
        s.namespaces = namespaces(["default", "kube-system"])

        XCTAssertNil(s.initialNamespaceChoice(preferred: "deleted-ns"))
    }

    func testDoesNotFallBackToWhicheverNamespaceHappensToBeFirst() {
        // API order is not a preference. Two users on the same cluster used to
        // land somewhere different depending on what the server listed first.
        let s = AppState()
        s.namespaces = namespaces(["alpha", "beta"])

        XCTAssertNil(s.initialNamespaceChoice(preferred: nil))
    }

    func testAllNamespacesCountsAsAChoiceAlready() {
        // Re-entering connect must not drag a user who is looking at the whole
        // cluster back into a single namespace.
        let s = AppState()
        s.namespaces = namespaces(["default", "payments"])
        s.allNamespaces = true

        XCTAssertFalse(s.shouldSelectInitialNamespace)
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
