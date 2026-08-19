import XCTest
@testable import K8Secret

/// The URL a list is fetched from, in one namespace or across the cluster.
///
/// This exists because all-namespaces is now where the app opens. Every list
/// used to be fetched per namespace and stitched together, which is correct but
/// costs one request per namespace — and the rail asks for seven lists at once,
/// so a 200-namespace cluster opened with 1,400 requests. Kubernetes publishes a
/// cluster-wide collection endpoint for each kind, which answers the same
/// question in one, and these pin that we build it correctly for every kind the
/// app lists.
final class CollectionPathTests: XCTestCase {

    // MARK: - Cluster-wide

    func testClusterWidePathsDropTheNamespaceSegment() {
        let cases: [(prefix: String, plural: String, expected: String)] = [
            ("/api/v1", "pods", "/api/v1/pods"),
            ("/api/v1", "secrets", "/api/v1/secrets"),
            ("/api/v1", "services", "/api/v1/services"),
            ("/api/v1", "configmaps", "/api/v1/configmaps"),
            ("/apis/apps/v1", "deployments", "/apis/apps/v1/deployments"),
            ("/apis/batch/v1", "cronjobs", "/apis/batch/v1/cronjobs"),
            ("/apis/batch/v1", "jobs", "/apis/batch/v1/jobs"),
            ("/apis/networking.k8s.io/v1", "ingresses", "/apis/networking.k8s.io/v1/ingresses"),
        ]
        for c in cases {
            XCTAssertEqual(
                K8sClient.collectionPath(c.prefix, c.plural, namespace: nil), c.expected,
                "\(c.plural) across the cluster")
        }
    }

    // MARK: - Scoped

    func testNamespacedPathsAreUnchanged() {
        XCTAssertEqual(K8sClient.collectionPath("/api/v1", "pods", namespace: "payments"),
                       "/api/v1/namespaces/payments/pods")
        XCTAssertEqual(K8sClient.collectionPath("/apis/apps/v1", "deployments", namespace: "kube-system"),
                       "/apis/apps/v1/namespaces/kube-system/deployments")
    }

    /// A namespace name reaches this from a kubeconfig, which the app does not
    /// control. Anything needing encoding must be encoded rather than pasted
    /// into a URL — and the cluster-wide form has no namespace to encode, so it
    /// cannot be reached this way at all.
    func testNamespaceNamesAreEncoded() {
        let path = K8sClient.collectionPath("/api/v1", "pods", namespace: "a b/../c")
        XCTAssertFalse(path.contains(" "), "a space would break the URL: \(path)")
        XCTAssertFalse(path.contains("/../"), "path traversal must not survive: \(path)")
        XCTAssertTrue(path.hasPrefix("/api/v1/namespaces/"), path)
    }

    /// The empty string is a namespace name, not an absence — it must not
    /// quietly become the cluster-wide endpoint, which would widen the scope of
    /// a read past what was asked for.
    func testEmptyNamespaceIsNotTreatedAsClusterWide() {
        let path = K8sClient.collectionPath("/api/v1", "secrets", namespace: "")
        XCTAssertEqual(path, "/api/v1/namespaces//secrets")
        XCTAssertNotEqual(path, K8sClient.collectionPath("/api/v1", "secrets", namespace: nil))
    }
}
