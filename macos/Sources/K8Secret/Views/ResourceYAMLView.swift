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
                    Text(YAMLHighlighter.attributed(yaml))
                        .font(.system(size: 12, design: .monospaced))
                        .lineSpacing(3.4)                 // the prototype's 1.7 line-height
                        .textSelection(.enabled)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.inset, in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(Theme.line, lineWidth: 1))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
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


/// The prototype's YAML colouring: keys in the cluster accent, quoted strings
/// in the warning hue, comments muted.
///
/// Deliberately lexical rather than a real parse. This renders a manifest the
/// server sent, so it is already valid YAML — the job here is to make structure
/// scannable, and a tokeniser that never fails is worth more than one that is
/// exactly right about edge cases nobody will look at.
enum YAMLHighlighter {
    static func attributed(_ yaml: String) -> AttributedString {
        var out = AttributedString()
        for (index, line) in yaml.components(separatedBy: "\n").enumerated() {
            if index > 0 { out += AttributedString("\n") }
            out += highlight(line)
        }
        return out
    }

    private static func highlight(_ line: String) -> AttributedString {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("#") {
            var comment = AttributedString(line)
            comment.foregroundColor = Theme.text3
            return comment
        }

        // `key:` — everything up to the first colon that isn't inside a value.
        // A leading "- " is a sequence marker and belongs with the indent.
        guard let colon = line.firstIndex(of: ":") else {
            var plain = AttributedString(line)
            plain.foregroundColor = Theme.text2
            return plain
        }

        let keyPart = String(line[line.startIndex...colon])
        let rest = String(line[line.index(after: colon)...])

        var key = AttributedString(keyPart)
        key.foregroundColor = Theme.accent

        var value = AttributedString(rest)
        // Quoted scalars read as data; everything else is ordinary text.
        value.foregroundColor = rest.contains("\"") ? Theme.warn : Theme.text2

        return key + value
    }
}
