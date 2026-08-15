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
        Form {
            Section {
                LabeledContent("Cluster color — \(state.context)") {
                    HStack(spacing: 8) {
                        ForEach(Theme.ClusterTint.allCases) { tint in
                            Button {
                                state.setClusterTint(tint)
                            } label: {
                                Circle()
                                    .fill(tint.color)
                                    .frame(width: 22, height: 22)
                                    .overlay {
                                        if state.clusterTint == tint {
                                            Circle().strokeBorder(.primary, lineWidth: 2)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .help(tint.label)
                            .accessibilityLabel("\(tint.label)\(state.clusterTint == tint ? ", selected" : "")")
                        }
                    }
                }
                Text("Tints this window's context dot and status bar edge, so a glance tells you which cluster you're in. Saved per context.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Appearance", selection: $appearanceOverride) {
                    Text("Light").tag("light")
                    Text("System").tag("system")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                .onChange(of: appearanceOverride) { _, newValue in
                    Self.apply(appearanceOverride: newValue)
                }
            }

            Section {
                LabeledContent("Feedback") {
                    Button("Send feedback…") { showFeedback = true }
                }
                Text("Opens a prefilled GitHub issue — bugs, ideas, anything.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
            .background(.bar)
        }
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
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 460)
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
