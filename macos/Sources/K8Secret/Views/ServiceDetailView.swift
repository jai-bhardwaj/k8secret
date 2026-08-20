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

    enum DetailTab: String, CaseIterable { case overview = "Overview", yaml = "YAML" }
    @State private var tab = DetailTab.overview

    private func detailContent(_ svc: K8sService) -> some View {
        VStack(spacing: 0) {
            headerSection(svc)
                .padding(.horizontal, 24)
                .padding(.top, 16)

            UnderlineTabBar(tabs: DetailTab.allCases.map { ($0, $0.rawValue) },
                            selection: $tab)
                .padding(.top, 6)

            switch tab {
            case .yaml:
                ResourceYAMLView(type: .services, namespace: svc.namespace, name: svc.name)
            case .overview:
                ScrollView {
            VStack(alignment: .leading, spacing: 20) {

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
            }
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
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .kerning(-0.25)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Circle().fill(typeColor(svc)).frame(width: 6, height: 6)
                    Text(svc.type)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(typeColor(svc))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(typeColor(svc).opacity(0.12), in: Capsule())
                .fixedSize()

                Label("\(svc.ports.count) port\(svc.ports.count == 1 ? "" : "s")", systemImage: "arrow.left.arrow.right")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize()

                Label(svc.age, systemImage: "clock")
                    .font(.system(size: 11, design: .monospaced))
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

        return HStack(spacing: 10) {
            forwardControl(svc, port: port, existing: existing, activeForward: activeForward)
            PortForwardPathField(
                context: state.context,
                namespace: svc.namespace,
                target: "svc/\(svc.name)",
                remotePort: port.port
            )
        }
    }

    @ViewBuilder
    private func forwardControl(_ svc: K8sService, port: ServicePort,
                                existing: PortForward?, activeForward: PortForward?) -> some View {
        let mgr = PortForwardManager.shared
        Group {
            if let fwd = activeForward {
                HStack(spacing: 8) {
                    Button {
                        mgr.openInBrowser(fwd.localURL)
                    } label: {
                        HStack(spacing: 5) {
                            Circle().fill(Theme.ok).frame(width: 6, height: 6)
                            Text(verbatim: "localhost:\(fwd.localPort)\(PortForward.normalize(fwd.path))")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.ok.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.ok.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.ok)

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
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Port forward starting")
            } else if existing?.status == .reconnecting {
                HStack(spacing: 6) {
                    Circle().fill(Theme.warn).frame(width: 6, height: 6)
                    Text("Reconnecting…")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.warn)
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
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.bad.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.bad.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.bad)
                    .accessibilityLabel("Retry port forward")

                    if let reason = failed.error {
                        Text(reason)
                            .font(.system(size: 10.5, design: .monospaced))
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
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Theme.cpu.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.cpu.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.cpu)
            }
        }
    }

    private func networkSection(_ svc: K8sService) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Network", systemImage: "network")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))

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
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
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
                .font(.system(size: 13, weight: .semibold, design: .monospaced))

            ForEach(svc.ports, id: \.self) { port in
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        portIdentity(port)
                        Spacer()
                        portActions(svc, port)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        portIdentity(port)
                        HStack(spacing: 10) { portActions(svc, port) }
                    }
                }
                .padding(10)
                .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    @ViewBuilder
    private func portIdentity(_ port: ServicePort) -> some View {
        if !port.name.isEmpty {
            Text(port.name)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 80, maxWidth: 140, alignment: .leading)
        }
        HStack(spacing: 6) {
            portChip("\(port.port)", color: Theme.cpu, label: "Port")
            Image(systemName: "arrow.right")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            portChip(port.targetPort, color: Theme.ok, label: "Target")
            if let np = port.nodePort {
                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                portChip("\(np)", color: Theme.warn, label: "Node")
            }
        }
    }

    @ViewBuilder
    private func portActions(_ svc: K8sService, _ port: ServicePort) -> some View {
        portForwardMiniButton(svc, port: port)
        Text(port.protocol_)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    private func portChip(_ value: String, color: Color, label: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10.5, design: .monospaced))
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
                        Circle().fill(Theme.ok).frame(width: 5, height: 5)
                        Text(verbatim: ":\(existing?.localPort ?? 0)")
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(Theme.ok)
                .help("Open http://localhost:\(existing?.localPort ?? 0)")
                .accessibilityLabel("Open forwarded port \(existing?.localPort ?? 0) in browser")

            case .starting:
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini).scaleEffect(0.6)
                    Text("starting")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Port forward starting")

            case .reconnecting:
                HStack(spacing: 4) {
                    Circle().fill(Theme.warn).frame(width: 5, height: 5)
                    Text("reconnecting")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.warn)
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
                        Text("retry").font(.system(size: 10.5, design: .monospaced))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(Theme.bad)
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
                .font(.system(size: 13, weight: .semibold, design: .monospaced))

            FlowLayout(spacing: 6) {
                ForEach(svc.selector.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    HStack(spacing: 4) {
                        Text(key)
                            .foregroundStyle(Theme.cpu)
                        Text("=")
                            .foregroundStyle(.tertiary)
                        Text(value)
                            .foregroundStyle(.primary)
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.cpu.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
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
                .font(.system(size: 13, weight: .semibold, design: .monospaced))

            if matching.isEmpty {
                Text("No pods match this selector — traffic to this service goes nowhere.")
                    .font(.system(size: 11))
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
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text(pod.podIP.isEmpty ? "—" : pod.podIP)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(pod.ready)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .lineLimit(1)
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
        case "loadbalancer": return Theme.memory
        case "nodeport": return Theme.warn
        case "clusterip": return Theme.cpu
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

/// The landing path for a forwarded port, e.g. `/admin/queues`.
///
/// A forwarded port is rarely useful at its root — a dashboard lives under a
/// path, an API's docs under another — so opening the tunnel always landed on
/// `/` and left the user to retype the rest. This sets it once per service and
/// remembers it, so every later click on the forward goes straight there.
///
/// It commits on blur and on Return rather than per keystroke: writing a
/// half-typed path to defaults would mean "/adm" is what gets remembered if
/// attention moves elsewhere mid-word.
struct PortForwardPathField: View {
    let context: String
    let namespace: String
    let target: String
    let remotePort: Int

    @State private var text = ""
    @FocusState private var focused: Bool

    private var manager: PortForwardManager { .shared }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 9))
                .foregroundStyle(Theme.text3)
            TextField("/path", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 108)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { wasFocused, isFocused in
                    if wasFocused && !isFocused { commit() }
                }
                .accessibilityLabel("Path to open for this port forward")
                .help("Opened after the port, e.g. /admin/queues. Remembered for this service.")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Theme.inset, in: Capsule())
        .overlay(Capsule().strokeBorder(focused ? Theme.cpu.opacity(0.55) : Theme.line, lineWidth: 1))
        .task(id: "\(context)|\(namespace)|\(target)|\(remotePort)") {
            // Keyed on the target: selecting a different service must not leave
            // the previous one's path sitting in the field.
            text = manager.savedPath(context: context, namespace: namespace,
                                     target: target, remotePort: remotePort)
        }
    }

    private func commit() {
        manager.setPath(text, context: context, namespace: namespace,
                        target: target, remotePort: remotePort)
        // Show it back the way it will actually be used, so a typed "admin"
        // visibly becomes "/admin" rather than silently differing from the URL.
        let normalized = PortForward.normalize(text)
        text = normalized.isEmpty ? "" : normalized
    }
}
