import SwiftUI

/// The vNext sidebar, matching the prototype's anatomy exactly: custom rows
/// (not a native List) so selection is accent-soft, hover is the inset well,
/// section labels are uppercase micro-type, and the port-forwards footer is
/// anchored at the bottom. Namespace is deliberately absent — it's a filter,
/// and lives in the toolbar scope control.
struct SidebarView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(NavGroup.all) { group in
                        if let label = group.label {
                            Text(label.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .kerning(0.9)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 10)
                                .padding(.top, 10)
                                .padding(.bottom, 4)
                        }
                        ForEach(group.items, id: \.self) { item in
                            NavRowButton(
                                destination: item,
                                isSelected: state.selectedDestination == item,
                                count: count(for: item)
                            ) {
                                Task { await state.selectDestination(item) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }

            Spacer(minLength: 0)
            portForwardsFooter
        }
        .background(Theme.raised)
        .overlay(alignment: .trailing) { Theme.line.frame(width: 1) }
        .navigationSplitViewColumnWidth(min: 190, ideal: 216, max: 280)
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

    /// The prototype's sidebar anchor: active forwards always visible, one
    /// click to stop — a background tunnel should never be out of sight.
    @ViewBuilder
    private var portForwardsFooter: some View {
        let mine = PortForwardManager.shared.forwards.filter { $0.context == state.context }
        VStack(alignment: .leading, spacing: 4) {
            Divider().overlay(Theme.line)
            Text("PORT FORWARDS")
                .font(.system(size: 9.5, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            if mine.isEmpty {
                Text("None active")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            } else {
                ForEach(mine) { fwd in
                    PortForwardChip(forward: fwd)
                }
                Spacer().frame(height: 8)
            }
        }
    }

}

/// One sidebar destination, with the prototype's three states: rest, hover
/// (inset well), selected (accent-soft + accent icon + semibold).
private struct NavRowButton: View {
    let destination: AppDestination
    let isSelected: Bool
    let count: Int?
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: destination.icon)
                    .font(.system(size: 13))
                    .frame(width: 17)
                    .foregroundStyle(isSelected ? Theme.accent : Color.secondary)
                Text(destination.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? Theme.accent : Color.secondary)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6.5)
            .background(
                isSelected ? Theme.soft(Theme.accent) : (hovering ? Theme.inset : Color.clear),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .onAppear {
            // Debug-only: render the hover state on demand so pixel parity of
            // hover can be screenshot-verified without synthesized input.
            if ProcessInfo.processInfo.environment["K8SECRET_UITEST_HOVER"] == destination.title {
                hovering = true
            }
        }
        .motion(Motion.stateChange, value: hovering)
        .accessibilityLabel(count.map { "\(destination.title), \($0)" } ?? destination.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct PortForwardChip: View {
    let forward: PortForward
    @State private var hovering = false
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(forward.status == .active ? Theme.ok : Theme.warn)
                .frame(width: 6, height: 6)
                .opacity(pulse ? 0.35 : 1)
            Text(":\(String(forward.localPort)) → \(forward.displayName)")
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                PortForwardManager.shared.stop(id: forward.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(hovering ? Theme.bad : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help("Stop forwarding \(forward.displayName)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(hovering ? Theme.inset : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        .padding(.horizontal, 8)
        .onHover { hovering = $0 }
        .onAppear {
            guard forward.status == .active, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.0).repeatForever()) { pulse = true }
        }
    }
}
