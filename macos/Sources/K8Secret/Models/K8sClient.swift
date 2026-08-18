import Foundation
import Security

// MARK: - Diagnostic tracing
//
// Off unless K8SECRET_TLS_DEBUG=1 is set. Writes to stderr, so it appears when
// the binary is run from a terminal:
//
//     K8SECRET_TLS_DEBUG=1 .build/release/K8Secret
//
// Deliberately says nothing about key material: certificate subjects, byte
// counts and status codes only.

let k8sTraceEnabled = ProcessInfo.processInfo.environment["K8SECRET_TLS_DEBUG"] == "1"

func k8sTrace(_ message: @autoclosure () -> String) {
    guard k8sTraceEnabled else { return }
    FileHandle.standardError.write(Data("[k8secret] \(message())\n".utf8))
}

/// Human-readable form of a Security.framework status.
func k8sStatusText(_ status: OSStatus) -> String {
    let text = (SecCopyErrorMessageString(status, nil) as String?) ?? "no description"
    return "\(status) (\(text))"
}

enum K8sError: LocalizedError {
    case noConfig
    case noContext
    case noCluster
    case noUser
    case configParse(String)
    case authFailed(String)
    case requestFailed(Int, String)
    case networkError(String)
    case parseError(String)

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
        case .parseError(let msg): return "Parse error: \(msg)"
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
    /// Number of keys, from the list payload — the prototype's Keys column.
    var keyCount: Int = 0

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

struct K8sCronJob: Identifiable, Hashable {
    let id: String
    let name: String
    let namespace: String
    let schedule: String
    let suspended: Bool
    let active: Int
    let lastScheduleTime: Date?
    let lastSuccessfulTime: Date?
    let createdAt: Date

    var age: String { formatAge(createdAt) }
    var lastRun: String { lastScheduleTime.map { formatAge($0) + " ago" } ?? "never" }
    /// The last scheduled run finished successfully iff a success time exists
    /// at or after the schedule time (controller updates success second).
    var lastRunSucceeded: Bool {
        guard let sched = lastScheduleTime else { return true }
        guard let ok = lastSuccessfulTime else { return false }
        return ok >= sched.addingTimeInterval(-1)
    }
}

struct K8sIngress: Identifiable, Hashable {
    struct Rule: Hashable {
        let host: String
        let path: String
        let serviceName: String
        let servicePort: Int
    }

    let id: String
    let name: String
    let namespace: String
    let className: String
    let rules: [Rule]
    let tlsHosts: [String]
    let createdAt: Date

    var age: String { formatAge(createdAt) }
    var primaryHost: String { rules.first?.host ?? "—" }
    var tls: Bool { !tlsHosts.isEmpty }
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
    /// "namespace/object" the event is about — the prototype's attribution.
    var about: String = ""
}

struct K8sJob: Identifiable, Hashable {
    let id: String
    let name: String
    let ownerCronJob: String
    let startTime: Date?
    let completionTime: Date?
    let succeeded: Bool
    let active: Bool

    var duration: String {
        guard let start = startTime else { return "—" }
        let end = completionTime ?? Date()
        let d = Int(end.timeIntervalSince(start))
        if d < 60 { return "\(d)s" }
        return "\(d / 60)m \(d % 60)s"
    }
}

extension K8sCronJob {
    /// Next scheduled run for standard 5-field cron specs (numbers, lists,
    /// */n steps, *); nil when suspended or the spec is beyond this parser.
    var nextRun: Date? {
        guard !suspended else { return nil }
        let fields = schedule.split(separator: " ").map(String.init)
        guard fields.count == 5 else { return nil }
        func matches(_ field: String, _ value: Int) -> Bool {
            if field == "*" { return true }
            for part in field.split(separator: ",").map(String.init) {
                if part.hasPrefix("*/"), let step = Int(part.dropFirst(2)), step > 0 {
                    if value % step == 0 { return true }
                } else if let n = Int(part), n == value {
                    return true
                } else if part.contains("-") {
                    let ends = part.split(separator: "-").compactMap { Int($0) }
                    if ends.count == 2, value >= ends[0], value <= ends[1] { return true }
                }
            }
            return false
        }
        var date = Calendar.current.date(bySetting: .second, value: 0, of: Date()) ?? Date()
        let cal = Calendar.current
        for _ in 0..<(60 * 24 * 366) {
            date = cal.date(byAdding: .minute, value: 1, to: date) ?? date
            let c = cal.dateComponents([.minute, .hour, .day, .month, .weekday], from: date)
            if matches(fields[0], c.minute ?? 0),
               matches(fields[1], c.hour ?? 0),
               matches(fields[2], c.day ?? 1),
               matches(fields[3], c.month ?? 1),
               matches(fields[4], (c.weekday ?? 1) - 1) {
                return date
            }
        }
        return nil
    }

    /// "in 3h 40m" — the prototype's phrasing.
    var nextRunLabel: String {
        guard let next = nextRun else { return "—" }
        let d = Int(next.timeIntervalSinceNow)
        if d < 60 { return "under a minute" }
        if d < 3600 { return "in \(d / 60)m" }
        return "in \(d / 3600)h \((d % 3600) / 60)m"
    }
}

extension K8sPod {
    /// Any container stuck in CrashLoopBackOff — the pod-level truth the
    /// prototype's status pill speaks.
    var isCrashLooping: Bool {
        containers.contains { $0.stateReason == "CrashLoopBackOff" }
    }
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
    case deployments = "Deployments"
    case pods = "Pods"
    case cronjobs = "CronJobs"
    case services = "Services"
    case ingresses = "Ingresses"
    case secrets = "Secrets"
    case configmaps = "ConfigMaps"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .deployments: return "shippingbox"
        case .pods: return "square.3.layers.3d"
        case .cronjobs: return "clock"
        case .services: return "arrow.left.arrow.right"
        case .ingresses: return "globe"
        case .secrets: return "key"
        case .configmaps: return "slider.horizontal.3"
        }
    }
}

