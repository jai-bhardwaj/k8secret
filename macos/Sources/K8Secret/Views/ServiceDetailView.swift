import SwiftUI

struct ServiceDetailView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Group {
            if let svc = state.selectedService {
                detailContent(svc)
            } else {
                // Only prompt for a selection when one is possible. With an empty
                // list this sat beside "No Services" telling the user to choose
                // from nothing — two placeholders contradicting each other.
                if !state.services.isEmpty {
                    ContentUnavailableView {
                        Label("Select a Service", systemImage: "network")
                    } description: {
                        Text("Choose a service to view its details.")
                    }
                } else {
                    Color.clear
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
                    endpointsSection(svc)
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
    }

    private func headerSection(_ svc: K8sService) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                headerInfo(svc)
                Spacer(minLength: 12)
                headerActions(svc)
            }
            VStack(alignment: .leading, spacing: 10) {
                headerInfo(svc)
                HStack(spacing: 8) { headerActions(svc) }
            }
        }
    }

    private func headerInfo(_ svc: K8sService) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            DetailBreadcrumb(type: "services")
                .padding(.bottom, 2)
            Text(svc.name)
                .font(.system(.title2, design: .monospaced, weight: .bold))
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Circle().fill(typeColor(svc)).frame(width: 6, height: 6)
                    Text(svc.type)
                        .font(.system(.caption, design: .monospaced, weight: .semibold))
                }
                .foregroundStyle(typeColor(svc))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(typeColor(svc).opacity(0.12), in: Capsule())
                .fixedSize()

                Label("\(svc.ports.count) port\(svc.ports.count == 1 ? "" : "s")", systemImage: "arrow.left.arrow.right")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize()

                Label(svc.age, systemImage: "clock")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
    }

    @ViewBuilder
    private func headerActions(_ svc: K8sService) -> some View {
        Button {
            Task { await state.refreshCurrentResource() }
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
        }
        .buttonStyle(Theme.SoftPill())
        .help("Refresh")

        if let firstPort = svc.ports.first {
            portForwardButton(svc, port: firstPort)
        }
    }

    private func portForwardButton(_ svc: K8sService, port: ServicePort) -> some View {
        let mgr = PortForwardManager.shared
        // Scoped by cluster and namespace, and only treated as usable once active —
        // a reconnecting tunnel is not something to hand the user a link to.
        let existing = mgr.forward(
            context: state.context,
            namespace: svc.namespace,
            target: "svc/\(svc.name)",
            remotePort: port.port
        )
        let activeForward = existing?.status == .active ? existing : nil

        return Group {
            if let fwd = activeForward {
                HStack(spacing: 8) {
                    Button {
                        mgr.openInBrowser(fwd.localURL)
                    } label: {
                        HStack(spacing: 5) {
                            Circle().fill(.green).frame(width: 6, height: 6)
                            Text(verbatim: "localhost:\(fwd.localPort)")
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
            } else if existing?.status == .starting {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Starting port forward…")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Port forward starting")
            } else if existing?.status == .reconnecting {
                HStack(spacing: 6) {
                    Circle().fill(.orange).frame(width: 6, height: 6)
                    Text("Reconnecting…")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.orange)
                }
                .help(existing?.error ?? "The tunnel dropped and is being re-established.")
                .accessibilityLabel("Port forward reconnecting")
            } else if let failed = existing, failed.status == .failed {
                HStack(spacing: 8) {
                    Button {
                        mgr.stop(id: failed.id)
                        mgr.forwardService(
                            context: state.context,
                            namespace: svc.namespace,
                            serviceName: svc.name,
                            remotePort: port.port
                        )
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .bold))
                            Text("Retry port forward")
                                .font(.system(.caption, design: .monospaced, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.red.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Retry port forward")

                    if let reason = failed.error {
                        Text(reason)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
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
        // Scoped to this cluster and namespace — see PortForwardManager.forward.
        let existing = mgr.forward(
            context: state.context,
            namespace: svc.namespace,
            target: "svc/\(svc.name)",
            remotePort: port.port
        )

        // Every state the forward can be in is rendered. Previously only "active"
        // was, so clicking sat silently for a second or two with no sign anything
        // had happened, and a failure looked identical to never having tried.
        return Group {
            switch existing?.status {
            case .active:
                Button {
                    if let fwd = existing { mgr.openInBrowser(fwd.localURL) }
                } label: {
                    HStack(spacing: 4) {
                        Circle().fill(.green).frame(width: 5, height: 5)
                        Text(verbatim: ":\(existing?.localPort ?? 0)")
                            .font(.system(.caption2, design: .monospaced, weight: .semibold))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(.green)
                .help("Open http://localhost:\(existing?.localPort ?? 0)")
                .accessibilityLabel("Open forwarded port \(existing?.localPort ?? 0) in browser")

            case .starting:
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini).scaleEffect(0.6)
                    Text("starting")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Port forward starting")

            case .reconnecting:
                HStack(spacing: 4) {
                    Circle().fill(.orange).frame(width: 5, height: 5)
                    Text("reconnecting")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.orange)
                }
                .help(existing?.error ?? "The tunnel dropped and is being re-established.")
                .accessibilityLabel("Port forward reconnecting")

            case .failed:
                Button {
                    if let fwd = existing { mgr.stop(id: fwd.id) }
                    mgr.forwardService(
                        context: state.context,
                        namespace: svc.namespace,
                        serviceName: svc.name,
                        remotePort: port.port
                    )
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9))
                        Text("retry").font(.system(.caption2, design: .monospaced))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(.red)
                .help(existing?.error ?? "Port forward failed. Click to try again.")
                .accessibilityLabel("Port forward failed, retry")

            case .none:
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
                .help("Forward port \(port.port) to a local port and open it")
                .accessibilityLabel("Port forward port \(port.port)")
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

    /// The selector resolved to actual pods: "which pods back this service"
    /// is the question routing debugging always ends at. A selector matching
    /// nothing is said out loud — traffic to that service goes nowhere.
    private func endpointsSection(_ svc: K8sService) -> some View {
        let matching = state.pods.filter { pod in
            !svc.selector.isEmpty && svc.selector.allSatisfy { key, value in
                pod.labels[key] == value
            }
        }
        return VStack(alignment: .leading, spacing: 8) {
            Label("Endpoints", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.system(.headline, design: .monospaced, weight: .semibold))

            if matching.isEmpty {
                Text("No pods match this selector — traffic to this service goes nowhere.")
                    .font(.caption)
                    .foregroundStyle(Theme.warn)
            } else {
                VStack(spacing: 2) {
                    ForEach(matching) { pod in
                        Button {
                            jumpToPod(pod)
                        } label: {
                            HStack(spacing: 9) {
                                Circle()
                                    .fill(pod.phase == "Running" ? Theme.ok : Theme.bad)
                                    .frame(width: 7, height: 7)
                                Text(pod.name)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text(pod.podIP.isEmpty ? "—" : pod.podIP)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                Text(pod.ready)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(pod.readyCount == pod.totalCount ? Theme.ok : Theme.warn)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Open pod \(pod.name)")
                    }
                }
            }
        }
    }

    private func jumpToPod(_ pod: K8sPod) {
        Task {
            await state.selectResourceType(.pods)
            state.selectedPod = state.pods.first { $0.id == pod.id }
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
