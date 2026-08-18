import SwiftUI

/// Editing a secret as YAML — the same surface grammar as everything else:
/// the cluster's canvas behind it, our type scale, and the accent it shares
/// with the window it came from.
struct YAMLEditorView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @Environment(\.clusterAccent) private var accent

    @State private var editedYAML: String = ""
    @State private var hasEdits = false

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.selectedSecret?.name ?? "YAML")
                        .font(.system(size: 14.5, weight: .bold, design: .monospaced))
                        .kerning(-0.2)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 6) {
                        Text("Applied as one write, on the version you opened")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.text3)
                        // The one place values are not masked, said plainly.
                        // They cannot be: this text is what gets written back,
                        // so a redacted line would overwrite a real secret with
                        // the word that hid it.
                        Label("values in full", systemImage: "eye")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.warn)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Theme.soft(Theme.warn), in: Capsule())
                    }
                    .lineLimit(1)
                }

                Spacer(minLength: 12)

                if hasEdits {
                    StatusPill(text: "Modified", color: accent)
                }

                Button("Close") { state.showYAMLEditor = false }
                    .buttonStyle(Theme.SoftPill())
                    .focusEffectDisabled()
                    .keyboardShortcut(.cancelAction)

                if hasEdits {
                    Button("Apply") {
                        state.rawYAML = editedYAML
                        // Close first — the confirmation is presented by
                        // ContentView and would otherwise sit under this.
                        state.showYAMLEditor = false
                        state.requestApplyRawYAML()
                    }
                    .buttonStyle(Theme.PrimaryPill())
                    .disabled(state.saving)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }

            // Editor
            if state.loadingYAML {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text("Reading the manifest…")
                        .foregroundStyle(Theme.text3)
                        .font(.system(size: 12))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TextEditor(text: $editedYAML)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Theme.inset)
                    .onChange(of: editedYAML) { _, newValue in
                        hasEdits = newValue != state.rawYAML
                    }
            }
        }
        // Bounded, not fixed: a hard 720×540 overflowed a window at the app's
        // own minimum size, clipping the editor's own Close button.
        .frame(maxWidth: 720, maxHeight: 540)
        .padding(24)
        .popGlass(radius: 20)
        .shadow(color: .black.opacity(0.4), radius: 40, y: 20)
        // The editor fetches its own manifest and follows it in. It used to
        // copy `rawYAML` once, on appear — which happens before the fetch it
        // was waiting on returns, so the editor opened empty and stayed empty.
        .task {
            if let secret = state.selectedSecret {
                await state.loadRawYAML(
                    apiPath: AppState.apiPath(for: .secrets,
                                              namespace: secret.namespace,
                                              name: secret.name))
            }
            editedYAML = state.rawYAML
        }
        .onChange(of: state.rawYAML) { _, loaded in
            guard !hasEdits else { return }
            editedYAML = loaded
        }
    }
}
