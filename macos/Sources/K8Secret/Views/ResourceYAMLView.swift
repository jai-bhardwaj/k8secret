import SwiftUI

/// The YAML tab, as the prototype has on every detail pane: the live manifest
/// straight from the API server, not a rendering of what the app parsed.
///
/// Secrets are the exception the app exists for — their values stay redacted
/// here, because base64 is not encryption and a manifest view is not a request
/// to reveal anything.
struct ResourceYAMLView: View {
    @Environment(AppState.self) private var state
    let type: ResourceType
    let namespace: String
    let name: String

    @State private var yaml = ""
    @State private var failure: String?
    @State private var loading = true
    @State private var copied = false

    private var path: String {
        AppState.apiPath(for: type, namespace: namespace, name: name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if type == .secrets {
                    Label("Values redacted", systemImage: "eye.slash")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.text3)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(yaml, forType: .string)
                    withAnimation(Motion.stateChange) { copied = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1.6))
                        withAnimation(Motion.stateChange) { copied = false }
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .buttonStyle(Theme.SoftPill())
                .disabled(yaml.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if loading {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 40)
            } else if let failure {
                Text(failure)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.bad)
                    .padding(.horizontal, 20)
            } else {
                ScrollView([.vertical, .horizontal]) {
                    Text(yaml)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Theme.text2)
                        .textSelection(.enabled)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: path) { await load() }
    }

    private func load() async {
        loading = true
        failure = nil
        do {
            yaml = try await state.manifestYAML(path: path, redactingData: type == .secrets)
        } catch {
            failure = error.localizedDescription
        }
        loading = false
    }
}
