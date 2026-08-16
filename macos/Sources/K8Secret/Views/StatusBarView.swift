import SwiftUI

// Predefined theme colors for status bar
enum StatusBarTheme: String, CaseIterable, Identifiable {
    case `default` = "Default"
    case blue = "Blue"
    case purple = "Purple"
    case red = "Red"
    case orange = "Orange"
    case green = "Green"
    case teal = "Teal"
    case pink = "Pink"
    case yellow = "Yellow"
    case indigo = "Indigo"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .default: return .primary
        case .blue: return .blue
        case .purple: return .purple
        case .red: return .red
        case .orange: return .orange
        case .green: return .green
        case .teal: return .teal
        case .pink: return .pink
        case .yellow: return .yellow
        case .indigo: return .indigo
        }
    }

    var barTint: Color {
        switch self {
        case .default: return .clear
        default: return color.opacity(0.08)
        }
    }

    /// Persist theme for a given context name
    static func save(_ theme: StatusBarTheme, for context: String) {
        UserDefaults.standard.set(theme.rawValue, forKey: "K8Secret.theme.\(context)")
    }

    /// Load saved theme for a given context name
    static func load(for context: String) -> StatusBarTheme {
        guard let raw = UserDefaults.standard.string(forKey: "K8Secret.theme.\(context)"),
              let theme = StatusBarTheme(rawValue: raw) else { return .default }
        return theme
    }
}

struct StatusBarView: View {
    @Environment(AppState.self) private var state
    @State private var theme: StatusBarTheme = .default

    private var accentColor: Color {
        theme == .default ? .secondary : theme.color
    }

