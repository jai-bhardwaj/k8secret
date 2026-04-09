import Foundation
import Security

enum K8sError: LocalizedError {
    case noConfig
    case noContext
    case noCluster
    case noUser
    case configParse(String)
    case authFailed(String)
    case requestFailed(Int, String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .noConfig: return "No kubeconfig found at ~/.kube/config"
        case .noContext: return "No current-context set in kubeconfig"
        case .noCluster: return "Cluster not found for current context"
        case .noUser: return "User not found for current context"
        case .configParse(let msg): return "Config parse error: \(msg)"
        case .authFailed(let msg): return "Auth failed: \(msg)"
        case .requestFailed(let code, let msg): return "HTTP \(code): \(msg)"
        case .networkError(let msg): return msg
        }
    }
}

// MARK: - Data types

struct K8sNamespace: Identifiable, Hashable {
    let id: String
    let name: String
    let status: String
}

struct K8sSecret: Identifiable, Hashable {
    let id: String
    let name: String
    let namespace: String
    let type: String
    let createdAt: Date

    var age: String { formatAge(createdAt) }
}

struct K8sKeyValue: Identifiable, Hashable {
    let id: String
    let key: String
    let value: String
}

struct K8sDeployment: Identifiable, Hashable {
    let id: String
    let name: String
    let namespace: String
    let replicas: Int
    let readyReplicas: Int
    let availableReplicas: Int
    let updatedReplicas: Int
    let images: [String]
    let strategy: String
    let createdAt: Date
    let labels: [String: String]
    let conditions: [DeploymentCondition]

    var status: DeploymentStatus {
        if availableReplicas == replicas && readyReplicas == replicas && replicas > 0 {
            return .running
        } else if updatedReplicas < replicas || readyReplicas < replicas {
            return .updating
        } else if replicas == 0 {
            return .scaled
        } else {
            return .degraded
        }
    }

    var age: String { formatAge(createdAt) }
}

struct DeploymentCondition: Hashable {
    let type: String
    let status: String
    let reason: String
    let message: String
    let lastTransition: Date?
}

enum DeploymentStatus { case running, updating, scaled, degraded }

struct K8sPod: Identifiable, Hashable {
    let id: String
    let name: String
    let namespace: String
    let phase: String
    let readyCount: Int
    let totalCount: Int
    let restarts: Int
    let nodeName: String
    let podIP: String
    let hostIP: String
    let createdAt: Date
    let labels: [String: String]
    let containers: [ContainerInfo]
    let ownerKind: String
    let ownerName: String

    var ready: String { "\(readyCount)/\(totalCount)" }
    var age: String { formatAge(createdAt) }

    var statusColor: String {
        switch phase.lowercased() {
        case "running": return readyCount == totalCount ? "green" : "yellow"
        case "succeeded": return "blue"
        case "pending": return "yellow"
        case "failed": return "red"
        default: return "gray"
        }
    }
}

struct ContainerInfo: Hashable {
    let name: String
    let image: String
    let ready: Bool
    let restarts: Int
    let state: String
    let stateReason: String
    let cpuRequest: String
    let cpuLimit: String
    let memRequest: String
    let memLimit: String
}

struct K8sService: Identifiable, Hashable {
    let id: String
    let name: String
    let namespace: String
    let type: String
    let clusterIP: String
    let externalIPs: [String]
    let ports: [ServicePort]
    let selector: [String: String]
    let createdAt: Date
    let labels: [String: String]

    var age: String { formatAge(createdAt) }
}

struct ServicePort: Hashable {
    let name: String
    let protocol_: String
    let port: Int
    let targetPort: String
    let nodePort: Int?

    var display: String {
        var s = "\(port)"
        if targetPort != "\(port)" { s += ":\(targetPort)" }
        if let np = nodePort { s += " → \(np)" }
        s += "/\(protocol_)"
        return s
    }
}

struct K8sConfigMap: Identifiable, Hashable {
    let id: String
    let name: String
    let namespace: String
    let dataCount: Int
    let createdAt: Date

    var age: String { formatAge(createdAt) }
}

struct K8sNode: Identifiable, Hashable {
    let id: String
    let name: String
    let status: String
    let roles: [String]
    let kubeletVersion: String
    let osImage: String
    let architecture: String
    let containerRuntime: String
    let internalIP: String
    let externalIP: String
    let podCIDR: String
    let capacityCPU: String
    let capacityMemory: String
    let capacityPods: String
    let allocatableCPU: String
    let allocatableMemory: String
    let allocatablePods: String
    let conditions: [NodeCondition]
    let taints: [NodeTaint]
    let labels: [String: String]
    let createdAt: Date
    let unschedulable: Bool

    var age: String { formatAge(createdAt) }

    var rolesDisplay: String {
        roles.isEmpty ? "worker" : roles.joined(separator: ", ")
    }
}

struct NodeCondition: Hashable {
    let type: String
    let status: String
    let reason: String
    let message: String
}

struct NodeTaint: Hashable {
    let key: String
    let value: String
    let effect: String
}

struct K8sEvent: Identifiable, Hashable {
    let id: String
    let type: String
    let reason: String
    let message: String
    let count: Int
    let firstSeen: Date?
    let lastSeen: Date?
    let source: String
}

struct PodMetrics: Hashable {
    let name: String
    let containers: [ContainerMetrics]

    var totalCPU: String {
        let total = containers.reduce(0) { $0 + parseCPU($1.cpu) }
        if total >= 1000 { return String(format: "%.1f", Double(total) / 1000) + " cores" }
        return "\(total)m"
    }

