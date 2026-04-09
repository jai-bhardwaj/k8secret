import SwiftUI

struct SecretDetailView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        Group {
            if state.selectedSecret == nil {
                ContentUnavailableView {
                    Label("Select a Secret", systemImage: "key")
                } description: {
                    Text("Choose a secret to view and edit its data.")
                }
            } else if state.loadingData {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading secret data...")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                detailContent
            }
        }
        .sheet(item: $state.editingKey) { kv in
            EditSheet(
                key: kv.key,
                initialValue: currentValue(for: kv.key),
                isNew: false
            ) { value in
                state.stageEdit(key: kv.key, value: value)
            }
        }
        .sheet(isPresented: $state.isAddingKey) {
            AddKeySheet { key, value in
                state.stageAdd(key: key, value: value)
            }
        }
    }

    private func currentValue(for key: String) -> String {
        if let mod = state.modifications[key] { return mod }
        if let add = state.additions[key] { return add }
        return state.secretData.first(where: { $0.key == key })?.value ?? ""
    }

    private var detailContent: some View {
        @Bindable var state = state

        return VStack(spacing: 0) {
            // Change summary bar
            if state.hasChanges {
                changeSummaryBar
            }

            // KV search bar — always visible, prominent
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search keys & values...", text: $state.kvSearch)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                if !state.kvSearch.isEmpty {
                    Button {
                        state.kvSearch = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Text("\(state.displayedKVs.count) result\(state.displayedKVs.count == 1 ? "" : "s")")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }

            // KV list
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(state.displayedKVs) { kv in
                        KVRow(kv: kv)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .overlay {
                if state.secretData.isEmpty && state.additions.isEmpty {
                    ContentUnavailableView {
                        Label("Empty Secret", systemImage: "tray")
                    } description: {
                        Text("This secret has no data. Add a key to get started.")
                    }
                } else if !state.kvSearch.isEmpty && state.displayedKVs.isEmpty {
                    ContentUnavailableView.search(text: state.kvSearch)
                }
            }
            // Floating add button — bottom right
            .overlay(alignment: .bottomTrailing) {
                Button {
                    state.isAddingKey = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(.green.gradient, in: Circle())
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n", modifiers: .command)
                .help("Add Key (⌘N)")
                .padding(20)
            }
        }
        .navigationTitle(state.selectedSecret?.name ?? "")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    state.discardChanges()
                } label: {
                    Label("Discard", systemImage: "arrow.uturn.backward")
                }
                .opacity(state.hasChanges ? 1 : 0)
                .disabled(!state.hasChanges)

                Button {
                    Task { await state.saveChanges() }
                } label: {
                    Label("Save", systemImage: "checkmark.circle.fill")
                }
                .tint(.green)
                .opacity(state.hasChanges ? 1 : 0)
                .disabled(!state.hasChanges || state.saving)

                Button { state.showBulkImport = true } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .help("Bulk import keys")

                Button { state.showYAMLEditor = true } label: {
                    Label("YAML", systemImage: "doc.text")
                }
                .help("Edit raw YAML")
            }
        }
        .sheet(isPresented: $state.showBulkImport) {
            BulkImportSheet()
        }
        .sheet(isPresented: $state.showYAMLEditor) {
            YAMLEditorView()
        }
        .onChange(of: state.showYAMLEditor) { _, show in
            if show, let ns = state.selectedNamespace, let secret = state.selectedSecret {
                Task { await state.loadRawYAML(apiPath: "/api/v1/namespaces/\(ns.name)/secrets/\(secret.name)") }
            }
        }
    }

    private var changeSummaryBar: some View {
        HStack(spacing: 16) {
            Image(systemName: "pencil.circle.fill")
                .foregroundStyle(.orange)

            Text("\(state.changeCount) unsaved change\(state.changeCount == 1 ? "" : "s")")
                .font(.system(.callout, design: .default, weight: .medium))

            if !state.modifications.isEmpty {
                badge("~\(state.modifications.count)", color: .orange)
            }
            if !state.additions.isEmpty {
                badge("+\(state.additions.count)", color: .green)
            }
            if !state.deletions.isEmpty {
                badge("-\(state.deletions.count)", color: .red)
            }

            Spacer()

            Button("Discard") {
                state.discardChanges()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button("Save All") {
                Task { await state.saveChanges() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.small)
            .disabled(state.saving)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.orange.opacity(0.06))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - KV Row

struct KVRow: View {
    @Environment(AppState.self) private var state
    let kv: DisplayKV

    @State private var isHovered = false

    @State private var showCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Line 1: Status icon + Key + Actions
            HStack(spacing: 8) {
                statusIcon

                Text(kv.key)
                    .font(.system(.body, design: .monospaced, weight: .semibold))
                    .foregroundStyle(keyColor)
                    .lineLimit(1)
                    .textSelection(.enabled)

                Spacer()

                // Actions
                HStack(spacing: 4) {
                    // Copy button
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(kv.value, forType: .string)
                        showCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            showCopied = false
                        }
                    } label: {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundStyle(showCopied ? .green : .secondary)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Copy value")
                    .disabled(kv.status == .deleted)

                    actions
                }
                .opacity(isHovered ? 1 : 0.6)
            }

            // Line 2: Value
            HStack(spacing: 0) {
                Text(kv.value)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(kv.status == .deleted ? Color.secondary : Color.primary.opacity(0.7))
                    .strikethrough(kv.status == .deleted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onTapGesture {
                if kv.status != .deleted {
                    state.editingKey = K8sKeyValue(id: kv.key, key: kv.key, value: kv.value)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch kv.status {
        case .modified:
            Image(systemName: "pencil.circle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 14))
        case .added:
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 14))
        case .deleted:
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 14))
        case .none:
            Image(systemName: "key.fill")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
        }
    }

    private var keyColor: Color {
        switch kv.status {
        case .modified: return .orange
        case .added: return .green
        case .deleted: return .red
        case .none: return .accentColor
        }
    }

    private var rowBackground: Color {
        switch kv.status {
        case .modified: return Color.orange.opacity(0.04)
        case .added: return Color.green.opacity(0.04)
        case .deleted: return Color.red.opacity(0.04)
        case .none: return isHovered ? Color.primary.opacity(0.03) : Color.clear
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 4) {
            if kv.status == .deleted {
                Button {
                    state.undoChange(key: kv.key)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Undo delete")
            } else {
                Button {
                    state.editingKey = K8sKeyValue(id: kv.key, key: kv.key, value: kv.value)
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Edit value")

                Button {
                    state.stageDelete(key: kv.key)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Delete key")
            }

            if kv.status == .modified || kv.status == .added {
                Button {
                    state.undoChange(key: kv.key)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Undo change")
            }
        }
    }
}

// MARK: - Edit Sheet

struct EditSheet: View {
    let key: String
    let initialValue: String
    let isNew: Bool
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var value: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "pencil.circle.fill")
                    .foregroundStyle(.orange)
                Text("Edit Value")
                    .font(.system(.title3, design: .monospaced, weight: .semibold))
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("KEY")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(key)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("VALUE")
                        .font(.system(.caption, design: .monospaced, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(value.count) chars")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                TextEditor(text: $value)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 160)
                    .padding(4)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
            }

            HStack {
                if value != initialValue {
                    Text("Modified")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(value)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(value == initialValue)
            }
        }
        .padding(24)
        .frame(width: 580)
        .onAppear {
            value = initialValue
            isFocused = true
        }
    }
}

// MARK: - Add Key Sheet

struct AddKeySheet: View {
    let onAdd: (String, String) -> Void

    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var value = ""
    @FocusState private var keyFieldFocused: Bool
    @FocusState private var valueFieldFocused: Bool

    private var trimmedKey: String { key.trimmingCharacters(in: .whitespaces) }
    private var isDuplicate: Bool { !trimmedKey.isEmpty && state.keyExists(trimmedKey) }
    private var canAdd: Bool { !trimmedKey.isEmpty && !isDuplicate }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.green)
                Text("Add Key")
                    .font(.system(.title3, design: .monospaced, weight: .semibold))
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("KEY")
                        .font(.system(.caption, design: .monospaced, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isDuplicate {
                        Label("Key already exists", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.red)
                    }
                }
                TextField("e.g. DATABASE_URL, API_KEY", text: $key)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .focused($keyFieldFocused)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isDuplicate ? Color.red.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
                    .onSubmit { valueFieldFocused = true }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("VALUE")
                        .font(.system(.caption, design: .monospaced, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !value.isEmpty {
                        Text("\(value.count) chars")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                TextEditor(text: $value)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 140)
                    .padding(4)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    .scrollContentBackground(.hidden)
                    .focused($valueFieldFocused)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    onAdd(trimmedKey, value)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(!canAdd)
            }
        }
        .padding(24)
        .frame(width: 580)
        .onAppear { keyFieldFocused = true }
    }
}
