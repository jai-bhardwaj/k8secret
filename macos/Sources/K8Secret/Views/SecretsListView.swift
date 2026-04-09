import SwiftUI

struct SecretsListView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        Group {
            if state.selectedNamespace == nil {
                ContentUnavailableView {
                    Label("Select a Namespace", systemImage: "sidebar.left")
                } description: {
                    Text("Choose a namespace from the sidebar to view its secrets.")
                }
            } else if state.loadingSecrets {
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
                    Text("This namespace has no secrets.")
                }
            } else if state.filteredSecrets.isEmpty {
                ContentUnavailableView.search(text: state.secretSearch)
            }
        }
        .onChange(of: state.selectedSecret) { _, newValue in
            if let secret = newValue {
                Task { await state.selectSecret(secret) }
            }
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
