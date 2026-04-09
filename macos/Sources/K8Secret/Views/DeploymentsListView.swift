import SwiftUI

struct DeploymentsListView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        Group {
            if state.selectedNamespace == nil {
                ContentUnavailableView {
                    Label("Select a Namespace", systemImage: "sidebar.left")
                } description: {
                    Text("Choose a namespace to view its deployments.")
                }
            } else if state.loadingDeployments {
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
        .navigationTitle(state.selectedNamespace?.name ?? "Deployments")
    }

    private var deploymentsList: some View {
        @Bindable var state = state

        return List(state.filteredDeployments, selection: $state.selectedDeployment) { dep in
            DeploymentRow(deployment: dep)
                .tag(dep)
        }
        .searchable(text: $state.deploymentSearch, prompt: "Filter deployments")
        .overlay {
            if state.deployments.isEmpty {
                ContentUnavailableView {
                    Label("No Deployments", systemImage: "shippingbox")
                } description: {
                    Text("This namespace has no deployments.")
                }
            } else if state.filteredDeployments.isEmpty {
                ContentUnavailableView.search(text: state.deploymentSearch)
            }
        }
        .onChange(of: state.selectedDeployment) { _, newValue in
            if let dep = newValue {
                Task { await state.selectDeployment(dep) }
            }
        }
    }
}

struct DeploymentRow: View {
    let deployment: K8sDeployment

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
                Text(deployment.name)
                    .font(.system(.body, design: .monospaced, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    // Replicas badge
                    HStack(spacing: 3) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 9))
                        Text("\(deployment.readyReplicas)/\(deployment.replicas)")
                    }
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(deployment.readyReplicas == deployment.replicas ? .green : .orange)

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
                Text(deployment.strategy)
                    .font(.system(.caption2, design: .monospaced))
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
