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
                    .font(.system(.title3, design: .monospaced, weight: .semibold))

                Spacer()

                if hasEdits {
                    Text("Modified")
                        .font(.system(.caption, design: .monospaced, weight: .medium))
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
                        Task {
                            await state.applyRawYAML()
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(state.saving)
                }
            }
            .padding(16)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }

            // Editor
            if state.loadingYAML {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading resource...")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TextEditor(text: $editedYAML)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color.black.opacity(0.2))
                    .onChange(of: editedYAML) { _, newValue in
                        hasEdits = newValue != state.rawYAML
                    }
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear {
            editedYAML = state.rawYAML
        }
    }
}
