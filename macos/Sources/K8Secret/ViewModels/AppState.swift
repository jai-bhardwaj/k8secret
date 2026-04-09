import SwiftUI

@MainActor
@Observable
final class AppState {
    // Connection
    var context: String = ""
    var availableContexts: [String] = []
    var connectionState: ConnectionState = .connecting
    var k8sVersion: String = ""
    var clusterUser: String = ""

    // Cluster metrics
    var clusterCPUPercent: Int = 0
    var clusterMemPercent: Int = 0
    var clusterCPUUsed: String = ""
    var clusterCPUTotal: String = ""
    var clusterMemUsed: String = ""
    var clusterMemTotal: String = ""

    // Resource type
    var selectedResourceType: ResourceType = .deployments

    // Data
    var namespaces: [K8sNamespace] = []
    var secrets: [K8sSecret] = []
    var secretData: [K8sKeyValue] = []
    var deployments: [K8sDeployment] = []
    var pods: [K8sPod] = []
    var podMetrics: [String: PodMetrics] = [:]  // keyed by pod name
    var services: [K8sService] = []
    var events: [K8sEvent] = []
    var podLogs: String = ""
    var rawYAML: String = ""

    // Selection
    var selectedNamespace: K8sNamespace?
    var selectedSecret: K8sSecret?
    var selectedDeployment: K8sDeployment?
    var selectedPod: K8sPod?
    var selectedService: K8sService?

    // Search
    var namespaceSearch: String = ""
    var secretSearch: String = ""
    var kvSearch: String = ""
    var deploymentSearch: String = ""
    var podSearch: String = ""
    var serviceSearch: String = ""

    // Edit state
    var editingKey: K8sKeyValue?
    var isAddingKey = false
    var newKeyName = ""
    var newKeyValue = ""
    var editValue = ""
    var showBulkImport = false
    var showYAMLEditor = false
    var yamlResourcePath: String = ""

    // Changes
    var modifications: [String: String] = [:]
    var deletions: Set<String> = []
    var additions: [String: String] = [:]

    // Loading states
    var loadingSecrets = false
    var loadingData = false
    var loadingDeployments = false
    var loadingPods = false
    var loadingServices = false
    var loadingLogs = false
    var loadingYAML = false
    var saving = false
    var scaling = false
    var rollingOut = false
    var rolloutProgress: String = ""

    // Polling
    private var pollTask: Task<Void, Never>?
    private var detailPollTask: Task<Void, Never>?
    private var metricsPollTask: Task<Void, Never>?
    private var clusterMetricsPollTask: Task<Void, Never>?

    // Confirmation
    var confirmAction: ConfirmAction?

    // Toast
    var toastMessage: String?
    var toastIsError = false

    // Initial context for this window
    var initialContext: String?

    // Client
    private let client = K8sClient()

    init(initialContext: String? = nil) {
        self.initialContext = initialContext
    }

