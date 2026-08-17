import SwiftUI

struct StatusBarView: View {
    @Environment(AppState.self) private var state
    var body: some View {
        HStack(spacing: 0) {
            leftSection

            Spacer(minLength: 4)

            rightSection
        }
        .padding(.horizontal, 18)
        .frame(height: 32)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) {
            // The cluster tint's second anchor (the context dot is the first):
            // a 2px edge in the color chosen for this context in Settings, so
            // "am I in prod?" is answerable from the bottom of the window too.
            Rectangle()
                .fill(state.clusterTint == .ocean ? AnyShapeStyle(.separator) : AnyShapeStyle(state.clusterTint.color))
                .frame(height: state.clusterTint == .ocean ? 1 : 2)
        }
    }

    // MARK: - Left

    @State private var hoveringCluster = false

    private var leftSection: some View {
        // Drop-order under width pressure: freshness and K8s version go
        // first; connection and watch state always survive.
        ViewThatFits(in: .horizontal) {
            leftRow(full: true)
            leftRow(full: false)
        }
    }

    private func leftRow(full: Bool) -> some View {
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
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 240, alignment: .leading)
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
            .focusEffectDisabled()
            .onHover { hoveringCluster = $0 }
            .help("Switch cluster context")
            .font(.system(size: 11))

            statusDivider

            Text(state.liveUpdatesInterrupted ? "watch: retrying" : "watch: live")
                .font(.system(size: 11))
                .foregroundStyle(state.liveUpdatesInterrupted ? Theme.warn : Color.secondary)

            if full, let updated = state.lastUpdated {
                statusDivider
                Text("refreshed \(formatAge(updated)) ago")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            if full, !state.k8sVersion.isEmpty {
                statusDivider
                Text("K8s \(state.k8sVersion)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
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
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
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
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
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
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
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
                .font(.system(size: 10.5, design: .monospaced))
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
