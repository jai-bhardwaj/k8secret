import SwiftUI

/// The vNext sidebar: resource-first, grouped by what the user is doing.
///
/// Namespace is deliberately *not* here any more — it's a filter, not a place,
/// and lives in the toolbar scope control. What earns a sidebar slot is a
/// destination: Overview, the resource types, Events. Counts ride along per
/// scope so the sidebar doubles as a cluster summary.
struct SidebarView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var state = state

        VStack(spacing: 0) {
            contextSwitcher
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 6)

            List(selection: Binding(
                get: { state.selectedDestination },
                set: { dest in
                    guard let dest else { return }
                    Task { await state.selectDestination(dest) }
                }
            )) {
                ForEach(NavGroup.all) { group in
                    if let label = group.label {
                        Section(label) {
                            ForEach(group.items, id: \.self) { item in
                                navRow(item)
                            }
                        }
                    } else {
                        ForEach(group.items, id: \.self) { item in
                            navRow(item)
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            portForwardsFooter
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 216, max: 280)
        .navigationTitle("K8Secret")
    }

    private func navRow(_ destination: AppDestination) -> some View {
        HStack(spacing: 9) {
            Image(systemName: destination.icon)
                .font(.system(size: 13))
                .frame(width: 18)
                .foregroundStyle(state.selectedDestination == destination ? Theme.accent : Color.secondary)
            // The floor is load-bearing: this List proposes near-zero width to
            // its rows, and a flexible Text collapses to nothing — the sidebar
            // rendered as a column of anonymous icons. Same fix, same reason,
            // as the old namespace rows.
            Text(destination.title)
                .lineLimit(1)
                .frame(minWidth: 110, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            if let count = count(for: destination), count > 0 {
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(state.selectedDestination == destination ? Theme.accent : Color.secondary)
                    .monospacedDigit()
                    .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tag(destination)
        .accessibilityLabel(accessibilityText(for: destination))
    }

    /// Sidebar counts are the loaded arrays — they fill in as types are
    /// visited and refresh with the watch/poll, so they're never a lie, at
    /// most an ellipsis.
    private func count(for destination: AppDestination) -> Int? {
        guard case .resource(let t) = destination else { return nil }
        switch t {
        case .deployments: return state.deployments.count
        case .pods: return state.pods.count
        case .cronjobs: return state.cronJobs.count
        case .services: return state.services.count
        case .ingresses: return state.ingresses.count
        case .secrets: return state.secrets.count
        case .configmaps: return state.configMaps.count
        }
    }

    private func accessibilityText(for destination: AppDestination) -> String {
        if let c = count(for: destination), c > 0 {
            return "\(destination.title), \(c)"
        }
        return destination.title
    }

    /// The prototype's sidebar anchor: active forwards always visible, one
    /// click to stop — a background tunnel should never be out of sight.
    @ViewBuilder
    private var portForwardsFooter: some View {
        let mine = PortForwardManager.shared.forwards.filter { $0.context == state.context }
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            Text("PORT FORWARDS")
                .font(.system(size: 9.5, weight: .semibold))
                .kerning(0.7)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.top, 6)
            if mine.isEmpty {
                Text("None active")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            } else {
                ForEach(mine) { fwd in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(fwd.status == .active ? Theme.ok : Theme.warn)
                            .frame(width: 6, height: 6)
                        Text(":\(String(fwd.localPort)) → \(fwd.displayName)")
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            PortForwardManager.shared.stop(id: fwd.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .buttonStyle(.borderless)
                        .help("Stop forwarding \(fwd.displayName)")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 2)
                }
                Spacer().frame(height: 6)
            }
        }
    }

    private var contextSwitcher: some View {
        Menu {
            ForEach(state.availableContexts, id: \.self) { ctx in
                Button {
                    Task { await state.switchContext(ctx) }
                } label: {
                    HStack {
                        Text(ctx)
                        if ctx == state.context {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .disabled(ctx == state.context)
            }

            Divider()

            Menu("Open in New Window") {
                ForEach(state.availableContexts, id: \.self) { ctx in
                    Button {
                        openWindow(id: "cluster-ctx", value: ctx)
                    } label: {
                        Label(ctx, systemImage: "macwindow.badge.plus")
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(state.clusterTint.color)
                    .frame(width: 8, height: 8)
                Text(state.context)
                    .font(.system(.callout, design: .monospaced, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help("Kubeconfig context — the dot color is this cluster's tint from Settings")
    }
}