/// Where the window is looking. Resources aren't the only destinations any
/// more: Overview answers "is anything wrong?" before drilling in, and Events
/// is the cross-cutting feed the per-resource tabs can't give.
enum AppDestination: Hashable {
    case overview
    case resource(ResourceType)
    case events

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .resource(let t): return t.rawValue
        case .events: return "Events"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "cube.transparent"
        case .resource(let t): return t.icon
        case .events: return "waveform.path.ecg"
        }
    }
}

/// The sidebar's information architecture — resource-first, grouped by what
/// the user is doing, matching the k9s/Lens mental model the redesign adopted:
/// namespace is a *filter* (toolbar scope), resources are *places*.
struct NavGroup: Identifiable {
    let id: String
    let label: String?
    let items: [AppDestination]

    static let all: [NavGroup] = [
        NavGroup(id: "home", label: nil, items: [.overview]),
        NavGroup(id: "workloads", label: "Workloads",
                 items: [.resource(.deployments), .resource(.pods), .resource(.cronjobs)]),
        NavGroup(id: "network", label: "Network",
                 items: [.resource(.services), .resource(.ingresses)]),
        NavGroup(id: "config", label: "Config",
                 items: [.resource(.secrets), .resource(.configmaps)]),
        NavGroup(id: "cluster", label: "Cluster", items: [.events]),
    ]
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

        // With tracing on, take one measured swing at the endpoint first. The
        // async `data(for:)` used everywhere else never delivers task-level
        // callbacks, so the negotiated TLS version — the one fact that differs
        // between a machine where this works and one where it doesn't — is
        // invisible without a task we drive ourselves.
        if k8sTraceEnabled { await traceHandshake() }

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
            let keys = (item["data"] as? [String: Any])?.count ?? 0
            return K8sSecret(id: "\(ns)/\(name)", name: name, namespace: ns, type: type,
                             createdAt: created, keyCount: keys)
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