    var totalMemory: String {
        let totalKi = containers.reduce(0) { $0 + parseMem($1.memory) }
        if totalKi >= 1024 * 1024 { return String(format: "%.1fGi", Double(totalKi) / 1024 / 1024) }
        if totalKi >= 1024 { return String(format: "%.0fMi", Double(totalKi) / 1024) }
        return "\(totalKi)Ki"
    }

    var cpuMillis: Int {
        containers.reduce(0) { $0 + parseCPU($1.cpu) }
    }

    var memoryKi: Int {
        containers.reduce(0) { $0 + parseMem($1.memory) }
    }

    /// Calculate CPU utilization % against requests for a pod
    func cpuPercent(pod: K8sPod) -> Int? {
        let totalRequest = pod.containers.reduce(0) { $0 + parseCPU($1.cpuRequest) }
        guard totalRequest > 0 else { return nil }
        return min(999, cpuMillis * 100 / totalRequest)
    }

    /// Calculate Memory utilization % against requests for a pod
    func memPercent(pod: K8sPod) -> Int? {
        let totalRequest = pod.containers.reduce(0) { $0 + parseMem($1.memRequest) }
        guard totalRequest > 0 else { return nil }
        return min(999, memoryKi * 100 / totalRequest)
    }

    /// CPU % against limits
    func cpuLimitPercent(pod: K8sPod) -> Int? {
        let totalLimit = pod.containers.reduce(0) { $0 + parseCPU($1.cpuLimit) }
        guard totalLimit > 0 else { return nil }
        return min(999, cpuMillis * 100 / totalLimit)
    }

    /// Memory % against limits
    func memLimitPercent(pod: K8sPod) -> Int? {
        let totalLimit = pod.containers.reduce(0) { $0 + parseMem($1.memLimit) }
        guard totalLimit > 0 else { return nil }
        return min(999, memoryKi * 100 / totalLimit)
    }

    private func parseCPU(_ s: String) -> Int {
        if s.hasSuffix("n") { return (Int(s.dropLast()) ?? 0) / 1_000_000 }
        if s.hasSuffix("u") { return (Int(s.dropLast()) ?? 0) / 1_000 }
        if s.hasSuffix("m") { return Int(s.dropLast()) ?? 0 }
        return (Int(s) ?? 0) * 1000
    }

    private func parseMem(_ s: String) -> Int {
        if s.hasSuffix("Ki") { return Int(s.dropLast(2)) ?? 0 }
        if s.hasSuffix("Mi") { return (Int(s.dropLast(2)) ?? 0) * 1024 }
        if s.hasSuffix("Gi") { return (Int(s.dropLast(2)) ?? 0) * 1024 * 1024 }
        if s.hasSuffix("k") { return (Int(s.dropLast()) ?? 0) }
        if s.hasSuffix("M") { return (Int(s.dropLast()) ?? 0) * 1024 }
        if s.hasSuffix("G") { return (Int(s.dropLast()) ?? 0) * 1024 * 1024 }
        return (Int(s) ?? 0) / 1024
    }
}

struct ContainerMetrics: Hashable {
    let name: String
    let cpu: String
    let memory: String
}

enum ResourceType: String, CaseIterable, Identifiable {
    case deployments = "Deploys"
    case pods = "Pods"
    case services = "Services"
    case secrets = "Secrets"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .secrets: return "key.fill"
        case .deployments: return "shippingbox.fill"
        case .pods: return "circle.hexagongrid.fill"
        case .services: return "network"
        }
    }
}

func formatAge(_ date: Date) -> String {
    let d = Date().timeIntervalSince(date)
    switch d {
    case ..<60: return "\(Int(d))s"
    case ..<3600: return "\(Int(d / 60))m"
    case ..<86400: return "\(Int(d / 3600))h"
    default: return "\(Int(d / 86400))d"
    }
}

// MARK: - Client