    struct ConfirmAction: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let destructive: Bool
        let action: () async -> Void
    }

    enum ConnectionState: Equatable {
        case connecting
        case connected
        case disconnected(String)
    }

    var hasChanges: Bool {
        !modifications.isEmpty || !deletions.isEmpty || !additions.isEmpty
    }

    var changeCount: Int {
        modifications.count + deletions.count + additions.count
    }

    // MARK: - Filtered lists

    var filteredNamespaces: [K8sNamespace] {
        if namespaceSearch.isEmpty { return namespaces }
        return namespaces.filter { $0.name.localizedCaseInsensitiveContains(namespaceSearch) }
    }

    var filteredSecrets: [K8sSecret] {
        if secretSearch.isEmpty { return secrets }
        return secrets.filter {
            $0.name.localizedCaseInsensitiveContains(secretSearch) ||
            $0.type.localizedCaseInsensitiveContains(secretSearch)
        }
    }

    var filteredDeployments: [K8sDeployment] {
        if deploymentSearch.isEmpty { return deployments }
        return deployments.filter {
            $0.name.localizedCaseInsensitiveContains(deploymentSearch) ||
            $0.images.joined(separator: " ").localizedCaseInsensitiveContains(deploymentSearch)
        }
    }

    var filteredPods: [K8sPod] {
        if podSearch.isEmpty { return pods }
        return pods.filter {
            $0.name.localizedCaseInsensitiveContains(podSearch) ||
            $0.phase.localizedCaseInsensitiveContains(podSearch) ||
            $0.nodeName.localizedCaseInsensitiveContains(podSearch)
        }
    }

    var filteredServices: [K8sService] {
        if serviceSearch.isEmpty { return services }
        return services.filter {
            $0.name.localizedCaseInsensitiveContains(serviceSearch) ||
            $0.type.localizedCaseInsensitiveContains(serviceSearch)
        }
    }

    /// Get metrics for a specific pod
    func metrics(for podName: String) -> PodMetrics? {
        podMetrics[podName]
    }

    var displayedKVs: [DisplayKV] {
        var rows: [DisplayKV] = []

        for kv in secretData {
            if deletions.contains(kv.key) {
                rows.append(DisplayKV(id: kv.key, key: kv.key, value: kv.value, status: .deleted))
            } else if let newVal = modifications[kv.key] {
                rows.append(DisplayKV(id: kv.key, key: kv.key, value: newVal, originalValue: kv.value, status: .modified))
            } else {
                rows.append(DisplayKV(id: kv.key, key: kv.key, value: kv.value, status: .none))
            }
        }

        for (key, value) in additions.sorted(by: { $0.key < $1.key }) {
            rows.append(DisplayKV(id: "new_\(key)", key: key, value: value, status: .added))
        }

        if !kvSearch.isEmpty {
            rows = rows.filter {
                $0.key.localizedCaseInsensitiveContains(kvSearch) ||
                $0.value.localizedCaseInsensitiveContains(kvSearch)
            }
        }

        return rows
    }

    /// Check if a key already exists in the current secret.
    func keyExists(_ key: String) -> Bool {
        secretData.contains(where: { $0.key == key }) || additions[key] != nil
    }

    // MARK: - Actions

    private static let lastContextKey = "K8Secret.lastContext"

    func connect(toContext: String? = nil) async {
        connectionState = .connecting
        // Load available contexts
        if let contexts = try? await client.availableContexts() {
            availableContexts = contexts
        }
        // Priority: explicit arg > initialContext (for this window) > saved default
        let targetContext = toContext ?? initialContext ?? UserDefaults.standard.string(forKey: Self.lastContextKey)
        // Consume initialContext so subsequent retries/switches don't force it
        if initialContext != nil && toContext == nil { initialContext = nil }
        do {
            let ctx = try await client.connect(context: targetContext)
            context = ctx
            UserDefaults.standard.set(ctx, forKey: Self.lastContextKey)
            connectionState = .connected

            // Fetch cluster info
            if let ver = try? await client.getServerVersion() { k8sVersion = ver }
            // Get user from kubeconfig context
            if let cfg = try? KubeConfig.load() {
                clusterUser = cfg.activeUser()?.name ?? ""
            }

            await loadClusterMetrics()
            startClusterMetricsPolling()
            await loadNamespaces()
        } catch {
            connectionState = .disconnected(error.localizedDescription)
        }
    }

    func switchContext(_ newContext: String) async {
        guard newContext != context else { return }
        UserDefaults.standard.set(newContext, forKey: Self.lastContextKey)
        // Reset all state
        selectedNamespace = nil
        selectedSecret = nil
        namespaces = []
        secrets = []
        secretData = []
        clearChanges()
        namespaceSearch = ""
        secretSearch = ""
        kvSearch = ""
        await connect(toContext: newContext)
    }

    func loadNamespaces() async {
        do {
            namespaces = try await client.listNamespaces()
        } catch {
            showToast("Failed to load namespaces: \(error.localizedDescription)", isError: true)
        }
    }

    func selectNamespace(_ ns: K8sNamespace) async {
        selectedNamespace = ns
        clearSelections()
        await loadResourcesForCurrentType()
    }

    private func clearSelections() {
        stopDetailPolling()
        stopRolloutPolling()
        stopMetricsPolling()
        selectedSecret = nil
        selectedDeployment = nil
        selectedPod = nil
        selectedService = nil
        clearChanges()
        secretData = []
        podMetrics = [:]
        secretSearch = ""
        deploymentSearch = ""
        podSearch = ""
        serviceSearch = ""
        kvSearch = ""
        podLogs = ""
        rawYAML = ""
        events = []
    }

    func selectResourceType(_ type: ResourceType) async {
        clearSelections()
        selectedResourceType = type
        if selectedNamespace != nil {
            await loadResourcesForCurrentType()
        }
    }

    func loadResourcesForCurrentType() async {
        guard let ns = selectedNamespace else { return }
        switch selectedResourceType {
        case .secrets:
            loadingSecrets = true
            do { secrets = try await client.listSecrets(namespace: ns.name) }
            catch { showToast("Failed to load secrets: \(error.localizedDescription)", isError: true) }
            loadingSecrets = false
        case .deployments:
            loadingDeployments = true
            do { deployments = try await client.listDeployments(namespace: ns.name) }
            catch { showToast("Failed to load deployments: \(error.localizedDescription)", isError: true) }
            loadingDeployments = false
        case .pods:
            loadingPods = true
            do {
                pods = try await client.listPods(namespace: ns.name)
                // Fetch metrics in parallel
                if let metrics = try? await client.getPodMetrics(namespace: ns.name) {
                    podMetrics = Dictionary(uniqueKeysWithValues: metrics.map { ($0.name, $0) })
                }
            }
            catch { showToast("Failed to load pods: \(error.localizedDescription)", isError: true) }
            loadingPods = false
            startMetricsPolling()
        case .services:
            stopMetricsPolling()
            loadingServices = true
            do { services = try await client.listServices(namespace: ns.name) }
            catch { showToast("Failed to load services: \(error.localizedDescription)", isError: true) }
            loadingServices = false
        }
    }

    // MARK: - Secret selection

    func selectSecret(_ secret: K8sSecret) async {
        selectedSecret = secret
        clearChanges()
        kvSearch = ""
        await loadSecretData()
    }

    func loadSecretData() async {
        guard let ns = selectedNamespace, let secret = selectedSecret else { return }
        loadingData = true
        do {
            secretData = try await client.getSecretData(namespace: ns.name, name: secret.name)
        } catch {
            showToast("Failed to load secret data: \(error.localizedDescription)", isError: true)
        }
        loadingData = false
    }

    // MARK: - Bulk Import

    func bulkImport(pairs: [(String, String)], replace: Bool) {
        if replace {
            // Mark all existing keys for deletion
            for kv in secretData {
                if !pairs.contains(where: { $0.0 == kv.key }) {
                    deletions.insert(kv.key)
                }
            }
        }
        for (key, value) in pairs {
            if secretData.contains(where: { $0.key == key }) {
                modifications[key] = value
            } else {
                additions[key] = value
            }
        }
        showToast("Imported \(pairs.count) key-value pairs")
    }

    func exportAsEnv() -> String {
        secretData.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
    }

    func exportAsJSON() -> String {
        var dict: [String: String] = [:]
        for kv in secretData { dict[kv.key] = kv.value }
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    // MARK: - YAML Editor

    func loadRawYAML(apiPath: String) async {
        yamlResourcePath = apiPath
        loadingYAML = true
        do {
            let data = try await client.getRawResource(path: apiPath)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            rawYAML = YAMLSerializer.serialize(json)
        } catch {
            rawYAML = "# Error loading resource: \(error.localizedDescription)"
        }
        loadingYAML = false
    }

    func applyRawYAML() async {
        guard !yamlResourcePath.isEmpty else { return }
        saving = true
        do {
            let parsed = YAMLParser.parse(rawYAML)
            let dict = yamlValueToDict(parsed)
            let jsonData = try JSONSerialization.data(withJSONObject: dict)
            try await client.applyRawResource(path: yamlResourcePath, jsonData: jsonData)
            showToast("YAML applied successfully")
        } catch {
            showToast("Failed to apply YAML: \(error.localizedDescription)", isError: true)
        }
        saving = false
    }

    private func yamlValueToDict(_ value: YAMLValue) -> Any {
        switch value {
        case .string(let s): return s
        case .map(let m):
            var dict: [String: Any] = [:]
            for (k, v) in m { dict[k] = yamlValueToDict(v) }
            return dict
        case .sequence(let arr): return arr.map { yamlValueToDict($0) }
        case .null: return NSNull()
        }
    }

    // MARK: - Deployment actions

    func selectDeployment(_ dep: K8sDeployment) async {
        selectedDeployment = dep
        await loadEvents(for: "Deployment", name: dep.name)
        startDetailPolling()
    }

    // MARK: - Detail Polling (keeps the right panel fresh)

    func startDetailPolling() {
        stopDetailPolling()

        detailPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if Task.isCancelled { break }

                guard let self,
                      let dep = self.selectedDeployment,
                      let ns = self.selectedNamespace else { break }

                // Fetch only the single deployment
                if let updated = try? await self.client.getDeployment(namespace: ns.name, name: dep.name) {
                    self.selectedDeployment = updated
                    // Update in the list too so the sidebar row stays in sync
                    if let idx = self.deployments.firstIndex(where: { $0.id == updated.id }) {
                        self.deployments[idx] = updated
                    }
                }

                // Refresh events silently
                await self.loadEvents(for: "Deployment", name: dep.name)
            }
        }
    }

    func stopDetailPolling() {
        detailPollTask?.cancel()
        detailPollTask = nil
    }

    // MARK: - Metrics Polling (real-time pod metrics)

    func startMetricsPolling() {
        stopMetricsPolling()

        metricsPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if Task.isCancelled { break }

                guard let self, let ns = self.selectedNamespace,
                      self.selectedResourceType == .pods else { break }

                // Refresh pod list (catches HPA scale-up/down, restarts, new pods)
                if let updatedPods = try? await self.client.listPods(namespace: ns.name) {
                    self.pods = updatedPods
                    // Re-select if the selected pod was updated
                    if let selected = self.selectedPod,
                       let refreshed = updatedPods.first(where: { $0.id == selected.id }) {
                        self.selectedPod = refreshed
                    } else if let selected = self.selectedPod,
                              !updatedPods.contains(where: { $0.id == selected.id }) {
                        // Pod was removed (scaled down / evicted)
                        self.selectedPod = nil
                    }
                }

                // Refresh metrics
                if let metrics = try? await self.client.getPodMetrics(namespace: ns.name) {
                    self.podMetrics = Dictionary(uniqueKeysWithValues: metrics.map { ($0.name, $0) })
                }
            }
        }
    }

    func stopMetricsPolling() {
        metricsPollTask?.cancel()
        metricsPollTask = nil
    }

    // MARK: - Cluster Metrics

    func loadClusterMetrics() async {
        do {
            let m = try await client.getClusterMetrics()
            clusterCPUPercent = m.cpuPercent
            clusterMemPercent = m.memPercent
            clusterCPUUsed = formatCPU(m.cpuUsed)
            clusterCPUTotal = formatCPU(m.cpuTotal)
            clusterMemUsed = formatMem(m.memUsedKi)
            clusterMemTotal = formatMem(m.memTotalKi)
        } catch { /* silently fail — metrics may not be available */ }
    }

    func startClusterMetricsPolling() {
        clusterMetricsPollTask?.cancel()
        clusterMetricsPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                if Task.isCancelled { break }
                guard let self else { break }
                await self.loadClusterMetrics()
            }
        }
    }

    private func formatCPU(_ millis: Int) -> String {
        if millis >= 1000 { return String(format: "%.1f cores", Double(millis) / 1000) }
        return "\(millis)m"
    }

    private func formatMem(_ ki: Int) -> String {
        if ki >= 1024 * 1024 { return String(format: "%.1fGi", Double(ki) / 1024 / 1024) }
        if ki >= 1024 { return String(format: "%.0fMi", Double(ki) / 1024) }
        return "\(ki)Ki"
    }

    func restartDeployment(_ dep: K8sDeployment) async {
        do {
            try await client.restartDeployment(namespace: dep.namespace, name: dep.name)
            showToast("Rolling restart initiated for \(dep.name)")
            startRolloutPolling(deploymentId: dep.id)
        } catch {
            showToast("Restart failed: \(error.localizedDescription)", isError: true)
        }
    }

    func scaleDeployment(_ dep: K8sDeployment, to replicas: Int) async {
        scaling = true
        do {
            try await client.scaleDeployment(namespace: dep.namespace, name: dep.name, replicas: replicas)
            showToast("Scaled \(dep.name) to \(replicas) replicas")
            startRolloutPolling(deploymentId: dep.id)
        } catch {
            showToast("Scale failed: \(error.localizedDescription)", isError: true)
        }
        scaling = false
    }

    // MARK: - Rollout Polling

    func startRolloutPolling(deploymentId: String) {
        stopRolloutPolling()
        rollingOut = true
        rolloutProgress = "Waiting for rollout to begin..."

        // Extract namespace and name from the id (format: "ns/name")
        let parts = deploymentId.split(separator: "/")
        guard parts.count == 2 else { return }
        let ns = String(parts[0])
        let depName = String(parts[1])

        pollTask = Task { [weak self] in
            guard let self else { return }

            // Wait for k8s to process the change — the deployment's
            // observedGeneration needs to catch up before status is meaningful
            try? await Task.sleep(for: .seconds(3))

            var sawProgressing = false

            for tick in 0..<60 { // Max 3 minutes
                if Task.isCancelled { break }

                // Fetch ONLY this deployment, not the whole namespace
                guard let updated = try? await self.client.getDeployment(namespace: ns, name: depName) else {
                    self.rolloutProgress = "Failed to fetch deployment status"
                    try? await Task.sleep(for: .seconds(3))
                    continue
                }

                // Update the selected deployment and its entry in the list
                self.selectedDeployment = updated
                if let idx = self.deployments.firstIndex(where: { $0.id == deploymentId }) {
                    self.deployments[idx] = updated
                }

                // Silently refresh events (no loading state)
                await self.loadEvents(for: "Deployment", name: depName)

                // Build progress text
                self.rolloutProgress = "\(updated.readyReplicas)/\(updated.replicas) ready · \(updated.updatedReplicas)/\(updated.replicas) updated · \(updated.availableReplicas)/\(updated.replicas) available"

                // Check if rollout has started (replicas mismatch = progressing)
                let isProgressing = updated.readyReplicas != updated.replicas
                    || updated.updatedReplicas != updated.replicas
                    || updated.availableReplicas != updated.replicas
                if isProgressing {
                    sawProgressing = true
                }

                // Rollout is complete when all counts match AND we either
                // saw it progressing or have waited long enough for k8s to start
                let isComplete = updated.replicas > 0
                    && updated.readyReplicas == updated.replicas
                    && updated.updatedReplicas == updated.replicas
                    && updated.availableReplicas == updated.replicas

                if isComplete && (sawProgressing || tick >= 3) {
                    self.rolloutProgress = "Rollout complete"
                    self.showToast("Rollout complete — all \(updated.replicas) replicas ready")
                    // Keep the banner visible briefly so user sees "complete"
                    try? await Task.sleep(for: .seconds(3))
                    break
                }

                // Scaled to 0
                if updated.replicas == 0 && (sawProgressing || tick >= 3) {
                    self.rolloutProgress = "Scaled to 0"
                    try? await Task.sleep(for: .seconds(2))
                    break
                }

                if tick == 59 {
                    self.rolloutProgress = "Rollout still in progress..."
                    self.showToast("Rollout is taking longer than expected", isError: false)
                }

                try? await Task.sleep(for: .seconds(3))
            }

            self.rollingOut = false
            self.rolloutProgress = ""
        }
    }

    func stopRolloutPolling() {
        pollTask?.cancel()
        pollTask = nil
        rollingOut = false
        rolloutProgress = ""
    }

    // MARK: - Pod actions

    func selectPod(_ pod: K8sPod) async {
        selectedPod = pod
        podLogs = ""
        await loadEvents(for: "Pod", name: pod.name)
    }

    func loadPodLogs(container: String? = nil) async {
        guard let ns = selectedNamespace, let pod = selectedPod else { return }
        loadingLogs = true
        do {
            podLogs = try await client.getPodLogs(namespace: ns.name, name: pod.name, container: container)
            if podLogs.isEmpty { podLogs = "(no logs available)" }
        } catch {
            podLogs = "Error loading logs: \(error.localizedDescription)"
        }
        loadingLogs = false
    }

    func deletePod(_ pod: K8sPod) async {
        do {
            try await client.deletePod(namespace: pod.namespace, name: pod.name)
            showToast("Deleted pod \(pod.name)")
            selectedPod = nil
            try? await Task.sleep(for: .seconds(1))
            await loadResourcesForCurrentType()
        } catch {
            showToast("Delete failed: \(error.localizedDescription)", isError: true)
        }
    }

    // MARK: - Service selection

    func selectService(_ svc: K8sService) async {
        selectedService = svc
        await loadEvents(for: "Service", name: svc.name)
    }

    // MARK: - Events

    func loadEvents(for kind: String, name: String) async {
        // Nodes are cluster-scoped, events are in default namespace
        let ns = selectedNamespace?.name ?? "default"
        do {
            events = try await client.getEvents(
                namespace: ns,
                fieldSelector: "involvedObject.name=\(name),involvedObject.kind=\(kind)"
            )
        } catch {
            events = []
        }
    }

    // MARK: - Refresh

    func refreshCurrentResource() async {
        await loadResourcesForCurrentType()
        // Re-select current item to refresh detail
        if let dep = selectedDeployment {
            if let updated = deployments.first(where: { $0.id == dep.id }) {
                selectedDeployment = updated
            }
        }
    }

    func stageEdit(key: String, value: String) {
        // Check if it's a new key
        if additions[key] != nil {
            additions[key] = value
            return
        }
        // Check if value matches original
        if let original = secretData.first(where: { $0.key == key }) {
            if original.value == value {
                modifications.removeValue(forKey: key)
            } else {
                modifications[key] = value
            }
        }
    }

    func stageDelete(key: String) {
        if additions[key] != nil {
            additions.removeValue(forKey: key)
        } else {
            deletions.insert(key)
            modifications.removeValue(forKey: key)
        }
    }

    func undoChange(key: String) {
        deletions.remove(key)
        modifications.removeValue(forKey: key)
        additions.removeValue(forKey: key)
    }

    func stageAdd(key: String, value: String) {
        guard !key.isEmpty else { return }
        if keyExists(key) {
            showToast("Key \"\(key)\" already exists", isError: true)
            return
        }
        additions[key] = value
        isAddingKey = false
        newKeyName = ""
        newKeyValue = ""
    }

    func saveChanges() async {
        guard let ns = selectedNamespace, let secret = selectedSecret else { return }
        saving = true

        var applied = 0
        do {
            for key in deletions {
                try await client.deleteSecretKey(namespace: ns.name, name: secret.name, key: key)
                applied += 1
            }
            for (key, value) in modifications {
                try await client.patchSecretKey(namespace: ns.name, name: secret.name, key: key, value: value)
                applied += 1
            }
            for (key, value) in additions {
                try await client.patchSecretKey(namespace: ns.name, name: secret.name, key: key, value: value)
                applied += 1
            }
            showToast("Applied \(applied) change\(applied == 1 ? "" : "s") successfully")
            clearChanges()
            await loadSecretData()
        } catch {
            showToast("Failed after \(applied) changes: \(error.localizedDescription)", isError: true)
            clearChanges()
            await loadSecretData()
        }
        saving = false
    }

    func discardChanges() {
        clearChanges()
        showToast("Changes discarded")
    }

    private func clearChanges() {
        modifications = [:]
        deletions = []
        additions = [:]
    }

    func showToast(_ message: String, isError: Bool = false) {
        toastMessage = message
        toastIsError = isError
        Task {
            try? await Task.sleep(for: .seconds(3))
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }
}

struct DisplayKV: Identifiable, Hashable {
    let id: String  // stable identity based on key
    let key: String
    let value: String
    var originalValue: String?
    let status: Status

    enum Status { case none, modified, added, deleted }
}
