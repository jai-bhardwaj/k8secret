import XCTest
@testable import K8Secret

/// Utilisation percentages drive the decision to scale or restart a workload, so
/// the unit conversions behind them need to be right.
final class MetricsTests: XCTestCase {

    private func pod(cpuRequest: String = "", cpuLimit: String = "",
                     memRequest: String = "", memLimit: String = "") -> K8sPod {
        K8sPod(
            id: "ns/pod", name: "pod", namespace: "ns", phase: "Running",
            readyCount: 1, totalCount: 1, restarts: 0, nodeName: "node",
            podIP: "10.0.0.1", hostIP: "10.0.0.2", createdAt: Date(), labels: [:],
            containers: [
                ContainerInfo(
                    name: "app", image: "app:1", ready: true, restarts: 0,
                    state: "running", stateReason: "",
                    cpuRequest: cpuRequest, cpuLimit: cpuLimit,
                    memRequest: memRequest, memLimit: memLimit
                )
            ],
            ownerKind: "ReplicaSet", ownerName: "rs"
        )
    }

    private func metrics(cpu: String, memory: String) -> PodMetrics {
        PodMetrics(name: "pod", containers: [ContainerMetrics(name: "app", cpu: cpu, memory: memory)])
    }

    // MARK: - CPU units

    func testParsesNanocores() {
        // metrics-server reports nanocores; 250_000_000n == 250m.
        XCTAssertEqual(metrics(cpu: "250000000n", memory: "0").cpuMillis, 250)
    }

    func testParsesMillicores() {
        XCTAssertEqual(metrics(cpu: "1500m", memory: "0").cpuMillis, 1500)
    }

    func testParsesWholeCores() {
        XCTAssertEqual(metrics(cpu: "2", memory: "0").cpuMillis, 2000)
    }

    // MARK: - Memory units

    func testParsesMemorySuffixes() {
        XCTAssertEqual(metrics(cpu: "0", memory: "1024Ki").memoryKi, 1024)
        XCTAssertEqual(metrics(cpu: "0", memory: "1Mi").memoryKi, 1024)
        XCTAssertEqual(metrics(cpu: "0", memory: "1Gi").memoryKi, 1024 * 1024)
    }

    // MARK: - Percentages

    func testCPUPercentAgainstRequests() {
        let usage = metrics(cpu: "500m", memory: "0")
        XCTAssertEqual(usage.cpuPercent(pod: pod(cpuRequest: "1")), 50)
    }

    func testCPUPercentAgainstLimits() {
        let usage = metrics(cpu: "500m", memory: "0")
        XCTAssertEqual(usage.cpuLimitPercent(pod: pod(cpuLimit: "2")), 25)
    }

    func testMemoryPercentAgainstRequests() {
        let usage = metrics(cpu: "0", memory: "512Mi")
        XCTAssertEqual(usage.memPercent(pod: pod(memRequest: "1Gi")), 50)
    }

    func testReturnsNilWhenNoRequestIsSet() {
        // A pod with no requests has no meaningful percentage — showing 0% or
        // dividing by zero would both be wrong.
        let usage = metrics(cpu: "500m", memory: "128Mi")
        XCTAssertNil(usage.cpuPercent(pod: pod()))
        XCTAssertNil(usage.memPercent(pod: pod()))
    }

    func testPercentageIsClampedForRunawayContainers() {
        let usage = metrics(cpu: "100", memory: "0")   // 100 cores against a 1m request
        XCTAssertEqual(usage.cpuPercent(pod: pod(cpuRequest: "1m")), 999)
    }

    // MARK: - Formatting

    func testFormatsTotals() {
        XCTAssertEqual(metrics(cpu: "250m", memory: "0").totalCPU, "250m")
        XCTAssertEqual(metrics(cpu: "2", memory: "0").totalCPU, "2.0 cores")
        XCTAssertEqual(metrics(cpu: "0", memory: "512Mi").totalMemory, "512Mi")
        XCTAssertEqual(metrics(cpu: "0", memory: "2Gi").totalMemory, "2.0Gi")
    }
}