actor K8sClient {
    private var config: KubeConfig?
    private var session: URLSession?
    private var streamSession: URLSession?
    private var serverURL: String = ""

    func connect(context: String? = nil) async throws -> String {
        var cfg = try KubeConfig.load()

        if let context, !context.isEmpty {
            cfg.currentContext = context
        }

        self.config = cfg

        guard !cfg.currentContext.isEmpty else { throw K8sError.noContext }
        guard let cluster = cfg.activeCluster() else { throw K8sError.noCluster }
        guard cfg.activeUser() != nil else { throw K8sError.noUser }

        self.serverURL = cluster.server
        self.session = try buildSession(config: cfg)
        self.streamSession = try buildSession(config: cfg, streaming: true)

        // Test connectivity
        let _ = try await request(path: "/api/v1/namespaces?limit=1")

        return cfg.currentContext
    }

    func availableContexts() throws -> [String] {
        let cfg = try KubeConfig.load()
        return cfg.contexts.map(\.name)
    }

    func listNamespaces() async throws -> [K8sNamespace] {
        let data = try await request(path: "/api/v1/namespaces")
        let json = try parseJSON(data)
        guard let items = json["items"] as? [[String: Any]] else { return [] }

        return items.compactMap { item in
            guard let meta = item["metadata"] as? [String: Any],
                  let name = meta["name"] as? String else { return nil }
            let status = (item["status"] as? [String: Any])?["phase"] as? String ?? "Unknown"
            return K8sNamespace(id: name, name: name, status: status)
        }
    }

    func listSecrets(namespace: String) async throws -> [K8sSecret] {
        let data = try await request(path: "/api/v1/namespaces/\(namespace)/secrets")
        let json = try parseJSON(data)
        guard let items = json["items"] as? [[String: Any]] else { return [] }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()

        return items.compactMap { item in
            guard let meta = item["metadata"] as? [String: Any],
                  let name = meta["name"] as? String,
                  let ns = meta["namespace"] as? String else { return nil }
            let type = item["type"] as? String ?? "Opaque"
            let tsStr = meta["creationTimestamp"] as? String ?? ""
            let created = dateFormatter.date(from: tsStr) ?? fallbackFormatter.date(from: tsStr) ?? Date()
            return K8sSecret(id: "\(ns)/\(name)", name: name, namespace: ns, type: type, createdAt: created)
        }
    }

    func getSecretData(namespace: String, name: String) async throws -> [K8sKeyValue] {
        let data = try await request(path: "/api/v1/namespaces/\(namespace)/secrets/\(name)")
        let json = try parseJSON(data)
        guard let dataMap = json["data"] as? [String: String] else { return [] }

        return dataMap.map { (key, val) in
            let decoded = Data(base64Encoded: val).flatMap { String(data: $0, encoding: .utf8) } ?? val
            return K8sKeyValue(id: key, key: key, value: decoded)
        }.sorted { $0.key < $1.key }
    }

    func patchSecretKey(namespace: String, name: String, key: String, value: String) async throws {
        let encoded = Data(value.utf8).base64EncodedString()
        let body: [String: Any] = ["data": [key: encoded]]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let _ = try await request(
            path: "/api/v1/namespaces/\(namespace)/secrets/\(name)",
            method: "PATCH",
            body: bodyData,
            contentType: "application/merge-patch+json"
        )
    }

    func deleteSecretKey(namespace: String, name: String, key: String) async throws {
        let patch: [[String: String]] = [["op": "remove", "path": "/data/\(key)"]]
        let bodyData = try JSONSerialization.data(withJSONObject: patch)
        let _ = try await request(
            path: "/api/v1/namespaces/\(namespace)/secrets/\(name)",
            method: "PATCH",
            body: bodyData,
            contentType: "application/json-patch+json"
        )
    }

    // MARK: - Deployments

    func listDeployments(namespace: String) async throws -> [K8sDeployment] {
        let data = try await request(path: "/apis/apps/v1/namespaces/\(namespace)/deployments")
        let json = try parseJSON(data)
        guard let items = json["items"] as? [[String: Any]] else { return [] }
        return items.compactMap { parseDeployment($0) }
    }

    func getDeployment(namespace: String, name: String) async throws -> K8sDeployment? {
        let data = try await request(path: "/apis/apps/v1/namespaces/\(namespace)/deployments/\(name)")
        let json = try parseJSON(data)
        return parseDeployment(json)
    }

    func scaleDeployment(namespace: String, name: String, replicas: Int) async throws {
        let body: [String: Any] = ["spec": ["replicas": replicas]]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let _ = try await request(
            path: "/apis/apps/v1/namespaces/\(namespace)/deployments/\(name)",
            method: "PATCH",
            body: bodyData,
            contentType: "application/merge-patch+json"
        )
    }

    func restartDeployment(namespace: String, name: String) async throws {
        let now = ISO8601DateFormatter().string(from: Date())
        let body: [String: Any] = [
            "spec": [
                "template": [
                    "metadata": [
                        "annotations": ["kubectl.kubernetes.io/restartedAt": now]
                    ]
                ]
            ]
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let _ = try await request(
            path: "/apis/apps/v1/namespaces/\(namespace)/deployments/\(name)",
            method: "PATCH",
            body: bodyData,
            contentType: "application/merge-patch+json"
        )
    }

    private func parseDeployment(_ item: [String: Any]) -> K8sDeployment? {
        guard let meta = item["metadata"] as? [String: Any],
              let name = meta["name"] as? String,
              let ns = meta["namespace"] as? String,
              let spec = item["spec"] as? [String: Any] else { return nil }

        let status = item["status"] as? [String: Any] ?? [:]
        let labels = meta["labels"] as? [String: String] ?? [:]
        let replicas = spec["replicas"] as? Int ?? 0
        let strategy = (spec["strategy"] as? [String: Any])?["type"] as? String ?? "RollingUpdate"

        // Extract images from containers
        var images: [String] = []
        if let template = spec["template"] as? [String: Any],
           let tSpec = template["spec"] as? [String: Any],
           let containers = tSpec["containers"] as? [[String: Any]] {
            images = containers.compactMap { $0["image"] as? String }
        }

        // Parse conditions
        let conditions: [DeploymentCondition] = (status["conditions"] as? [[String: Any]])?.compactMap { c in
            guard let type = c["type"] as? String else { return nil }
            let df = ISO8601DateFormatter()
            return DeploymentCondition(
                type: type,
                status: c["status"] as? String ?? "",
                reason: c["reason"] as? String ?? "",
                message: c["message"] as? String ?? "",
                lastTransition: (c["lastTransitionTime"] as? String).flatMap { df.date(from: $0) }
            )
        } ?? []

        let created = parseDate(meta["creationTimestamp"] as? String)

        return K8sDeployment(
            id: "\(ns)/\(name)",
            name: name,
            namespace: ns,
            replicas: replicas,
            readyReplicas: status["readyReplicas"] as? Int ?? 0,
            availableReplicas: status["availableReplicas"] as? Int ?? 0,
            updatedReplicas: status["updatedReplicas"] as? Int ?? 0,
            images: images,
            strategy: strategy,
            createdAt: created,
            labels: labels,
            conditions: conditions
        )
    }

    // MARK: - Pods

    func listPods(namespace: String) async throws -> [K8sPod] {
        let data = try await request(path: "/api/v1/namespaces/\(namespace)/pods")
        let json = try parseJSON(data)
        guard let items = json["items"] as? [[String: Any]] else { return [] }
        return items.compactMap { parsePod($0) }
    }

    func deletePod(namespace: String, name: String) async throws {
        let _ = try await request(
            path: "/api/v1/namespaces/\(namespace)/pods/\(name)",
            method: "DELETE"
        )
    }

    func getPodLogs(namespace: String, name: String, container: String?, tailLines: Int = 200) async throws -> String {
        var path = "/api/v1/namespaces/\(namespace)/pods/\(name)/log?tailLines=\(tailLines)"
        if let c = container {
            path += "&container=\(c)"
        }
        let data = try await request(path: path)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func parsePod(_ item: [String: Any]) -> K8sPod? {
        guard let meta = item["metadata"] as? [String: Any],
              let name = meta["name"] as? String,
              let ns = meta["namespace"] as? String else { return nil }

        let spec = item["spec"] as? [String: Any] ?? [:]
        let status = item["status"] as? [String: Any] ?? [:]
        let labels = meta["labels"] as? [String: String] ?? [:]

        let phase = status["phase"] as? String ?? "Unknown"
        let nodeName = spec["nodeName"] as? String ?? ""
        let podIP = status["podIP"] as? String ?? ""
        let hostIP = status["hostIP"] as? String ?? ""

        // Owner references
        var ownerKind = ""
        var ownerName = ""
        if let owners = meta["ownerReferences"] as? [[String: Any]], let first = owners.first {
            ownerKind = first["kind"] as? String ?? ""
            ownerName = first["name"] as? String ?? ""
        }

        // Container statuses merged with specs (for requests/limits)
        let containerSpecs = spec["containers"] as? [[String: Any]] ?? []
        let containerStatuses = status["containerStatuses"] as? [[String: Any]] ?? []

        // Build a lookup of spec resources by container name
        var specResources: [String: (cpuReq: String, cpuLim: String, memReq: String, memLim: String)] = [:]
        for cs in containerSpecs {
            let cName = cs["name"] as? String ?? ""
            let resources = cs["resources"] as? [String: Any] ?? [:]
            let requests = resources["requests"] as? [String: String] ?? [:]
            let limits = resources["limits"] as? [String: String] ?? [:]
            specResources[cName] = (
                cpuReq: requests["cpu"] ?? "",
                cpuLim: limits["cpu"] ?? "",
                memReq: requests["memory"] ?? "",
                memLim: limits["memory"] ?? ""
            )
        }

        var containers: [ContainerInfo] = []
        var readyCount = 0
        var totalRestarts = 0

        for cs in containerStatuses {
            let cName = cs["name"] as? String ?? ""
            let ready = cs["ready"] as? Bool ?? false
            let restarts = cs["restartCount"] as? Int ?? 0
            if ready { readyCount += 1 }
            totalRestarts += restarts

            let image = cs["image"] as? String ?? ""
            var state = "unknown"
            var stateReason = ""
            if let s = cs["state"] as? [String: Any] {
                if s["running"] != nil {
                    state = "running"
                } else if let w = s["waiting"] as? [String: Any] {
                    state = "waiting"
                    stateReason = w["reason"] as? String ?? ""
                } else if let t = s["terminated"] as? [String: Any] {
                    state = "terminated"
                    stateReason = t["reason"] as? String ?? ""
                }
            }

            let res = specResources[cName]
            containers.append(ContainerInfo(
                name: cName, image: image, ready: ready,
                restarts: restarts, state: state, stateReason: stateReason,
                cpuRequest: res?.cpuReq ?? "", cpuLimit: res?.cpuLim ?? "",
                memRequest: res?.memReq ?? "", memLimit: res?.memLim ?? ""
            ))
        }

        // If no statuses yet, use specs
        if containers.isEmpty {
            for cs in containerSpecs {
                let cName = cs["name"] as? String ?? ""
                let res = specResources[cName]
                containers.append(ContainerInfo(
                    name: cName,
                    image: cs["image"] as? String ?? "",
                    ready: false, restarts: 0, state: "pending", stateReason: "",
                    cpuRequest: res?.cpuReq ?? "", cpuLimit: res?.cpuLim ?? "",
                    memRequest: res?.memReq ?? "", memLimit: res?.memLim ?? ""
                ))
            }
        }

        return K8sPod(
            id: "\(ns)/\(name)",
            name: name, namespace: ns, phase: phase,
            readyCount: readyCount, totalCount: max(containerSpecs.count, containers.count),
            restarts: totalRestarts, nodeName: nodeName,
            podIP: podIP, hostIP: hostIP,
            createdAt: parseDate(meta["creationTimestamp"] as? String),
            labels: labels, containers: containers,
            ownerKind: ownerKind, ownerName: ownerName
        )
    }

    // MARK: - Pod Metrics

    func getPodMetrics(namespace: String) async throws -> [PodMetrics] {
        let data = try await request(path: "/apis/metrics.k8s.io/v1beta1/namespaces/\(namespace)/pods")
        let json = try parseJSON(data)
        guard let items = json["items"] as? [[String: Any]] else { return [] }

        return items.compactMap { item in
            guard let meta = item["metadata"] as? [String: Any],
                  let name = meta["name"] as? String,
                  let containers = item["containers"] as? [[String: Any]] else { return nil }

            let cms = containers.compactMap { c -> ContainerMetrics? in
                guard let cName = c["name"] as? String,
                      let usage = c["usage"] as? [String: String] else { return nil }
                return ContainerMetrics(
                    name: cName,
                    cpu: usage["cpu"] ?? "0",
                    memory: usage["memory"] ?? "0"
                )
            }
            return PodMetrics(name: name, containers: cms)
        }
    }

    // MARK: - Cluster Info

    func getClusterMetrics() async throws -> (cpuPercent: Int, memPercent: Int, cpuUsed: Int, cpuTotal: Int, memUsedKi: Int, memTotalKi: Int) {
        // Get node metrics
        let metricsData = try await request(path: "/apis/metrics.k8s.io/v1beta1/nodes")
        let metricsJson = try parseJSON(metricsData)
        let metricsItems = metricsJson["items"] as? [[String: Any]] ?? []

        // Get node capacity
        let nodesData = try await request(path: "/api/v1/nodes")
        let nodesJson = try parseJSON(nodesData)
        let nodeItems = nodesJson["items"] as? [[String: Any]] ?? []

        var totalCpuMillis = 0
        var totalMemKi = 0
        var capacityCpuMillis = 0
        var capacityMemKi = 0

        // Sum usage from metrics
        for item in metricsItems {
            if let usage = item["usage"] as? [String: String] {
                totalCpuMillis += parseCPUValue(usage["cpu"] ?? "0")
                totalMemKi += parseMemValue(usage["memory"] ?? "0")
            }
        }

        // Sum capacity from nodes
        for item in nodeItems {
            if let status = item["status"] as? [String: Any],
               let alloc = status["allocatable"] as? [String: String] {
                capacityCpuMillis += parseCPUValue(alloc["cpu"] ?? "0")
                capacityMemKi += parseMemValue(alloc["memory"] ?? "0")
            }
        }

        let cpuPct = capacityCpuMillis > 0 ? totalCpuMillis * 100 / capacityCpuMillis : 0
        let memPct = capacityMemKi > 0 ? totalMemKi * 100 / capacityMemKi : 0

        return (cpuPct, memPct, totalCpuMillis, capacityCpuMillis, totalMemKi, capacityMemKi)
    }

    func getServerVersion() async throws -> String {
        let data = try await request(path: "/version")
        let json = try parseJSON(data)
        let major = json["major"] as? String ?? ""
        let minor = json["minor"] as? String ?? ""
        return "v\(major).\(minor)"
    }

    private func parseCPUValue(_ s: String) -> Int {
        if s.hasSuffix("n") { return (Int(s.dropLast()) ?? 0) / 1_000_000 }
        if s.hasSuffix("u") { return (Int(s.dropLast()) ?? 0) / 1_000 }
        if s.hasSuffix("m") { return Int(s.dropLast()) ?? 0 }
        return (Int(s) ?? 0) * 1000
    }

    private func parseMemValue(_ s: String) -> Int {
        if s.hasSuffix("Ki") { return Int(s.dropLast(2)) ?? 0 }
        if s.hasSuffix("Mi") { return (Int(s.dropLast(2)) ?? 0) * 1024 }
        if s.hasSuffix("Gi") { return (Int(s.dropLast(2)) ?? 0) * 1024 * 1024 }
        if s.hasSuffix("k") { return Int(s.dropLast()) ?? 0 }
        if s.hasSuffix("M") { return (Int(s.dropLast()) ?? 0) * 1024 }
        if s.hasSuffix("G") { return (Int(s.dropLast()) ?? 0) * 1024 * 1024 }
        return (Int(s) ?? 0) / 1024
    }

    // MARK: - Services

    func listServices(namespace: String) async throws -> [K8sService] {
        let data = try await request(path: "/api/v1/namespaces/\(namespace)/services")
        let json = try parseJSON(data)
        guard let items = json["items"] as? [[String: Any]] else { return [] }
        return items.compactMap { parseService($0) }
    }

    private func parseService(_ item: [String: Any]) -> K8sService? {
        guard let meta = item["metadata"] as? [String: Any],
              let name = meta["name"] as? String,
              let ns = meta["namespace"] as? String,
              let spec = item["spec"] as? [String: Any] else { return nil }

        let labels = meta["labels"] as? [String: String] ?? [:]
        let selector = spec["selector"] as? [String: String] ?? [:]
        let svcType = spec["type"] as? String ?? "ClusterIP"
        let clusterIP = spec["clusterIP"] as? String ?? ""
        let externalIPs = spec["externalIPs"] as? [String] ?? []

        // Load balancer ingress IPs
        var allExternalIPs = externalIPs
        if let status = item["status"] as? [String: Any],
           let lb = status["loadBalancer"] as? [String: Any],
           let ingress = lb["ingress"] as? [[String: Any]] {
            for ing in ingress {
                if let ip = ing["ip"] as? String { allExternalIPs.append(ip) }
                if let host = ing["hostname"] as? String { allExternalIPs.append(host) }
            }
        }

        let ports: [ServicePort] = (spec["ports"] as? [[String: Any]])?.compactMap { p in
            guard let port = p["port"] as? Int else { return nil }
            let tp = p["targetPort"]
            let targetPort: String
            if let tpInt = tp as? Int { targetPort = "\(tpInt)" }
            else if let tpStr = tp as? String { targetPort = tpStr }
            else { targetPort = "\(port)" }
            return ServicePort(
                name: p["name"] as? String ?? "",
                protocol_: p["protocol"] as? String ?? "TCP",
                port: port,
                targetPort: targetPort,
                nodePort: p["nodePort"] as? Int
            )
        } ?? []

        return K8sService(
            id: "\(ns)/\(name)",
            name: name, namespace: ns, type: svcType,
            clusterIP: clusterIP, externalIPs: allExternalIPs,
            ports: ports, selector: selector,
            createdAt: parseDate(meta["creationTimestamp"] as? String),
            labels: labels
        )
    }

    // MARK: - ConfigMaps

    func listConfigMaps(namespace: String) async throws -> [K8sConfigMap] {
        let data = try await request(path: "/api/v1/namespaces/\(namespace)/configmaps")
        let json = try parseJSON(data)
        guard let items = json["items"] as? [[String: Any]] else { return [] }

        return items.compactMap { item in
            guard let meta = item["metadata"] as? [String: Any],
                  let name = meta["name"] as? String,
                  let ns = meta["namespace"] as? String else { return nil }
            let dataMap = item["data"] as? [String: Any] ?? [:]
            return K8sConfigMap(
                id: "\(ns)/\(name)", name: name, namespace: ns,
                dataCount: dataMap.count,
                createdAt: parseDate(meta["creationTimestamp"] as? String)
            )
        }
    }

    func getConfigMapData(namespace: String, name: String) async throws -> [K8sKeyValue] {
        let data = try await request(path: "/api/v1/namespaces/\(namespace)/configmaps/\(name)")
        let json = try parseJSON(data)
        let dataMap = json["data"] as? [String: String] ?? [:]
        return dataMap.map { K8sKeyValue(id: $0.key, key: $0.key, value: $0.value) }
            .sorted { $0.key < $1.key }
    }

    func patchConfigMapKey(namespace: String, name: String, key: String, value: String) async throws {
        let body: [String: Any] = ["data": [key: value]]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let _ = try await request(
            path: "/api/v1/namespaces/\(namespace)/configmaps/\(name)",
            method: "PATCH", body: bodyData, contentType: "application/merge-patch+json"
        )
    }

    func deleteConfigMapKey(namespace: String, name: String, key: String) async throws {
        let patch: [[String: String]] = [["op": "remove", "path": "/data/\(key)"]]
        let bodyData = try JSONSerialization.data(withJSONObject: patch)
        let _ = try await request(
            path: "/api/v1/namespaces/\(namespace)/configmaps/\(name)",
            method: "PATCH", body: bodyData, contentType: "application/json-patch+json"
        )
    }

    // MARK: - Nodes

    func listNodes() async throws -> [K8sNode] {
        let data = try await request(path: "/api/v1/nodes")
        let json = try parseJSON(data)
        guard let items = json["items"] as? [[String: Any]] else { return [] }
        return items.compactMap { parseNode($0) }
    }

    func cordonNode(name: String) async throws {
        let body: [String: Any] = ["spec": ["unschedulable": true]]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let _ = try await request(
            path: "/api/v1/nodes/\(name)",
            method: "PATCH", body: bodyData, contentType: "application/merge-patch+json"
        )
    }

    func uncordonNode(name: String) async throws {
        let body: [String: Any] = ["spec": ["unschedulable": false]]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let _ = try await request(
            path: "/api/v1/nodes/\(name)",
            method: "PATCH", body: bodyData, contentType: "application/merge-patch+json"
        )
    }

    private func parseNode(_ item: [String: Any]) -> K8sNode? {
        guard let meta = item["metadata"] as? [String: Any],
              let name = meta["name"] as? String else { return nil }

        let spec = item["spec"] as? [String: Any] ?? [:]
        let status = item["status"] as? [String: Any] ?? [:]
        let labels = meta["labels"] as? [String: String] ?? [:]

        // Roles from labels
        var roles: [String] = []
        for (key, _) in labels {
            if key.hasPrefix("node-role.kubernetes.io/") {
                roles.append(String(key.dropFirst("node-role.kubernetes.io/".count)))
            }
        }

        // Addresses
        var internalIP = ""
        var externalIP = ""
        if let addresses = status["addresses"] as? [[String: String]] {
            for addr in addresses {
                if addr["type"] == "InternalIP" { internalIP = addr["address"] ?? "" }
                if addr["type"] == "ExternalIP" { externalIP = addr["address"] ?? "" }
            }
        }

        // Node info
        let nodeInfo = status["nodeInfo"] as? [String: String] ?? [:]

        // Capacity & allocatable
        let capacity = status["capacity"] as? [String: String] ?? [:]
        let allocatable = status["allocatable"] as? [String: String] ?? [:]

        // Conditions
        let conditions: [NodeCondition] = (status["conditions"] as? [[String: Any]])?.compactMap { c in
            guard let type = c["type"] as? String else { return nil }
            return NodeCondition(
                type: type,
                status: c["status"] as? String ?? "",
                reason: c["reason"] as? String ?? "",
                message: c["message"] as? String ?? ""
            )
        } ?? []

        // Taints
        let taints: [NodeTaint] = (spec["taints"] as? [[String: String]])?.compactMap { t in
            guard let key = t["key"] else { return nil }
            return NodeTaint(
                key: key,
                value: t["value"] ?? "",
                effect: t["effect"] ?? ""
            )
        } ?? []

        return K8sNode(
            id: name, name: name,
            status: conditions.first(where: { $0.type == "Ready" })?.status == "True" ? "Ready" : "NotReady",
            roles: roles,
            kubeletVersion: nodeInfo["kubeletVersion"] ?? "",
            osImage: nodeInfo["osImage"] ?? "",
            architecture: nodeInfo["architecture"] ?? "",
            containerRuntime: nodeInfo["containerRuntimeVersion"] ?? "",
            internalIP: internalIP, externalIP: externalIP,
            podCIDR: spec["podCIDR"] as? String ?? "",
            capacityCPU: capacity["cpu"] ?? "", capacityMemory: capacity["memory"] ?? "",
            capacityPods: capacity["pods"] ?? "",
            allocatableCPU: allocatable["cpu"] ?? "", allocatableMemory: allocatable["memory"] ?? "",
            allocatablePods: allocatable["pods"] ?? "",
            conditions: conditions, taints: taints, labels: labels,
            createdAt: parseDate(meta["creationTimestamp"] as? String),
            unschedulable: spec["unschedulable"] as? Bool ?? false
        )
    }

    // MARK: - Raw YAML

    func getRawResource(path: String) async throws -> Data {
        try await request(path: path)
    }

    func applyRawResource(path: String, jsonData: Data) async throws {
        let _ = try await request(
            path: path, method: "PUT", body: jsonData, contentType: "application/json"
        )
    }

    // MARK: - Events

    func getEvents(namespace: String, fieldSelector: String? = nil) async throws -> [K8sEvent] {
        var path = "/api/v1/namespaces/\(namespace)/events"
        if let fs = fieldSelector {
            path += "?fieldSelector=\(fs.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? fs)"
        }
        let data = try await request(path: path)
        let json = try parseJSON(data)
        guard let items = json["items"] as? [[String: Any]] else { return [] }

        let df = ISO8601DateFormatter()
        return items.compactMap { e in
            guard let meta = e["metadata"] as? [String: Any],
                  let name = meta["name"] as? String else { return nil }
            let source = (e["source"] as? [String: Any])?["component"] as? String ?? ""
            return K8sEvent(
                id: name,
                type: e["type"] as? String ?? "Normal",
                reason: e["reason"] as? String ?? "",
                message: e["message"] as? String ?? "",
                count: e["count"] as? Int ?? 1,
                firstSeen: (e["firstTimestamp"] as? String).flatMap { df.date(from: $0) },
                lastSeen: (e["lastTimestamp"] as? String).flatMap { df.date(from: $0) },
                source: source
            )
        }.sorted { ($0.lastSeen ?? .distantPast) > ($1.lastSeen ?? .distantPast) }
    }

    // MARK: - Helpers

    private func parseDate(_ str: String?) -> Date {
        guard let str else { return Date() }
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        return df.date(from: str) ?? fallback.date(from: str) ?? Date()
    }

    // MARK: - HTTP

    private func request(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        contentType: String? = nil
    ) async throws -> Data {
        guard let session else { throw K8sError.noConfig }

        var url = serverURL
        if !path.hasPrefix("/") { url += "/" }
        url += path

        guard let requestURL = URL(string: url) else {
            throw K8sError.networkError("Invalid URL: \(url)")
        }

        var req = URLRequest(url: requestURL)
        req.httpMethod = method
        req.httpBody = body
        if let ct = contentType {
            req.setValue(ct, forHTTPHeaderField: "Content-Type")
        }
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        // Auth header
        if let token = try await resolveToken() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw K8sError.requestFailed(http.statusCode, msg)
            }
            return data
        } catch let e as K8sError {
            throw e
        } catch {
            throw K8sError.networkError(error.localizedDescription)
        }
    }

    /// Stream pod logs line-by-line using `follow=true`. Calls `onLine` for each new line.
    /// Returns when the stream ends or the task is cancelled.
    func streamPodLogs(
        namespace: String,
        name: String,
        container: String?,
        tailLines: Int = 100,
        onLine: @Sendable @escaping (String) -> Void
    ) async throws {
        guard let session else { throw K8sError.noConfig }

        var path = "/api/v1/namespaces/\(namespace)/pods/\(name)/log?follow=true&tailLines=\(tailLines)"
        if let c = container {
            path += "&container=\(c)"
        }

        var url = serverURL
        if !path.hasPrefix("/") { url += "/" }
        url += path

        guard let requestURL = URL(string: url) else {
            throw K8sError.networkError("Invalid URL: \(url)")
        }

        var req = URLRequest(url: requestURL)
        req.httpMethod = "GET"
        if let token = try await resolveToken() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let activeSession = streamSession ?? session
        let (bytes, response) = try await activeSession.bytes(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw K8sError.requestFailed(http.statusCode, "Log stream failed")
        }

        for try await line in bytes.lines {
            if Task.isCancelled { break }
            onLine(line)
        }
    }

    private func resolveToken() async throws -> String? {
        guard let user = config?.activeUser() else { return nil }

        if let token = user.token { return token }

        // Exec-based auth (e.g., az, gcloud, aws)
        if let exec = user.exec {
            return try runExecPlugin(exec)
        }

        // Client cert auth doesn't use bearer tokens
        if user.clientCertificateData != nil { return nil }

        return nil
    }

    private func runExecPlugin(_ exec: KubeConfig.ExecConfig) throws -> String {
        let process = Process()
        let pipe = Pipe()

        // Resolve full path for common commands
        process.executableURL = URL(fileURLWithPath: resolveCommand(exec.command))
        process.arguments = exec.args
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        // Inherit PATH
        var env = ProcessInfo.processInfo.environment
        if let extra = exec.env {
            for (k, v) in extra { env[k] = v }
        }
        process.environment = env

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? [String: Any],
              let token = status["token"] as? String else {
            throw K8sError.authFailed("exec plugin '\(exec.command)' did not return a valid token")
        }

        return token
    }

    private func resolveCommand(_ cmd: String) -> String {
        if cmd.hasPrefix("/") { return cmd }
        // Search common paths
        let paths = [
            "/usr/local/bin/\(cmd)",
            "/opt/homebrew/bin/\(cmd)",
            "/usr/bin/\(cmd)",
            "\(NSHomeDirectory())/.local/bin/\(cmd)",
            "\(NSHomeDirectory())/bin/\(cmd)",
        ]
        return paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) ?? cmd
    }

    // MARK: - TLS Session

    private func buildSession(config: KubeConfig, streaming: Bool = false) throws -> URLSession {
        let cluster = config.activeCluster()!
        let user = config.activeUser()!

        let delegate = K8sTLSDelegate(
            caData: cluster.certificateAuthorityData,
            clientCertData: user.clientCertificateData,
            clientKeyData: user.clientKeyData,
            insecure: cluster.insecureSkipTLSVerify
        )

        let sessionConfig = URLSessionConfiguration.default
        if streaming {
            sessionConfig.timeoutIntervalForRequest = 300
            sessionConfig.timeoutIntervalForResource = 0  // no limit
        } else {
            sessionConfig.timeoutIntervalForRequest = 30
            sessionConfig.timeoutIntervalForResource = 60
        }

        return URLSession(configuration: sessionConfig, delegate: delegate, delegateQueue: nil)
    }

    private func parseJSON(_ data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw K8sError.configParse("Invalid JSON response")
        }
        return json
    }
}

