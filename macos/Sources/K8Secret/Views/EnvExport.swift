import SwiftUI
import AppKit

/// Render key/value pairs as a `.env` file.
///
/// Quoting is the whole job: a value with spaces, quotes, `#`, `$`, or a
/// newline written bare would parse back as a different value — or as several
/// lines — so anything that could round-trip wrong is double-quoted with
/// backslash escapes. Everything else stays bare, which is what people expect
/// a .env to look like.
enum EnvExport {
    static func quote(_ value: String) -> String {
        let needsQuoting = value.isEmpty || value.contains(where: {
            $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "#" || $0 == "\"" ||
            $0 == "'" || $0 == "\\" || $0 == "$"
        })
        guard needsQuoting else { return value }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    static func render(_ pairs: [(String, String)]) -> String {
        pairs.map { "\($0.0)=\(quote($0.1))" }.joined(separator: "\n")
    }
}

/// The export sheet both Secrets and ConfigMaps use.
///
/// The preview shows plaintext deliberately: export is a single-purpose act the
/// user just asked for, and masking the thing they're about to copy would be
/// security theater. The warning does the real work instead.
struct EnvExportSheet: View {
    let title: String
    let pairs: [(String, String)]
    /// e.g. "includes 2 staged changes not yet saved" — nil when clean.
    let stagedNote: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var state

    private var rendered: String { EnvExport.render(pairs) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export \(title) as .env")
                .font(.system(size: 13, weight: .semibold))
            Text("\(pairs.count) keys\(stagedNote.map { " — \($0)" } ?? ""). This is plaintext: treat the result like the secrets themselves.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text("PREVIEW")
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(Theme.text3)

            ScrollView {
                Text(rendered)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(minHeight: 120, maxHeight: 260)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save to file…") { saveToFile() }
                Button("Copy to clipboard") { copyAll() }
                    .buttonStyle(Theme.PrimaryPill())
            }
        }
        .padding(20)
        .frame(minWidth: 460)
        .background(Theme.CanvasBackground(tint: state.clusterTint, hero: false))
    }

    private func copyAll() {
        // The same concealed clipboard single-key copies use: invisible to
        // clipboard managers, cleared after 30 seconds.
        SecretPasteboard.copySecret(rendered)
        dismiss()
        state.showToast("\(title).env copied — clipboard clears in 30 s")
    }

    private func saveToFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(title).env"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            // 0600: a plaintext env file should at least not be group-readable.
            try rendered.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: url.path)
            dismiss()
            state.showToast("Saved \(url.lastPathComponent) — plaintext on disk outlives the app's protections")
        } catch {
            state.showToast("Save failed: \(error.localizedDescription)", isError: true)
        }
    }
}
