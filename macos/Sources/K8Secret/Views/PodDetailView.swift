import SwiftUI

struct PodDetailView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @State private var selectedLogContainer: String?
    @State private var logFilter = ""
    @State private var followLogs = false
    @State private var logRange: LogRange = .last200

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
    enum DetailTab: String, CaseIterable { case overview = "Overview", logs = "Logs", events = "Events", yaml = "YAML" }

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
            case .yaml:
                ResourceYAMLView(type: .pods, namespace: pod.namespace, name: pod.name)
            }
        }
        .navigationTitle(pod.name)
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
                .font(.system(size: 14.5, weight: .bold, design: .monospaced))
                .kerning(-0.2)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 12) {
                phaseBadge(pod)

                Label(pod.ready + " ready", systemImage: "checkmark.circle")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize()

                if pod.restarts > 0 {
                    Label("\(pod.restarts) restarts", systemImage: "arrow.clockwise")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(pod.restarts > 5 ? Theme.bad : Theme.warn)
                        .fixedSize()
                }

                Label(pod.age, systemImage: "clock")
                    .font(.system(size: 11, design: .monospaced))
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
        Button("Delete") {
            state.confirm(
                title: "Delete \(pod.name)?",
                message: "If a controller owns this pod, Kubernetes will start a replacement immediately.",
                confirmLabel: "Delete"
            ) { await state.deletePod(pod) }
        }
            .buttonStyle(Theme.DangerPill())
            .help("Delete pod")
    }

    /// The prototype's red crash-loop banner: the diagnosis, above the fold.
    private func crashBanner(_ pod: K8sPod) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.octagon.fill")
                .foregroundStyle(Theme.bad)
            Text("Crash-looping — \(pod.restarts) restart\(pod.restarts == 1 ? "" : "s"). Kubernetes is backing off before the next attempt.")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
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
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
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
                .font(.system(size: 13, weight: .semibold, design: .monospaced))

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
                .foregroundStyle(completed ? Theme.cpu : healthy ? Theme.ok : Theme.bad)

            VStack(alignment: .leading, spacing: 3) {
                Text(container.name)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(container.image)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                containerStateBadge(container)
                if container.restarts > 0 {
                    Text(verbatim: "\(container.restarts) restarts")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(container.restarts > 3 ? Theme.bad : Theme.warn)
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
    }

    private func containerStateBadge(_ c: ContainerInfo) -> some View {
        let info = containerStateInfo(c)
        return Text(info.0)
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .foregroundStyle(info.1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(info.1.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    private func containerStateInfo(_ c: ContainerInfo) -> (String, Color) {
        switch c.state {
        case "running": return ("Running", Theme.ok)
        case "waiting": return (c.stateReason.isEmpty ? "Waiting" : c.stateReason, Theme.warn)
        case "terminated":
            let isSuccess = c.stateReason == "Completed" || c.stateReason.isEmpty
            return (isSuccess ? "Completed" : c.stateReason, isSuccess ? Theme.cpu : Theme.bad)
        default: return ("Unknown", .secondary)
        }
    }

    private func logsSection(_ pod: K8sPod) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            logsHeader(pod)
            logsContent
        }
        // The chosen container belongs to the pod it was chosen in. This view is
        // one instance for every pod, so without clearing it, picking "sidecar"
        // on one pod and then selecting a pod that has no such container asked
        // the API server for logs from a container that isn't there — an error
        // where the obvious behaviour is simply the new pod's first container.
        .onChange(of: pod.id) { _, _ in
            selectedLogContainer = nil
            logFilter = ""
        }
        // Logs load because the tab was opened. Asking the user to press "Load
        // Logs" first made the pane's whole purpose a second click, and the
        // prototype simply shows them.
        .task(id: logsRequestKey(pod)) {
            await state.loadPodLogs(container: selectedLogContainer ?? pod.containers.first?.name,
                                    tailLines: logRange.tail,
                                    sinceSeconds: logRange.since)
        }
        // Follow re-reads the tail. A crash-looping container is the case that
        // matters: its next attempt appears without anyone touching anything.
        .task(id: followLogs ? logsRequestKey(pod) + "|follow" : "") {
            guard followLogs else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                if Task.isCancelled { return }
                await state.loadPodLogs(container: selectedLogContainer ?? pod.containers.first?.name,
                                        tailLines: logRange.tail,
                                        sinceSeconds: logRange.since)
            }
        }
    }

    /// Everything that decides which lines we should be showing. When any of it
    /// changes the tail is re-read, and nothing else re-reads it.
    private func logsRequestKey(_ pod: K8sPod) -> String {
        [pod.namespace, pod.name,
         selectedLogContainer ?? pod.containers.first?.name ?? "",
         logRange.rawValue].joined(separator: "|")
    }

    /// The prototype's `.loghead`: container, range, a filter, and Follow —
    /// all in the app's own controls. Native pickers and bordered buttons wore
    /// system chrome in the middle of a canvas that has none.
    private func logsHeader(_ pod: K8sPod) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { logsControls(pod) }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) { logsPickers(pod) }
                HStack(spacing: 8) { logsFilterAndActions(pod) }
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
    private func logsControls(_ pod: K8sPod) -> some View {
        logsPickers(pod)
        logsFilterAndActions(pod)
    }

    @ViewBuilder
    private func logsPickers(_ pod: K8sPod) -> some View {
        if pod.containers.count > 1 {
            LogMenu(title: selectedLogContainer ?? pod.containers.first?.name ?? "container",
                    options: pod.containers.map(\.name)) { selectedLogContainer = $0 }
        }
        LogMenu(title: logRange.rawValue, options: LogRange.allCases.map(\.rawValue)) { picked in
            if let range = LogRange(rawValue: picked) { logRange = range }
        }
    }

    @ViewBuilder
    private func logsFilterAndActions(_ pod: K8sPod) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 10))
                .foregroundStyle(Theme.text3)
            TextField("Filter…", text: $logFilter)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .frame(width: 130)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Theme.inset, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.line, lineWidth: 1))

        Spacer(minLength: 4)

        // Follow: the prototype's switch. Re-reads the tail on a timer, so a
        // crash-looping container shows its next attempt without a click.
        Toggle("Follow", isOn: $followLogs)
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.text2)

        Button {
            let container = selectedLogContainer ?? pod.containers.first?.name ?? ""
            openWindow(id: "log-stream", value: LogStreamID(
                context: state.context, namespace: pod.namespace,
                pod: pod.name, container: container))
        } label: {
            Label("Live Tail", systemImage: "play.circle")
                .font(.system(size: 11.5, weight: .semibold))
        }
        .buttonStyle(Theme.SoftPill())

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(state.podLogs, forType: .string)
            state.showToast("Logs copied")
        } label: {
            Image(systemName: "doc.on.doc")
        }
        .buttonStyle(IconButtonStyle())
        .disabled(state.podLogs.isEmpty)
        .help("Copy all logs")
    }

    /// The prototype's `.logstream`: fills the pane, 11.5pt mono at a 1.75
    /// line-height, timestamps muted and errors in the bad hue.
    @ViewBuilder
    private var logsContent: some View {
        Group {
            if state.loadingLogs && state.podLogs.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading the container's output…")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.text3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredLogLines.isEmpty {
                Text(state.podLogs.isEmpty
                     ? "This container hasn't logged anything yet."
                     : "No lines match “\(logFilter)”.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.text3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(filteredLogLines.enumerated()), id: \.offset) { _, line in
                            Text(LogLine.attributed(line))
                                .font(.system(size: 11.5, design: .monospaced))
                                .lineSpacing(3)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.inset, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.line, lineWidth: 1))
    }

    private var filteredLogLines: [String] {
        // "(no logs available)" is the loader's stand-in for an empty read, not
        // something the container printed — showing it as a log line puts a
        // sentence in monospace where output belongs.
        guard state.podLogs != "(no logs available)" else { return [] }
        let lines = state.podLogs
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !logFilter.isEmpty else { return lines }
        return lines.filter { $0.localizedCaseInsensitiveContains(logFilter) }
    }

    private func phaseColor(_ pod: K8sPod) -> Color {
        switch pod.phase.lowercased() {
        case "running": return pod.readyCount == pod.totalCount ? Theme.ok : Theme.warn
        case "succeeded": return Theme.cpu
        case "pending": return Theme.warn
        case "failed": return Theme.bad
        default: return .secondary
        }
    }
}

