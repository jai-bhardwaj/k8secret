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
    /// Where the window is looking. Overview and Events are destinations that
    /// aren't resource lists; when a resource is selected the two stay in sync.
    var selectedDestination: AppDestination = .overview
    /// "All namespaces" scope: lists aggregate across every namespace and rows
    /// carry a namespace badge. Selecting an item scopes back into its own
    /// namespace so detail panes are always unambiguous.
    var allNamespaces = false
    /// Per-context cluster color — the "am I in prod?" glance. Persisted per
    /// context name; loaded on connect and on context switch.
    var clusterTint: Theme.ClusterTint = .ocean
    /// Sidebar rail collapse (56pt icon rail vs 208pt full sidebar). Persisted
    /// app-wide — it's a workspace preference, not a per-context one.
    var sidebarCollapsed = UserDefaults.standard.bool(forKey: "sidebarCollapsed") {
        didSet { UserDefaults.standard.set(sidebarCollapsed, forKey: "sidebarCollapsed") }
    }
    /// ⌘K overlay visibility — lives here so the palette can be summoned from
    /// menu commands and dismissed from anywhere.
    var paletteOpen = false
    /// Sheet/tab state hoisted from the views so it survives selection changes
    /// and can be driven by the debug tour (UITestTour).
    var settingsOpen = false
    /// Status-bar cluster switcher panel (the VS Code quick-pick pattern).
    var clusterSwitcherOpen = false
    var namespaceMenuOpen = false

    /// The clusters this person actually works in, most recent first. With a
    /// hundred contexts in a merged kubeconfig, alphabetical order buries the
    /// four that matter.
    static let recentContextsKey = "cluster.recentContexts"
    static var recentContexts: [String] {
        UserDefaults.standard.stringArray(forKey: recentContextsKey) ?? []
    }
    static func rememberRecentContext(_ ctx: String) {
        var list = recentContexts.filter { $0 != ctx }
        list.insert(ctx, at: 0)
        UserDefaults.standard.set(Array(list.prefix(8)), forKey: recentContextsKey)
    }
    /// Which stop of the guided tour is showing, or nil when it isn't running.
    var tourStep: Int?
    /// How far the launch sequence's checklist has got. Driven by `connect`,
    /// so the steps describe work that actually happened.
    var launchPhase = 0
    /// Compact (single-pane) navigation: below ~780pt the prototype shows the
    /// list OR the detail, never both; selecting a row pushes the detail.
    var compactShowDetail = false
    var secretExportOpen = false
    var podDetailTab: PodDetailView.DetailTab = .overview
    var deploymentDetailTab: DeploymentDetailView.DetailTab = .overview

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
    var configMaps: [K8sConfigMap] = []
    var cronJobs: [K8sCronJob] = []
    /// Recent Jobs in scope, keyed to their owning CronJob for run history.
    var cronJobRuns: [K8sJob] = []
    /// The scope each list was last loaded for ("context|namespace"). The
    /// sidebar counts are only true for the *current* scope: after a namespace
    /// switch the untouched arrays still hold the old namespace's rows, and
    /// showing their length claimed 6 deployments in a namespace with 2.
    var listScopeStamp: [ResourceType: String] = [:]

    /// The scope key lists are stamped with.
    var currentScopeKey: String {
        "\(context)|\(allNamespaces ? "*" : (selectedNamespace?.name ?? "—"))"
    }

    /// Count for the sidebar: the loaded length when that list belongs to the
    /// scope on screen, otherwise nil so the badge stays empty rather than lying.
    func sidebarCount(for type: ResourceType) -> Int? {
        guard listScopeStamp[type] == currentScopeKey else { return nil }
        switch type {
        case .deployments: return deployments.count
        case .pods: return pods.count
        case .cronjobs: return cronJobs.count
        case .services: return services.count
        case .ingresses: return ingresses.count
        case .secrets: return secrets.count
        case .configmaps: return configMaps.count
        }
    }
    var ingresses: [K8sIngress] = []
    var clusterEvents: [K8sEvent] = []
    var configMapData: [K8sKeyValue] = []
    var loadingConfigMapData = false
    var events: [K8sEvent] = []
    var podLogs: String = ""
    var rawYAML: String = ""

    // Selection
    var selectedNamespace: K8sNamespace?
    var selectedSecret: K8sSecret?
    var selectedDeployment: K8sDeployment?
    var selectedPod: K8sPod?
    var selectedService: K8sService?
    var selectedConfigMap: K8sConfigMap?
    var selectedCronJob: K8sCronJob?
    var selectedIngress: K8sIngress?

    // Search
    var namespaceSearch: String = ""
    var secretSearch: String = ""
    var kvSearch: String = ""
    var deploymentSearch: String = ""
    var podSearch: String = ""
    var serviceSearch: String = ""
    var configMapSearch: String = ""
    var cronJobSearch: String = ""
    var ingressSearch: String = ""

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
    var loadingConfigMaps = false
    var loadingCronJobs = false
    var loadingIngresses = false
    var loadingClusterEvents = false
    var loadingLogs = false
    var loadingYAML = false
    var saving = false
    var scaling = false
    var rollingOut = false
    var rolloutProgress: String = ""
    /// Which deployment the rollout poll is watching. A rollout outlives the
    /// user's attention — they can scale one deployment and go look at another —
    /// so progress has to say who it belongs to rather than being read as
    /// belonging to whatever happens to be selected.
    var rolloutDeploymentId: String?

    /// Whether the rollout banner belongs on screen right now: something is
    /// rolling out *and* it is the deployment being looked at.
    var showsRolloutBanner: Bool {
        rollingOut && rolloutDeploymentId != nil && rolloutDeploymentId == selectedDeployment?.id
    }

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
        // The canvas has to be this cluster's color on the very first frame.
        // Which cluster we are about to reach is already known from disk, so
        // its tint is too — waiting for connect() to resolve the context meant
        // the window opened in the default blue and then changed color while
        // the launch was still playing.
        let known = initialContext ?? UserDefaults.standard.string(forKey: Self.lastContextKey)
        if let known, !known.isEmpty {
            context = known
            loadClusterTint()
        }
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
        // Never replace a confirmation the user hasn't answered yet.
        //
        // Any path that fires twice — a control that commits on both Return and
        // blur, a double click, a re-entrant callback — used to overwrite the
        // pending dialog with a second one. What the user saw was a confirmation
        // appearing twice, and answering one of them acted on an action they
        // hadn't read. Dropping the duplicate is right in every one of those
        // cases: the first request is the one the user initiated.
        guard confirmAction == nil else { return }

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

    var filteredConfigMaps: [K8sConfigMap] {
        if configMapSearch.isEmpty { return configMaps }
        return configMaps.filter { $0.name.localizedCaseInsensitiveContains(configMapSearch) }
    }

    var filteredCronJobs: [K8sCronJob] {
        if cronJobSearch.isEmpty { return cronJobs }
        return cronJobs.filter {
            $0.name.localizedCaseInsensitiveContains(cronJobSearch) ||
            $0.schedule.localizedCaseInsensitiveContains(cronJobSearch)
        }
    }

    var filteredIngresses: [K8sIngress] {
        if ingressSearch.isEmpty { return ingresses }
        return ingresses.filter {
            $0.name.localizedCaseInsensitiveContains(ingressSearch) ||
            $0.rules.contains { r in r.host.localizedCaseInsensitiveContains(ingressSearch) }
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
        launchPhase = 0
        // Load available contexts
        if let contexts = try? await client.availableContexts() {
            availableContexts = contexts
        }
        launchPhase = 1                      // kubeconfig read
        // Priority: explicit arg > initialContext (for this window) > saved default
        let targetContext = toContext ?? initialContext ?? UserDefaults.standard.string(forKey: Self.lastContextKey)
        // Consume initialContext so subsequent retries/switches don't force it
        if initialContext != nil && toContext == nil { initialContext = nil }
        do {
            let ctx = try await client.connect(context: targetContext)
            launchPhase = 2                  // API server answered
            context = ctx
            UserDefaults.standard.set(ctx, forKey: Self.lastContextKey)
            loadClusterTint()
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
            // The window opens on Overview, whose .task fired before the
            // namespace list existed — so its first load saw an empty cluster
            // and reported 0/0 in perfect confidence. Load it again now that
            // there are namespaces to span.
            if selectedDestination == .overview {
                await loadOverview()
                startDestinationPolling(every: 10) { [weak self] in await self?.loadOverview() }
            }
        } catch {
            connectionState = .disconnected(error.localizedDescription)
        }
    }

    func switchContext(_ newContext: String) async {
        guard newContext != context else { return }
        UserDefaults.standard.set(newContext, forKey: Self.lastContextKey)
        Self.rememberRecentContext(newContext)

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
        configMaps = []
        cronJobs = []
        ingresses = []
        clusterEvents = []
        overviewDeployments = []
        overviewPods = []

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
            if launchPhase == 2 { launchPhase = 3 }   // namespaces in hand
        } catch {
            showToast("Failed to load namespaces: \(error.localizedDescription)", isError: true)
        }
    }

    func loadClusterTint() {
        let raw = UserDefaults.standard.string(forKey: "clusterTint.\(context)") ?? ""
        clusterTint = Theme.ClusterTint(rawValue: raw) ?? .ocean
    }

    func setClusterTint(_ tint: Theme.ClusterTint) {
        clusterTint = tint
        UserDefaults.standard.set(tint.rawValue, forKey: "clusterTint.\(context)")
    }

    func selectNamespace(_ ns: K8sNamespace) async {
        if allNamespaces { allNamespaces = false }
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
        selectedConfigMap = nil
        selectedCronJob = nil
        selectedIngress = nil
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
        selectedDestination = .resource(type)
        if selectedNamespace != nil || allNamespaces {
            await loadResourcesForCurrentType()
        }
    }

    func selectDestination(_ destination: AppDestination) async {
        stopDestinationPolling()
        switch destination {
        case .resource(let t):
            await selectResourceType(t)
        case .overview:
            clearSelections()
            selectedDestination = .overview
            await loadOverview()
            startDestinationPolling(every: 10) { [weak self] in await self?.loadOverview() }
        case .events:
            clearSelections()
            selectedDestination = .events
            await loadClusterEvents()
            startDestinationPolling(every: 15) { [weak self] in await self?.loadClusterEvents() }
        }
    }

    /// Overview and Events are dashboards: a "needs attention" panel that goes
    /// stale is a lying dashboard, so both refresh while visible and stop the
    /// moment the user leaves. `loadOverview`/`loadClusterEvents` already guard
    /// on `selectedDestination`, so a late tick can't write into another pane.
    private var destinationPollTask: Task<Void, Never>?

    private func startDestinationPolling(every seconds: Double,
                                         _ tick: @escaping @MainActor () async -> Void) {
        destinationPollTask = Task { [weak self] in
            while !Task.isCancelled, self != nil {
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                await tick()
            }
        }
    }

    func stopDestinationPolling() {
        destinationPollTask?.cancel()
        destinationPollTask = nil
    }

    /// Scope the window to one namespace, or to all of them.
    func selectNamespaceScope(all: Bool) async {
        guard allNamespaces != all else { return }
        allNamespaces = all
        clearSelections()
        await loadResourcesForCurrentType()
    }

    /// The namespaces the current scope spans.
    var scopedNamespaceNames: [String] {
        if allNamespaces { return namespaces.map(\.name) }
        return selectedNamespace.map { [$0.name] } ?? []
    }

    /// List a resource across every namespace in scope, concurrently, keeping a
    /// deterministic order (namespace order, then API order within each).
    private func listScoped<T: Sendable>(
        _ fetch: @escaping @Sendable (String) async throws -> [T]
    ) async throws -> [T] {
        let names = scopedNamespaceNames
        guard names.count > 1 else {
            guard let only = names.first else { return [] }
            return try await fetch(only)
        }
        return try await withThrowingTaskGroup(of: (Int, [T]).self) { group in
            for (i, ns) in names.enumerated() {
                group.addTask { (i, try await fetch(ns)) }
            }
            var slots = [[T]](repeating: [], count: names.count)
            for try await (i, items) in group { slots[i] = items }
            return slots.flatMap { $0 }
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
        case .configmaps:  return loadingConfigMaps && configMaps.isEmpty
        case .cronjobs:    return loadingCronJobs && cronJobs.isEmpty
        case .ingresses:   return loadingIngresses && ingresses.isEmpty
        }
    }

    /// True while refreshing content that is already visible.
    var isRefreshing: Bool {
        let loading = switch selectedResourceType {
        case .secrets:     loadingSecrets
        case .deployments: loadingDeployments
        case .pods:        loadingPods
        case .services:    loadingServices
        case .configmaps:  loadingConfigMaps
        case .cronjobs:    loadingCronJobs
        case .ingresses:   loadingIngresses
        }
        return loading && !isInitialLoad
    }

    func loadResourcesForCurrentType(restartWatch: Bool = true) async {
        guard selectedNamespace != nil || allNamespaces else { return }
        let ns = selectedNamespace ?? K8sNamespace(id: "*", name: "*", status: "Active")
        let wasAll = allNamespaces
        // Switching namespaces twice in quick succession leaves two loads racing,
        // and the slower one wins by arriving last — the list then shows a
        // namespace the sidebar says you left.
        func stillCurrent() -> Bool {
            wasAll ? allNamespaces : (!allNamespaces && selectedNamespace?.name == ns.name)
        }
        /// Stamp the freshly-loaded list with the scope it belongs to.
        func stamp() {
            listScopeStamp[selectedResourceType] = currentScopeKey
        }
        switch selectedResourceType {
        case .secrets:
            loadingSecrets = true
            do { let listed = try await listScoped { [client] in try await client.listSecrets(namespace: $0) }
                 if stillCurrent() { secrets = listed; stamp() } }
            catch { showToast("Failed to load secrets: \(error.localizedDescription)", isError: true) }
            loadingSecrets = false
        case .deployments:
            loadingDeployments = true
            do { let listed = try await listScoped { [client] in try await client.listDeployments(namespace: $0) }
                 if stillCurrent() { deployments = listed; stamp() } }
            catch { showToast("Failed to load deployments: \(error.localizedDescription)", isError: true) }
            loadingDeployments = false
        case .pods:
            loadingPods = true
            if wasAll {
                // All-namespaces: aggregate plain lists; the watch and metrics
                // polling are per-namespace machinery and stay off in this
                // scope — rows still refresh through the destination poll.
                stopMetricsPolling()
                do {
                    let listed = try await listScoped { [client] in try await client.listPods(namespace: $0) }
                    if stillCurrent() { pods = listed; stamp() }
                    var merged: [String: PodMetrics] = [:]
                    for name in scopedNamespaceNames {
                        if let metrics = try? await client.getPodMetrics(namespace: name) {
                            for m in metrics { merged[m.name] = m }
                        }
                    }
                    if stillCurrent() { podMetrics = merged }
                }
                catch { showToast("Failed to load pods: \(error.localizedDescription)", isError: true) }
                loadingPods = false
            } else {
                do {
                    // The watch does its own initial list, so take the version-bearing
                    // one here and hand it straight to the watcher rather than listing
                    // the namespace twice on every selection.
                    let page = try await client.listPodsWithVersion(namespace: ns.name)
                    if stillCurrent() { pods = page.pods; stamp() }
                    if let metrics = try? await client.getPodMetrics(namespace: ns.name), stillCurrent() {
                        podMetrics = Dictionary(uniqueKeysWithValues: metrics.map { ($0.name, $0) })
                    }
                }
                catch { showToast("Failed to load pods: \(error.localizedDescription)", isError: true) }
                loadingPods = false
                // A manual refresh re-lists, but the watch is already delivering
                // changes — restarting it would drop the stream and re-list again.
                if restartWatch { startMetricsPolling() }
            }
        case .services:
            stopMetricsPolling()
            loadingServices = true
            do { let listed = try await listScoped { [client] in try await client.listServices(namespace: $0) }
                 if stillCurrent() { services = listed; stamp() } }
            catch { showToast("Failed to load services: \(error.localizedDescription)", isError: true) }
            loadingServices = false
        case .configmaps:
            loadingConfigMaps = true
            do { let listed = try await listScoped { [client] in try await client.listConfigMaps(namespace: $0) }
                 if stillCurrent() { configMaps = listed; stamp() } }
            catch { showToast("Failed to load configmaps: \(error.localizedDescription)", isError: true) }
            loadingConfigMaps = false
        case .cronjobs:
            loadingCronJobs = true
            do { let listed = try await listScoped { [client] in try await client.listCronJobs(namespace: $0) }
                 if stillCurrent() { cronJobs = listed; stamp() } }
            catch { showToast("Failed to load cronjobs: \(error.localizedDescription)", isError: true) }
            // Run history rides along: recent Jobs, matched to owners in the view.
            if let runs = try? await listScoped({ [client] in try await client.listJobs(namespace: $0) }),
               stillCurrent() {
                cronJobRuns = runs
            }
            loadingCronJobs = false
        case .ingresses:
            loadingIngresses = true
            do { let listed = try await listScoped { [client] in try await client.listIngresses(namespace: $0) }
                 if stillCurrent() { ingresses = listed; stamp() } }
            catch { showToast("Failed to load ingresses: \(error.localizedDescription)", isError: true) }
            loadingIngresses = false
        }
    }

    // MARK: - ConfigMap selection

    func selectConfigMap(_ cm: K8sConfigMap) async {
        selectedConfigMap = cm
        configMapData = []
        await loadConfigMapData()
    }

    func loadConfigMapData() async {
        guard let cm = selectedConfigMap else { return }
        loadingConfigMapData = true
        do {
            let result = try await client.getConfigMapData(namespace: cm.namespace, name: cm.name)
            // Same late-reply guard as secrets: values must never land under a
            // different name than they belong to.
            guard isStillSelected(kind: "ConfigMap", name: cm.name, namespace: cm.namespace)
                    || allNamespaces && selectedConfigMap?.name == cm.name else {
                loadingConfigMapData = false
                return
            }
            configMapData = result.sorted { $0.key < $1.key }
        } catch {
            showToast("Failed to load configmap: \(error.localizedDescription)", isError: true)
        }
        loadingConfigMapData = false
    }

    /// Create an empty ConfigMap in the scoped namespace (the list's "+ New").
    func createConfigMap(named name: String) async {
        guard let ns = selectedNamespace else { return }
        let body: [String: Any] = [
            "apiVersion": "v1", "kind": "ConfigMap",
            "metadata": ["name": name, "namespace": ns.name],
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: body)
            try await client.createRawResource(
                collectionPath: "/api/v1/namespaces/\(ns.name)/configmaps", jsonData: data)
            showToast("Created configmap \(name)")
            await refreshCurrentResource()
        } catch {
            showToast("Create failed: \(error.localizedDescription)", isError: true)
        }
    }

    func saveConfigMapKey(namespace: String, name: String, key: String, value: String) async {
        do {
            try await client.patchConfigMapKey(namespace: namespace, name: name, key: key, value: value)
            showToast("\(key) saved")
            await loadConfigMapData()
            await refreshCurrentResource()
        } catch {
            showToast("Save failed: \(error.localizedDescription)", isError: true)
        }
    }

    func removeConfigMapKey(namespace: String, name: String, key: String) async {
        do {
            try await client.deleteConfigMapKey(namespace: namespace, name: name, key: key)
            showToast("\(key) deleted")
            await loadConfigMapData()
            await refreshCurrentResource()
        } catch {
            showToast("Delete failed: \(error.localizedDescription)", isError: true)
        }
    }

    // MARK: - CronJob operations

    func setCronJobSuspended(_ cj: K8sCronJob, suspended: Bool) async {
        do {
            try await client.setCronJobSuspended(namespace: cj.namespace, name: cj.name, suspended: suspended)
            showToast(suspended ? "\(cj.name) suspended" : "\(cj.name) resumed")
            await refreshCurrentResource()
        } catch {
            showToast("Failed: \(error.localizedDescription)", isError: true)
        }
    }

    func runCronJobNow(_ cj: K8sCronJob) async {
        do {
            let job = try await client.triggerCronJob(namespace: cj.namespace, name: cj.name)
            showToast("\(cj.name) started — job \(job)")
            await refreshCurrentResource()
        } catch {
            showToast("Run failed: \(error.localizedDescription)", isError: true)
        }
    }

    // MARK: - Overview + cluster events

    func loadOverview() async {
        // Overview spans every namespace regardless of scope: "is anything
        // wrong?" has to mean anywhere, or a red deployment hides behind the
        // namespace filter and the answer lies.
        async let deps: [K8sDeployment] = (try? listAcrossAll { [client] in
            try await client.listDeployments(namespace: $0) }) ?? []
        async let pds: [K8sPod] = (try? listAcrossAll { [client] in
            try await client.listPods(namespace: $0) }) ?? []
        let (d, p) = await (deps, pds)
        guard selectedDestination == .overview else { return }
        overviewDeployments = d
        overviewPods = p
        lastUpdated = Date()
    }

    var overviewDeployments: [K8sDeployment] = []
    var overviewPods: [K8sPod] = []

    /// Pods per namespace, for the namespace menu. Keyed by namespace, so
    /// unlike the scoped lists it cannot go stale against the current scope —
    /// and it is read-only decoration, never something an action acts on.
    var namespacePodCounts: [String: Int] = [:]
    private var namespaceCountsAt: Date?

    /// Refreshed when the menu opens, and not more than twice a minute: a
    /// count beside a namespace is worth one list call, not a poll.
    func loadNamespacePodCounts() async {
        if let at = namespaceCountsAt, Date().timeIntervalSince(at) < 30 { return }
        let pods = (try? await listAcrossAll { [client] in
            try await client.listPods(namespace: $0) }) ?? []
        // Every known namespace gets an entry: an empty namespace reads "0",
        // which is information, rather than a blank, which looks like a gap.
        var counts: [String: Int] = [:]
        for ns in namespaces { counts[ns.name] = 0 }
        for pod in pods { counts[pod.namespace, default: 0] += 1 }
        namespacePodCounts = counts
        namespaceCountsAt = Date()
    }

    private func listAcrossAll<T: Sendable>(
        _ fetch: @escaping @Sendable (String) async throws -> [T]
    ) async throws -> [T] {
        let names = namespaces.map(\.name)
        return try await withThrowingTaskGroup(of: (Int, [T]).self) { group in
            for (i, ns) in names.enumerated() { group.addTask { (i, try await fetch(ns)) } }
            var slots = [[T]](repeating: [], count: names.count)
            for try await (i, items) in group { slots[i] = items }
            return slots.flatMap { $0 }
        }
    }

    func loadClusterEvents() async {
        loadingClusterEvents = true
        let fetched = (try? await listAcrossAll { [client] in
            try await client.getEvents(namespace: $0, fieldSelector: nil) }) ?? []
        guard selectedDestination == .events else { loadingClusterEvents = false; return }
        // Newest first; the feed answers "what just happened".
        clusterEvents = fetched.sorted { ($0.lastSeen ?? .distantPast) > ($1.lastSeen ?? .distantPast) }
        loadingClusterEvents = false
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
            // Decrypted values under the wrong name is the worst version of this
            // race: click one secret while another's fetch is in flight and you
            // were shown its contents as though they belonged to the one named on
            // screen. `secretResourceVersion` is the save's precondition, so it
            // has to describe the same secret as the values beside it.
            guard isStillSelected(kind: "Secret", name: secret.name, namespace: ns.name) else {
                loadingData = false
                return
            }
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
            // Apply PUTs `rawYAML` back to `yamlResourcePath`. If a slower load
            // lands after a newer one, those two describe different objects — so
            // the editor would be showing one resource while aimed at another.
            // The API server rejects a name mismatch, but the editor should never
            // get into that state to begin with.
            guard yamlResourcePath == apiPath else { return }
            rawYAML = YAMLSerializer.serialize(json)
        } catch {
            guard yamlResourcePath == apiPath else { return }
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
                    // The fetch above is a suspension point: the user can select
                    // a different deployment while it is in flight, and this task
                    // is cancelled but not stopped mid-await. Without this check
                    // the reply for the old deployment lands on the new one's
                    // selection — the same theft the rollout poll used to commit,
                    // just one tick wide instead of three minutes.
                    if Task.isCancelled || self.selectedDeployment?.id != dep.id { break }
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
                    // Namespace can change while this is in flight, and pod
                    // metrics key on bare name — so one namespace's readings can
                    // land against another's identically-named pods.
                    guard !Task.isCancelled, self.selectedNamespace?.name == ns.name else { break }
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
                    guard !Task.isCancelled, self.selectedNamespace?.name == ns.name else { return }
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
                        // This hop is an unstructured Task, so it does not inherit
                        // the watch's cancellation: events already in the callback
                        // still ran after the watch was torn down, applying one
                        // namespace's pod changes to whatever namespace had since
                        // been opened. The namespace it was started for is the
                        // only thing that makes it safe to apply.
                        Task { @MainActor [weak self] in
                            guard let self, self.selectedNamespace?.name == ns.name else { return }
                            self.apply(event)
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
    /// Pods belonging to a deployment (their ReplicaSet is named
    /// "<deployment>-<hash>"). Powers the detail's PODS table and the
    /// aggregate metric chips on deployment rows.
    func pods(of dep: K8sDeployment) -> [K8sPod] {
        pods.filter { pod in
            guard pod.namespace == dep.namespace, pod.ownerKind == "ReplicaSet",
                  pod.ownerName.hasPrefix(dep.name + "-") else { return false }
            // The remainder must be the ReplicaSet's single hash segment —
            // otherwise deployment "web" would claim "web-api"'s pods.
            let rest = pod.ownerName.dropFirst(dep.name.count + 1)
            return !rest.isEmpty && !rest.contains("-")
        }
    }

    /// Summed live CPU/memory across a deployment's pods; nil until metrics
    /// are known, so the UI can simply omit the chips.
    func aggregateMetrics(of dep: K8sDeployment) -> (cpu: String, mem: String)? {
        let ms = pods(of: dep).compactMap { metrics(for: $0.name) }
        guard !ms.isEmpty else { return nil }
        let millis = ms.reduce(0) { $0 + $1.cpuMillis }
        let ki = ms.reduce(0) { $0 + $1.memoryKi }
        let cpu = millis >= 1000 ? String(format: "%.1f cores", Double(millis) / 1000) : "\(millis)m"
        let mem = ki >= 1024 * 1024 ? String(format: "%.1fGi", Double(ki) / 1_048_576) : "\(ki / 1024)Mi"
        return (cpu, mem)
    }

    /// "100m · 256Mi  /  500m · 512Mi per pod" from the first pod's first
    /// container requests/limits; nil when unknown.
    func requestsSummary(of dep: K8sDeployment) -> String? {
        guard let pod = pods(of: dep).first,
              let c = pod.containers.first else { return nil }
        let req = [c.cpuRequest, c.memRequest].filter { !$0.isEmpty }
        let lim = [c.cpuLimit, c.memLimit].filter { !$0.isEmpty }
        guard !req.isEmpty || !lim.isEmpty else { return nil }
        let reqStr = req.isEmpty ? "—" : req.joined(separator: " · ")
        let limStr = lim.isEmpty ? "—" : lim.joined(separator: " · ")
        return "\(reqStr)  /  \(limStr) per pod"
    }

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
        rolloutDeploymentId = deploymentId
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

                // The list row is this deployment's own, so it always updates.
                if let idx = self.deployments.firstIndex(where: { $0.id == deploymentId }) {
                    self.deployments[idx] = updated
                }

                // Selection and the events pane belong to whoever is being looked
                // at, which may no longer be this deployment: a rollout runs for
                // up to three minutes and the user is free to click away during
                // it. Writing them unconditionally dragged the selection back to
                // the scaling deployment every tick, and since the list observes
                // selection by id, that re-ran selection and reloaded its events
                // — the user could not stay on another deployment at all.
                let stillSelected = self.selectedDeployment?.id == deploymentId
                if stillSelected {
                    if updated != self.selectedDeployment {
                        self.selectedDeployment = updated
                    }
                    // Silently refresh events (no loading state)
                    await self.loadEvents(for: "Deployment", name: depName)
                }

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
                    // Names the deployment: the toast can land while the user is
                    // looking at a different one, where "all 10 replicas ready"
                    // alone reads as being about whatever is on screen.
                    self.showToast("\(depName): rollout complete — all \(updated.replicas) replicas ready")
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
        rolloutDeploymentId = nil
    }

    // MARK: - Pod actions

    func selectPod(_ pod: K8sPod) async {
        selectedPod = pod
        podLogs = ""
        await loadEvents(for: "Pod", name: pod.name)
    }

    func loadPodLogs(container: String? = nil, tailLines: Int = 200, sinceSeconds: Int? = nil) async {
        guard let ns = selectedNamespace, let pod = selectedPod else { return }
        loadingLogs = true
        do {
            let fetched = try await client.getPodLogs(namespace: ns.name, name: pod.name, container: container,
                                                      tailLines: tailLines, sinceSeconds: sinceSeconds)
            // Logs are the pane people read most carefully, so showing one pod's
            // output under another's name is worth guarding even though the fetch
            // is usually quick.
            guard isStillSelected(kind: "Pod", name: pod.name, namespace: ns.name) else {
                loadingLogs = false
                return
            }
            podLogs = fetched.isEmpty ? "(no logs available)" : fetched
        } catch {
            guard isStillSelected(kind: "Pod", name: pod.name, namespace: ns.name) else {
                loadingLogs = false
                return
            }
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

    /// Whether `name` is still the selected resource of `kind`, in `namespace`.
    ///
    /// Every load has to ask this after its await. A request takes as long as it
    /// takes and the user is free to click elsewhere meanwhile, so a reply that
    /// arrives late describes a resource that may no longer be on screen —
    /// writing it anyway puts one resource's data under another one's name.
    func isStillSelected(kind: String, name: String, namespace: String) -> Bool {
        guard selectedNamespace?.name ?? "default" == namespace else { return false }
        switch kind {
        case "Pod":        return selectedPod?.name == name
        case "Deployment": return selectedDeployment?.name == name
        case "Service":    return selectedService?.name == name
        case "Secret":     return selectedSecret?.name == name
        case "ConfigMap":  return selectedConfigMap?.name == name
        case "CronJob":    return selectedCronJob?.name == name
        case "Ingress":    return selectedIngress?.name == name
        default:           return true   // cluster-scoped: nothing to race against
        }
    }

    func loadEvents(for kind: String, name: String) async {
        // Nodes are cluster-scoped, events are in default namespace
        let ns = selectedNamespace?.name ?? "default"
        do {
            let fetched = try await client.getEvents(
                namespace: ns,
                fieldSelector: "involvedObject.name=\(name),involvedObject.kind=\(kind)"
            )
            // The events pane belongs to whatever is selected now, which may not
            // be what this fetch was for: clicking B while A's events are in
            // flight used to land A's events under B.
            guard isStillSelected(kind: kind, name: name, namespace: ns) else { return }
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
        if let cm = selectedConfigMap, let updated = configMaps.first(where: { $0.id == cm.id }) {
            selectedConfigMap = updated
        }
        if let cj = selectedCronJob, let updated = cronJobs.first(where: { $0.id == cj.id }) {
            selectedCronJob = updated
        }
        if let ing = selectedIngress, let updated = ingresses.first(where: { $0.id == ing.id }) {
            selectedIngress = updated
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
