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
    private var serverURL: String = ""

    /// Cached exec-plugin credential, reused until shortly before it expires.
    private var cachedExecToken: (token: String, expiry: Date)?
    private var execRefreshTask: Task<(token: String, expiry: Date?), Error>?

    /// Refresh this long before the stated expiry, so a token can't lapse mid-request.
    private static let execTokenRefreshMargin: TimeInterval = 60
    /// TTL applied when a plugin omits `expirationTimestamp`.
    private static let execTokenDefaultTTL: TimeInterval = 300

    /// Retry policy for transient failures (429, 5xx, network blips).
    private static let maxRetries = 3
    private static let baseRetryDelay: Double = 0.5
    private static let maxRetryDelay: Double = 8

    /// Page size for list calls, and a ceiling on how many pages we'll follow so a
    /// pathological cluster can't spin this forever.
    private static let pageSize = 500
    private static let maxPages = 40

    deinit {
        // URLSession retains its delegate until explicitly invalidated.
        session?.invalidateAndCancel()
    }

    func connect(context: String? = nil) async throws -> String {
        var cfg = try KubeConfig.load()

        // Only honour a requested context that still exists. The app remembers the
        // last context it connected to, and that name can disappear — a context
        // renamed, a cluster torn down, a kubeconfig swapped. Forcing it anyway
        // dead-ends on "Cluster not found for current context", which reads like
        // the cluster is broken rather than the remembered name being stale.
        if let context, !context.isEmpty, cfg.contexts.contains(where: { $0.name == context }) {
            cfg.currentContext = context
        }

        // Fall back to any context that resolves, so a stale `current-context` in
        // the file itself doesn't strand the user either.
        if !cfg.contexts.contains(where: { $0.name == cfg.currentContext }),
           let first = cfg.contexts.first {
            cfg.currentContext = first.name
        }

        self.config = cfg

        guard !cfg.currentContext.isEmpty else { throw K8sError.noContext }
        guard let cluster = cfg.activeCluster() else { throw K8sError.noCluster }
        guard cfg.activeUser() != nil else { throw K8sError.noUser }

        // Credentials are per-user; never carry one context's token into another.
        cachedExecToken = nil
        execRefreshTask = nil

        // Tear down the previous session — otherwise every context switch leaks a
        // session, its delegate, and its pooled connections.
        session?.invalidateAndCancel()

        self.serverURL = cluster.server
        self.session = try buildSession(config: cfg)

        // Test connectivity
        let _ = try await request(path: "/api/v1/namespaces?limit=1")

        return cfg.currentContext
    }

    func availableContexts() throws -> [String] {
        let cfg = try KubeConfig.load()
        return cfg.contexts.map(\.name)
    }

    /// Connect and list pods in one call (convenience for deployment log streaming)
    func listPodsAfterConnect(context: String, namespace: String) async throws -> [K8sPod] {
        _ = try await connect(context: context)
        return try await listPods(namespace: namespace)
    }

    func listNamespaces() async throws -> [K8sNamespace] {
        let items = try await listItems(basePath: "/api/v1/namespaces")

        return items.compactMap { item in
            guard let meta = item["metadata"] as? [String: Any],
                  let name = meta["name"] as? String else { return nil }
            let status = (item["status"] as? [String: Any])?["phase"] as? String ?? "Unknown"
            return K8sNamespace(id: name, name: name, status: status)
        }
    }

    func listSecrets(namespace: String) async throws -> [K8sSecret] {
        let items = try await listItems(basePath: "/api/v1/namespaces/\(Self.encodePath(namespace))/secrets")

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

    /// Decoded key/value pairs plus the `resourceVersion` they were read at, so a
    /// subsequent write can detect that someone else edited the secret in between.
    func getSecretData(
        namespace: String,
        name: String
    ) async throws -> (items: [K8sKeyValue], resourceVersion: String?) {
        let data = try await request(path: "/api/v1/namespaces/\(Self.encodePath(namespace))/secrets/\(Self.encodePath(name))")
        let json = try parseJSON(data)
        let resourceVersion = (json["metadata"] as? [String: Any])?["resourceVersion"] as? String

        guard let dataMap = json["data"] as? [String: String] else {
            return ([], resourceVersion)
        }

        let items = dataMap.map { (key, val) in
            // Binary secrets (TLS keys, keystores) aren't valid UTF-8. Surface that
            // rather than showing the raw base64 as if it were the value.
            let decoded = Data(base64Encoded: val).flatMap { String(data: $0, encoding: .utf8) }
                ?? "<binary — \(Data(base64Encoded: val)?.count ?? 0) bytes>"
            return K8sKeyValue(id: key, key: key, value: decoded)
        }.sorted { $0.key < $1.key }

        return (items, resourceVersion)
    }

    func patchSecretKey(namespace: String, name: String, key: String, value: String) async throws {
        let encoded = Data(value.utf8).base64EncodedString()
        let body: [String: Any] = ["data": [key: encoded]]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let _ = try await request(
            path: "/api/v1/namespaces/\(Self.encodePath(namespace))/secrets/\(Self.encodePath(name))",
            method: "PATCH",
            body: bodyData,
            contentType: "application/merge-patch+json"
        )
    }

    func deleteSecretKey(namespace: String, name: String, key: String) async throws {
        try await applySecretChanges(namespace: namespace, name: name, upserts: [:], removals: [key])
    }

    /// Apply every staged edit to a secret in a single request.
    ///
    /// Writing key-by-key meant a failure partway through left the secret in a
    /// half-updated state that matched neither the old nor the new intent. A JSON
    /// merge-patch is atomic at the API server: either all keys land or none do.
    /// Merge-patch also defines `null` as "delete this key", so additions,
    /// modifications and removals travel together.
    ///
    /// `resourceVersion` makes the write conditional: if someone else changed the
    /// secret since it was read, the server rejects with 409 instead of silently
    /// overwriting their change.
    func applySecretChanges(
        namespace: String,
        name: String,
        upserts: [String: String],
        removals: [String],
        resourceVersion: String? = nil
    ) async throws {
        guard !upserts.isEmpty || !removals.isEmpty else { return }

        var data: [String: Any] = [:]
        for (key, value) in upserts {
            data[key] = Data(value.utf8).base64EncodedString()
        }
        for key in removals {
            data[key] = NSNull()
        }

        var body: [String: Any] = ["data": data]
        if let resourceVersion {
            body["metadata"] = ["resourceVersion": resourceVersion]
        }

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let _ = try await request(
            path: "/api/v1/namespaces/\(Self.encodePath(namespace))/secrets/\(Self.encodePath(name))",
            method: "PATCH",
            body: bodyData,
            contentType: "application/merge-patch+json"
        )
    }

    /// Current `resourceVersion` of a secret, for optimistic-concurrency writes.
    func getSecretResourceVersion(namespace: String, name: String) async throws -> String? {
        let data = try await request(path: "/api/v1/namespaces/\(Self.encodePath(namespace))/secrets/\(Self.encodePath(name))")
        let json = try parseJSON(data)
        return (json["metadata"] as? [String: Any])?["resourceVersion"] as? String
    }

    // MARK: - Deployments

    func listDeployments(namespace: String) async throws -> [K8sDeployment] {
        let items = try await listItems(basePath: "/apis/apps/v1/namespaces/\(Self.encodePath(namespace))/deployments")
        return items.compactMap { parseDeployment($0) }
    }

    func getDeployment(namespace: String, name: String) async throws -> K8sDeployment? {
        let data = try await request(path: "/apis/apps/v1/namespaces/\(Self.encodePath(namespace))/deployments/\(Self.encodePath(name))")
        let json = try parseJSON(data)
        return parseDeployment(json)
    }

    func scaleDeployment(namespace: String, name: String, replicas: Int) async throws {
        let body: [String: Any] = ["spec": ["replicas": replicas]]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let _ = try await request(
            path: "/apis/apps/v1/namespaces/\(Self.encodePath(namespace))/deployments/\(Self.encodePath(name))",
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
            path: "/apis/apps/v1/namespaces/\(Self.encodePath(namespace))/deployments/\(Self.encodePath(name))",
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
        let items = try await listItems(basePath: "/api/v1/namespaces/\(Self.encodePath(namespace))/pods")
        return items.compactMap { parsePod($0) }
    }

    func deletePod(namespace: String, name: String) async throws {
        let _ = try await request(
            path: "/api/v1/namespaces/\(Self.encodePath(namespace))/pods/\(Self.encodePath(name))",
            method: "DELETE"
        )
    }

    func getPodLogs(namespace: String, name: String, container: String?, tailLines: Int = 200) async throws -> String {
        var path = "/api/v1/namespaces/\(Self.encodePath(namespace))/pods/\(Self.encodePath(name))/log?tailLines=\(tailLines)"
        if let c = container {
            path += "&container=\(Self.encodeQuery(c))"
        }
        let data = try await request(path: path)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func parsePod(_ item: [String: Any]) -> K8sPod? { Self.parsePodStatic(item) }

    nonisolated static func parsePodStatic(_ item: [String: Any]) -> K8sPod? {
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
            createdAt: parseDateStatic(meta["creationTimestamp"] as? String),
            labels: labels, containers: containers,
            ownerKind: ownerKind, ownerName: ownerName
        )
    }

    // MARK: - Pod Metrics

    func getPodMetrics(namespace: String) async throws -> [PodMetrics] {
        let items = try await listItems(basePath: "/apis/metrics.k8s.io/v1beta1/namespaces/\(Self.encodePath(namespace))/pods")

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
        let items = try await listItems(basePath: "/api/v1/namespaces/\(Self.encodePath(namespace))/services")
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
        let items = try await listItems(basePath: "/api/v1/namespaces/\(Self.encodePath(namespace))/configmaps")

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
        let data = try await request(path: "/api/v1/namespaces/\(Self.encodePath(namespace))/configmaps/\(Self.encodePath(name))")
        let json = try parseJSON(data)
        let dataMap = json["data"] as? [String: String] ?? [:]
        return dataMap.map { K8sKeyValue(id: $0.key, key: $0.key, value: $0.value) }
            .sorted { $0.key < $1.key }
    }

    func patchConfigMapKey(namespace: String, name: String, key: String, value: String) async throws {
        let body: [String: Any] = ["data": [key: value]]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let _ = try await request(
            path: "/api/v1/namespaces/\(Self.encodePath(namespace))/configmaps/\(Self.encodePath(name))",
            method: "PATCH", body: bodyData, contentType: "application/merge-patch+json"
        )
    }

    func deleteConfigMapKey(namespace: String, name: String, key: String) async throws {
        let patch: [[String: String]] = [["op": "remove", "path": "/data/\(key)"]]
        let bodyData = try JSONSerialization.data(withJSONObject: patch)
        let _ = try await request(
            path: "/api/v1/namespaces/\(Self.encodePath(namespace))/configmaps/\(Self.encodePath(name))",
            method: "PATCH", body: bodyData, contentType: "application/json-patch+json"
        )
    }

    // MARK: - Nodes

    func listNodes() async throws -> [K8sNode] {
        let items = try await listItems(basePath: "/api/v1/nodes")
        return items.compactMap { parseNode($0) }
    }

    func cordonNode(name: String) async throws {
        let body: [String: Any] = ["spec": ["unschedulable": true]]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let _ = try await request(
            path: "/api/v1/nodes/\(Self.encodePath(name))",
            method: "PATCH", body: bodyData, contentType: "application/merge-patch+json"
        )
    }

    func uncordonNode(name: String) async throws {
        let body: [String: Any] = ["spec": ["unschedulable": false]]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let _ = try await request(
            path: "/api/v1/nodes/\(Self.encodePath(name))",
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
        let basePath = "/api/v1/namespaces/\(Self.encodePath(namespace))/events"
        // A field selector is `k=v,k=v`, so its separators must survive encoding
        // while the values inside it must not — encode each value on its own.
        let query = fieldSelector.map { selector -> String in
            let encoded = selector.split(separator: ",").map { clause -> String in
                guard let eq = clause.firstIndex(of: "=") else { return String(clause) }
                let key = String(clause[clause.startIndex..<eq])
                let value = String(clause[clause.index(after: eq)...])
                return "\(key)=\(Self.encodeQuery(value))"
            }.joined(separator: ",")
            return "fieldSelector=\(encoded)"
        }

        let items = try await listItems(basePath: basePath, query: query)

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

    private func parseDate(_ str: String?) -> Date { Self.parseDateStatic(str) }

    nonisolated static func parseDateStatic(_ str: String?) -> Date {
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
        var attempt = 0

        while true {
            do {
                return try await performRequest(path: path, method: method, body: body, contentType: contentType)
            } catch let error as K8sError {
                guard attempt < Self.maxRetries,
                      let delay = Self.retryDelay(for: error, attempt: attempt) else {
                    throw error
                }
                attempt += 1
                try? await Task.sleep(for: .seconds(delay))
                if Task.isCancelled { throw error }
            }
        }
    }

    /// How long to wait before retrying, or nil if the failure isn't worth retrying.
    ///
    /// Poll loops used to hammer a throttling or struggling API server at full rate,
    /// which makes an overloaded cluster worse rather than better.
    /// Non-private so the retry policy can be unit tested without a live cluster.
    static func retryDelay(for error: K8sError, attempt: Int) -> Double? {
        let retryable: Bool
        var serverHint: Double?

        switch error {
        case .requestFailed(let code, let message):
            // 429 and 5xx are transient. 4xx (other than 429) means the request is
            // wrong and will stay wrong, so retrying just delays the error.
            retryable = code == 429 || (500...599).contains(code)
            if code == 429 {
                serverHint = Self.retryAfterSeconds(in: message)
            }
        case .networkError:
            retryable = true
        case .noConfig, .noContext, .noCluster, .noUser, .configParse, .authFailed:
            retryable = false
        }

        guard retryable else { return nil }

        // Exponential backoff with jitter, so a burst of parallel pollers doesn't
        // retry in lockstep and re-create the spike that caused the throttling.
        let backoff = min(Self.maxRetryDelay, Self.baseRetryDelay * pow(2, Double(attempt)))
        let jitter = Double.random(in: 0...(backoff / 2))
        return max(serverHint ?? 0, backoff + jitter)
    }

    /// Kubernetes reports throttling in the response body ("retry after 3s").
    static func retryAfterSeconds(in message: String) -> Double? {
        guard let range = message.range(of: #"retry after (\d+)"#, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let digits = message[range].filter(\.isNumber)
        return Double(digits).map { min($0, Self.maxRetryDelay) }
    }

    private func performRequest(
        path: String,
        method: String,
        body: Data?,
        contentType: String?
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
        } else if let basic = basicAuthHeader() {
            req.setValue(basic, forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                // A 401 right after we failed to build a client identity is not a
                // credentials problem the user can fix by re-reading their token —
                // say what actually happened.
                if http.statusCode == 401, K8sTLSDelegate.clientCertificateUnavailable {
                    throw K8sError.authFailed(
                        "This cluster uses client-certificate authentication, which K8Secret "
                        + "doesn't support — presenting a client certificate on macOS requires "
                        + "storing your private key in a keychain, and K8Secret doesn't touch the "
                        + "keychain. Use a token instead: "
                        + "kubectl create token <serviceaccount>"
                    )
                }
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

    // MARK: - Paged list

    /// Fetch every page of a collection, following `metadata.continue`.
    ///
    /// List calls used to request the whole collection in one unbounded response.
    /// On a namespace with thousands of pods that's a multi-megabyte payload, a
    /// memory spike, and a long stall — and it failed hardest on exactly the large
    /// clusters that matter most. Paging keeps each response bounded.
    private func listItems(basePath: String, query: String? = nil) async throws -> [[String: Any]] {
        var items: [[String: Any]] = []
        var continueToken: String?
        var pagesFetched = 0

        repeat {
            var components = ["limit=\(Self.pageSize)"]
            if let query, !query.isEmpty { components.append(query) }
            if let token = continueToken {
                components.append("continue=\(Self.encodeQuery(token))")
            }

            let separator = basePath.contains("?") ? "&" : "?"
            let data = try await request(path: basePath + separator + components.joined(separator: "&"))
            let json = try parseJSON(data)

            items.append(contentsOf: json["items"] as? [[String: Any]] ?? [])

            let metadata = json["metadata"] as? [String: Any]
            let next = metadata?["continue"] as? String
            continueToken = (next?.isEmpty == false) ? next : nil

            pagesFetched += 1
        } while continueToken != nil && pagesFetched < Self.maxPages

        return items
    }

    // MARK: - Watch

    /// One incremental change from a watch stream.
    enum PodWatchEvent: Sendable {
        case added(K8sPod)
        case modified(K8sPod)
        case deleted(K8sPod)
        /// The server's periodic "you're up to date as of here" marker.
        case bookmark(String)
    }

    /// Raised when the server can no longer serve changes from our `resourceVersion`
    /// (HTTP 410). The caller has to re-list and start a fresh watch.
    struct WatchExpired: Error {}

    struct PodListPage: Sendable {
        let pods: [K8sPod]
        let resourceVersion: String?
    }

    /// List pods along with the `resourceVersion` to start watching from.
    func listPodsWithVersion(namespace: String) async throws -> PodListPage {
        let basePath = "/api/v1/namespaces/\(Self.encodePath(namespace))/pods"
        var pods: [K8sPod] = []
        var continueToken: String?
        var resourceVersion: String?
        var pagesFetched = 0

        repeat {
            var components = ["limit=\(Self.pageSize)"]
            if let token = continueToken { components.append("continue=\(Self.encodeQuery(token))") }

            let data = try await request(path: basePath + "?" + components.joined(separator: "&"))
            let json = try parseJSON(data)

            pods.append(contentsOf: (json["items"] as? [[String: Any]] ?? []).compactMap { parsePod($0) })

            let metadata = json["metadata"] as? [String: Any]
            // The version to watch from is the one on the *first* page: it covers the
            // whole collection as of that read.
            if resourceVersion == nil { resourceVersion = metadata?["resourceVersion"] as? String }

            let next = metadata?["continue"] as? String
            continueToken = (next?.isEmpty == false) ? next : nil
            pagesFetched += 1
        } while continueToken != nil && pagesFetched < Self.maxPages

        return PodListPage(pods: pods, resourceVersion: resourceVersion)
    }

    /// Stream pod changes instead of re-listing the namespace on a timer.
    ///
    /// Polling re-downloaded every pod in the namespace every five seconds, which is
    /// wasteful on a small cluster and untenable on a large one. A watch sends only
    /// what actually changed, and it arrives immediately rather than up to a poll
    /// interval late.
    func watchPods(
        namespace: String,
        resourceVersion: String,
        onEvent: @Sendable @escaping (PodWatchEvent) -> Void
    ) async throws {
        let path = "/api/v1/namespaces/\(Self.encodePath(namespace))/pods"
            + "?watch=true&allowWatchBookmarks=true"
            + "&resourceVersion=\(Self.encodeQuery(resourceVersion))"
            + "&timeoutSeconds=\(Self.watchTimeoutSeconds)"

        try await streamLines(path: path) { [weak self] line in
            guard let self else { return }
            guard let data = line.data(using: .utf8),
                  let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = envelope["type"] as? String,
                  let object = envelope["object"] as? [String: Any] else { return }

            if type == "BOOKMARK" {
                if let version = (object["metadata"] as? [String: Any])?["resourceVersion"] as? String {
                    onEvent(.bookmark(version))
                }
                return
            }

            guard let pod = self.parsePodSendable(object) else { return }
            switch type {
            case "ADDED":    onEvent(.added(pod))
            case "MODIFIED": onEvent(.modified(pod))
            case "DELETED":  onEvent(.deleted(pod))
            default: break   // ERROR frames fall through to the stream ending
            }
        }
    }

    /// `parsePod` is actor-isolated; the watch callback needs it without hopping.
    private nonisolated func parsePodSendable(_ object: [String: Any]) -> K8sPod? {
        Self.parsePodStatic(object)
    }

    /// Shared line-oriented streaming used by both log follow and watch.
    private func streamLines(path: String, onLine: @Sendable @escaping (String) -> Void) async throws {
        guard let session else { throw K8sError.noConfig }

        var url = serverURL
        if !path.hasPrefix("/") { url += "/" }
        url += path

        guard let requestURL = URL(string: url) else {
            throw K8sError.networkError("Invalid URL: \(url)")
        }

        var req = URLRequest(url: requestURL)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = try await resolveToken() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if let basic = basicAuthHeader() {
            req.setValue(basic, forHTTPHeaderField: "Authorization")
        }

        let (bytes, response) = try await session.bytes(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            // 410 Gone means our resourceVersion aged out of the server's history
            // window — expected on a busy cluster, and recoverable by re-listing.
            if http.statusCode == 410 { throw WatchExpired() }
            throw K8sError.requestFailed(http.statusCode, "Watch failed")
        }

        try await withTaskCancellationHandler {
            for try await line in bytes.lines {
                if Task.isCancelled { break }
                onLine(line)
            }
        } onCancel: {
            bytes.task.cancel()
        }
    }

    private static let watchTimeoutSeconds = 300

    // MARK: - URL escaping

    /// Percent-encode a single path segment.
    ///
    /// Kubernetes names are RFC 1123 labels and therefore already URL-safe, so this
    /// is defense in depth — it keeps a future CRD, a projected name, or an API
    /// change from being able to alter the request path.
    private static func encodePath(_ segment: String) -> String {
        segment.addingPercentEncoding(withAllowedCharacters: Self.pathSegmentAllowed) ?? segment
    }

    private static func encodeQuery(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: Self.queryValueAllowed) ?? value
    }

    private static let pathSegmentAllowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "/;")
        return set
    }()

    private static let queryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=+?#")
        return set
    }()

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

        var path = "/api/v1/namespaces/\(Self.encodePath(namespace))/pods/\(Self.encodePath(name))/log?follow=true&tailLines=\(tailLines)"
        if let c = container {
            path += "&container=\(Self.encodeQuery(c))"
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
        } else if let basic = basicAuthHeader() {
            req.setValue(basic, forHTTPHeaderField: "Authorization")
        }

        let (bytes, response) = try await session.bytes(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw K8sError.requestFailed(http.statusCode, "Log stream failed")
        }

        // The cancellation check below only runs when a line arrives, so a quiet pod
        // would keep the connection open indefinitely after the window closed.
        // withTaskCancellationHandler tears the stream down the moment we're
        // cancelled, regardless of whether the pod is saying anything.
        try await withTaskCancellationHandler {
            for try await line in bytes.lines {
                if Task.isCancelled { break }
                onLine(line)
            }
        } onCancel: {
            bytes.task.cancel()
        }
    }

    /// HTTP basic auth, for the older `username`/`password` kubeconfig form.
    private func basicAuthHeader() -> String? {
        guard let user = config?.activeUser(),
              let username = user.username, let password = user.password else { return nil }
        let encoded = Data("\(username):\(password)".utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    private func resolveToken() async throws -> String? {
        guard let user = config?.activeUser() else { return nil }

        if let token = user.token { return token }

        // Exec-based auth (e.g. aws-iam-authenticator, gke-gcloud-auth-plugin, az).
        // Each invocation forks a process that can take hundreds of milliseconds,
        // so reuse the credential until it is close to expiring.
        if let exec = user.exec {
            if let cached = cachedExecToken, cached.expiry > Date().addingTimeInterval(Self.execTokenRefreshMargin) {
                return cached.token
            }
            // Coalesce concurrent refreshes: without this, a burst of parallel
            // requests would each fork their own credential process.
            if let inFlight = execRefreshTask {
                return try await inFlight.value.token
            }
            let task = Task { try await Self.runExecPlugin(exec) }
            execRefreshTask = task
            defer { execRefreshTask = nil }

            let result = try await task.value
            // Plugins may omit expirationTimestamp; fall back to a short TTL rather
            // than caching forever, so rotated credentials are picked up.
            cachedExecToken = (result.token, result.expiry ?? Date().addingTimeInterval(Self.execTokenDefaultTTL))
            return result.token
        }

        // Client cert auth doesn't use bearer tokens
        if user.clientCertificateData != nil { return nil }

        return nil
    }

    /// Runs the credential plugin off the actor's executor — `waitUntilExit()` blocks
    /// its thread, which would otherwise stall every other request on this client.
    private static func runExecPlugin(
        _ exec: KubeConfig.ExecConfig
    ) async throws -> (token: String, expiry: Date?) {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                let errPipe = Pipe()

                // Resolve full path for common commands
                process.executableURL = URL(fileURLWithPath: resolveCommand(exec.command))
                process.arguments = exec.args
                process.standardOutput = pipe
                process.standardError = errPipe

                // Inherit PATH
                var env = ProcessInfo.processInfo.environment
                if let extra = exec.env {
                    for (k, v) in extra { env[k] = v }
                }
                process.environment = env

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: K8sError.authFailed("\(exec.command): \(error.localizedDescription)"))
                    return
                }

                // Drain stdout before waiting: a plugin whose output exceeds the pipe
                // buffer would otherwise block forever writing into a full pipe.
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let status = json["status"] as? [String: Any],
                      let token = status["token"] as? String else {
                    let errMsg = String(data: errData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let detail = errMsg.isEmpty ? "did not return a valid token" : errMsg
                    continuation.resume(throwing: K8sError.authFailed("\(exec.command): \(detail)"))
                    return
                }

                let formatter = ISO8601DateFormatter()
                let expiry = (status["expirationTimestamp"] as? String).flatMap { formatter.date(from: $0) }
                continuation.resume(returning: (token, expiry))
            }
        }
    }

    private static func resolveCommand(_ cmd: String) -> String {
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

    private func buildSession(config: KubeConfig) throws -> URLSession {
        let cluster = config.activeCluster()!
        let user = config.activeUser()!

        let delegate = K8sTLSDelegate(
            caData: cluster.certificateAuthorityData,
            clientCertData: user.clientCertificateData,
            clientKeyData: user.clientKeyData,
            insecure: cluster.insecureSkipTLSVerify
        )

        let sessionConfig = URLSessionConfiguration.default
        // timeoutIntervalForRequest is the gap allowed *between* packets, not the
        // total call duration — at 300s a pod that simply didn't log for five
        // minutes had its follow stream dropped with no reconnect.
        sessionConfig.timeoutIntervalForRequest = 3600
        // Total-transfer ceiling. 0 is not "unlimited" here (that's an unspecified
        // value); a large explicit interval is.
        sessionConfig.timeoutIntervalForResource = 86_400

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
    /// Set when a client certificate was configured but no usable identity could be
    /// built, so a 401 can say why instead of just "Unauthorized".
    nonisolated(unsafe) static var clientCertificateUnavailable = false

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

        // Honour `insecure-skip-tls-verify: true` from kubeconfig — an explicit,
        // per-cluster opt-in by the user. Everything else fails closed.
        if insecure {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }

        guard let caData else {
            // No custom CA — let the system evaluate against its trust store,
            // including hostname verification and revocation policy.
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // A CA bundle may legitimately carry several certificates; all of them are
        // anchors the user asked us to trust.
        let caCerts = createCertificates(from: caData)
        guard !caCerts.isEmpty else {
            // A CA was configured but we couldn't parse it. Refusing is the only
            // safe option: falling back to system roots would silently accept a
            // certificate the user never intended to trust.
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Evaluate the server chain against the kubeconfig CA *only*, and keep
        // hostname verification on by binding an SSL policy for the requested host.
        let policy = SecPolicyCreateSSL(true, challenge.protectionSpace.host as CFString)
        SecTrustSetPolicies(trust, policy)
        SecTrustSetAnchorCertificates(trust, caCerts as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)

        if SecTrustEvaluateWithError(trust, nil) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    /// Every certificate in a PEM bundle, in order.
    ///
    /// `certificate-authority-data` and `client-certificate-data` routinely hold a
    /// *chain* rather than a single certificate — k3s, colima and kubeadm all emit
    /// leaf + issuing CA. Concatenating the base64 of every block into one blob (as
    /// this used to) produces bytes that are not a valid certificate at all, so
    /// parsing failed and the client silently presented nothing.
    private func createCertificates(from data: Data) -> [SecCertificate] {
        let blocks = pemBlocks(data)
        if !blocks.isEmpty {
            let certs = blocks.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
            if !certs.isEmpty { return certs }
        }
        // Not PEM — may already be raw DER.
        if let cert = SecCertificateCreateWithData(nil, data as CFData) { return [cert] }
        return []
    }

    /// The leaf certificate of a bundle.
    private func createCertificate(from data: Data) -> SecCertificate? {
        createCertificates(from: data).first
    }

    private func handleClientCert(
        challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let certData = clientCertData, let keyData = clientKeyData else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        if let identity = createIdentity(certPEM: certData, keyPEM: keyData) {
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

    /// Build a client-certificate identity without ever prompting the user.
    ///
    /// macOS forms a `SecIdentity` only from a keychain-resident key, so a keychain
    /// is unavoidable — but it is a throwaway created for this process, never the
    /// login keychain, and it is deleted on quit (see `TransientKeychain`).
    ///
    /// The route matters. `SecItemAdd` of a `SecKeyCreateWithData` key into a
    /// file-based keychain now fails with `errSecParam` — the approach v0.3.4 used,
    /// which stopped working on a later macOS — and `SecIdentityCreateWithCertificate`
    /// wanders into the login keychain and prompts when it finds nothing. What does
    /// work is importing a PKCS#12 with the destination keychain named explicitly:
    /// it returns the identity directly, with no prompt and nothing left behind.
    private func createIdentity(certPEM: Data, keyPEM: Data) -> SecIdentity? {
        // Before the cache check, not after: the identity is cached for the life of
        // the process but its keychain locks itself on sleep, and using the private
        // key from a locked keychain is what makes macOS prompt. This runs on every
        // handshake because that is where the key is about to be used.
        TransientKeychain.shared.ensureUnlocked()

        if let cached = Self.cachedIdentity { return cached }

        guard let keychain = TransientKeychain.shared.get(),
              let bundle = Self.buildPKCS12(certPEM: certPEM, keyPEM: keyPEM) else {
            Self.clientCertificateUnavailable = true
            return nil
        }

        var options: [String: Any] = [
            kSecImportExportPassphrase as String: bundle.passphrase,
            kSecImportExportKeychain as String: keychain,
        ]
        // Grant "any application" so macOS never challenges for the keychain
        // password. Safe because this keychain is process-private, randomly named
        // and keyed, absent from the search list, and deleted on quit.
        if let access = TransientKeychain.shared.promptlessAccess(label: "K8Secret client certificate") {
            options[kSecImportExportAccess as String] = access
        }

        var items: CFArray?
        guard SecPKCS12Import(bundle.data as CFData, options as CFDictionary, &items) == errSecSuccess,
              let entries = items as? [[String: Any]],
              let identityRef = entries.first?[kSecImportItemIdentity as String] else {
            Self.clientCertificateUnavailable = true
            return nil
        }

        let identity = identityRef as! SecIdentity
        Self.cachedIdentity = identity
        return identity
    }

    /// Built once per process — the conversion forks a subprocess, and the
    /// credentials do not change while the app is running.
    nonisolated(unsafe) private static var cachedIdentity: SecIdentity?

    /// Convert a PEM certificate + key into a PKCS#12 blob.
    ///
    /// Security has no API to assemble one, so this uses the `openssl` that ships
    /// with macOS. The key is the credential for the whole cluster, so it is staged
    /// in a private `0700` directory with `0600` files, the passphrase is random and
    /// single-use, and it is passed through the environment rather than argv —
    /// argv is world-readable via `ps`.
    private static func buildPKCS12(certPEM: Data, keyPEM: Data) -> (data: Data, passphrase: String)? {
        let staging = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("k8secret-identity-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        guard (try? FileManager.default.createDirectory(
            at: staging,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )) != nil else { return nil }

        let certPath = staging.appendingPathComponent("client.pem").path
        let keyPath = staging.appendingPathComponent("client-key.pem").path
        let p12Path = staging.appendingPathComponent("identity.p12").path

        var randomBytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes) == errSecSuccess else {
            return nil
        }
        let passphrase = Data(randomBytes).base64EncodedString()

        let ownerOnly: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        guard FileManager.default.createFile(atPath: certPath, contents: certPEM, attributes: ownerOnly),
              FileManager.default.createFile(atPath: keyPath, contents: keyPEM, attributes: ownerOnly) else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = ["pkcs12", "-export", "-out", p12Path,
                             "-inkey", keyPath, "-in", certPath,
                             "-passout", "env:K8SECRET_P12_PASS"]
        process.environment = ["K8SECRET_P12_PASS": passphrase]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let data = try? Data(contentsOf: URL(fileURLWithPath: p12Path)) else { return nil }
        return (data, passphrase)
    }

    /// Each PEM block decoded to its own DER blob, preserving order.
    ///
    /// Splitting on the BEGIN/END markers is the whole point: a bundle's blocks are
    /// separate DER documents and must not be run together.
    private func pemBlocks(_ data: Data) -> [Data] {
        guard let pem = String(data: data, encoding: .utf8), pem.contains("-----BEGIN") else {
            return []
        }

        var blocks: [Data] = []
        var current: [String] = []
        var inBlock = false

        for rawLine in pem.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("-----BEGIN") {
                inBlock = true
                current = []
            } else if line.hasPrefix("-----END") {
                if inBlock, let der = Data(base64Encoded: current.joined()) {
                    blocks.append(der)
                }
                inBlock = false
                current = []
            } else if inBlock, !line.isEmpty {
                current.append(line)
            }
        }
        return blocks
    }

    /// Convert PEM-encoded data to raw DER bytes, taking the *first* block.
    /// If the data is already raw DER (no PEM headers), returns it unchanged.
    private func pemToDER(_ data: Data) -> Data {
        pemBlocks(data).first ?? data
    }
}
