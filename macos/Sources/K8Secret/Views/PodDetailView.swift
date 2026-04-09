import SwiftUI

struct PodDetailView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @State private var selectedLogContainer: String?
    @State private var showDeleteAlert = false

    var body: some View {
        Group {
            if let pod = state.selectedPod {
                podDetail(pod)
            } else {
                ContentUnavailableView {
                    Label("Select a Pod", systemImage: "circle.hexagongrid")
                } description: {
                    Text("Choose a pod to view its details and logs.")
                }
            }
        }
    }

    @ViewBuilder
    private func podDetail(_ pod: K8sPod) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection(pod)

                // Metrics cards
                if let m = state.metrics(for: pod.name) {
                    metricsSection(m)
                }

                Divider()
                infoSection(pod)
                Divider()
                containersSection(pod)
                Divider()
                logsSection(pod)
                labelsBlock(pod)
                eventsBlock
            }
            .padding(24)
        }
        .navigationTitle(pod.name)
        .toolbar { podToolbar(pod) }
        .alert("Delete Pod", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await state.deletePod(pod) }
            }
        } message: {
            Text("Delete pod \(pod.name)? If managed by a controller, a new pod will be created.")
        }
    }

    @ToolbarContentBuilder
    private func podToolbar(_ pod: K8sPod) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                showDeleteAlert = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .foregroundStyle(.red)
            }
            .help("Delete pod")

            Button {
                Task { await state.refreshCurrentResource() }
            } label: {
                Label("Refresh", systemImage: "arrow.triangle.2.circlepath")
            }

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
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(phaseColor(pod).opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(phaseColor(pod))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(pod.name)
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                    .lineLimit(1)

                HStack(spacing: 12) {
                    phaseBadge(pod)

                    Label(pod.ready + " ready", systemImage: "checkmark.circle")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)

                    if pod.restarts > 0 {
                        Label("\(pod.restarts) restarts", systemImage: "arrow.clockwise")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(pod.restarts > 5 ? .red : .orange)
                    }

                    Label(pod.age, systemImage: "clock")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private func phaseBadge(_ pod: K8sPod) -> some View {
        let color = phaseColor(pod)
        return HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(pod.phase)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }

    private func infoSection(_ pod: K8sPod) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Info", systemImage: "info.circle")
                .font(.system(.headline, design: .monospaced, weight: .semibold))

            LazyVGrid(columns: [
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading),
            ], spacing: 10) {
                infoRow("Node", pod.nodeName.isEmpty ? "—" : pod.nodeName)
                infoRow("Pod IP", pod.podIP.isEmpty ? "—" : pod.podIP)
                infoRow("Host IP", pod.hostIP.isEmpty ? "—" : pod.hostIP)
                infoRow("Owner", pod.ownerKind.isEmpty ? "—" : "\(pod.ownerKind)/\(pod.ownerName)")
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(.caption, design: .monospaced, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
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
                Text(container.image)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                containerStateBadge(container)
                if container.restarts > 0 {
                    Text("\(container.restarts) restarts")
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
        HStack {
            Label("Logs", systemImage: "text.alignleft")
                .font(.system(.headline, design: .monospaced, weight: .semibold))

            Spacer()

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

            Button {
                Task {
                    await state.loadPodLogs(container: selectedLogContainer ?? pod.containers.first?.name)
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
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.green)

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

    private func metricsSection(_ m: PodMetrics) -> some View {
        let pod = state.selectedPod!

        return VStack(alignment: .leading, spacing: 12) {
            // Metric cards
            HStack(spacing: 16) {
                metricCard(
                    icon: "cpu", label: "CPU", value: m.totalCPU,
                    pctR: m.cpuPercent(pod: pod),
                    pctL: m.cpuLimitPercent(pod: pod),
                    color: .blue
                )
                metricCard(
                    icon: "memorychip", label: "Memory", value: m.totalMemory,
                    pctR: m.memPercent(pod: pod),
                    pctL: m.memLimitPercent(pod: pod),
                    color: .purple
                )
            }

            // Per-container resource breakdown
            let hasResources = pod.containers.contains { !$0.cpuRequest.isEmpty || !$0.cpuLimit.isEmpty || !$0.memRequest.isEmpty || !$0.memLimit.isEmpty }
            if hasResources || m.containers.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Resources", systemImage: "gauge.with.dots.needle.bottom.50percent")
                        .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                        .foregroundStyle(.secondary)

                    ForEach(pod.containers, id: \.self) { c in
                        let cm = m.containers.first(where: { $0.name == c.name })
                        containerResourceCard(container: c, metrics: cm)
                    }
                }
            }
        }
    }

    private func containerResourceCard(container: ContainerInfo, metrics: ContainerMetrics?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(container.name)
                .font(.system(.caption, design: .monospaced, weight: .semibold))

            HStack(spacing: 16) {
                // CPU column
                VStack(alignment: .leading, spacing: 3) {
                    Text("CPU")
                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                        .foregroundStyle(.blue.opacity(0.7))

                    if let cm = metrics {
                        HStack(spacing: 4) {
                            Text("Used")
                                .foregroundStyle(.tertiary)
                                .frame(width: 40, alignment: .leading)
                            Text(formatCPUReadable(cm.cpu))
                                .foregroundStyle(.blue)
                        }
                    }
                    if !container.cpuRequest.isEmpty {
                        HStack(spacing: 4) {
                            Text("Req")
                                .foregroundStyle(.tertiary)
                                .frame(width: 40, alignment: .leading)
                            Text(container.cpuRequest)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !container.cpuLimit.isEmpty {
                        HStack(spacing: 4) {
                            Text("Lim")
                                .foregroundStyle(.tertiary)
                                .frame(width: 40, alignment: .leading)
                            Text(container.cpuLimit)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.system(.caption, design: .monospaced))

                Divider().frame(height: 40)

                // Memory column
                VStack(alignment: .leading, spacing: 3) {
                    Text("Memory")
                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                        .foregroundStyle(.purple.opacity(0.7))

                    if let cm = metrics {
                        HStack(spacing: 4) {
                            Text("Used")
                                .foregroundStyle(.tertiary)
                                .frame(width: 40, alignment: .leading)
                            Text(formatMemReadable(cm.memory))
                                .foregroundStyle(.purple)
                        }
                    }
                    if !container.memRequest.isEmpty {
                        HStack(spacing: 4) {
                            Text("Req")
                                .foregroundStyle(.tertiary)
                                .frame(width: 40, alignment: .leading)
                            Text(container.memRequest)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !container.memLimit.isEmpty {
                        HStack(spacing: 4) {
                            Text("Lim")
                                .foregroundStyle(.tertiary)
                                .frame(width: 40, alignment: .leading)
                            Text(container.memLimit)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.system(.caption, design: .monospaced))

                Spacer()
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }

    private func formatCPUReadable(_ cpu: String) -> String {
        if cpu.hasSuffix("n") {
            let n = Int(cpu.dropLast()) ?? 0
            let m = n / 1_000_000
            if m == 0 { return "<1m" }
            return "\(m)m"
        }
        if cpu.hasSuffix("u") {
            let u = Int(cpu.dropLast()) ?? 0
            return "\(u / 1000)m"
        }
        return cpu
    }

    private func formatMemReadable(_ mem: String) -> String {
        if mem.hasSuffix("Ki") {
            let ki = Int(mem.dropLast(2)) ?? 0
            if ki >= 1024 * 1024 { return String(format: "%.1fGi", Double(ki) / 1024 / 1024) }
            if ki >= 1024 { return String(format: "%.0fMi", Double(ki) / 1024) }
            return "\(ki)Ki"
        }
        return mem
    }

    private func metricCard(icon: String, label: String, value: String, pctR: Int?, pctL: Int?, color: Color) -> some View {
        let displayPct = pctL ?? pctR  // prefer limit for the ring
        return HStack(spacing: 10) {
            // Circular progress ring
            ZStack {
                Circle()
                    .stroke(color.opacity(0.15), lineWidth: 4)
                    .frame(width: 40, height: 40)
                if let p = displayPct {
                    Circle()
                        .trim(from: 0, to: min(CGFloat(p) / 100, 1.0))
                        .stroke(
                            p > 90 ? Color.red : p > 70 ? Color.orange : color,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 40, height: 40)
                        .rotationEffect(.degrees(-90))
                }
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.system(.title3, design: .monospaced, weight: .bold))
                    .foregroundStyle(color)

                HStack(spacing: 8) {
                    if let r = pctR {
                        HStack(spacing: 2) {
                            Text("\(r)%")
                                .foregroundStyle(r > 90 ? .red : r > 70 ? .orange : .green)
                            Text("req")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    if let l = pctL {
                        HStack(spacing: 2) {
                            Text("\(l)%")
                                .foregroundStyle(l > 90 ? .red : l > 70 ? .orange : .green)
                            Text("lim")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    if pctR == nil && pctL == nil {
                        Text("no limits set")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.system(.caption2, design: .monospaced, weight: .medium))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(color.opacity(0.12), lineWidth: 0.5))
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
