import SwiftUI

struct PodDetailView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @State private var selectedLogContainer: String?
    @State private var logRange: LogRange = .last200
    @State private var showDeleteAlert = false

    var body: some View {
        Group {
            if let pod = state.selectedPod {
                podDetail(pod)
            } else {
                // Only prompt for a selection when one is possible. With an empty
                // list this sat beside "No Pods" telling the user to choose
                // from nothing — two placeholders contradicting each other.
                if !state.pods.isEmpty {
                    ContentUnavailableView {
                        Label("Select a Pod", systemImage: "circle.hexagongrid")
                    } description: {
                        Text("Choose a pod to view its details and logs.")
                    }
                } else {
                    Color.clear
                }
            }
        }
    }

    /// Tabs instead of one long scroll: Logs get the full pane height they
    /// deserve, and Events stop living below three screens of sections.
    enum DetailTab: String, CaseIterable { case overview = "Overview", logs = "Logs", events = "Events" }

    @ViewBuilder
    private func podDetail(_ pod: K8sPod) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                DetailBreadcrumb(type: "pods")
                headerSection(pod)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            UnderlineTabBar(
                tabs: DetailTab.allCases.map { ($0, $0.rawValue) },
                selection: Binding(get: { state.podDetailTab }, set: { state.podDetailTab = $0 })
            )
            .padding(.top, 6)

            switch state.podDetailTab {
            case .overview:
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if pod.isCrashLooping {
                            crashBanner(pod)
                        }
                        statTiles(pod)
                        infoSection(pod)
                        Divider()
                        containersSection(pod)
                        labelsBlock(pod)
                    }
                    .padding(24)
                }
            case .logs:
                // Full-height logs — the reason tabs exist.
                logsSection(pod)
                    .padding(16)
            case .events:
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        eventsBlock
                    }
                    .padding(24)
                }
            }
        }
        .navigationTitle(pod.name)
        .alert("Delete Pod", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await state.deletePod(pod) }
            }
        } message: {
            Text("Delete pod \(pod.name)? If managed by a controller, a new pod will be created.")
        }
    }


    @ViewBuilder
    private func labelsBlock(_ pod: K8sPod) -> some View {
        if !pod.labels.isEmpty {
            Divider()
            labelsSection(pod.labels)
        }
    }

    @ViewBuilder
    private var eventsBlock: some View {
        if !state.events.isEmpty {
            Divider()
            eventsSection
        }
    }

    // MARK: - Sections

    private func headerSection(_ pod: K8sPod) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                headerInfo(pod)
                Spacer(minLength: 12)
                headerActions(pod)
            }
            VStack(alignment: .leading, spacing: 10) {
                headerInfo(pod)
                HStack(spacing: 8) { headerActions(pod) }
            }
        }
    }

    private func headerInfo(_ pod: K8sPod) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(pod.name)
                .font(.system(.title2, design: .monospaced, weight: .bold))
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 12) {
                phaseBadge(pod)

                Label(pod.ready + " ready", systemImage: "checkmark.circle")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize()

                if pod.restarts > 0 {
                    Label("\(pod.restarts) restarts", systemImage: "arrow.clockwise")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(pod.restarts > 5 ? .red : .orange)
                        .fixedSize()
                }

                Label(pod.age, systemImage: "clock")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
    }

    @ViewBuilder
    private func headerActions(_ pod: K8sPod) -> some View {
        // Actions live here, in the detail header — the prototype's
        // grammar. The titlebar belongs to scope and search alone.
        Button {
            Task { await state.refreshCurrentResource() }
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
        }
        .buttonStyle(Theme.SoftPill())
        .help("Refresh")
        Button("Delete") { showDeleteAlert = true }
            .buttonStyle(Theme.DangerPill())
            .help("Delete pod")
    }

    /// The prototype's red crash-loop banner: the diagnosis, above the fold.
    private func crashBanner(_ pod: K8sPod) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.octagon.fill")
                .foregroundStyle(Theme.bad)
            Text("Crash-looping — \(pod.restarts) restart\(pod.restarts == 1 ? "" : "s"). Kubernetes is backing off before the next attempt.")
                .font(.system(.callout, design: .monospaced, weight: .semibold))
                .foregroundStyle(Theme.bad)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
        .background(Theme.soft(Theme.bad), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.bad.opacity(0.45), lineWidth: 1))
    }

    private func phaseBadge(_ pod: K8sPod) -> some View {
        let color = pod.isCrashLooping ? Theme.bad : phaseColor(pod)
        return HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(pod.isCrashLooping ? "CrashLoop" : pod.phase)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }

    /// The prototype's stat-card row: the numbers that matter, big, first.
    private func statTiles(_ pod: K8sPod) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
            StatCard(label: "Ready", value: pod.ready, mono: true)
            StatCard(label: "Restarts", value: "\(pod.restarts)",
                     valueColor: pod.restarts > 5 ? Theme.bad : (pod.restarts > 0 ? Theme.warn : nil))
            let m = state.metrics(for: pod.name)
            StatCard(label: "CPU", value: m?.totalCPU ?? "—", mono: true, valueColor: m == nil ? nil : Theme.cpu)
            StatCard(label: "Memory", value: m?.totalMemory ?? "—", mono: true, valueColor: m == nil ? nil : Theme.memory)
        }
    }

    private func infoSection(_ pod: K8sPod) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PLACEMENT")
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(Theme.text3)
                .padding(.bottom, 4)
            KVDetailRow(label: "Node", value: pod.nodeName.isEmpty ? "—" : pod.nodeName)
            KVDetailRow(label: "Pod IP", value: pod.podIP.isEmpty ? "—" : pod.podIP)
            KVDetailRow(label: "Host IP", value: pod.hostIP.isEmpty ? "—" : pod.hostIP)
            KVDetailRow(label: "Controlled by", value: pod.ownerKind.isEmpty ? "—" : "\(pod.ownerKind)/\(pod.ownerName)")
            KVDetailRow(label: "Age", value: pod.age)
        }
    }

    private func containersSection(_ pod: K8sPod) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Containers (\(pod.containers.count))", systemImage: "square.stack.3d.down.right")
                .font(.system(.headline, design: .monospaced, weight: .semibold))

            ForEach(pod.containers, id: \.self) { container in
                containerRow(container)
            }
        }
    }

    private func isContainerHealthy(_ c: ContainerInfo) -> Bool {
        c.ready || (c.state == "terminated" && (c.stateReason == "Completed" || c.stateReason.isEmpty))
    }

    private func containerRow(_ container: ContainerInfo) -> some View {
        let healthy = isContainerHealthy(container)
        let completed = container.state == "terminated" && healthy
        return HStack(spacing: 12) {
            Image(systemName: healthy ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(completed ? .blue : healthy ? .green : .red)

            VStack(alignment: .leading, spacing: 3) {
                Text(container.name)
                    .font(.system(.callout, design: .monospaced, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(container.image)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                containerStateBadge(container)
                if container.restarts > 0 {
                    Text(verbatim: "\(container.restarts) restarts")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(container.restarts > 3 ? .red : .orange)
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
    }

    private func containerStateBadge(_ c: ContainerInfo) -> some View {
        let info = containerStateInfo(c)
        return Text(info.0)
            .font(.system(.caption2, design: .monospaced, weight: .medium))
            .foregroundStyle(info.1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(info.1.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    private func containerStateInfo(_ c: ContainerInfo) -> (String, Color) {
        switch c.state {
        case "running": return ("Running", .green)
        case "waiting": return (c.stateReason.isEmpty ? "Waiting" : c.stateReason, .yellow)
        case "terminated":
            let isSuccess = c.stateReason == "Completed" || c.stateReason.isEmpty
            return (isSuccess ? "Completed" : c.stateReason, isSuccess ? .blue : .red)
        default: return ("Unknown", .secondary)
        }
    }

    private func logsSection(_ pod: K8sPod) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            logsHeader(pod)
            logsContent
        }
    }

    private func logsHeader(_ pod: K8sPod) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                logsTitle(pod)
                Spacer(minLength: 8)
                logsActions(pod)
            }
            VStack(alignment: .leading, spacing: 8) {
                logsTitle(pod)
                HStack(spacing: 8) { logsActions(pod) }
            }
        }
    }

    /// The prototype's tail/since ranges.
    enum LogRange: String, CaseIterable {
        case last200 = "last 200", last1000 = "last 1000", since5m = "since 5m", since1h = "since 1h"
        var tail: Int { self == .last1000 ? 1000 : 200 }
        var since: Int? { self == .since5m ? 300 : (self == .since1h ? 3600 : nil) }
    }

    @ViewBuilder
    private func logsTitle(_ pod: K8sPod) -> some View {
        Label("Logs", systemImage: "text.alignleft")
            .font(.system(.headline, design: .monospaced, weight: .semibold))
        Picker("Range", selection: $logRange) {
            ForEach(LogRange.allCases, id: \.self) { r in
                Text(r.rawValue).tag(r)
            }
        }
        .frame(maxWidth: 120)
        .labelsHidden()
        if pod.containers.count > 1 {
            Picker("Container", selection: Binding(
                get: { selectedLogContainer ?? pod.containers.first?.name ?? "" },
                set: { selectedLogContainer = $0 }
            )) {
                ForEach(pod.containers, id: \.name) { c in
                    Text(c.name).tag(c.name)
                }
            }
            .frame(maxWidth: 200)
        }
    }

    @ViewBuilder
    private func logsActions(_ pod: K8sPod) -> some View {
        Button {
            Task {
                await state.loadPodLogs(container: selectedLogContainer ?? pod.containers.first?.name,
                                        tailLines: logRange.tail, sinceSeconds: logRange.since)
            }
        } label: {
            Label(state.podLogs.isEmpty ? "Load Logs" : "Refresh", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(state.loadingLogs)

        Button {
            let container = selectedLogContainer ?? pod.containers.first?.name ?? ""
            let logID = LogStreamID(
                context: state.context,
                namespace: pod.namespace,
                pod: pod.name,
                container: container
            )
            openWindow(id: "log-stream", value: logID)
        } label: {
            Label("Live Tail", systemImage: "play.circle")
        }
        .buttonStyle(Theme.PrimaryPill())
        .controlSize(.small)

        if !state.podLogs.isEmpty {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(state.podLogs, forType: .string)
                state.showToast("Logs copied")
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var logsContent: some View {
        if state.loadingLogs {
            HStack {
                ProgressView().controlSize(.small)
                Text("Loading logs...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
        } else if !state.podLogs.isEmpty {
            ScrollView(.vertical) {
                Text(state.podLogs)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxHeight: 400)
            .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.06), lineWidth: 0.5))
        } else {
            HStack {
                Image(systemName: "text.alignleft")
                    .foregroundStyle(.tertiary)
                Text("Click \"Load Logs\" to view container output")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func phaseColor(_ pod: K8sPod) -> Color {
        switch pod.phase.lowercased() {
        case "running": return pod.readyCount == pod.totalCount ? .green : .yellow
        case "succeeded": return .blue
        case "pending": return .yellow
        case "failed": return .red
        default: return .secondary
        }
    }
}
