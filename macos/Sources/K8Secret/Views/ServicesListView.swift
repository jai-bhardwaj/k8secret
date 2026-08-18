import SwiftUI

struct ServicesListView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        Group {
            if state.selectedNamespace == nil && !state.allNamespaces {
                ContentUnavailableView {
                    Label("Select a Namespace", systemImage: "sidebar.left")
                } description: {
                    Text("Choose a namespace to view its services.")
                }
            } else if state.loadingServices && state.services.isEmpty {
                // Only take over the view when there is nothing to show yet.
                // Refreshing content that is already on screen stays in place; the
                // spinner used to replace the list on every refresh, losing scroll
                // position and flashing the rows.
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading services...")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                servicesList
            }
        }
        // A refresh over existing content shows here instead of replacing the
        // list, so the rows stay put and the work is still visible.
        .overlay(alignment: .topTrailing) {
            if state.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .padding(8)
                    .transition(.opacity)
                    .accessibilityLabel("Refreshing")
            }
        }
        .motion(Motion.stateChange, value: state.isRefreshing)
        // A list of names, ages and status pills needs real width. Without a
        // floor this column collapsed next to the detail pane and truncated
        // its own empty-state title to "No Deploy…".
        .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 560)
    }

    private var servicesList: some View {
        @Bindable var state = state

        return VStack(spacing: 0) {
        PaneHeader(
            title: "Services",
            subtitle: "\(state.services.count) \(state.allNamespaces ? "across all namespaces" : "in " + (state.selectedNamespace?.name ?? "—"))")
        FilterField(prompt: "Filter services…", text: $state.serviceSearch)
        ListColumnHeader(columns: [("Name", nil), ("Cluster IP", 92), ("Ports", 62)])
        List(state.filteredServices) { svc in
            ServiceRow(service: svc)
                .vnextRow(isSelected: state.selectedService?.id == svc.id)
                .onTapGesture { state.selectedService = svc }
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(Theme.line)
                .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
        }
        .vnextKeyboardSelection(items: state.filteredServices, selection: $state.selectedService)
        .overlay {
            if state.services.isEmpty {
                // An empty namespace is a dead end unless it says where to go
                // next. A fresh install lands on `default`, which on most
                // clusters holds nothing, so this was the first screen many
                // people saw.
                EmptyPane(icon: "network", title: "No Services",
                           message: "Nothing here in \(state.selectedNamespace?.name ?? "this namespace"). Pick another namespace from the menu above, or a different resource type in the sidebar.")
            } else if state.filteredServices.isEmpty {
                EmptyPane(icon: "magnifyingglass", title: "No matches",
                           message: "No results for “\(state.serviceSearch)”. The filter matches anywhere in the name.")
            }
        }
        .onChange(of: state.selectedService?.id) { _, _ in
            // Keyed on id, not the whole value. Polling and the watch stream
            // rewrite the selected object in place as its status changes, and
            // reacting to that as if the user had clicked a different row reran
            // selection — which clears the log pane and refetches events out from
            // under someone who is reading them.
            guard let svc = state.selectedService else { return }
            Task { await state.selectService(svc) }
        }
        }
        .vnextListPane()
    }
}
struct ServiceRow: View {
    let service: K8sService

    /// The prototype's `.row.c-svc`: name, cluster IP, ports — three columns
    /// under a header, rather than a card with an icon and a second line.
    var body: some View {
        HStack(spacing: 8) {
            Text(service.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(service.clusterIP == "None" ? "—" : service.clusterIP)
                .font(.system(size: 11, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(Theme.text2)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 92, alignment: .trailing)

            Text(service.ports.isEmpty ? "—" : service.ports.map { String($0.port) }.joined(separator: ", "))
                .font(.system(size: 11, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(Theme.text2)
                .lineLimit(1)
                .frame(width: 62, alignment: .trailing)
        }
    }


    private var serviceIcon: String {
        switch service.type.lowercased() {
        case "loadbalancer": return "globe"
        case "nodeport": return "arrow.up.forward.app"
        case "clusterip": return "network"
        case "externalname": return "link"
        default: return "network"
        }
    }

    private var typeBadge: some View {
        // "ClusterIP" was being hyphenated across two lines as "Clus-terIP".
        Text(service.type)
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(typeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(typeColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    private var typeColor: Color {
        switch service.type.lowercased() {
        case "loadbalancer": return Theme.memory
        case "nodeport": return Theme.warn
        case "clusterip": return Theme.cpu
        default: return .secondary
        }
    }
}
