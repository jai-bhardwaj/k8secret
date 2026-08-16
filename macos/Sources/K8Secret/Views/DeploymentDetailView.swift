import SwiftUI

struct DeploymentDetailView: View {
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

    enum DetailTab: String, CaseIterable { case overview = "Overview", events = "Events" }

    @ViewBuilder
    private func deploymentDetail(_ dep: K8sDeployment) -> some View {
        VStack(spacing: 0) {
            // The rollout banner stays above the tabs: an in-flight write is
            // never allowed to hide behind a tab the user isn't on.
            if state.showsRolloutBanner {
                rolloutBanner
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
                        headerSection(dep)
                        Divider()
                        scaleSection(dep)
                        Divider()
                        imagesSection(dep)
                        conditionsBlock(dep)
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
    private func conditionsBlock(_ dep: K8sDeployment) -> some View {
        if !dep.conditions.isEmpty {
            Divider()
            conditionsSection(dep)
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

    private var rolloutBanner: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                Text("Rollout in progress")
                    .font(.system(.callout, design: .monospaced, weight: .semibold))
                Text(state.rolloutProgress)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                state.stopRolloutPolling()
            } label: {
                Text("Dismiss")
                    .font(.system(.caption, design: .monospaced))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.blue.opacity(0.2), lineWidth: 1))
        .animation(.easeInOut, value: state.rolloutProgress)
    }

    // MARK: - Sections

    private func headerSection(_ dep: K8sDeployment) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(statusColor(dep).opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(statusColor(dep))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(dep.name)
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                HStack(spacing: 12) {
                    statusBadge(dep)
                    Label(dep.strategy, systemImage: "arrow.triangle.swap")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Label(dep.age, systemImage: "clock")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

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
            liveTailButton(dep)
        }
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

    private func statusBadge(_ dep: K8sDeployment) -> some View {
        let info = statusInfo(dep)
        return HStack(spacing: 4) {
            Circle().fill(info.1).frame(width: 6, height: 6)
            Text(info.0)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
        }
        .foregroundStyle(info.1)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(info.1.opacity(0.12), in: Capsule())
    }

    private func scaleSection(_ dep: K8sDeployment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Replicas", systemImage: "square.stack.3d.up.fill")
                .font(.system(.headline, design: .monospaced, weight: .semibold))

            HStack(spacing: 16) {
                HStack(spacing: 18) {
                    replicaStat("Desired", value: dep.replicas, color: .primary)
                    replicaStat("Ready", value: dep.readyReplicas, color: .green)
                    replicaStat("Updated", value: dep.updatedReplicas, color: .blue)
                    replicaStat("Available", value: dep.availableReplicas, color: .green)
                }

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    Button {
                        // Step from what is on screen, not from the last count the
                        // cluster reported. After setting 100 the field shows 100
                        // while the cluster still says 2, and stepping off the
                        // stale value took "minus one" from 2 to 1 — discarding
                        // the number the user was looking at.
                        let current = displayedReplicas(dep)
                        if current > 0 {
                            state.requestScale(dep, to: current - 1)
                        }
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.line, lineWidth: 1))
                    .accessibilityLabel("Scale down one replica")
                    .disabled(displayedReplicas(dep) <= 0 || state.scaling)

                    // Type the count directly. With only +/- available, going from
                    // 2 to 100 meant 98 clicks and 98 API calls, and there was no
                    // way to state a target at all.
                    ZStack {
                        TextField("", text: $replicaInput)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.center)
                            .font(.system(.title2, design: .monospaced, weight: .bold))
                            .frame(width: 56)
                            .padding(.vertical, 4)
                            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(replicaFieldFocused ? Color.accentColor : .clear, lineWidth: 1.5)
                            )
                            .focused($replicaFieldFocused)
                            .disabled(state.scaling)
                            .opacity(state.scaling ? 0.25 : 1)
                            .onSubmit { commitReplicaInput(dep) }
                            .onChange(of: replicaFieldFocused) { _, focused in
                                // Commit on blur as well, so clicking away doesn't
                                // discard what was typed — but pressing Return
                                // *also* moves focus to the confirmation dialog,
                                // so this fired straight after onSubmit and asked
                                // for the same scale a second time.
                                // commitReplicaInput is idempotent per target.
                                if !focused { commitReplicaInput(dep) }
                            }
                            .accessibilityLabel("Replica count")
                            .help("Type a replica count and press Return")

                        if state.scaling {
                            ProgressView().controlSize(.small)
                        }
                    }
                    .motion(Motion.stateChange, value: state.scaling)
                    // Track the cluster while the user isn't editing.
                    .onAppear { replicaInput = String(dep.replicas) }
                    .onChange(of: dep.replicas) { _, newValue in
                        if !replicaFieldFocused { replicaInput = String(newValue) }
                        // Scale landed: allow this target to be requested again later.
                        if newValue == lastRequestedReplicas { lastRequestedReplicas = nil }
                    }

                    Button {
                        state.requestScale(dep, to: displayedReplicas(dep) + 1)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.line, lineWidth: 1))
                    .accessibilityLabel("Scale up one replica")
                    .disabled(state.scaling)

                    // Taking a workload down is a thing people actually want to do,
                    // and clicking minus until it reaches zero is a poor way to
                    // express it. Confirms, like any scale to zero.
                    if dep.replicas > 0 {
                        Button {
                            replicaFieldFocused = false
                            state.requestScale(dep, to: 0)
                        } label: {
                            Text("Stop")
                                .font(.system(.caption, design: .monospaced, weight: .semibold))
                                .lineLimit(1)
                                .fixedSize()
                                .padding(.horizontal, 4)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(state.scaling)
                        .fixedSize()
                        .help("Scale to 0 — stops all pods for this deployment")
                        .accessibilityLabel("Stop deployment, scale to zero")
                    }
                }
                // Never let the controls be the thing that compresses — Stop was
                // squeezed to an unlabelled grey box against the pane edge.
                .fixedSize()
            }
        }
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

    private func replicaStat(_ label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: "\(value)")
                .font(.system(.title3, design: .monospaced, weight: .bold))
                .foregroundStyle(color)
                .contentTransition(.numericText())
            // "Desired" and "Available" were being hyphenated across two lines
            // once the scale controls shared the row.
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
        .motion(Motion.stateChange, value: value)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label.lowercased())")
    }

    private func imagesSection(_ dep: K8sDeployment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Container Images", systemImage: "shippingbox")
                .font(.system(.headline, design: .monospaced, weight: .semibold))

            ForEach(dep.images, id: \.self) { image in
                HStack {
                    Text(image)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(image, forType: .string)
                        state.showToast("Image copied")
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(10)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func conditionsSection(_ dep: K8sDeployment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Conditions", systemImage: "checkmark.shield")
                .font(.system(.headline, design: .monospaced, weight: .semibold))

            ForEach(dep.conditions, id: \.self) { cond in
                conditionRow(cond)
            }
        }
    }

    private func conditionRow(_ cond: DeploymentCondition) -> some View {
        HStack(spacing: 10) {
            Image(systemName: cond.status == "True" ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(cond.status == "True" ? .green : .red)

            VStack(alignment: .leading, spacing: 2) {
                Text(cond.type)
                    .font(.system(.callout, design: .monospaced, weight: .medium))
                if !cond.message.isEmpty {
                    Text(cond.message)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if !cond.reason.isEmpty {
                Text(cond.reason)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
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
            .font(.system(.headline, design: .monospaced, weight: .semibold))

        FlowLayout(spacing: 6) {
            ForEach(labels.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                HStack(spacing: 4) {
                    Text(key)
                        .foregroundStyle(.secondary)
                    Text("=")
                        .foregroundStyle(.tertiary)
                    Text(value)
                        .foregroundStyle(.primary)
                }
                .font(.system(.caption, design: .monospaced))
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
                .font(.system(.headline, design: .monospaced, weight: .semibold))

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
                        .font(.system(.callout, design: .monospaced, weight: .medium))
                    if event.count > 1 {
                        Text(verbatim: "×\(event.count)")
                            .font(.system(.caption, design: .monospaced, weight: .bold))
                            .foregroundStyle(.orange)
                    }
                }
                Text(event.message)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Spacer()

            if let last = event.lastSeen {
                Text(formatAge(last))
                    .font(.system(.caption2, design: .monospaced))
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