/// A small menu in the app's own pill grammar.
///
/// SwiftUI's `Picker` renders as an AppKit popup button: grey system chrome,
/// system accent, system focus ring — three things this canvas has none of, in
/// the middle of a log toolbar.
struct LogMenu: View {
    let title: String
    let options: [String]
    let onPick: (String) -> Void

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(option) { onPick(option) }
            }
        } label: {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.text2)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.text3)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Theme.inset, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// Colouring for one log line, following the prototype: the leading timestamp
/// muted, a line that announces a failure in the bad hue, everything else
/// ordinary. Matching on the text is what a reader does at a glance, and it is
/// all that is available — container logs carry no severity metadata.
enum LogLine {
    private static let failureMarkers = ["error", "err ", "fatal", "panic", "exception",
                                         "failed", "failure", "cannot", "unable to"]

    static func attributed(_ line: String) -> AttributedString {
        var body = AttributedString(line)
        let lowered = line.lowercased()
        body.foregroundColor = failureMarkers.contains(where: lowered.contains)
            ? Theme.bad
            : Theme.text2

        // Split a leading ISO-ish timestamp off, if the line starts with one.
        guard let space = line.firstIndex(of: " ") else { return body }
        let head = String(line[line.startIndex..<space])
        guard head.count >= 8, head.first?.isNumber == true,
              head.contains(":") || head.contains("-") else { return body }

        var stamp = AttributedString(head)
        stamp.foregroundColor = Theme.text3
        var rest = AttributedString(String(line[space...]))
        rest.foregroundColor = body.foregroundColor
        return stamp + rest
    }
}
