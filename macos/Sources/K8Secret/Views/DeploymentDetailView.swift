import SwiftUI

struct DeploymentDetailView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @State private var showRestartAlert = false

    var body: some View {
        Group {
            if let dep = state.selectedDeployment {
                deploymentDetail(dep)
            } else {
                ContentUnavailableView {
                    Label("Select a Deployment", systemImage: "shippingbox")
                } description: {
                    Text("Choose a deployment to view its details.")
                }
            }
        }
    }

    @ViewBuilder
    private func deploymentDetail(_ dep: K8sDeployment) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection(dep)

                // Rollout progress bar
                if state.rollingOut {
                    rolloutBanner
                }

                Divider()
                scaleSection(dep)
                Divider()
                imagesSection(dep)
                conditionsBlock(dep)
                labelsBlock(dep)
                eventsBlock
            }
            .padding(24)
        }
        .onDisappear {
            state.stopRolloutPolling()
        }
        .navigationTitle(dep.name)
        .toolbar { deploymentToolbar(dep) }
        .alert("Restart Deployment", isPresented: $showRestartAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Restart") {
                Task { await state.restartDeployment(dep) }
            }
        } message: {
            Text("This will perform a rolling restart of \(dep.name). All pods will be recreated.")
        }
    }

    @ToolbarContentBuilder
    private func deploymentToolbar(_ dep: K8sDeployment) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                showRestartAlert = true
            } label: {
                Label("Restart", systemImage: "arrow.clockwise")
            }
            .help("Rolling restart")

            Button {
                Task { await state.refreshCurrentResource() }
            } label: {
                Label("Refresh", systemImage: "arrow.triangle.2.circlepath")
            }
            .help("Refresh")
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

            HStack(spacing: 20) {
                HStack(spacing: 24) {
                    replicaStat("Desired", value: dep.replicas, color: .primary)
                    replicaStat("Ready", value: dep.readyReplicas, color: .green)
                    replicaStat("Updated", value: dep.updatedReplicas, color: .blue)
                    replicaStat("Available", value: dep.availableReplicas, color: .green)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        if dep.replicas > 0 {
                            Task { await state.scaleDeployment(dep, to: dep.replicas - 1) }
                        }
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.bordered)
                    .disabled(dep.replicas <= 0 || state.scaling)

                    Text("\(dep.replicas)")
                        .font(.system(.title2, design: .monospaced, weight: .bold))
                        .frame(minWidth: 40)

                    Button {
                        Task { await state.scaleDeployment(dep, to: dep.replicas + 1) }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.bordered)
                    .disabled(state.scaling)
                }
            }
        }
    }

    private func replicaStat(_ label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(.title3, design: .monospaced, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
        }
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
                        Text("×\(event.count)")
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
