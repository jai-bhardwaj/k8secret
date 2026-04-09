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
        .onChange(of: state.selectedNamespace) { _, newValue in
            if let ns = newValue {
                Task { await state.selectNamespace(ns) }
            }
        }
    }

}

struct NamespaceRow: View {
    let namespace: K8sNamespace

    var body: some View {
        HStack {
            Image(systemName: "folder.fill")
                .foregroundStyle(.tint)
                .font(.system(size: 14))

            Text(namespace.name)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)

            Spacer()

            Text(namespace.status)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(namespace.status == "Active" ? .green : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    (namespace.status == "Active" ? Color.green : Color.secondary)
                        .opacity(0.1),
                    in: Capsule()
                )
        }
        .padding(.vertical, 2)
    }
}
