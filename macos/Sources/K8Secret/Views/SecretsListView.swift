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
                        .font(.system(size: 12))
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
    }

    private var secretsList: some View {
        @Bindable var state = state

        return VStack(spacing: 0) {
        PaneHeader(
            title: "Secrets",
            subtitle: "\(state.secrets.count) \(state.allNamespaces ? "across all namespaces" : "in " + (state.selectedNamespace?.name ?? "—"))")
        FilterField(prompt: "Filter secrets…", text: $state.secretSearch)
        ListColumnHeader(columns: [("Name", nil), ("Keys", 46), ("Age", 44)])
        List(state.filteredSecrets) { secret in
            SecretRow(secret: secret)
                .vnextRow(isSelected: state.selectedSecret?.id == secret.id)
                .onTapGesture { state.selectedSecret = secret }
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(Theme.line)
                .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
        }
        .vnextKeyboardSelection(items: state.filteredSecrets, selection: $state.selectedSecret)
        .overlay {
            if state.secrets.isEmpty {
                EmptyPane(icon: "lock.slash", title: "No Secrets",
                           message: "Nothing here in \(state.selectedNamespace?.name ?? "this namespace"). Pick another namespace from the menu above, or a different resource type in the sidebar.")
            } else if state.filteredSecrets.isEmpty {
                EmptyPane(icon: "magnifyingglass", title: "No matches",
                           message: "No results for “\(state.secretSearch)”. The filter matches anywhere in the name.")
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
        .vnextListPane()
    }
}

struct SecretRow: View {
    let secret: K8sSecret

    /// The prototype's `.row.c-sec`: name, key count, age — the type belongs
    /// in the detail pane, not repeated down the list.
    var body: some View {
        HStack(spacing: 8) {
            Text(secret.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(secret.keyCount > 0 ? "\(secret.keyCount)" : "—")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(Theme.text2)
                .frame(width: 46, alignment: .trailing)

            Text(secret.age)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(Theme.text3)
                .frame(width: 44, alignment: .trailing)
        }
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
