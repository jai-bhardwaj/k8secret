import SwiftUI

struct ServicesListView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        Group {
            if state.selectedNamespace == nil {
                ContentUnavailableView {
                    Label("Select a Namespace", systemImage: "sidebar.left")
                } description: {
                    Text("Choose a namespace to view its services.")
                }
            } else if state.loadingServices {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading services...")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                servicesList
            }
        }
        .navigationTitle(state.selectedNamespace?.name ?? "Services")
    }

    private var servicesList: some View {
        @Bindable var state = state

        return List(state.filteredServices, selection: $state.selectedService) { svc in
            ServiceRow(service: svc)
                .tag(svc)
        }
        .searchable(text: $state.serviceSearch, prompt: "Filter services")
        .overlay {
            if state.services.isEmpty {
                ContentUnavailableView {
                    Label("No Services", systemImage: "network")
                } description: {
                    Text("This namespace has no services.")
                }
            } else if state.filteredServices.isEmpty {
                ContentUnavailableView.search(text: state.serviceSearch)
            }
        }
        .onChange(of: state.selectedService) { _, newValue in
            if let svc = newValue {
                Task { await state.selectService(svc) }
            }
        }
    }
}

struct ServiceRow: View {
    let service: K8sService

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: serviceIcon)
                .foregroundStyle(.tint)
                .font(.system(size: 16))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(service.name)
                    .font(.system(.body, design: .monospaced, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    // Cluster IP
                    if service.clusterIP != "None" {
                        Text(service.clusterIP)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    // Ports summary
                    if !service.ports.isEmpty {
                        Text(service.ports.map { "\($0.port)/\($0.protocol_)" }.joined(separator: ", "))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                typeBadge

                Text(service.age)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
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
        Text(service.type)
            .font(.system(.caption2, design: .monospaced, weight: .medium))
            .foregroundStyle(typeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(typeColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    private var typeColor: Color {
        switch service.type.lowercased() {
        case "loadbalancer": return .purple
        case "nodeport": return .orange
        case "clusterip": return .blue
        default: return .secondary
        }
    }
}
