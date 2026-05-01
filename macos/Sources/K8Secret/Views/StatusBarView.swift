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
        .background(theme.barTint)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
        .onAppear { loadTheme() }
        .onChange(of: state.context) { _, _ in loadTheme() }
    }

    private func loadTheme() {
        guard !state.context.isEmpty else { return }
        theme = StatusBarTheme.load(for: state.context)
    }

    // MARK: - Left

    private var leftSection: some View {
        HStack(spacing: 12) {
            statusItem(icon: "app.badge", text: "\(AppConstants.appName) v\(AppConstants.version)")

            statusDivider

            if !state.k8sVersion.isEmpty {
                statusItem(icon: "helm", sfSymbol: false, text: "K8s \(state.k8sVersion)")
            }

            if !state.clusterUser.isEmpty {
                statusDivider
                statusItem(icon: "person.fill", text: shortenUser(state.clusterUser))
            }
        }
    }

    // MARK: - Right

    private var rightSection: some View {
        HStack(spacing: 12) {
            if !state.namespaces.isEmpty {
                statusItem(
                    icon: "folder.fill",
                    text: "\(state.namespaces.count) namespaces"
                )
                statusDivider
            }

            if state.clusterCPUPercent > 0 || state.clusterMemPercent > 0 {
                miniGauge(
                    label: "CPU",
                    percent: state.clusterCPUPercent,
                    detail: state.clusterCPUUsed.isEmpty ? nil : "\(state.clusterCPUUsed)/\(state.clusterCPUTotal)"
                )

                miniGauge(
                    label: "MEM",
                    percent: state.clusterMemPercent,
                    detail: state.clusterMemUsed.isEmpty ? nil : "\(state.clusterMemUsed)/\(state.clusterMemTotal)"
                )

                statusDivider
            }

            // Active port forwards
            portForwardsMenu

            // Connection status — plain, no pill
            connectionInfo

            statusDivider

            // Theme picker
            themeMenu
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
                    Text("\(activeCount)")
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

            Text("\(percent)%")
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