    func getPodLogs(namespace: String, name: String, container: String?, tailLines: Int = 200,
                    sinceSeconds: Int? = nil) async throws -> String {
        var path = "/api/v1/namespaces/\(Self.encodePath(namespace))/pods/\(Self.encodePath(name))/log?tailLines=\(tailLines)"
        if let since = sinceSeconds {
            path += "&sinceSeconds=\(since)"
        }
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

    // MARK: - CronJobs

    /// Jobs in the namespace, with their owning CronJob (for run history).
    func listJobs(namespace: String) async throws -> [K8sJob] {
        let items = try await listItems(basePath: "/apis/batch/v1/namespaces/\(Self.encodePath(namespace))/jobs")
        return items.compactMap { item in
            guard let meta = item["metadata"] as? [String: Any],
                  let name = meta["name"] as? String else { return nil }
            let status = item["status"] as? [String: Any] ?? [:]
            var owner = ""
            if let owners = meta["ownerReferences"] as? [[String: Any]],
               let first = owners.first(where: { ($0["kind"] as? String) == "CronJob" }) {
                owner = first["name"] as? String ?? ""
            }
            return K8sJob(
                id: name,
                name: name,
                ownerCronJob: owner,
                startTime: parseDate(status["startTime"] as? String),
                completionTime: parseDate(status["completionTime"] as? String),
                succeeded: (status["succeeded"] as? Int ?? 0) > 0,
                active: (status["active"] as? Int ?? 0) > 0
            )
        }
    }

    func listCronJobs(namespace: String) async throws -> [K8sCronJob] {
        let items = try await listItems(basePath: "/apis/batch/v1/namespaces/\(Self.encodePath(namespace))/cronjobs")
        return items.compactMap { Self.parseCronJobStatic($0) }
    }

    /// Pause or resume a schedule. A strategic-merge on `spec.suspend` — nothing
    /// currently running is touched, which is exactly the kubectl semantics.
    func setCronJobSuspended(namespace: String, name: String, suspended: Bool) async throws {
        let patch: [String: Any] = ["spec": ["suspend": suspended]]
        let data = try JSONSerialization.data(withJSONObject: patch)
        _ = try await request(
            path: "/apis/batch/v1/namespaces/\(Self.encodePath(namespace))/cronjobs/\(Self.encodePath(name))",
            method: "PATCH",
            body: data,
            contentType: "application/merge-patch+json"
        )
    }

    /// Run a CronJob now, out of schedule — what `kubectl create job --from=cronjob/x`
    /// does: read the cronjob's jobTemplate and POST it as a Job with a
    /// `generateName` derived from the parent, so runs are attributable.
    func triggerCronJob(namespace: String, name: String) async throws -> String {
        let data = try await request(
            path: "/apis/batch/v1/namespaces/\(Self.encodePath(namespace))/cronjobs/\(Self.encodePath(name))")
        let json = try parseJSON(data)
        guard let spec = json["spec"] as? [String: Any],
              var template = spec["jobTemplate"] as? [String: Any] else {
            throw K8sError.parseError("CronJob \(name) has no jobTemplate")
        }
        var meta = template["metadata"] as? [String: Any] ?? [:]
        meta["generateName"] = "\(name)-manual-"
        // The annotation kubectl sets; controllers and humans both look for it.
        var annotations = meta["annotations"] as? [String: String] ?? [:]
        annotations["cronjob.kubernetes.io/instantiate"] = "manual"
        meta["annotations"] = annotations
        template["metadata"] = meta
        template["apiVersion"] = "batch/v1"
        template["kind"] = "Job"

        let body = try JSONSerialization.data(withJSONObject: template)
        let created = try await request(
            path: "/apis/batch/v1/namespaces/\(Self.encodePath(namespace))/jobs",
            method: "POST",
            body: body,
            contentType: "application/json"
        )
        let createdJSON = try parseJSON(created)
        let createdMeta = createdJSON["metadata"] as? [String: Any]
        return createdMeta?["name"] as? String ?? "\(name)-manual"
    }

    /// Non-private and static so parse coverage doesn't need a live server.
    nonisolated static func parseCronJobStatic(_ item: [String: Any]) -> K8sCronJob? {
        guard let meta = item["metadata"] as? [String: Any],
              let name = meta["name"] as? String,
              let ns = meta["namespace"] as? String,
              let spec = item["spec"] as? [String: Any],
              let schedule = spec["schedule"] as? String else { return nil }
        let status = item["status"] as? [String: Any] ?? [:]
        let active = (status["active"] as? [[String: Any]])?.count ?? 0
        return K8sCronJob(
            id: "\(ns)/\(name)",
            name: name,
            namespace: ns,
            schedule: schedule,
            suspended: spec["suspend"] as? Bool ?? false,
            active: active,
            // map, not a bare call: parseDateStatic coerces absence to a real
            // date, and "never ran" must stay distinguishable from "just ran".
            lastScheduleTime: (status["lastScheduleTime"] as? String).map { parseDateStatic($0) },
            lastSuccessfulTime: (status["lastSuccessfulTime"] as? String).map { parseDateStatic($0) },
            createdAt: parseDateStatic(meta["creationTimestamp"] as? String)
        )
    }

    // MARK: - Ingresses

    func listIngresses(namespace: String) async throws -> [K8sIngress] {
        let items = try await listItems(basePath: "/apis/networking.k8s.io/v1/namespaces/\(Self.encodePath(namespace))/ingresses")
        return items.compactMap { Self.parseIngressStatic($0) }
    }

    nonisolated static func parseIngressStatic(_ item: [String: Any]) -> K8sIngress? {
        guard let meta = item["metadata"] as? [String: Any],
              let name = meta["name"] as? String,
              let ns = meta["namespace"] as? String else { return nil }
        let spec = item["spec"] as? [String: Any] ?? [:]
        let tlsHosts = (spec["tls"] as? [[String: Any]])?
            .flatMap { ($0["hosts"] as? [String]) ?? [] } ?? []

        var rules: [K8sIngress.Rule] = []
        for rule in (spec["rules"] as? [[String: Any]]) ?? [] {
            let host = rule["host"] as? String ?? "*"
            let paths = ((rule["http"] as? [String: Any])?["paths"] as? [[String: Any]]) ?? []
            for p in paths {
                let backend = (p["backend"] as? [String: Any])?["service"] as? [String: Any]
                let port = (backend?["port"] as? [String: Any])
                rules.append(K8sIngress.Rule(
                    host: host,
                    path: p["path"] as? String ?? "/",
                    serviceName: backend?["name"] as? String ?? "",
                    servicePort: port?["number"] as? Int ?? 0
                ))
            }
        }
        return K8sIngress(
            id: "\(ns)/\(name)",
            name: name,
            namespace: ns,
            className: spec["ingressClassName"] as? String ?? "",
            rules: rules,
            tlsHosts: tlsHosts,
            createdAt: parseDateStatic(meta["creationTimestamp"] as? String)
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

    /// POST a manifest to a collection path (create), and delete by path.
    /// Exists for the live test suite's create→operate→delete cycles, and is
    /// generally useful for anything the typed API doesn't cover yet.
    func createRawResource(collectionPath: String, jsonData: Data) async throws {
        _ = try await request(
            path: collectionPath, method: "POST", body: jsonData, contentType: "application/json")
    }

    func deleteRawResource(path: String) async throws {
        _ = try await request(path: path, method: "DELETE")
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
            let obj = e["involvedObject"] as? [String: Any] ?? [:]
            let aboutNS = obj["namespace"] as? String ?? ""
            let aboutName = obj["name"] as? String ?? ""
            return K8sEvent(
                id: name,
                type: e["type"] as? String ?? "Normal",
                reason: e["reason"] as? String ?? "",
                message: e["message"] as? String ?? "",
                count: e["count"] as? Int ?? 1,
                firstSeen: (e["firstTimestamp"] as? String).flatMap { df.date(from: $0) },
                lastSeen: (e["lastTimestamp"] as? String).flatMap { df.date(from: $0) },
                source: source,
                about: aboutName.isEmpty ? "" : (aboutNS.isEmpty ? aboutName : "\(aboutNS)/\(aboutName)")
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
        case .noConfig, .noContext, .noCluster, .noUser, .configParse, .authFailed, .parseError:
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
            // Pass the delegate explicitly: the async `data(for:)` form does not
            // route task-level callbacks — metrics among them — to the session
            // delegate, so the negotiated TLS version was never recorded.
            // The delegate is passed explicitly as the task delegate too. The
            // async form does not reliably route task-level callbacks to the
            // session delegate — that is how the client-certificate challenge
            // went missing in the first place — and naming it here does not
            // depend on which way a given system happens to fall back.
            let (data, response) = try await session.data(
                for: req,
                delegate: session.delegate as? URLSessionTaskDelegate)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                // A 401 right after we failed to build a client identity is not a
                // credentials problem the user can fix by re-reading their token —
                // say what actually happened.
                if http.statusCode == 401,
                   let tlsDelegate = session.delegate as? K8sTLSDelegate,
                   tlsDelegate.clientCertificateUnavailable {
                    throw K8sError.authFailed(
                        "This cluster authenticates with a client certificate, and K8Secret "
                        + "could not build a usable identity from the certificate and key in "
                        + "your kubeconfig. Check that client-certificate-data and "
                        + "client-key-data decode to a matching pair, or use a token instead: "
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
            let ns = error as NSError
            k8sTrace("request FAILED \(method) \(path)")
            k8sTrace("  NSError domain=\(ns.domain) code=\(ns.code)")
            k8sTrace("  localizedDescription=\(ns.localizedDescription)")
            for (key, value) in ns.userInfo where key != NSLocalizedDescriptionKey {
                k8sTrace("  userInfo[\(key)] = \(value)")
            }
            if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
                k8sTrace("  underlying domain=\(underlying.domain) code=\(underlying.code) "
                         + "desc=\(underlying.localizedDescription)")
            }
            // A handshake failure right after we failed to build a client identity
            // is not the server's fault, and "a secure connection cannot be made"
            // sends people to look at the cluster. We know we presented nothing;
            // say so, and name the step that actually broke.
            if ns.domain == NSURLErrorDomain,
               let tlsDelegate = session.delegate as? K8sTLSDelegate {
                // We refused the handshake and know why. Cancelling a challenge
                // surfaces as NSURLErrorCancelled — the bare word "cancelled",
                // which reads as though the user did it — rather than as a TLS
                // error, so this cannot be keyed on the TLS code. It is keyed on
                // having actually recorded a refusal, which nothing else sets.
                if let refusal = tlsDelegate.handshakeRefusal {
                    throw K8sError.networkError("K8Secret closed the connection: \(refusal).")
                }
                guard ns.code == NSURLErrorSecureConnectionFailed else {
                    throw K8sError.networkError(error.localizedDescription)
                }

                // A TLS failure we didn't cause. How far the handshake got says
                // which one it is, and the user cannot see that from "a TLS
                // error caused the secure connection to fail" — a sentence that
                // describes the cluster, our certificate and macOS's own
                // policies equally well.
                let progress = tlsDelegate.handshakeProgress
                let endpoint = URL(string: serverURL)
                let host = endpoint?.host ?? serverURL
                let port = endpoint?.port ?? 443
                if !progress.serverTrust {
                    throw K8sError.networkError(
                        "The TLS handshake with \(host) failed before its certificate could be "
                        + "checked, so this is not about the certificate. macOS and the server "
                        + "could not agree on a TLS version or cipher — recent macOS refuses "
                        + "TLS 1.0 and 1.1 outright. Check what the endpoint terminates TLS with; "
                        + "`openssl s_client -connect \(host):\(port)` will name it."
                    )
                }
                if progress.presented {
                    throw K8sError.networkError(
                        "\(host) rejected this cluster's client certificate and closed the "
                        + "connection. The certificate was read and presented, so it is the "
                        + "certificate itself the server won't take — most often expired, or "
                        + "signed by a CA the cluster has since rotated. `kubectl` would fail "
                        + "the same way; re-fetch your credentials for this cluster."
                    )
                }
                if progress.clientCertAsked {
                    throw K8sError.networkError(
                        "\(host) asked for a client certificate and this context has none, so "
                        + "the server closed the connection. Check the user for this context in "
                        + "your kubeconfig — it needs client-certificate/client-key, a token, or "
                        + "an exec plugin."
                    )
                }
                // We presented nothing because the identity wouldn't build.
                if tlsDelegate.clientCertificateUnavailable {
                    throw K8sError.networkError(
                        "Couldn't present this cluster's client certificate, so the server closed "
                        + "the connection. The certificate and key in your kubeconfig were read, but "
                        + "macOS wouldn't build an identity from them. Re-run with "
                        + "K8SECRET_TLS_DEBUG=1 for the exact step that failed."
                    )
                }
            }
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

    /// Subject, issuer and validity of a client certificate, for the trace.
    ///
    /// An expired client certificate produces the same symptom as everything
    /// else in this area — the server simply stops talking to you — and nothing
    /// in the app has ever looked at the dates. `az aks get-credentials` and
    /// friends issue certificates that do expire.
    static func describeCertificate(_ pem: Data) -> String {
        let blocks = K8sTLSDelegate.pemBlocksStatic(pem)
        let der = blocks.first ?? pem
        guard let cert = SecCertificateCreateWithData(nil, der as CFData) else {
            return "clientCert: could not be parsed as a certificate (\(pem.count) bytes)"
        }
        let subject = (SecCertificateCopySubjectSummary(cert) as String?) ?? "<no subject>"

        var text = "clientCert: subject=\(subject)"
        var error: Unmanaged<CFError>?
        if let values = SecCertificateCopyValues(cert, [kSecOIDX509V1ValidityNotBefore,
                                                        kSecOIDX509V1ValidityNotAfter] as CFArray,
                                                 &error) as? [String: Any] {
            func date(_ oid: CFString) -> Date? {
                guard let entry = values[oid as String] as? [String: Any],
                      let seconds = entry["value"] as? Double else { return nil }
                // Values are seconds since the 2001 reference date.
                return Date(timeIntervalSinceReferenceDate: seconds)
            }
            let formatter = ISO8601DateFormatter()
            if let notBefore = date(kSecOIDX509V1ValidityNotBefore) {
                text += " notBefore=\(formatter.string(from: notBefore))"
            }
            if let notAfter = date(kSecOIDX509V1ValidityNotAfter) {
                text += " notAfter=\(formatter.string(from: notAfter))"
                let days = Int(notAfter.timeIntervalSinceNow / 86_400)
                text += days < 0 ? "  *** EXPIRED \(-days) DAYS AGO ***" : " (\(days) days left)"
            }
        }
        return text
    }

    /// One request run through `dataTask`, purely so its metrics are collected.
    /// Failures are expected and reported, never thrown: this exists to describe
    /// the handshake, not to gate the connection on it.
    private func traceHandshake() async {
        guard let session, let url = URL(string: serverURL) else { return }
        k8sTrace("probe: measuring a handshake with \(url.host ?? serverURL)")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var request = URLRequest(url: url.appendingPathComponent("version"))
            request.timeoutInterval = 20
            let task = session.dataTask(with: request) { _, response, error in
                if let http = response as? HTTPURLResponse {
                    k8sTrace("probe: HTTP \(http.statusCode) — the handshake completed")
                }
                if let error {
                    let ns = error as NSError
                    k8sTrace("probe: failed domain=\(ns.domain) code=\(ns.code) — \(ns.localizedDescription)")
                    if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
                        k8sTrace("probe: underlying domain=\(underlying.domain) code=\(underlying.code) "
                                 + "— \(underlying.localizedDescription)")
                    }
                }
                continuation.resume()
            }
            task.resume()
        }
    }

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

        // Cap at TLS 1.2 when this cluster authenticates with a client
        // certificate, because URLSession cannot present one over TLS 1.3 here.
        //
        // In TLS 1.2 the server asks for the certificate during the handshake and
        // URLSession turns that into an NSURLAuthenticationMethodClientCertificate
        // challenge we answer. TLS 1.3 moved that request after the handshake —
        // and some API server front ends, AKS among them, send nothing during it
        // at all. Probing one directly shows the difference plainly: at TLS 1.2 it
        // offers "Acceptable client certificate CA names", at TLS 1.3 it offers
        // none. URLSession never raises a challenge, we never send the
        // certificate we were holding, and the server closes an unauthenticated
        // connection — surfacing as "a TLS error caused the secure connection to
        // fail", which sounds like the cluster's fault and is not.
        //
        // It also explains why this depended on the machine: whether 1.3 is
        // negotiated is a property of the OS, so the same kubeconfig connects on
        // one Mac and fails on the next. kubectl is unaffected because Go's TLS
        // stack implements post-handshake auth.
        //
        // Scoped to client-certificate clusters: token and exec clusters keep
        // TLS 1.3. The cost is small — 1.2 here negotiates ECDHE with AES-GCM,
        // so forward secrecy and an AEAD cipher either way — and the alternative
        // is not connecting at all.
        // K8SECRET_TLS_MAX=1.3 lifts the cap, =1.2 forces it, unset uses the rule
        // above. The cap is a hypothesis about why a client certificate is never
        // requested, and a hypothesis that cannot be turned off is untestable on
        // the one machine that reproduces the problem.
        // No explicit TLS floor. Setting one to 1.2 alongside the 1.2 ceiling
        // below collapsed the range and broke the handshake outright
        // (errSSLPeerHandshakeFail on a cluster that had been connecting), and
        // it buys nothing: macOS has refused TLS 1.0 and 1.1 by default for
        // years, with or without ATS.

        let capOverride = ProcessInfo.processInfo.environment["K8SECRET_TLS_MAX"]
        let usesClientCert = user.clientCertificateData != nil && user.clientKeyData != nil
        switch capOverride {
        case "1.2":
            sessionConfig.tlsMaximumSupportedProtocolVersion = .TLSv12
            k8sTrace("session: TLS capped at 1.2 (forced by K8SECRET_TLS_MAX)")
        case "1.3":
            sessionConfig.tlsMaximumSupportedProtocolVersion = .TLSv13
            k8sTrace("session: TLS allowed up to 1.3 (forced by K8SECRET_TLS_MAX)")
        default:
            if usesClientCert {
                sessionConfig.tlsMaximumSupportedProtocolVersion = .TLSv12
                k8sTrace("session: TLS capped at 1.2 — this cluster uses a client certificate. "
                         + "Set K8SECRET_TLS_MAX=1.3 to lift this.")
            } else {
                k8sTrace("session: TLS uncapped — this cluster does not use a client certificate")
            }
        }
        k8sTrace("session: auth material — clientCert=\(user.clientCertificateData != nil) "
                 + "clientKey=\(user.clientKeyData != nil) token=\(user.token != nil) "
                 + "exec=\(user.exec != nil) basicAuth=\(user.username != nil)")
        if let certData = user.clientCertificateData {
            k8sTrace("session: " + Self.describeCertificate(certData))
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

final class K8sTLSDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    /// Guards the two pieces of per-connection state below. Delegate callbacks
    /// arrive on arbitrary queues, and this class is `@unchecked Sendable`.
    private let identityLock = NSLock()

    /// Set when a client certificate was configured but no usable identity could be
    /// built, so a 401 can say why instead of just "Unauthorized".
    ///
    /// Per-delegate, and therefore per-cluster. As a `static` this leaked across
    /// windows: one cluster failing to build an identity changed how every other
    /// cluster explained its own 401.
    private var _clientCertificateUnavailable = false
    var clientCertificateUnavailable: Bool {
        identityLock.lock()
        defer { identityLock.unlock() }
        return _clientCertificateUnavailable
    }

    /// Why *we* refused the handshake, if we did.
    ///
    /// When this delegate cancels a challenge, URLSession reports only that a
    /// TLS error occurred — the same sentence whether the server's certificate
    /// failed to verify, the kubeconfig's CA couldn't be parsed, or the server
    /// simply hung up. We always know which; keeping the reason here lets the
    /// error say it instead of asking the user to guess, or to reproduce the
    /// problem on a machine someone else owns.
    /// What the handshake actually got as far as. A TLS failure means something
    /// very different depending on how far we got, and only the delegate knows:
    /// never consulted at all is a negotiation failure below us; consulted for
    /// the server and then dying is the server rejecting what we presented.
    private var _sawServerTrustChallenge = false
    private var _sawClientCertChallenge = false
    private var _presentedClientCertificate = false
    var handshakeProgress: (serverTrust: Bool, clientCertAsked: Bool, presented: Bool) {
        identityLock.lock()
        defer { identityLock.unlock() }
        return (_sawServerTrustChallenge, _sawClientCertChallenge, _presentedClientCertificate)
    }

    private var _handshakeRefusal: String?
    var handshakeRefusal: String? {
        identityLock.lock()
        defer { identityLock.unlock() }
        return _handshakeRefusal
    }

    private func refuse(_ reason: String) {
        identityLock.lock()
        _handshakeRefusal = reason
        identityLock.unlock()
        k8sTrace("  -> cancelAuthenticationChallenge: \(reason)")
    }

    /// The identity built from *this delegate's* certificate and key.
    ///
    /// This was `static`. A delegate is created per cluster and carries that
    /// cluster's `clientCertData`/`clientKeyData` as instance properties, but the
    /// cache in front of them was process-wide: the first client-certificate
    /// cluster to complete a handshake populated it, and every cluster opened
    /// afterwards hit `if let cached` and presented that first cluster's
    /// certificate instead of its own. With several client-cert clusters in one
    /// kubeconfig at most one could connect per launch — the rest had their
    /// certificate rejected during the handshake, which surfaces as
    /// "A TLS error caused the secure connection to fail".
    private var cachedIdentity: SecIdentity?

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

    /// What actually happened on the wire.
    ///
    /// Every other line in this trace is what *we* did; this is what the two
    /// machines agreed on, which is the part that differs between them. Without
    /// it, "the handshake failed" leaves the negotiated version, the cipher and
    /// whether the connection was even reused entirely to guesswork.
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard k8sTraceEnabled else { return }
        for transaction in metrics.transactionMetrics {
            let version = transaction.negotiatedTLSProtocolVersion.map {
                switch $0 {
                case .TLSv10: return "TLS 1.0"
                case .TLSv11: return "TLS 1.1"
                case .TLSv12: return "TLS 1.2"
                case .TLSv13: return "TLS 1.3"
                case .DTLSv10: return "DTLS 1.0"
                case .DTLSv12: return "DTLS 1.2"
                @unknown default: return String(format: "0x%04X", $0.rawValue)
                }
            } ?? "none (handshake did not complete)"
            let suite = transaction.negotiatedTLSCipherSuite.map {
                String(format: "0x%04X", $0.rawValue)
            } ?? "none"
            k8sTrace("metrics: negotiated=\(version) cipher=\(suite) "
                     + "reusedConnection=\(transaction.isReusedConnection) "
                     + "proxy=\(transaction.isProxyConnection) "
                     + "protocol=\(transaction.networkProtocolName ?? "?") "
                     + "remote=\(transaction.remoteAddress ?? "?"):\(transaction.remotePort.map(String.init) ?? "?")")
            if let start = transaction.secureConnectionStartDate {
                let finished = transaction.secureConnectionEndDate
                k8sTrace("metrics: TLS handshake "
                         + (finished == nil
                            ? "started at \(start) and never finished"
                            : "took \(String(format: "%.3f", finished!.timeIntervalSince(start)))s"))
            }
        }
    }

    /// The task-level challenge. This is where client certificates arrive.
    ///
    /// URLSession splits authentication in two. Connection-level challenges —
    /// server trust among them — go to the session delegate. Everything else,
    /// **client certificates included**, is delivered to the *task* delegate,
    /// and only falls back to the session delegate on some systems. macOS 14
    /// falls back; macOS 26 does not.
    ///
    /// With only the session method implemented, the effect on the newer system
    /// was total and silent: the server asked for a certificate, nothing
    /// answered, no certificate was sent, and the API server closed the
    /// connection. The trace showed a server-trust challenge, a completed TLS
    /// 1.2 handshake, and then failure with NSErrorClientCertificateStateKey=0
    /// — none sent — and not one client-certificate challenge anywhere in it.
    ///
    /// Both methods route to the same handler, so behaviour is identical
    /// wherever the challenge happens to be delivered.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        k8sTrace("task-level challenge arrived")
        handle(challenge: challenge, completionHandler: completionHandler)
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handle(challenge: challenge, completionHandler: completionHandler)
    }

    private func handle(
        challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let protection = challenge.protectionSpace

        k8sTrace("challenge: method=\(protection.authenticationMethod) "
                 + "host=\(protection.host):\(protection.port) "
                 + "caBytes=\(caData?.count ?? -1) "
                 + "clientCertBytes=\(clientCertData?.count ?? -1) "
                 + "clientKeyBytes=\(clientKeyData?.count ?? -1) "
                 + "insecure=\(insecure)")

        if protection.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            identityLock.lock(); _sawServerTrustChallenge = true; identityLock.unlock()
            handleServerTrust(challenge: challenge, completionHandler: completionHandler)
        } else if protection.authenticationMethod == NSURLAuthenticationMethodClientCertificate {
            identityLock.lock(); _sawClientCertChallenge = true; identityLock.unlock()
            handleClientCert(challenge: challenge, completionHandler: completionHandler)
        } else {
            k8sTrace("  -> performDefaultHandling (unhandled challenge type)")
            completionHandler(.performDefaultHandling, nil)
        }
    }

    private func handleServerTrust(
        challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let trust = challenge.protectionSpace.serverTrust else {
            refuse("the server offered no certificate to evaluate")
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
        k8sTrace("  serverTrust: anchors parsed from kubeconfig CA = \(caCerts.count)")
        for cert in caCerts {
            k8sTrace("    anchor: \((SecCertificateCopySubjectSummary(cert) as String?) ?? "<none>")")
        }
        if let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] {
            k8sTrace("  serverTrust: server presented \(chain.count) certificate(s)")
            for cert in chain {
                k8sTrace("    served: \((SecCertificateCopySubjectSummary(cert) as String?) ?? "<none>")")
            }
        }
        guard !caCerts.isEmpty else {
            // A CA was configured but we couldn't parse it. Refusing is the only
            // safe option: falling back to system roots would silently accept a
            // certificate the user never intended to trust.
            refuse("this cluster's certificate-authority-data could not be read as a "
                   + "certificate — \(caData.count) bytes that are neither PEM nor DER")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Evaluate the server chain against the kubeconfig CA *only*, and keep
        // hostname verification on by binding an SSL policy for the requested host.
        let policy = SecPolicyCreateSSL(true, challenge.protectionSpace.host as CFString)
        SecTrustSetPolicies(trust, policy)
        SecTrustSetAnchorCertificates(trust, caCerts as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)

        var trustError: CFError?
        if SecTrustEvaluateWithError(trust, &trustError) {
            k8sTrace("  serverTrust: PASS -> useCredential")
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            let detail = trustError
                .flatMap { CFErrorCopyDescription($0) as String? }
                ?? "no reason given"
            if let trustError {
                k8sTrace("  serverTrust: FAIL domain=\(CFErrorGetDomain(trustError) as String? ?? "?") "
                         + "code=\(CFErrorGetCode(trustError)) reason=\(detail)")
            } else {
                k8sTrace("  serverTrust: FAIL (no CFError returned)")
            }
            // Name the host: with hostname verification on, the commonest cause is
            // a server certificate that doesn't cover the address in the
            // kubeconfig — which the user can check.
            refuse("the server's certificate for \(challenge.protectionSpace.host) did not "
                   + "verify against this cluster's certificate-authority-data — \(detail)")
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
        if let issuers = challenge.protectionSpace.distinguishedNames {
            k8sTrace("  clientCert: server accepts \(issuers.count) issuer name(s)")
        }

        guard let certData = clientCertData, let keyData = clientKeyData else {
            k8sTrace("  clientCert: none configured -> performDefaultHandling "
                     + "(NO certificate is presented; the server will drop the handshake "
                     + "if it requires one)")
            completionHandler(.performDefaultHandling, nil)
            return
        }

        if let identity = createIdentity(certPEM: certData, keyPEM: keyData) {
            var certRef: SecCertificate?
            SecIdentityCopyCertificate(identity, &certRef)
            k8sTrace("  clientCert: presenting "
                     + "\(certRef.flatMap { SecCertificateCopySubjectSummary($0) as String? } ?? "<unknown>")")
            let credential = URLCredential(
                identity: identity,
                certificates: nil,
                persistence: .forSession
            )
            identityLock.lock(); _presentedClientCertificate = true; identityLock.unlock()
            completionHandler(.useCredential, credential)
        } else {
            k8sTrace("  clientCert: identity could NOT be built -> performDefaultHandling "
                     + "(no certificate presented)")
            completionHandler(.performDefaultHandling, nil)
        }
    }

    /// Build a client-certificate identity without ever prompting the user.
    ///
    /// This used to import into a throwaway file-based keychain, because macOS
    /// was believed to form a `SecIdentity` only from a keychain-resident key.
    /// That has not been true for years: `SecPKCS12Import` with no destination
    /// keychain returns an identity whose key lives only in this process, and it
    /// signs a handshake exactly as well — verified against a server that
    /// *requires* a client certificate.
    ///
    /// Dropping the keychain removes the only deprecated API left in the app and,
    /// more usefully, an entire class of bug: that keychain locked itself when the
    /// Mac slept, and using a key from a locked keychain is what made macOS ask
    /// for a password nobody could answer — it was randomly generated and held in
    /// memory. There is now no keychain to lock, nothing written to disk, and
    /// nothing to clean up on quit.
    private func createIdentity(certPEM: Data, keyPEM: Data) -> SecIdentity? {
        identityLock.lock()
        let cached = cachedIdentity
        identityLock.unlock()
        if let cached {
            k8sTrace("    createIdentity: returning cached identity for THIS delegate")
            return cached
        }

        func unavailable() -> SecIdentity? {
            identityLock.lock()
            _clientCertificateUnavailable = true
            identityLock.unlock()
            return nil
        }

        guard let bundle = Self.buildPKCS12(certPEM: certPEM, keyPEM: keyPEM) else {
            k8sTrace("    createIdentity: buildPKCS12 -> nil (openssl failed)")
            return unavailable()
        }
        k8sTrace("    createIdentity: buildPKCS12 -> \(bundle.data.count) bytes")

        // Keep the identity in memory. Apple's own note on SecPKCS12Import:
        // "The normal behavior of this function is to import items into process
        // memory on iOS, and *into the default keychain on macOS*." That default
        // is what made this app start writing users' cluster keys into their
        // login keychain, and then asking them for a keychain password to use
        // one — an ad-hoc signed app gets a fresh signature every release, so
        // macOS sees each update as a different application reaching for an item
        // the last one stored, and challenges it.
        //
        // kSecImportToMemoryOnly says don't store it, which is what this app
        // always wanted: the key is needed for one handshake, in one process,
        // and belongs nowhere else.
        var options: [String: Any] = [kSecImportExportPassphrase as String: bundle.passphrase]
        if #available(macOS 15.0, *) {
            options[kSecImportToMemoryOnly as String] = true
            k8sTrace("    createIdentity: importing to memory only, nothing is stored")
        } else {
            // macOS 14 has no way to say this, so the import lands in the default
            // keychain. It is removed again below.
            k8sTrace("    createIdentity: macOS 14 — import goes via the keychain and is cleaned up")
        }

        var items: CFArray?
        let importStatus = SecPKCS12Import(bundle.data as CFData, options as CFDictionary, &items)
        k8sTrace("    createIdentity: SecPKCS12Import -> \(k8sStatusText(importStatus))")

        guard importStatus == errSecSuccess,
              let entries = items as? [[String: Any]],
              let identityRef = entries.first?[kSecImportItemIdentity as String] else {
            // errSecPkcs12VerifyFailure (-25264) here says "wrong password?", which
            // is misleading: the passphrase was generated moments ago and used
            // once. It means Security would not read the bundle's encryption —
            // see buildPKCS12, which pins the algorithms it accepts.
            k8sTrace("    createIdentity: no identity in imported bundle")
            return unavailable()
        }

        let identity = identityRef as! SecIdentity

        // On macOS 14 the import persisted; take it back out. The identity we
        // already hold keeps working for this process, and nothing is left in
        // the user's keychain to prompt about later.
        if #unavailable(macOS 15.0) {
            var certificate: SecCertificate?
            SecIdentityCopyCertificate(identity, &certificate)
            if let certificate {
                let removed = SecItemDelete([
                    kSecClass as String: kSecClassCertificate,
                    kSecValueRef as String: certificate,
                ] as CFDictionary)
                k8sTrace("    createIdentity: removed the stored certificate -> \(k8sStatusText(removed))")
            }
        }

        identityLock.lock()
        cachedIdentity = identity
        identityLock.unlock()
        return identity
    }

    /// Convert a PEM certificate + key into a PKCS#12 blob.
    ///
    /// Security has no API to assemble one, so this uses the `openssl` that ships
    /// with macOS. The key is the credential for the whole cluster, so it is staged
    /// in a private `0700` directory with `0600` files, the passphrase is random and
    /// single-use, and it is passed through the environment rather than argv —
    /// argv is world-readable via `ps`.
    /// Internal rather than private so a test can hold it to its contract:
    /// whatever openssl this machine ships, the bundle must be one that
    /// Security.framework will import.
    static func buildPKCS12(certPEM: Data, keyPEM: Data) -> (data: Data, passphrase: String)? {
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

        // Pin the PKCS#12 algorithms rather than taking openssl's defaults.
        //
        // Security.framework only imports the legacy PKCS#12 encryption. Apple's
        // LibreSSL still defaults to it, so this worked — but the default is a
        // property of whichever openssl the machine happens to ship, not of
        // anything we control. OpenSSL 3.x defaults to AES-256-CBC with a SHA-256
        // MAC, and `SecPKCS12Import` rejects that with errSecPkcs12VerifyFailure
        // (-25264), whose message claims a wrong password. The identity then can't
        // be built, no client certificate is presented, and the server drops the
        // handshake — which surfaces as "a secure connection cannot be made", three
        // steps removed from the actual cause.
        //
        // 3DES for both bags with a SHA-1 MAC is what Security accepts, and unlike
        // the RC2 that openssl otherwise picks for certificates it doesn't need
        // OpenSSL 3.x's legacy provider.
        let pinned = ["-certpbe", "PBE-SHA1-3DES", "-keypbe", "PBE-SHA1-3DES", "-macalg", "sha1"]

        func export(_ extraArguments: [String]) -> Data? {
            try? FileManager.default.removeItem(atPath: p12Path)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
            process.arguments = ["pkcs12", "-export", "-out", p12Path,
                                 "-inkey", keyPath, "-in", certPath,
                                 "-passout", "env:K8SECRET_P12_PASS"] + extraArguments
            process.environment = ["K8SECRET_P12_PASS": passphrase]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch {
                k8sTrace("    buildPKCS12: could not run /usr/bin/openssl — \(error.localizedDescription)")
                return nil
            }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                k8sTrace("    buildPKCS12: openssl exited \(process.terminationStatus) "
                         + "for arguments \(extraArguments.isEmpty ? "<defaults>" : extraArguments.joined(separator: " "))")
                return nil
            }
            return try? Data(contentsOf: URL(fileURLWithPath: p12Path))
        }

        if let data = export(pinned) {
            k8sTrace("    buildPKCS12: exported with pinned legacy algorithms")
            return (data, passphrase)
        }
        // An openssl that rejects those flags is not one we know of, but falling
        // back to its defaults is strictly better than failing outright: on a
        // machine whose defaults Security accepts, this still connects.
        if let data = export([]) {
            k8sTrace("    buildPKCS12: pinned flags rejected; exported with openssl defaults")
            return (data, passphrase)
        }
        return nil
    }

    /// Each PEM block decoded to its own DER blob, preserving order.
    ///
    /// Splitting on the BEGIN/END markers is the whole point: a bundle's blocks are
    /// separate DER documents and must not be run together.
    static func pemBlocksStatic(_ data: Data) -> [Data] {
        K8sTLSDelegate(caData: nil, clientCertData: nil, clientKeyData: nil, insecure: false)
            .pemBlocks(data)
    }

    fileprivate func pemBlocks(_ data: Data) -> [Data] {
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
