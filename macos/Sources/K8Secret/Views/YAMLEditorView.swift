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
                    Text("Editing the manifest — applied as one write, on the version you opened")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.text3)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                if hasEdits {
                    StatusPill(text: "Modified", color: accent)
                }

                Button("Close") { dismiss() }
                    .buttonStyle(Theme.SoftPill())
                    .keyboardShortcut(.cancelAction)

                if hasEdits {
                    Button("Apply") {
                        state.rawYAML = editedYAML
                        // Close the sheet first — the confirmation is presented by
                        // ContentView and would otherwise be covered by it.
                        dismiss()
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
        .frame(minWidth: 700, minHeight: 500)
        .background(Theme.CanvasBackground(tint: state.clusterTint, hero: false))
        .onAppear {
            editedYAML = state.rawYAML
        }
    }
}
