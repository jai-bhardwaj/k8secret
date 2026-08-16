import SwiftUI

struct DeploymentDetailView: View {
    @Environment(\.clusterAccent) private var accent
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @State private var showRestartAlert = false
    /// Text backing the editable replica count. Kept as a String so a partially
    /// typed value ("" or "1" on the way to "100") doesn't fight the stepper.
    @State private var replicaInput = ""
    @FocusState private var replicaFieldFocused: Bool
    /// The target already asked about, so the same edit isn't submitted twice.
    @State private var lastRequestedReplicas: Int?

    var body: some View {
        Group {
            if let dep = state.selectedDeployment {
                deploymentDetail(dep)
            } else {
                // Only prompt for a selection when one is possible. With an empty
                // list this sat beside "No Deployments" telling the user to choose
                // from nothing — two placeholders contradicting each other.
                if !state.deployments.isEmpty {
                    ContentUnavailableView {
                        Label("Select a Deployment", systemImage: "shippingbox")
                    } description: {
                        Text("Choose a deployment to view its details.")
                    }
                } else {
                    Color.clear
                }
            }
        }
    }

    enum DetailTab: String, CaseIterable { case overview = "Overview", events = "Events", yaml = "YAML" }

    @ViewBuilder
    private func deploymentDetail(_ dep: K8sDeployment) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                DetailBreadcrumb(type: "deployments")
                headerSection(dep)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            // The rollout banner stays above the tabs: an in-flight write is
            // never allowed to hide behind a tab the user isn't on. A rollout
            // the cluster is doing on its own gets the passive variant.
            if state.showsRolloutBanner {
                rolloutBanner
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            } else if dep.status == .updating {
                passiveRolloutBanner(dep)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            }

            UnderlineTabBar(
                tabs: DetailTab.allCases.map { ($0, $0.rawValue) },
                selection: Binding(get: { state.deploymentDetailTab }, set: { state.deploymentDetailTab = $0 })
            )
            .padding(.top, 6)

