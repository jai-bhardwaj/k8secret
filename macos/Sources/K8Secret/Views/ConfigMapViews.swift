import SwiftUI

// MARK: - List

struct ConfigMapsListView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        List(state.filteredConfigMaps, selection: $state.selectedConfigMap) { cm in
            HStack(spacing: 8) {
                Text(cm.name)
                    .font(.system(.body, weight: .semibold))
                    .lineLimit(1)
                if state.allNamespaces { NamespaceBadge(name: cm.namespace) }
                Spacer(minLength: 4)
                Text("\(cm.dataCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(cm.age)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .padding(.vertical, 3)
            .tag(cm)
        }
        .searchable(text: $state.configMapSearch, prompt: "Filter configmaps")
        .navigationTitle("ConfigMaps")
        .overlay {
            if state.isInitialLoad {
                ProgressView()
            } else if state.configMaps.isEmpty {
                ContentUnavailableView {
                    Label("No ConfigMaps", systemImage: "slider.horizontal.3")
                } description: {
                    Text(state.allNamespaces
                         ? "No configmaps in any namespace."
                         : "No configmaps in this namespace.")
                }
            } else if state.filteredConfigMaps.isEmpty {
                ContentUnavailableView.search(text: state.configMapSearch)
            }
        }
        .onChange(of: state.selectedConfigMap?.id) { _, _ in
            guard let cm = state.selectedConfigMap else { return }
            Task { await state.selectConfigMap(cm) }
        }
        .motion(Motion.listChange, value: state.configMaps)
    }
}

// MARK: - Detail

/// The secret editor's sibling with masking off: ConfigMaps aren't sensitive,
/// so values show in full — but the same editor, the same confirm-before-write,
/// and the same .env round-trip apply.
struct ConfigMapDetailView: View {
    @Environment(AppState.self) private var state
    @State private var editingKey: K8sKeyValue?
    @State private var editValue = ""
    @State private var showExport = false

    var body: some View {
        if let cm = state.selectedConfigMap {
            VStack(alignment: .leading, spacing: 0) {
                header(cm)
                Divider()
                if state.loadingConfigMapData && state.configMapData.isEmpty {
                    Spacer(); ProgressView().frame(maxWidth: .infinity); Spacer()
                } else if state.configMapData.isEmpty {
                    ContentUnavailableView {
                        Label("Empty ConfigMap", systemImage: "slider.horizontal.3")
                    } description: { Text("No keys yet.") }
                } else {
                    List(state.configMapData) { kv in
                        row(cm, kv)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(cm.name)
            .sheet(item: $editingKey) { kv in
                editSheet(cm, kv)
            }
            .sheet(isPresented: $showExport) {
                EnvExportSheet(
                    title: cm.name,
                    pairs: state.configMapData.map { ($0.key, $0.value) },
                    stagedNote: nil
                )
            }
        } else {
            ContentUnavailableView {
                Label("No ConfigMap Selected", systemImage: "slider.horizontal.3")
            } description: {
                Text("Choose a configmap to view and edit its data.")
            }
        }
    }

    private func header(_ cm: K8sConfigMap) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(cm.name).font(.title3.weight(.bold))
                Text("\(state.configMapData.count) keys · created \(cm.age) ago")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button("Export .env") { showExport = true }
                .disabled(state.configMapData.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func row(_ cm: K8sConfigMap, _ kv: K8sKeyValue) -> some View {
        HStack(spacing: 10) {
            Text(kv.key)
                .font(.system(.callout, design: .monospaced, weight: .semibold))
                .frame(minWidth: 120, maxWidth: 220, alignment: .leading)
                .lineLimit(1)
            Text(kv.value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)
            Spacer(minLength: 4)
            Button {
                editValue = kv.value
                editingKey = kv
            } label: { Image(systemName: "pencil") }
                .buttonStyle(.borderless)
                .help("Edit \(kv.key)")
            Button {
                deleteKey(cm, kv)
            } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .help("Delete \(kv.key)")
        }
        .padding(.vertical, 3)
    }

    private func editSheet(_ cm: K8sConfigMap, _ kv: K8sKeyValue) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit \(kv.key)").font(.headline)
            TextEditor(text: $editValue)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 100)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            HStack {
                Spacer()
                Button("Cancel") { editingKey = nil }
                Button("Save") {
                    let newValue = editValue
                    editingKey = nil
                    state.confirm(
                        title: "Save \(kv.key)?",
                        message: "Writes the new value to \(cm.name) in \(cm.namespace). Pods read it on their next restart.",
                        confirmLabel: "Save",
                        destructive: false
                    ) { [state] in
                        await state.saveConfigMapKey(
                            namespace: cm.namespace, name: cm.name, key: kv.key, value: newValue)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(editValue == kv.value)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }

    private func deleteKey(_ cm: K8sConfigMap, _ kv: K8sKeyValue) {
        state.confirm(
            title: "Delete \(kv.key)?",
            message: "Removes the key from \(cm.name) in \(cm.namespace). Pods keep their current value until restarted.",
            confirmLabel: "Delete key"
        ) { [state] in
            await state.removeConfigMapKey(namespace: cm.namespace, name: cm.name, key: kv.key)
        }
    }
}
