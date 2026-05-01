import SwiftUI

struct ServiceDetailView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Group {
            if let svc = state.selectedService {
                detailContent(svc)
            } else {
                ContentUnavailableView {
                    Label("Select a Service", systemImage: "network")
                } description: {
                    Text("Choose a service to view its details.")
                }
            }
        }
    }

    private func detailContent(_ svc: K8sService) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection(svc)

                Divider()

                // Network info
                networkSection(svc)

                // Ports
                if !svc.ports.isEmpty {
                    Divider()
                    portsSection(svc)
                }

                // Selector
                if !svc.selector.isEmpty {
                    Divider()
                    selectorSection(svc)
                }

                // Labels
                if !svc.labels.isEmpty {
                    Divider()
                    labelsSection(svc.labels)
                }

                // Events
                if !state.events.isEmpty {
                    Divider()
                    eventsSection
                }
            }
            .padding(24)
        }
        .navigationTitle(svc.name)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await state.refreshCurrentResource() }
                } label: {
                    Label("Refresh", systemImage: "arrow.triangle.2.circlepath")
                }

            }
        }
    }

    private func headerSection(_ svc: K8sService) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(typeColor(svc).opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: typeIcon(svc))
                    .font(.system(size: 20))
                    .foregroundStyle(typeColor(svc))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(svc.name)
                    .font(.system(.title2, design: .monospaced, weight: .bold))

                HStack(spacing: 12) {
                    // Type badge
                    HStack(spacing: 4) {
                        Circle().fill(typeColor(svc)).frame(width: 6, height: 6)
                        Text(svc.type)
                            .font(.system(.caption, design: .monospaced, weight: .semibold))
                    }
                    .foregroundStyle(typeColor(svc))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(typeColor(svc).opacity(0.12), in: Capsule())

                    Label("\(svc.ports.count) port\(svc.ports.count == 1 ? "" : "s")", systemImage: "arrow.left.arrow.right")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Label(svc.age, systemImage: "clock")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Port forward button — forward the first port
            if let firstPort = svc.ports.first {
                portForwardButton(svc, port: firstPort)
            }
        }
    }

    private func portForwardButton(_ svc: K8sService, port: ServicePort) -> some View {
        let mgr = PortForwardManager.shared
        let activeForward = mgr.forwards.first(where: {
            $0.target == "svc/\(svc.name)" && $0.remotePort == port.port && ($0.status == .active || $0.status == .reconnecting)
        })

        return Group {
            if let fwd = activeForward {
                HStack(spacing: 8) {
                    Button {
                        mgr.openInBrowser(fwd.localURL)
                    } label: {
                        HStack(spacing: 5) {
                            Circle().fill(.green).frame(width: 6, height: 6)
                            Text("localhost:\(fwd.localPort)")
                                .font(.system(.caption, design: .monospaced, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.green.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.green)

                    Button {
                        mgr.stop(id: fwd.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button {
                    mgr.forwardService(
                        context: state.context,
                        namespace: svc.namespace,
                        serviceName: svc.name,
                        remotePort: port.port
                    )
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "network.badge.shield.half.filled")
                            .font(.system(size: 12))
                        Text("Port Forward")
                            .font(.system(.caption, design: .monospaced, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.blue.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }
        }
    }

    private func networkSection(_ svc: K8sService) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Network", systemImage: "network")
                .font(.system(.headline, design: .monospaced, weight: .semibold))

            LazyVGrid(columns: [
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading),
            ], spacing: 10) {
                networkInfoRow("Cluster IP", svc.clusterIP, copyable: true)

                if !svc.externalIPs.isEmpty {
                    networkInfoRow("External", svc.externalIPs.joined(separator: ", "), copyable: true)
                } else if svc.type == "LoadBalancer" {
                    networkInfoRow("External", "Pending...", copyable: false)
                }
            }
        }
    }

    private func networkInfoRow(_ label: String, _ value: String, copyable: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
            }

            Spacer()

            if copyable && value != "None" {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                    state.showToast("Copied")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
    }

    private func portsSection(_ svc: K8sService) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Ports", systemImage: "arrow.left.arrow.right")
                .font(.system(.headline, design: .monospaced, weight: .semibold))

            ForEach(svc.ports, id: \.self) { port in
                HStack(spacing: 16) {
                    if !port.name.isEmpty {
                        Text(port.name)
                            .font(.system(.callout, design: .monospaced, weight: .medium))
                            .frame(minWidth: 80, alignment: .leading)
                    }

                    HStack(spacing: 6) {
                        portChip("\(port.port)", color: .blue, label: "Port")
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        portChip(port.targetPort, color: .green, label: "Target")

                        if let np = port.nodePort {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                            portChip("\(np)", color: .orange, label: "Node")
                        }
                    }

                    Spacer()

                    // Per-port forward button
                    portForwardMiniButton(svc, port: port)

                    Text(port.protocol_)
                        .font(.system(.caption, design: .monospaced, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
                .padding(10)
                .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func portChip(_ value: String, color: Color, label: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(.callout, design: .monospaced, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    private func portForwardMiniButton(_ svc: K8sService, port: ServicePort) -> some View {
        let mgr = PortForwardManager.shared
        let active = mgr.forwards.first(where: {
            $0.target == "svc/\(svc.name)" && $0.remotePort == port.port && ($0.status == .active || $0.status == .reconnecting)
        })

        return Group {
            if let fwd = active {
                Button {
                    mgr.openInBrowser(fwd.localURL)
                } label: {
                    HStack(spacing: 4) {
                        Circle().fill(.green).frame(width: 5, height: 5)
                        Text(":\(fwd.localPort)")
                            .font(.system(.caption2, design: .monospaced, weight: .semibold))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(.green)
            } else {
                Button {
                    mgr.forwardService(
                        context: state.context,
                        namespace: svc.namespace,
                        serviceName: svc.name,
                        remotePort: port.port
                    )
                } label: {
                    Image(systemName: "bolt.horizontal")
                        .font(.system(size: 10))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Port forward \(port.port)")
            }
        }
    }

    private func selectorSection(_ svc: K8sService) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Selector", systemImage: "line.3.horizontal.decrease.circle")
                .font(.system(.headline, design: .monospaced, weight: .semibold))

            FlowLayout(spacing: 6) {
                ForEach(svc.selector.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    HStack(spacing: 4) {
                        Text(key)
                            .foregroundStyle(.blue)
                        Text("=")
                            .foregroundStyle(.tertiary)
                        Text(value)
                            .foregroundStyle(.primary)
                    }
                    .font(.system(.caption, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    private func typeColor(_ svc: K8sService) -> Color {
        switch svc.type.lowercased() {
        case "loadbalancer": return .purple
        case "nodeport": return .orange
        case "clusterip": return .blue
        default: return .secondary
        }
    }

    private func typeIcon(_ svc: K8sService) -> String {
        switch svc.type.lowercased() {
        case "loadbalancer": return "globe"
        case "nodeport": return "arrow.up.forward.app"
        case "clusterip": return "network"
        default: return "network"
        }
    }
}
