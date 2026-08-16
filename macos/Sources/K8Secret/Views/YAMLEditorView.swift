import SwiftUI

struct YAMLEditorView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var editedYAML: String = ""
    @State private var hasEdits = false

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.orange)
                Text("YAML Editor")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))

                Spacer()

                if hasEdits {
                    Text("Modified")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.orange.opacity(0.12), in: Capsule())
                }

                Button("Close") { dismiss() }
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
            .padding(16)
            .background(Theme.inset)
            .overlay(alignment: .bottom) { Divider() }

            // Editor
            if state.loadingYAML {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading resource...")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TextEditor(text: $editedYAML)
                    .font(.system(size: 12.5, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color.black.opacity(0.2))
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
