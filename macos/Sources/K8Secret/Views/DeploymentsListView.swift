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
                        .font(.callout)
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
        List(state.filteredDeployments, selection: $state.selectedDeployment) { dep in
            DeploymentRow(deployment: dep, showNamespace: state.allNamespaces)
                .tag(dep)
                .vnextRow(isSelected: state.selectedDeployment?.id == dep.id)
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(Theme.line)
                .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
        }
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
    let deployment: K8sDeployment
    var showNamespace = false

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .overlay {
                    if deployment.status == .updating {
                        Circle()
                            .stroke(statusColor, lineWidth: 2)
                            .frame(width: 16, height: 16)
                            .opacity(0.5)
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(deployment.name)
                        .font(.system(.body, design: .monospaced, weight: .medium))
                        .lineLimit(1)
                    if showNamespace { NamespaceBadge(name: deployment.namespace) }
                }

                HStack(spacing: 8) {
                    // Replicas badge
                    HStack(spacing: 3) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 9))
                        Text(verbatim: "\(deployment.readyReplicas)/\(deployment.replicas)")
                    }
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(deployment.readyReplicas == deployment.replicas ? Theme.ok : Theme.warn)

                    // Image name (shortened)
                    if let image = deployment.images.first {
                        Text(shortenImage(image))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // Strategy + Age
            VStack(alignment: .trailing, spacing: 4) {
                // "RollingUpdate" is long enough to hyphenate in a narrow column.
                Text(deployment.strategy)
                    .font(.system(.caption2, design: .monospaced))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                Text(deployment.age)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch deployment.status {
        case .running: return .green
        case .updating: return .orange
        case .scaled: return .blue
        case .degraded: return .red
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
