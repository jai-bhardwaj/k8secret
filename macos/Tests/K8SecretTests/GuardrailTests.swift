import XCTest
@testable import K8Secret

/// The production heuristic only ever *adds* a confirmation step, so a false
/// positive costs one click. A false negative is the expensive direction, which is
/// why the matching is deliberately generous about separators.
@MainActor
final class GuardrailTests: XCTestCase {

    private func state(context: String) -> AppState {
        let s = AppState()
        s.context = context
        return s
    }

    func testRecognisesCommonProductionContextNames() {
        for name in [
            "prod",
            "production",
            "prd",
            "live",
            "prod-us-east-1",
            "acme-prod",
            "eks-prod-cluster",
            "arn:aws:eks:us-east-1:1234:cluster/prod",
        ] {
            XCTAssertTrue(state(context: name).looksLikeProduction, "\(name) should read as production")
        }
    }

    func testIsCaseInsensitive() {
        XCTAssertTrue(state(context: "PROD").looksLikeProduction)
        XCTAssertTrue(state(context: "Acme-Production").looksLikeProduction)
    }

    func testDoesNotFlagNonProductionContexts() {
        for name in ["staging", "dev", "minikube", "docker-desktop", "test-cluster", "qa"] {
            XCTAssertFalse(state(context: name).looksLikeProduction, "\(name) should not read as production")
        }
    }

    func testDoesNotFlagSubstringMatches() {
        // "reproduction" and "prodigy" contain "prod" but aren't production clusters.
        XCTAssertFalse(state(context: "reproduction-tests").looksLikeProduction)
        XCTAssertFalse(state(context: "prodigy").looksLikeProduction)
    }

    func testEmptyContextIsNotProduction() {
        XCTAssertFalse(state(context: "").looksLikeProduction)
    }

    // MARK: - Scale confirmation routing

    func testScalingToZeroAsksForConfirmation() {
        let s = state(context: "staging")
        s.requestScale(deployment(replicas: 3), to: 0)

        let action = s.confirmAction
        XCTAssertNotNil(action, "taking a workload to zero must confirm")
        XCTAssertTrue(action?.destructive == true)
    }

    func testOrdinaryScaleUpDoesNotAsk() {
        // Prompting on every ±1 trains people to dismiss dialogs without reading.
        let s = state(context: "staging")
        s.requestScale(deployment(replicas: 3), to: 4)
        XCTAssertNil(s.confirmAction)
    }

    func testAnyScaleOnProductionAsks() {
        let s = state(context: "prod-us-east-1")
        s.requestScale(deployment(replicas: 3), to: 4)
        XCTAssertNotNil(s.confirmAction, "production scaling should confirm even when scaling up")
        XCTAssertEqual(s.confirmAction?.message.contains("looks like production"), true)
    }

    // MARK: - Secret save confirmation

    func testSaveConfirmationItemisesTheChanges() {
        let s = state(context: "staging")
        s.selectedSecret = K8sSecret(
            id: "ns/app-config", name: "app-config", namespace: "ns",
            type: "Opaque", createdAt: Date()
        )
        s.secretData = [K8sKeyValue(id: "OLD", key: "OLD", value: "x")]
        s.additions = ["NEW": "1"]
        s.deletions = ["OLD"]

        s.requestSaveChanges()

        let message = try? XCTUnwrap(s.confirmAction?.message)
        XCTAssertEqual(message?.contains("add 1"), true)
        XCTAssertEqual(message?.contains("delete 1"), true)
        // Deletions are unrecoverable, so they're named explicitly.
        XCTAssertEqual(message?.contains("OLD"), true)
        XCTAssertEqual(s.confirmAction?.destructive, true)
    }

    func testSaveWithNoChangesDoesNotPrompt() {
        let s = state(context: "staging")
        s.requestSaveChanges()
        XCTAssertNil(s.confirmAction)
    }

    // MARK: - Helpers

    private func deployment(replicas: Int) -> K8sDeployment {
        K8sDeployment(
            id: "ns/api", name: "api", namespace: "ns",
            replicas: replicas, readyReplicas: replicas,
            availableReplicas: replicas, updatedReplicas: replicas,
            images: ["api:1"], strategy: "RollingUpdate",
            createdAt: Date(), labels: [:], conditions: []
        )
    }
}
