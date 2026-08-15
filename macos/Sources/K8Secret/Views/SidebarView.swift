import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var state = state

        VStack(spacing: 0) {
            // Context switcher
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
                        .fill(.green)
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
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 4)

            // Resource type picker
            HStack(spacing: 2) {
                ForEach(ResourceType.allCases) { type in
                    Button {
                        Task { await state.selectResourceType(type) }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: type.icon)
                                .font(.system(size: 14))
                            Text(type.rawValue)
                                .font(.system(.caption2, design: .monospaced, weight: .medium))
                                // Four tabs in a narrow sidebar were breaking
                                // words across lines — "De-ploy s", "Se-cret s".
                                // Shrink slightly rather than hyphenate.
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                        .background(
                            state.selectedResourceType == type
                                ? Color.accentColor.opacity(0.15)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .foregroundStyle(state.selectedResourceType == type ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)

            Divider()

            List(state.filteredNamespaces, selection: $state.selectedNamespace) { ns in
                NamespaceRow(namespace: ns)
                    .tag(ns)
            }
            .searchable(text: $state.namespaceSearch, placement: .sidebar, prompt: "Filter namespaces")
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 340)
        .navigationTitle("Namespaces")
        .overlay {
            if state.namespaces.isEmpty && state.connectionState != .connecting {
                ContentUnavailableView {
                    Label("No Namespaces", systemImage: "folder")
                } description: {
                    Text("No namespaces found in this cluster.")
                }
            } else if state.filteredNamespaces.isEmpty && !state.namespaceSearch.isEmpty {
                ContentUnavailableView.search(text: state.namespaceSearch)
            }
        }
        .onChange(of: state.selectedNamespace?.id) { _, _ in
            // Keyed on id: a namespace list refresh rewrites these values, and
            // reacting to that as a new selection reloads everything underneath
            // the user.
            guard let ns = state.selectedNamespace else { return }
            Task { await state.selectNamespace(ns) }
        }
    }

}

struct NamespaceRow: View {
    let namespace: K8sNamespace

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.tint)
                .font(.system(size: 13))

            // The name is why the row exists, so it wins the available width.
            // Without the priority it was compressed to nothing by the status
            // pill, leaving a sidebar of anonymous folder icons.
            // The Text takes the remaining width directly. Leaving it to compete
            // with a Spacer let SwiftUI compress it to a single character, so the
            // sidebar rendered as a column of anonymous folder icons.
            // minWidth, not just maxWidth. This List sits inside a VStack in the
            // split-view sidebar and proposes a near-zero width to its rows, so a
            // flexible Text collapsed to "…" and the sidebar showed a column of
            // anonymous folder icons. A floor makes the name survive the proposal;
            // maxWidth then lets it use whatever real width exists.
            Text(namespace.name)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 90, maxWidth: .infinity, alignment: .leading)

            // "Active" is the state of virtually every namespace, so showing it
            // spent the row's width saying nothing. Only the exception is worth
            // the space.
            if namespace.status != "Active" {
                Text(namespace.status)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.12), in: Capsule())
                    .fixedSize()
                    .help("This namespace is \(namespace.status.lowercased())")
            }
        }
        // Claim the row's full width. Without this the HStack sizes to its
        // content's *ideal* width inside the sidebar List and the name gets
        // squeezed down to a single character.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(namespace.status == "Active"
            ? namespace.name
            : "\(namespace.name), \(namespace.status)")
    }
}