            switch state.deploymentDetailTab {
            case .overview:
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        statTiles(dep)
                        scaleSection(dep)
                        specSection(dep)
                        podsSection(dep)
                        labelsBlock(dep)
                    }
                    .padding(24)
                }
            case .events:
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        eventsBlock
                    }
                    .padding(24)
                }
            case .yaml:
                ResourceYAMLView(type: .deployments, namespace: dep.namespace, name: dep.name)
            }
        }
        .onDisappear {
            state.stopRolloutPolling()
        }
        .navigationTitle(dep.name)
                .alert("Restart Deployment", isPresented: $showRestartAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Restart") {
                Task { await state.restartDeployment(dep) }
            }
        } message: {
            Text("This will perform a rolling restart of \(dep.name). All pods will be recreated.")
        }
    }


    @ViewBuilder
    private func labelsBlock(_ dep: K8sDeployment) -> some View {
        if !dep.labels.isEmpty {
            Divider()
            labelsSection(dep.labels)
        }
    }

    @ViewBuilder
    private var eventsBlock: some View {
        if !state.events.isEmpty {
            Divider()
            eventsSection
        }
    }

    /// A rollout the cluster is doing on its own — same banner, nothing to
    /// dismiss, because the app isn't holding a poll open for it.
    private func passiveRolloutBanner(_ dep: K8sDeployment) -> some View {
        RolloutBanner(name: dep.name, ready: dep.readyReplicas, total: dep.replicas)
    }

    /// A rollout this window started: the same banner, with a way to stop
    /// watching if the cluster stalls.
    @ViewBuilder
    private var rolloutBanner: some View {
        if let dep = state.selectedDeployment {
            RolloutBanner(name: dep.name,
                          ready: dep.readyReplicas,
                          total: dep.replicas) {
                state.stopRolloutPolling()
            }
        }
    }

    // MARK: - Sections

    private func headerSection(_ dep: K8sDeployment) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                headerInfo(dep)
                Spacer(minLength: 12)
                headerActions(dep)
            }
            VStack(alignment: .leading, spacing: 10) {
                headerInfo(dep)
                HStack(spacing: 8) { headerActions(dep) }
            }
        }
    }

    private func headerInfo(_ dep: K8sDeployment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(dep.name)
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .kerning(-0.25)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 12) {
                statusBadge(dep)
            }
        }
    }

    @ViewBuilder
    private func headerActions(_ dep: K8sDeployment) -> some View {
        Button {
            Task { await state.refreshCurrentResource() }
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
        }
        .buttonStyle(Theme.SoftPill())
        .help("Refresh")
        Button("Restart") { showRestartAlert = true }
            .buttonStyle(Theme.SoftPill())
            .help("Rolling restart — recreates every pod")
        if dep.replicas > 0 {
            Button("Stop") { state.requestScale(dep, to: 0) }
                .buttonStyle(Theme.DangerPill())
                .disabled(state.scaling)
                .help("Scale to 0 — stops every pod for this deployment")
        }
        liveTailButton(dep)
    }

    private func liveTailButton(_ dep: K8sDeployment) -> some View {
        Button {
            let matchingPods = state.pods.filter { $0.name.hasPrefix(dep.name) }
            if matchingPods.isEmpty {
                Task {
                    guard let ns = state.selectedNamespace else { return }
                    let allPods = (try? await K8sClient().listPodsAfterConnect(
                        context: state.context, namespace: ns.name)) ?? []
                    let depPods = allPods.filter { $0.name.hasPrefix(dep.name) }
                    if depPods.isEmpty {
                        state.showToast("No pods found for \(dep.name)", isError: true)
                        return
                    }
                    let podNames = depPods.map(\.name).joined(separator: ",")
                    openWindow(id: "log-stream", value: LogStreamID(
                        context: state.context, namespace: dep.namespace,
                        pod: podNames, container: ""
                    ))
                }
            } else {
                let podNames = matchingPods.map(\.name).joined(separator: ",")
                openWindow(id: "log-stream", value: LogStreamID(
                    context: state.context, namespace: dep.namespace,
                    pod: podNames, container: ""
                ))
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "text.line.last.and.arrowtriangle.forward")
                    .font(.system(size: 12))
                Text("Live Tail")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(accent.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(accent)
    }

    private func statusBadge(_ dep: K8sDeployment) -> some View {
        let info = statusInfo(dep)
        return HStack(spacing: 4) {
            Circle().fill(info.1).frame(width: 6, height: 6)
            Text(info.0)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(info.1)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(info.1.opacity(0.12), in: Capsule())
    }

    private func statTiles(_ dep: K8sDeployment) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
            StatCard(label: "Ready", value: "\(dep.readyReplicas)", suffix: " / \(dep.replicas)",
                     valueColor: dep.readyReplicas < dep.replicas ? Theme.warn : nil)
            let agg = state.aggregateMetrics(of: dep)
            StatCard(label: "CPU", value: agg?.cpu ?? "—", mono: true, valueColor: agg == nil ? nil : Theme.cpu)
            StatCard(label: "Memory", value: agg?.mem ?? "—", mono: true, valueColor: agg == nil ? nil : Theme.memory)
            StatCard(label: "Age", value: dep.age, mono: true)
        }
    }

    private func scaleSection(_ dep: K8sDeployment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("Replicas")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.text)

                // One control, not three: the prototype's stepper is a single
                // capsule with the count living between its two buttons.
                HStack(spacing: 0) {
                    stepButton("minus", enabled: displayedReplicas(dep) > 0 && !state.scaling) {
                        replicaInput = String(max(0, displayedReplicas(dep) - 1))
                    }

                    ZStack {
                        TextField("", text: $replicaInput)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.center)
                            .font(.system(size: 13.5, weight: .bold, design: .monospaced))
                            .frame(width: 56, height: 30)
                            // Focus lights the field itself rather than ringing
                            // it — a ring inside the capsule reads as a second
                            // control.
                            .background(replicaFieldFocused ? Theme.soft(accent) : Color.clear)
                            .focused($replicaFieldFocused)
                            .disabled(state.scaling)
                            .opacity(state.scaling ? 0.25 : 1)
                            .onSubmit { commitReplicaInput(dep) }
                            .accessibilityLabel("Replica count")
                            .help("Type a replica count, then Apply")
                        if state.scaling {
                            ProgressView().controlSize(.small)
                        }
                    }
                    .motion(Motion.stateChange, value: state.scaling)
                    .onAppear { replicaInput = String(dep.replicas) }
                    .onChange(of: dep.replicas) { _, newValue in
                        if !replicaFieldFocused { replicaInput = String(newValue) }
                        if newValue == lastRequestedReplicas { lastRequestedReplicas = nil }
                    }

                    stepButton("plus", enabled: !state.scaling) {
                        replicaInput = String(displayedReplicas(dep) + 1)
                    }
                }
                .background(Theme.inset)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.lineStrong, lineWidth: 1)
                )

                Button("Apply") { commitReplicaInput(dep) }
                    .buttonStyle(Theme.PrimaryPill())
                    .disabled(state.scaling || displayedReplicas(dep) == dep.replicas)
                    .keyboardShortcut(.defaultAction)

                Spacer(minLength: 0)
            }

            Text("Steppers count from the number shown, never a stale cluster read. Jumps of ±5 or more, and any scale to zero, confirm first. Ceiling \(Self.maxReplicas).")
                .font(.system(size: 11))
                .foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text2)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(symbol == "minus" ? "One fewer replica" : "One more replica")
    }

    /// Apply a typed replica count, or put the field back if it isn't usable.
    /// The count the user is currently looking at: what's typed if it parses,
    /// otherwise what the cluster reports.
    private func displayedReplicas(_ dep: K8sDeployment) -> Int {
        Int(replicaInput.trimmingCharacters(in: .whitespaces)) ?? dep.replicas
    }

    private func commitReplicaInput(_ dep: K8sDeployment) {
        let trimmed = replicaInput.trimmingCharacters(in: .whitespaces)

        // Reject anything that isn't a plain non-negative integer rather than
        // guessing — this scales a live workload.
        guard let target = Int(trimmed), target >= 0, trimmed.allSatisfy(\.isNumber) else {
            replicaInput = String(dep.replicas)
            state.showToast("Replicas must be a whole number, 0 or more.", isError: true)
            return
        }
        guard target != dep.replicas else {
            lastRequestedReplicas = nil
            return
        }
        // Return and the resulting focus change both land here for a single edit.
        // Requesting the same target twice produced two confirmation dialogs.
        guard target != lastRequestedReplicas else { return }
        guard target <= Self.maxReplicas else {
            replicaInput = String(dep.replicas)
            state.showToast("\(target) replicas is beyond what this control will set (max \(Self.maxReplicas)).", isError: true)
            return
        }

        lastRequestedReplicas = target
        state.requestScale(dep, to: target)
    }

    /// A ceiling on what a typed value can request. A stray keystroke turning 2
    /// into 2000 would try to schedule two thousand pods.
    private static let maxReplicas = 500

    /// The prototype's SPEC block: quiet label/value rows, conditions as
    /// pills — a failing condition speaks its message on a line below.
    private func specSection(_ dep: K8sDeployment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SPEC")
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(Theme.text3)
                .padding(.bottom, 4)
            ForEach(Array(dep.images.enumerated()), id: \.offset) { i, image in
                KVDetailRow(label: i == 0 ? "Image" : "", value: image)
            }
            KVDetailRow(label: "Strategy", value: dep.strategy.isEmpty ? "—" : dep.strategy)
            KVDetailRow(label: "Selector",
                        value: dep.labels["app"].map { "app=\($0)" } ?? "—")
            KVDetailRow(label: "Requests / Limits", value: state.requestsSummary(of: dep) ?? "—")
            if !dep.conditions.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Conditions")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text2)
                        .frame(width: 130, alignment: .leading)
                    HStack(spacing: 6) {
                        ForEach(dep.conditions, id: \.self) { cond in
                            StatusPill(text: cond.type,
                                       color: cond.status == "True" ? Theme.ok : Theme.bad)
                                .help(cond.reason.isEmpty ? cond.type : cond.reason)
                        }
                    }
                }
                .padding(.vertical, 3)
                ForEach(dep.conditions.filter { $0.status != "True" && !$0.message.isEmpty }, id: \.self) { cond in
                    Text("\(cond.type): \(cond.message)")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Theme.bad)
                        .padding(.leading, 142)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The prototype's PODS table: this deployment's pods with a jump link.
    @ViewBuilder
    private func podsSection(_ dep: K8sDeployment) -> some View {
        let pods = state.pods(of: dep)
        if !pods.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("PODS")
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(Theme.text3)
                    .padding(.bottom, 4)
                HStack(spacing: 12) {
                    Text("NAME").frame(maxWidth: .infinity, alignment: .leading)
                    Text("READY").frame(width: 54, alignment: .leading)
                    Text("RESTARTS").frame(width: 72, alignment: .leading)
                    Spacer().frame(width: 56)
                }
                .font(.system(size: 9.5, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(Theme.text3)
                ForEach(pods) { pod in
                    HStack(spacing: 12) {
                        Text(pod.name)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(pod.ready)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.text2)
                            .frame(width: 54, alignment: .leading)
                        Text("\(pod.restarts)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(pod.restarts > 5 ? Theme.bad : Theme.text2)
                            .frame(width: 72, alignment: .leading)
                        Button("Open") {
                            Task {
                                await state.selectDestination(.resource(.pods))
                                state.selectedPod = pod
                                await state.selectPod(pod)
                            }
                        }
                        .buttonStyle(Theme.SoftPill())
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private func statusColor(_ dep: K8sDeployment) -> Color {
        switch dep.status {
        case .running: return .green
        case .updating: return .orange
        case .scaled: return .blue
        case .degraded: return .red
        }
    }

    private func statusInfo(_ dep: K8sDeployment) -> (String, Color) {
        switch dep.status {
        case .running: return ("Running", .green)
        case .updating: return ("Updating", .orange)
        case .scaled: return ("Scaled to 0", .blue)
        case .degraded: return ("Degraded", .red)
        }
    }
}

// MARK: - Shared components

func labelsSection(_ labels: [String: String]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Label("Labels", systemImage: "tag")
            .font(.system(size: 13, weight: .semibold, design: .monospaced))

        FlowLayout(spacing: 6) {
            ForEach(labels.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                HStack(spacing: 4) {
                    Text(key)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("=")
                        .foregroundStyle(.tertiary)
                    Text(value)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.system(size: 11, design: .monospaced))
                .frame(maxWidth: 280)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

var eventsSection: some View {
    EventsSectionView()
}

struct EventsSectionView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Events (\(state.events.count))", systemImage: "list.bullet.rectangle")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))

            ForEach(state.events) { event in
                eventRow(event)
            }
        }
    }

    private func eventRow(_ event: K8sEvent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: event.type == "Warning" ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(event.type == "Warning" ? .orange : .blue)
                .font(.system(size: 12))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(event.reason)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                    if event.count > 1 {
                        Text(verbatim: "×\(event.count)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.orange)
                    }
                }
                Text(event.message)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Spacer()

            if let last = event.lastSeen {
                Text(formatAge(last))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(8)
        .background(
            (event.type == "Warning" ? Color.orange : Color.blue).opacity(0.04),
            in: RoundedRectangle(cornerRadius: 6)
        )
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