    var body: some View {
        HStack(spacing: 0) {
            leftSection

            Spacer(minLength: 4)

            rightSection
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        // vNext: the status bar sits directly on the canvas — no material,
        // no opaque bar. The optional per-context barTint stays as a wash.
        .background(theme.barTint)
        .overlay(alignment: .top) {
            // The cluster tint's second anchor (the context dot is the first):
            // a 2px edge in the color chosen for this context in Settings, so
            // "am I in prod?" is answerable from the bottom of the window too.
            Rectangle()
                .fill(state.clusterTint == .mint ? AnyShapeStyle(.separator) : AnyShapeStyle(state.clusterTint.color))
                .frame(height: state.clusterTint == .mint ? 1 : 2)
        }
        .onAppear { loadTheme() }
        .onChange(of: state.context) { _, _ in loadTheme() }
    }

    private func loadTheme() {
        guard !state.context.isEmpty else { return }
        theme = StatusBarTheme.load(for: state.context)
    }

    // MARK: - Left

    @State private var hoveringCluster = false

    private var leftSection: some View {
        HStack(spacing: 12) {
            // The prototype leads with what matters live: connection, then the
            // watch, then freshness. App version moves to the right edge.
            // The connection segment is the cluster switcher (the VS Code
            // status-bar pattern): click it and the picker rises from here.
            Button {
                state.clusterSwitcherOpen.toggle()
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(state.connectionState == .connected ? Theme.ok : Theme.bad)
                        .frame(width: 6, height: 6)
                    Text(state.connectionState == .connected ? "Connected · \(state.context)" : "Not connected")
                        .foregroundStyle(hoveringCluster ? Theme.text : Theme.text2)
                    Image(systemName: "chevron.up")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(Theme.text3)
                        .opacity(hoveringCluster ? 1 : 0)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(hoveringCluster ? Theme.inset : Color.clear, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hoveringCluster = $0 }
            .help("Switch cluster context")
            .font(.system(size: 11))

            statusDivider

            Text(state.liveUpdatesInterrupted ? "watch: retrying" : "watch: live")
                .font(.system(size: 11))
                .foregroundStyle(state.liveUpdatesInterrupted ? Theme.warn : Color.secondary)

            if let updated = state.lastUpdated {
                statusDivider
                Text("refreshed \(formatAge(updated)) ago")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            if !state.k8sVersion.isEmpty {
                statusDivider
                Text("K8s \(state.k8sVersion)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Right

    private var rightSection: some View {
        // The design's right edge: forwards, then version. Cluster CPU/MEM
        // moved to Overview's stat cards where capacity questions belong; the
        // legacy status-bar theme picker is superseded by cluster tints.
        HStack(spacing: 12) {
            portForwardsMenu

            statusDivider

            Text("v\(AppConstants.version)")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
    }

    // MARK: - Connection info (no pill)

    private var connectionInfo: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connectionColor)
                .frame(width: 7, height: 7)
                .shadow(color: connectionColor.opacity(0.6), radius: 3)

            Text(connectionLabel)
                .font(.system(.caption2, design: .monospaced, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            // Whether what is on screen is actually current.
            //
            // "Connected" only describes the last request that succeeded, so a
            // window could sit on minutes-old rows behind a green dot with no way
            // to tell. This says when data last arrived, and calls out a stream
            // that has stopped delivering.
            if case .connected = state.connectionState {
                if state.liveUpdatesInterrupted {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 8))
                        Text("reconnecting")
                            .font(.system(.caption2, design: .monospaced))
                    }
                    .foregroundStyle(.orange)
                    .help("Live updates were interrupted and are being retried. Values may be out of date.")
                    .accessibilityLabel("Live updates interrupted, reconnecting")
                } else if let stamp = state.lastUpdated {
                    Text(freshness(since: stamp))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .help("How long ago this view last received data")
                        .accessibilityLabel("Last updated \(freshness(since: stamp))")
                }
            }
        }
    }

    /// Re-rendered by the same updates that move `lastUpdated`, so it stays roughly
    /// honest without a timer of its own.
    private func freshness(since stamp: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(stamp))
        switch seconds {
        case ..<5:   return "live"
        case ..<60:  return "\(seconds)s ago"
        case ..<3600: return "\(seconds / 60)m ago"
        default:     return "\(seconds / 3600)h ago"
        }
    }

    private var connectionColor: Color {
        switch state.connectionState {
        case .connected: return theme == .default ? .green : theme.color
        case .connecting: return .orange
        case .disconnected: return .red
        }
    }

    private var connectionLabel: String {
        switch state.connectionState {
        case .connected:
            return state.context.isEmpty ? "Connected" : state.context
        case .connecting:
            return "Connecting…"
        case .disconnected:
            return "Disconnected"
        }
    }

    // MARK: - Theme menu

    private var themeMenu: some View {
        Menu {
            ForEach(StatusBarTheme.allCases) { t in
                Button {
                    theme = t
                    if !state.context.isEmpty {
                        StatusBarTheme.save(t, for: state.context)
                    }
                } label: {
                    HStack {
                        Circle()
                            .fill(t == .default ? Color.gray : t.color)
                            .frame(width: 8, height: 8)
                        Text(t.rawValue)
                        if t == theme {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "paintpalette")
                .font(.system(size: 10))
                .foregroundStyle(theme == .default ? .secondary : theme.color)
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    // MARK: - Port forwards menu

    @ViewBuilder
    private var portForwardsMenu: some View {
        let mgr = PortForwardManager.shared
        let activeCount = mgr.forwards.filter { $0.status == .active || $0.status == .reconnecting }.count

        if !mgr.forwards.isEmpty {
            statusDivider

            Menu {
                ForEach(mgr.forwards) { fwd in
                    Section(fwd.displayName) {
                        if fwd.status == .active {
                            Button {
                                mgr.openInBrowser(fwd.localURL)
                            } label: {
                                Label("Open localhost:\(fwd.localPort)", systemImage: "safari")
                            }
                        }
                        if fwd.status == .failed, let err = fwd.error {
                            Text(err)
                        }
                        Button(role: .destructive) {
                            mgr.stop(id: fwd.id)
                        } label: {
                            Label("Stop", systemImage: "xmark.circle")
                        }
                    }
                }

                Divider()

                Button(role: .destructive) {
                    mgr.stopAll()
                } label: {
                    Label("Stop All", systemImage: "xmark.circle.fill")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.horizontal.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                    Text(verbatim: "\(activeCount)")
                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                        .foregroundStyle(.green)
                }
            }
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        }
    }

    // MARK: - Mini gauge

    private func miniGauge(label: String, percent: Int, detail: String?) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(.caption2, design: .monospaced, weight: .bold))
                .foregroundStyle(.secondary)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.quaternary)
                    .frame(width: 40, height: 4)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(gaugeColor(percent))
                    .frame(width: 40 * CGFloat(min(percent, 100)) / 100, height: 4)
            }

            Text(verbatim: "\(percent)%")
                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                .foregroundStyle(gaugeColor(percent))
                .frame(width: 28, alignment: .trailing)
        }
        .help(detail ?? "\(label): \(percent)%")
    }

    private func gaugeColor(_ percent: Int) -> Color {
        if percent > 85 { return .red }
        if percent > 65 { return .orange }
        return .green
    }

    // MARK: - Helpers

    private func statusItem(icon: String, sfSymbol: Bool = true, text: String) -> some View {
        HStack(spacing: 4) {
            if sfSymbol {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                Text("⎈")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Text(text)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var statusDivider: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: 1, height: 12)
    }

    private func shortenUser(_ user: String) -> String {
        if user.count > 20 { return String(user.prefix(18)) + "…" }
        return user
    }
}
