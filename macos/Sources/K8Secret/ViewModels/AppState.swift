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
    /// `resourceVersion` the open secret was read at, used to make saves conditional.
    var secretResourceVersion: String?
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

    // Liveness
    //
    // Polling and watch failures were swallowed by `try?`, so a window could sit
    // showing minutes-old data with a green "connected" dot and no way to tell.
    // These let the UI say when data last arrived and whether updates are still
    // flowing.
    var lastUpdated: Date?
    var liveUpdatesInterrupted = false

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
    private var podWatchTask: Task<Void, Never>?
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
        let confirmLabel: String
        let destructive: Bool
        let action: () async -> Void
    }

    /// Ask before doing something irreversible. Presented centrally by `ContentView`.
    func confirm(
        title: String,
        message: String,
        confirmLabel: String,
        destructive: Bool = true,
        action: @escaping () async -> Void
    ) {
        confirmAction = ConfirmAction(
            title: title,
            message: message,
            confirmLabel: confirmLabel,
            destructive: destructive,
            action: action
        )
    }

    /// Best-effort guess that the current context is production, used only to *add*
    /// friction — never to remove it. A false positive costs one extra click; a
    /// false negative leaves behaviour exactly as it would be otherwise.
    var looksLikeProduction: Bool {
        let name = context.lowercased()
        return ["prod", "production", "prd", "live"].contains { token in
            name == token
                || name.hasPrefix("\(token)-") || name.hasSuffix("-\(token)")
                || name.contains("-\(token)-") || name.contains("/\(token)")
        }
    }

    private var productionWarning: String {
        looksLikeProduction ? "\n\nThis context (\(context)) looks like production." : ""
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
            // Get user and preferred namespace from the kubeconfig context
            var preferredNamespace: String?
            if let cfg = try? KubeConfig.load() {
                clusterUser = cfg.activeUser()?.name ?? ""
                preferredNamespace = cfg.activeNamespace()
            }

            await loadClusterMetrics()
            startClusterMetricsPolling()
            await loadNamespaces()
            await selectInitialNamespace(preferred: preferredNamespace)
        } catch {
            connectionState = .disconnected(error.localizedDescription)
        }
    }

    func switchContext(_ newContext: String) async {
        guard newContext != context else { return }
        UserDefaults.standard.set(newContext, forKey: Self.lastContextKey)

        // Drop *everything* from the previous cluster before connecting to the new
        // one. Leaving deployments/pods/services behind meant that after switching
        // staging → production the window still listed the old cluster's workloads,
        // which is both wrong and a genuinely dangerous thing to act on.
        selectedNamespace = nil
        namespaces = []
        namespaceSearch = ""
        clearSelections()
        secrets = []
        deployments = []
        pods = []
        services = []

        await connect(toContext: newContext)
    }

    /// Land the user on something useful instead of an empty pane.
    ///
    /// Opening the app used to show two side-by-side placeholders — "Select a
    /// Namespace" next to "Select a Deployment" — even when the kubeconfig said
    /// exactly which namespace this context works in. That field
    /// (`activeNamespace()`) was parsed and then never read. First impression of a
    /// fresh install was an app that looked empty and asked the user to go find
    /// their own data.
    ///
    /// Preference order: the namespace named by the current context, then
    /// `default`, then the first one that exists. Only ever runs when nothing is
    /// selected, so it can't override a choice the user already made.
    private func selectInitialNamespace(preferred: String?) async {
        guard shouldSelectInitialNamespace,
              let namespace = initialNamespaceChoice(preferred: preferred) else { return }
        await selectNamespace(namespace)
    }

    /// Only auto-select when the user hasn't chosen anything yet.
    var shouldSelectInitialNamespace: Bool {
        selectedNamespace == nil && !namespaces.isEmpty
    }

    /// Context namespace, then `default`, then whatever exists.
    func initialNamespaceChoice(preferred: String?) -> K8sNamespace? {
        let candidates = [preferred, "default"].compactMap { $0 }
        let match = candidates.lazy
            .compactMap { name in self.namespaces.first { $0.name == name } }
            .first
        return match ?? namespaces.first
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
        autoLockTask?.cancel()
        autoLockTask = nil
        isLocked = false
        secretData = []
        secretResourceVersion = nil
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

    /// True while a list is being fetched *and* there is nothing to show yet.
    ///
    /// The loading flags used to drive a full-screen spinner unconditionally, so
    /// every refresh — manual or automatic — replaced the list with a spinner and
    /// then rebuilt it, losing scroll position and flashing the content. A refresh
    /// of data that is already on screen should be invisible.
    var isInitialLoad: Bool {
        switch selectedResourceType {
        case .secrets:     return loadingSecrets && secrets.isEmpty
        case .deployments: return loadingDeployments && deployments.isEmpty
        case .pods:        return loadingPods && pods.isEmpty
        case .services:    return loadingServices && services.isEmpty
        }
    }

    /// True while refreshing content that is already visible.
    var isRefreshing: Bool {
        let loading = switch selectedResourceType {
        case .secrets:     loadingSecrets
        case .deployments: loadingDeployments
        case .pods:        loadingPods
        case .services:    loadingServices
        }
        return loading && !isInitialLoad
    }

    func loadResourcesForCurrentType(restartWatch: Bool = true) async {
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
                // The watch does its own initial list, so take the version-bearing
                // one here and hand it straight to the watcher rather than listing
                // the namespace twice on every selection.
                let page = try await client.listPodsWithVersion(namespace: ns.name)
                pods = page.pods
                if let metrics = try? await client.getPodMetrics(namespace: ns.name) {
                    podMetrics = Dictionary(uniqueKeysWithValues: metrics.map { ($0.name, $0) })
                }
            }
            catch { showToast("Failed to load pods: \(error.localizedDescription)", isError: true) }
            loadingPods = false
            // A manual refresh re-lists, but the watch is already delivering
            // changes — restarting it would drop the stream and re-list again.
            if restartWatch { startMetricsPolling() }
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
        isLocked = false
        await loadSecretData()
        scheduleAutoLock()
    }

    func loadSecretData() async {
        guard let ns = selectedNamespace, let secret = selectedSecret else { return }
        loadingData = true
        do {
            let result = try await client.getSecretData(namespace: ns.name, name: secret.name)
            secretData = result.items
            secretResourceVersion = result.resourceVersion
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
        var staged = 0
        for (key, value) in pairs {
            if secretData.contains(where: { $0.key == key }) {
                modifications[key] = value
            } else {
                additions[key] = value
            }
            staged += 1
        }

        // Replace mode stages a deletion for every key not in the import. Say so —
        // nothing is written until Apply, but the user should see the scope now
        // rather than discovering it in the confirmation dialog.
        if replace && !deletions.isEmpty {
            showToast("Staged \(staged) key\(staged == 1 ? "" : "s") · \(deletions.count) existing key\(deletions.count == 1 ? "" : "s") marked for deletion")
        } else {
            showToast("Staged \(staged) key\(staged == 1 ? "" : "s") — review, then Apply")
        }
    }

    func exportAsEnv() -> String {
        secretData.map { "\($0.key)=\(Self.envQuoted($0.value))" }.joined(separator: "\n")
    }

    /// Quote a value so the export round-trips. Multi-line values (certificates,
    /// private keys, JSON blobs) are extremely common in secrets, and emitting them
    /// raw produced a `.env` file that silently parsed back as garbage.
    nonisolated static func envQuoted(_ value: String) -> String {
        let needsQuoting = value.contains(where: { " \t\n\r\"'\\$#=".contains($0) })
        guard needsQuoting || value.isEmpty else { return value }

        var escaped = ""
        for ch in value {
            switch ch {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "$":  escaped += "\\$"
            default:   escaped.append(ch)
            }
        }
        return "\"\(escaped)\""
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

    /// Entry point for the YAML editor's Apply button. A raw `PUT` replaces the
    /// whole object, so this always confirms.
    func requestApplyRawYAML() {
        guard !yamlResourcePath.isEmpty else { return }
        confirm(
            title: "Replace this resource?",
            message: "The edited YAML will replace the live object in full. Fields you removed will be removed from the cluster."
                + productionWarning,
            confirmLabel: "Apply",
            destructive: true
        ) { [weak self] in
            await self?.applyRawYAML()
        }
    }

    func applyRawYAML() async {
        guard !yamlResourcePath.isEmpty else { return }

        // The parser handles a subset of YAML. Anything outside it would be applied
        // to a live resource in a shape the user didn't write, so refuse instead.
        let problems = YAMLParser.validate(rawYAML)
        guard problems.isEmpty else {
            showToast(problems.joined(separator: " "), isError: true)
            return
        }

        let parsed = YAMLParser.parse(rawYAML)
        guard let root = parsed.mapValue, !root.isEmpty else {
            showToast("Couldn't parse this as a Kubernetes resource.", isError: true)
            return
        }
        // A PUT that drops apiVersion/kind replaces the resource with something the
        // API server may accept but the user didn't intend.
        guard root["apiVersion"] != nil, root["kind"] != nil else {
            showToast("Resource is missing apiVersion or kind — refusing to apply.", isError: true)
            return
        }

        saving = true
        defer { saving = false }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: parsed.jsonObject)
            try await client.applyRawResource(path: yamlResourcePath, jsonData: jsonData)
            showToast("YAML applied successfully")
        } catch {
            showToast("Failed to apply YAML: \(error.localizedDescription)", isError: true)
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

                // Fetch only the single deployment. Assign only on a real change:
                // an identical value still invalidates every view reading it, so
                // the detail pane rebuilt itself every 5 seconds while idle.
                if let updated = try? await self.client.getDeployment(namespace: ns.name, name: dep.name) {
                    if updated != self.selectedDeployment {
                        self.selectedDeployment = updated
                    }
                    if let idx = self.deployments.firstIndex(where: { $0.id == updated.id }),
                       self.deployments[idx] != updated {
                        self.deployments[idx] = updated
                    }
                    self.lastUpdated = Date()
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

    /// Keep the pod list live via a watch stream, and poll metrics separately.
    ///
    /// This used to re-list every pod in the namespace every 5 seconds. A watch
    /// sends only what changed, arrives as it happens rather than up to a poll
    /// interval late, and doesn't grow more expensive with the size of the
    /// namespace. Metrics still poll — the metrics API has no watch — but at 10s,
    /// which is closer to metrics-server's own resolution than 5s was.
    func startMetricsPolling() {
        stopMetricsPolling()
        startPodWatch()

        metricsPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                if Task.isCancelled { break }

                guard let self, let ns = self.selectedNamespace,
                      self.selectedResourceType == .pods else { break }

                if let metrics = try? await self.client.getPodMetrics(namespace: ns.name) {
                    let updated = Dictionary(uniqueKeysWithValues: metrics.map { ($0.name, $0) })
                    if updated != self.podMetrics { self.podMetrics = updated }
                    self.lastUpdated = Date()
                }
            }
        }
    }

    private func startPodWatch() {
        podWatchTask?.cancel()

        podWatchTask = Task { [weak self] in
            var backoff: Double = 1

            while !Task.isCancelled {
                guard let self, let ns = self.selectedNamespace,
                      self.selectedResourceType == .pods else { return }

                do {
                    // Re-list to get a consistent snapshot plus the version to watch from.
                    let page = try await self.client.listPodsWithVersion(namespace: ns.name)
                    self.pods = page.pods
                    self.reconcileSelectedPod()
                    self.lastUpdated = Date()
                    self.liveUpdatesInterrupted = false
                    backoff = 1

                    guard let version = page.resourceVersion else {
                        // No version to watch from — fall back to a slow re-list.
                        try? await Task.sleep(for: .seconds(10))
                        continue
                    }

                    try await self.client.watchPods(namespace: ns.name, resourceVersion: version) { event in
                        Task { @MainActor [weak self] in
                            self?.apply(event)
                        }
                    }
                    // A watch ends normally when the server's timeout elapses; loop
                    // around and start a fresh one.
                } catch is K8sClient.WatchExpired {
                    // resourceVersion aged out — re-list immediately, no backoff.
                    continue
                } catch {
                    if Task.isCancelled { return }
                    // Surface the gap rather than quietly showing stale rows.
                    self.liveUpdatesInterrupted = true
                    try? await Task.sleep(for: .seconds(backoff))
                    backoff = min(30, backoff * 2)
                }
            }
        }
    }

    /// Non-private so watch-event handling can be tested without a live cluster.
    func apply(_ event: K8sClient.PodWatchEvent) {
        lastUpdated = Date()
        liveUpdatesInterrupted = false

        switch event {
        case .added(let pod):
            if let idx = pods.firstIndex(where: { $0.id == pod.id }) {
                // A replay of something already listed: update in place, silently.
                pods[idx] = pod
            } else {
                // A genuinely new pod. Animate the insert — rows arriving on their
                // own popped into existence, which reads as the list glitching
                // rather than the cluster changing.
                withAnimation(Motion.listChange) {
                    pods.append(pod)
                }
            }
            if selectedPod?.id == pod.id { selectedPod = pod }

        case .modified(let pod):
            // In-place field changes must not animate: a restart count ticking is
            // not a list change, and animating it would shuffle rows under the
            // pointer.
            if let idx = pods.firstIndex(where: { $0.id == pod.id }) {
                pods[idx] = pod
            } else {
                withAnimation(Motion.listChange) { pods.append(pod) }
            }
            if selectedPod?.id == pod.id { selectedPod = pod }

        case .deleted(let pod):
            withAnimation(Motion.listChange) {
                pods.removeAll { $0.id == pod.id }
            }
            if selectedPod?.id == pod.id { selectedPod = nil }

        case .bookmark:
            break   // position marker only; nothing to display
        }
    }

    /// Keep the detail pane pointing at something that still exists.
    private func reconcileSelectedPod() {
        guard let selected = selectedPod else { return }
        if let refreshed = pods.first(where: { $0.id == selected.id }) {
            selectedPod = refreshed
        } else {
            selectedPod = nil
        }
    }

    func stopMetricsPolling() {
        metricsPollTask?.cancel()
        metricsPollTask = nil
        podWatchTask?.cancel()
        podWatchTask = nil
    }

    // MARK: - Cluster Metrics

    func loadClusterMetrics() async {
        do {
            let m = try await client.getClusterMetrics()
            // Guarded so an unchanged reading doesn't invalidate the status bar.
            if clusterCPUPercent != m.cpuPercent { clusterCPUPercent = m.cpuPercent }
            if clusterMemPercent != m.memPercent { clusterMemPercent = m.memPercent }

            let cpuUsed = formatCPU(m.cpuUsed), cpuTotal = formatCPU(m.cpuTotal)
            let memUsed = formatMem(m.memUsedKi), memTotal = formatMem(m.memTotalKi)
            if clusterCPUUsed != cpuUsed { clusterCPUUsed = cpuUsed }
            if clusterCPUTotal != cpuTotal { clusterCPUTotal = cpuTotal }
            if clusterMemUsed != memUsed { clusterMemUsed = memUsed }
            if clusterMemTotal != memTotal { clusterMemTotal = memTotal }
            lastUpdated = Date()
        } catch {
            // Metrics-server is optional; its absence is not a connection problem
            // and must not be reported as one.
        }
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

    /// Entry point for the scale controls.
    ///
    /// Routine scaling stays a single click — prompting on every ±1 would train
    /// people to dismiss the dialog. Taking a workload to zero is a different act
    /// (it stops serving traffic), and so is any scale on a production-looking
    /// context, so those confirm.
    func requestScale(_ dep: K8sDeployment, to replicas: Int) {
        let takingDown = replicas == 0 && dep.replicas > 0

        // A big jump is usually deliberate, but it is also what a typo looks like
        // — now that the count can be typed, "20" instead of "2" is one keystroke
        // away and would schedule eighteen extra pods.
        let jump = replicas - dep.replicas
        let bigJump = jump >= Self.largeScaleUp

        guard takingDown || bigJump || looksLikeProduction else {
            Task { await scaleDeployment(dep, to: replicas) }
            return
        }

        let what: String
        if takingDown {
            what = "Scale \(dep.name) to 0 replicas? It will stop serving traffic."
        } else if bigJump {
            what = "Scale \(dep.name) from \(dep.replicas) to \(replicas) replicas? "
                 + "That's \(jump) more pod\(jump == 1 ? "" : "s") to schedule."
        } else {
            what = "Scale \(dep.name) from \(dep.replicas) to \(replicas) replicas?"
        }

        confirm(
            title: takingDown ? "Stop \(dep.name)?" : "Scale deployment",
            message: what + productionWarning,
            confirmLabel: takingDown ? "Stop" : "Scale",
            destructive: takingDown
        ) { [weak self] in
            await self?.scaleDeployment(dep, to: replicas)
        }
    }

    /// An increase of at least this many replicas asks first.
    private static let largeScaleUp = 5

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
            let fetched = try await client.getEvents(
                namespace: ns,
                fieldSelector: "involvedObject.name=\(name),involvedObject.kind=\(kind)"
            )
            // Assign only on a real change. This refetches every 5s while a detail
            // pane is open, and reassigning an identical array still invalidates
            // the view — the events list visibly reshuffled and lost scroll
            // position twelve times a minute for no reason.
            if fetched != events { events = fetched }
        } catch {
            // A failed refresh should not erase events that are already on screen;
            // only clear when there was nothing to preserve.
            if events.isEmpty { events = [] }
        }
    }

    // MARK: - Refresh

    func refreshCurrentResource() async {
        await loadResourcesForCurrentType(restartWatch: false)

        // Keep the detail pane pointing at the refreshed copy of whatever is open,
        // matched by id — the value will have changed.
        if let dep = selectedDeployment, let updated = deployments.first(where: { $0.id == dep.id }) {
            selectedDeployment = updated
        }
        if let pod = selectedPod, let updated = pods.first(where: { $0.id == pod.id }) {
            selectedPod = updated
        }
        if let svc = selectedService, let updated = services.first(where: { $0.id == svc.id }) {
            selectedService = updated
        }
        lastUpdated = Date()
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

    /// Entry point for the Apply button — writing to a live secret always confirms,
    /// with an itemised summary of what is about to change.
    func requestSaveChanges() {
        guard hasChanges, let secret = selectedSecret else { return }

        var parts: [String] = []
        if !additions.isEmpty { parts.append("add \(additions.count)") }
        if !modifications.isEmpty { parts.append("change \(modifications.count)") }
        if !deletions.isEmpty { parts.append("delete \(deletions.count)") }
        let summary = parts.joined(separator: ", ")

        var message = "This will \(summary) key\(changeCount == 1 ? "" : "s") in \(secret.name)."
        if !deletions.isEmpty {
            message += "\n\nDeleted keys can't be recovered: \(deletions.sorted().joined(separator: ", "))."
        }

        confirm(
            title: "Apply changes to \(secret.name)?",
            message: message + productionWarning,
            confirmLabel: "Apply",
            destructive: !deletions.isEmpty
        ) { [weak self] in
            await self?.saveChanges()
        }
    }

    func saveChanges() async {
        guard let ns = selectedNamespace, let secret = selectedSecret else { return }
        guard hasChanges else { return }
        saving = true
        defer { saving = false }

        let count = changeCount
        var upserts = modifications
        for (key, value) in additions { upserts[key] = value }

        do {
            // One atomic merge-patch: all keys land, or none do.
            try await client.applySecretChanges(
                namespace: ns.name,
                name: secret.name,
                upserts: upserts,
                removals: Array(deletions),
                resourceVersion: secretResourceVersion
            )
            showToast("Applied \(count) change\(count == 1 ? "" : "s") successfully")
            clearChanges()
            await loadSecretData()
        } catch {
            // Keep the staged edits. The write was atomic, so nothing was applied —
            // discarding them here would destroy work the user can still retry.
            if case K8sError.requestFailed(409, _) = error {
                showToast(
                    "\(secret.name) changed in the cluster since you opened it. Reload to see the current values, then re-apply.",
                    isError: true
                )
            } else {
                showToast("Save failed — your changes are still staged: \(error.localizedDescription)", isError: true)
            }
        }
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

    // MARK: - Auto-lock

    /// Drop decoded secret values after a period of inactivity.
    ///
    /// Decoded secrets are ordinary Swift strings held in observable state, so they
    /// can't be zeroed and may reach swap. Not holding them any longer than needed
    /// is the meaningful mitigation available without a locked-buffer type: an
    /// unattended laptop stops having a namespace of plaintext credentials sitting
    /// in a window.
    ///
    /// Staged edits are never discarded — locking with unsaved work would destroy
    /// exactly the thing the user cares about, so an edited secret stays open.
    static let autoLockInterval: TimeInterval = 5 * 60

    private var autoLockTask: Task<Void, Never>?

    var isLocked = false

    func noteUserActivity() {
        isLocked = false
        scheduleAutoLock()
    }

    func scheduleAutoLock() {
        autoLockTask?.cancel()
        guard selectedSecret != nil else { return }

        autoLockTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.autoLockInterval))
            guard !Task.isCancelled, let self else { return }
            self.lockSecrets()
        }
    }

    func lockSecrets() {
        // Unsaved work outranks the lock.
        guard !hasChanges, selectedSecret != nil else { return }
        secretData = []
        secretResourceVersion = nil
        isLocked = true
    }

    /// Re-fetch after a lock, when the user comes back to the window.
    func unlockSecrets() async {
        isLocked = false
        await loadSecretData()
        scheduleAutoLock()
    }

    private var toastDismissTask: Task<Void, Never>?

    func showToast(_ message: String, isError: Bool = false) {
        toastMessage = message
        toastIsError = isError

        // Matching on the message text meant two identical toasts in a row shared
        // a dismissal — the second vanished on the first one's timer, after as
        // little as a moment on screen. Cancelling the previous timer gives every
        // toast its own full three seconds.
        toastDismissTask?.cancel()
        toastDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.toastMessage = nil
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
