import SwiftUI

struct DeploymentsListView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        Group {
            if state.selectedNamespace == nil && !state.allNamespaces {
                ContentUnavailableView {
                    Label("Select a Namespace", systemImage: "sidebar.left")
                } description: {
                    Text("Choose a namespace to view its deployments.")
                }
            } else if state.loadingDeployments && state.deployments.isEmpty {
                // Only take over the view when there is nothing to show yet.
                // Refreshing content that is already on screen stays in place; the
                // spinner used to replace the list on every refresh, losing scroll
                // position and flashing the rows.
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading deployments...")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                deploymentsList
            }
        }
        // A refresh over existing content shows here instead of replacing the
        // list, so the rows stay put and the work is still visible.
        .overlay(alignment: .topTrailing) {
            if state.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .padding(8)
                    .transition(.opacity)
                    .accessibilityLabel("Refreshing")
            }
        }
        .motion(Motion.stateChange, value: state.isRefreshing)
        // A list of names, ages and status pills needs real width. Without a
        // floor this column collapsed next to the detail pane and truncated
        // its own empty-state title to "No Deploy…".
        .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 560)
    }

    private var deploymentsList: some View {
        @Bindable var state = state

        return VStack(spacing: 0) {
        PaneHeader(
            title: "Deployments",
            subtitle: "\(state.deployments.count) \(state.allNamespaces ? "across all namespaces" : "in " + (state.selectedNamespace?.name ?? "—"))")
        FilterField(prompt: "Filter deployments…", text: $state.deploymentSearch)
        List(state.filteredDeployments) { dep in
            DeploymentRow(deployment: dep, showNamespace: state.allNamespaces)
                .vnextRow(isSelected: state.selectedDeployment?.id == dep.id)
                .onTapGesture { state.selectedDeployment = dep }
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(Theme.line)
                .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
        }
        .vnextKeyboardSelection(items: state.filteredDeployments, selection: $state.selectedDeployment)
        .overlay {
            if state.deployments.isEmpty {
                // An empty namespace is a dead end unless it says where to go
                // next. A fresh install lands on `default`, which on most
                // clusters holds nothing, so this was the first screen many
                // people saw.
                EmptyPane(icon: "shippingbox", title: "No Deployments",
                           message: "Nothing here in \(state.selectedNamespace?.name ?? "this namespace"). Pick another namespace from the menu above, or a different resource type in the sidebar.")
            } else if state.filteredDeployments.isEmpty {
                EmptyPane(icon: "magnifyingglass", title: "No matches",
                           message: "No results for “\(state.deploymentSearch)”. The filter matches anywhere in the name.")
            }
        }
        .onChange(of: state.selectedDeployment?.id) { _, _ in
            // Keyed on id, not the whole value. Polling and the watch stream
            // rewrite the selected object in place as its status changes, and
            // reacting to that as if the user had clicked a different row reran
            // selection — which clears the log pane and refetches events out from
            // under someone who is reading them.
            guard let dep = state.selectedDeployment else { return }
            Task { await state.selectDeployment(dep) }
        }
        }
        .vnextListPane()
    }
}

struct DeploymentRow: View {
    @Environment(AppState.self) private var state
    let deployment: K8sDeployment
    var showNamespace = false

    var body: some View {
        // The prototype's two-line anatomy: name + state pill + age, then the
        // data line — ready-with-check and the image as a neutral chip. The
        // strategy string moved to the detail pane where it belongs.
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(deployment.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if showNamespace { NamespaceBadge(name: deployment.namespace) }
                Spacer(minLength: 4)
                statusPill
                Text(deployment.age)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            HStack(spacing: 6) {
                // The prototype's data line: live CPU + memory, not the image
                // (that's SPEC's job in the detail pane).
                if let agg = state.aggregateMetrics(of: deployment) {
                    MetricChip(icon: "cpu", text: agg.cpu, hue: Theme.cpu)
                    MetricChip(icon: "memorychip", text: agg.mem, hue: Theme.memory)
                } else {
                    MetricChip(icon: "moon.zzz", text: "no usage", hue: nil)
                }
                Spacer(minLength: 4)
                HStack(spacing: 3) {
                    Text(verbatim: "\(deployment.readyReplicas)/\(deployment.replicas)")
                    if deployment.readyReplicas == deployment.replicas && deployment.replicas > 0 {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                    }
                }
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(deployment.readyReplicas == deployment.replicas && deployment.replicas > 0
                                 ? Theme.ok : (deployment.replicas == 0 ? Color.secondary : Theme.warn))
            }
            // Mid-rollout: the prototype's progress minibar under the row.
            if deployment.status == .updating, deployment.replicas > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.inset)
                        Capsule().fill(Theme.warn)
                            .frame(width: geo.size.width * CGFloat(deployment.readyReplicas) / CGFloat(deployment.replicas))
                    }
                }
                .frame(height: 3)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var statusPill: some View {
        switch deployment.status {
        case .running: StatusPill(text: "Running", color: Theme.ok)
        case .updating: StatusPill(text: "Rolling", color: Theme.accent, pulses: true)
        case .scaled: StatusPill(text: "Stopped", color: Theme.warn)
        case .degraded: StatusPill(text: "Degraded", color: Theme.bad)
        }
    }

    private func shortenImage(_ image: String) -> String {
        // Show only repo/name:tag, strip registry
        let parts = image.components(separatedBy: "/")
        if parts.count > 2 {
            return parts.suffix(2).joined(separator: "/")
        }
        return image
    }
}
