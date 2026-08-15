import SwiftUI

struct SecretsListView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        Group {
            if state.selectedNamespace == nil && !state.allNamespaces {
                ContentUnavailableView {
                    Label("Select a Namespace", systemImage: "sidebar.left")
                } description: {
                    Text("Choose a namespace from the sidebar to view its secrets.")
                }
            } else if state.loadingSecrets && state.secrets.isEmpty {
                // Only take over the view when there is nothing to show yet.
                // Refreshing content that is already on screen stays in place; the
                // spinner used to replace the list on every refresh, losing scroll
                // position and flashing the rows.
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading secrets...")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                secretsList
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
        .navigationTitle(state.selectedNamespace?.name ?? "Secrets")
    }

    private var secretsList: some View {
        @Bindable var state = state

        return List(state.filteredSecrets, selection: $state.selectedSecret) { secret in
            SecretRow(secret: secret)
                .tag(secret)
        }
        .searchable(text: $state.secretSearch, prompt: "Filter secrets")
        .overlay {
            if state.secrets.isEmpty {
                ContentUnavailableView {
                    Label("No Secrets", systemImage: "lock.slash")
                } description: {
                    Text("Nothing here in **\(state.selectedNamespace?.name ?? "this namespace")**. Pick another namespace from the menu above, or a different resource type in the sidebar.")
                }
            } else if state.filteredSecrets.isEmpty {
                ContentUnavailableView.search(text: state.secretSearch)
            }
        }
        .onChange(of: state.selectedSecret?.id) { _, _ in
            // Keyed on id, not the whole value. Polling and the watch stream
            // rewrite the selected object in place as its status changes, and
            // reacting to that as if the user had clicked a different row reran
            // selection — which clears the log pane and refetches events out from
            // under someone who is reading them.
            guard let secret = state.selectedSecret else { return }
            Task { await state.selectSecret(secret) }
        }
    }
}

struct SecretRow: View {
    let secret: K8sSecret

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: secretIcon)
                .foregroundStyle(.tint)
                .font(.system(size: 16))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(secret.name)
                    .font(.system(.body, design: .monospaced, weight: .medium))
                    .lineLimit(1)

                Text(secret.type)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(secret.age)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(.vertical, 4)
    }

    private var secretIcon: String {
        let type = secret.type.lowercased()
        if type.contains("tls") { return "lock.shield.fill" }
        if type.contains("dockercfg") || type.contains("docker") { return "shippingbox.fill" }
        if type.contains("service-account") { return "person.badge.key.fill" }
        if type.contains("basic-auth") { return "person.fill" }
        if type.contains("ssh") { return "terminal.fill" }
        return "key.fill"
    }
}