// MARK: - TLS Delegate

final class K8sTLSDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    let caData: Data?
    let clientCertData: Data?
    let clientKeyData: Data?
    let insecure: Bool

    init(caData: Data?, clientCertData: Data?, clientKeyData: Data?, insecure: Bool) {
        self.caData = caData
        self.clientCertData = clientCertData
        self.clientKeyData = clientKeyData
        self.insecure = insecure
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let protection = challenge.protectionSpace

        if protection.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            handleServerTrust(challenge: challenge, completionHandler: completionHandler)
        } else if protection.authenticationMethod == NSURLAuthenticationMethodClientCertificate {
            handleClientCert(challenge: challenge, completionHandler: completionHandler)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    private func handleServerTrust(
        challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        if insecure {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }

        if let caData = caData {
            let caDER = pemToDER(caData)
            if let caCert = SecCertificateCreateWithData(nil, caDER as CFData) {
                SecTrustSetAnchorCertificates(trust, [caCert] as CFArray)
                SecTrustSetAnchorCertificatesOnly(trust, true)
            }
        }

        var error: CFError?
        if SecTrustEvaluateWithError(trust, &error) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            // Try again allowing system roots alongside custom CA
            if caData != nil, let trust2 = challenge.protectionSpace.serverTrust {
                let caDER = pemToDER(caData!)
                if let caCert = SecCertificateCreateWithData(nil, caDER as CFData) {
                    SecTrustSetAnchorCertificates(trust2, [caCert] as CFArray)
                    SecTrustSetAnchorCertificatesOnly(trust2, false)
                }
                if SecTrustEvaluateWithError(trust2, nil) {
                    completionHandler(.useCredential, URLCredential(trust: trust2))
                    return
                }
            }
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    private func handleClientCert(
        challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let certData = clientCertData, let keyData = clientKeyData else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Build PKCS12 from PEM cert + key, then create credential
        if let identity = createIdentity(certDER: certData, keyDER: keyData) {
            let credential = URLCredential(
                identity: identity,
                certificates: nil,
                persistence: .forSession
            )
            completionHandler(.useCredential, credential)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    /// Temporary keychain used to store client certs without touching the
    /// user's default keychain (avoids password/biometric prompts).
    private var tempKeychain: SecKeychain?

    private func createIdentity(certDER: Data, keyDER: Data) -> SecIdentity? {
        let certDERBytes = pemToDER(certDER)
        let keyDERBytes = pemToDER(keyDER)

        guard let cert = SecCertificateCreateWithData(nil, certDERBytes as CFData) else { return nil }

        // Try RSA first, then EC
        var key: SecKey?
        for keyType in [kSecAttrKeyTypeRSA, kSecAttrKeyTypeECSECPrimeRandom] {
            let keyAttrs: [String: Any] = [
                kSecAttrKeyType as String: keyType,
                kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            ]
            key = SecKeyCreateWithData(keyDERBytes as CFData, keyAttrs as CFDictionary, nil)
            if key != nil { break }
        }
        guard let privateKey = key else { return nil }

        // Create a temporary file-based keychain so we never touch the user's
        // default keychain (which would trigger password/biometric prompts).
        let tempPath = NSTemporaryDirectory() + "k8secret-\(UUID().uuidString).keychain"
        let password = UUID().uuidString
        var keychain: SecKeychain?
        guard SecKeychainCreate(tempPath, UInt32(password.utf8.count), password, false, nil, &keychain) == errSecSuccess,
              let keychain else { return nil }
        self.tempKeychain = keychain

        // Add cert and key to the temporary keychain
        let tempLabel = "k8secret"
        let addCertQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: cert,
            kSecAttrLabel as String: tempLabel,
            kSecUseKeychain as String: keychain,
        ]
        SecItemAdd(addCertQuery as CFDictionary, nil)

        let addKeyQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecValueRef as String: privateKey,
            kSecAttrLabel as String: tempLabel,
            kSecUseKeychain as String: keychain,
        ]
        SecItemAdd(addKeyQuery as CFDictionary, nil)

        // Query the identity from the temporary keychain
        let identityQuery: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: tempLabel,
            kSecReturnRef as String: true,
            kSecMatchSearchList as String: [keychain],
        ]
        var ref: CFTypeRef?
        if SecItemCopyMatching(identityQuery as CFDictionary, &ref) == errSecSuccess {
            return (ref as! SecIdentity)
        }

        return nil
    }

    /// Convert PEM-encoded data to raw DER bytes.
    /// If the data is already raw DER (no PEM headers), returns it unchanged.
    private func pemToDER(_ data: Data) -> Data {
        guard let pem = String(data: data, encoding: .utf8) else { return data }
        let lines = pem.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("-----") }
        let base64 = lines.joined()
        return Data(base64Encoded: base64) ?? data
    }
}
