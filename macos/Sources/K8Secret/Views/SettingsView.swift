import SwiftUI
import AppKit

/// App settings — deliberately small. Cluster color is a safety feature
/// dressed as personalization: the tint marks *which cluster this window is*
/// (context dot + status bar edge), so amber-for-staging and rose-for-prod
/// become glanceable habits. Appearance follows macOS unless chosen.
struct SettingsView: View {
    @Environment(AppState.self) private var state
    @AppStorage("appearanceOverride") private var appearanceOverride = "system"
    @State private var showFeedback = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.text)

            // Cluster color — paints the whole canvas.
            VStack(alignment: .leading, spacing: 6) {
                Text("Cluster color — \(state.context)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Paints this whole window's canvas — rose for prod means prod is unmistakable from across the room. Saved per context.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    ForEach(Theme.ClusterTint.allCases) { tint in
                        Button {
                            withAnimation(Theme.easeOut) { state.setClusterTint(tint) }
                        } label: {
                            Circle()
                                .fill(tint.color)
                                .frame(width: 26, height: 26)
                                .overlay {
                                    if state.clusterTint == tint {
                                        Circle().strokeBorder(.white, lineWidth: 2.5)
                                            .shadow(color: .black.opacity(0.3), radius: 2)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .help(tint.label)
                        .accessibilityLabel("\(tint.label)\(state.clusterTint == tint ? ", selected" : "")")
                    }
                }
                .padding(.top, 4)
            }

            Divider().overlay(Color.white.opacity(0.14))

            // Appearance
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Appearance")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("Follows macOS unless you choose.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.text2)
                }
                Spacer()
                Theme.SegmentedPills(
                    options: [("light", "Light"), ("system", "System"), ("dark", "Dark")],
                    selection: $appearanceOverride)
                    .frame(width: 220)
                    .onChange(of: appearanceOverride) { _, newValue in
                        Self.apply(appearanceOverride: newValue)
                    }
            }

            Divider().overlay(Color.white.opacity(0.14))

            // Feedback
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Feedback")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("Opens a prefilled GitHub issue — bugs, ideas, anything.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.text2)
                }
                Spacer()
                Button("Send feedback…") { showFeedback = true }
                    .buttonStyle(Theme.SoftPill())
            }

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Guide")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("Five stops over the real window — the rail, scope, search, secrets and clusters.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Show me around") {
                    state.settingsOpen = false
                    state.tourStep = 0
                }
                .buttonStyle(Theme.SoftPill())
            }

            HStack {
                Spacer()
                Button("Done") { state.settingsOpen = false }
                    .buttonStyle(Theme.PrimaryPill())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 460)
        .popGlass(radius: 22)
        .sheet(isPresented: $showFeedback) { FeedbackSheet() }
    }

    /// Applied at launch too, from K8SecretApp.
    ///
    /// `NSApplication.shared`, never the `NSApp` global: this runs inside
    /// `App.init()`, before AppKit has populated `NSApp`, and the global is an
    /// implicitly-unwrapped optional — using it there crashed the app on
    /// launch before the first frame.
    static func apply(appearanceOverride: String) {
        let app = NSApplication.shared
        switch appearanceOverride {
        case "light": app.appearance = NSAppearance(named: .aqua)
        case "dark": app.appearance = NSAppearance(named: .darkAqua)
        default: app.appearance = nil
        }
    }
}

/// Feedback goes to GitHub issues — no backend, no account of ours, and the
/// diagnostics disclosure is explicit about what is included and, for a
/// secrets manager more importantly, what never is.
struct FeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var state
    @State private var message = ""
    @State private var includeDiagnostics = true

    private var diagnostics: String {
        """
        ---
        K8Secret \(AppConstants.version) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        contexts: \(state.availableContexts.count) · k8s: \(state.k8sVersion.isEmpty ? "n/a" : state.k8sVersion)
        """
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Send feedback").font(.headline)
            Text("What's broken, confusing, or missing? This opens a GitHub issue with your text prefilled.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $message)
                .font(.body)
                .frame(minHeight: 110)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))

            Toggle(isOn: $includeDiagnostics) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Include diagnostics")
                    Text("App version, macOS version, context count. Never secret values, kubeconfig contents, or cluster names.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Open GitHub issue") { send() }
                    .buttonStyle(Theme.PrimaryPill())
                    .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 460)
        .background(Theme.CanvasBackground(tint: state.clusterTint, hero: false))
    }

    private func send() {
        var body = message
        if includeDiagnostics { body += "\n\n" + diagnostics }
        var components = URLComponents(string: "https://github.com/jai-bhardwaj/k8secret/issues/new")!
        components.queryItems = [URLQueryItem(name: "body", value: body)]
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
        dismiss()
    }
}
