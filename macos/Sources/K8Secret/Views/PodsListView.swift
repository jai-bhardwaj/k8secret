import SwiftUI

struct PodsListView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        Group {
            if state.selectedNamespace == nil && !state.allNamespaces {
                ContentUnavailableView {
                    Label("Select a Namespace", systemImage: "sidebar.left")
                } description: {
                    Text("Choose a namespace to view its pods.")
                }
            } else if state.loadingPods && state.pods.isEmpty {
                // Only take over the view when there is nothing to show yet.
                // Refreshing content that is already on screen stays in place; the
                // spinner used to replace the list on every refresh, losing scroll
                // position and flashing the rows.
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading pods...")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                podsList
            }
        }
        // A refresh over existing content shows here instead of replacing the
        // list, so the rows stay put and the work is still visible.
        .overlay(alignment: .topTrailing) {
            if state.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .padding(8)
                    .transition(.opacity)
                    .accessibilityLabel("Refreshing")
            }
        }
        .motion(Motion.stateChange, value: state.isRefreshing)
        // A list of names, ages and status pills needs real width. Without a
        // floor this column collapsed next to the detail pane and truncated
        // its own empty-state title to "No Deploy…".
        .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 560)
    }

    private var podsList: some View {
        @Bindable var state = state

        return VStack(spacing: 0) {
        PaneHeader(
            title: "Pods",
            subtitle: "\(state.pods.count) \(state.allNamespaces ? "across all namespaces" : "in " + (state.selectedNamespace?.name ?? "—"))")
        FilterField(prompt: "Filter pods…", text: $state.podSearch)
        List(state.filteredPods) { pod in
            PodRow(pod: pod, metrics: state.metrics(for: pod.name),
                   showNamespace: state.allNamespaces)
                .vnextRow(isSelected: state.selectedPod?.id == pod.id, hoverKey: pod.name)
                .onTapGesture { state.selectedPod = pod }
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(Theme.line)
                .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
        }
        .vnextKeyboardSelection(items: state.filteredPods, selection: $state.selectedPod)
        .overlay {
            if state.pods.isEmpty {
                // An empty namespace is a dead end unless it says where to go
                // next. A fresh install lands on `default`, which on most
                // clusters holds nothing, so this was the first screen many
                // people saw.
                EmptyPane(icon: "circle.hexagongrid", title: "No Pods",
                           message: "Nothing here in \(state.selectedNamespace?.name ?? "this namespace"). Pick another namespace from the menu above, or a different resource type in the sidebar.")
            } else if state.filteredPods.isEmpty {
                EmptyPane(icon: "magnifyingglass", title: "No matches",
                           message: "No results for “\(state.podSearch)”. The filter matches anywhere in the name.")
            }
        }
        .onChange(of: state.selectedPod?.id) { _, _ in
            // Keyed on id, not the whole value. Polling and the watch stream
            // rewrite the selected object in place as its status changes, and
            // reacting to that as if the user had clicked a different row reran
            // selection — which clears the log pane and refetches events out from
            // under someone who is reading them.
            guard let pod = state.selectedPod else { return }
            Task { await state.selectPod(pod) }
        }
        }
        .vnextListPane()
    }
}

struct PodRow: View {
    let pod: K8sPod
    let metrics: PodMetrics?
    var showNamespace = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Row 1: phase icon, name, phase badge, age
            HStack(spacing: 8) {
                phaseIcon
                    .frame(width: 18)

                Text(pod.name)
                    .font(.system(.body, design: .monospaced, weight: .medium))
                    .lineLimit(1)

                if showNamespace { NamespaceBadge(name: pod.namespace) }

                Spacer()

                phaseBadge

                Text(pod.age)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            // Row 2: metrics chips (only for running pods with metrics)
            if let m = metrics, pod.phase.lowercased() == "running" {
                // Degrade predictably in the 280pt column: drop the R/L
                // badges before anything can crush or wrap.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        metricsChip(icon: "cpu", color: Theme.cpu, usage: m.totalCPU,
                                    requestPct: m.cpuPercent(pod: pod),
                                    limitPct: m.cpuLimitPercent(pod: pod))
                        metricsChip(icon: "memorychip", color: Theme.memory, usage: m.totalMemory,
                                    requestPct: m.memPercent(pod: pod),
                                    limitPct: m.memLimitPercent(pod: pod))
                        Spacer(minLength: 8)
                        podInfoChips
                    }
                    HStack(spacing: 10) {
                        compactChip(icon: "cpu", color: Theme.cpu, usage: m.totalCPU)
                        compactChip(icon: "memorychip", color: Theme.memory, usage: m.totalMemory)
                        Spacer(minLength: 8)
                        podInfoChips
                    }
                }
            } else {
                // No metrics — still show ready/restarts/containers
                podInfoChips
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Pod info chips

    private var podInfoChips: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                Text(pod.ready)
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 9))
            }
            .foregroundStyle(pod.readyCount == pod.totalCount && pod.totalCount > 0 ? .green : .orange)

            if pod.restarts > 0 {
                HStack(spacing: 3) {
                    Text(verbatim: "\(pod.restarts)")
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9))
                }
                .foregroundStyle(pod.restarts > 5 ? .red : .orange)
            }

            if pod.containers.count > 1 {
                HStack(spacing: 3) {
                    Text(verbatim: "\(pod.containers.count)")
                    Image(systemName: "shippingbox")
                        .font(.system(size: 9))
                }
                .foregroundStyle(.secondary)
            }
        }
        .font(.system(.caption2, design: .monospaced))
    }

    // MARK: - Metrics chip

    private func metricsChip(
        icon: String,
        color: Color,
        usage: String,
        requestPct: Int?,
        limitPct: Int?
    ) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color)

            // Usage value
            Text(usage)
                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(color)

            // Percentage badges: req% / lim%
            if requestPct != nil || limitPct != nil {
                HStack(spacing: 3) {
                    if let rPct = requestPct {
                        Text("R\(rPct)%")
                            .foregroundStyle(pctColor(rPct))
                    }
                    if let lPct = limitPct {
                        Text("L\(lPct)%")
                            .foregroundStyle(pctColor(lPct))
                    }
                }
                .font(.system(.caption2, design: .monospaced, weight: .bold))
                .lineLimit(1)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 3))
            }
        }
        .font(.system(.caption2, design: .monospaced))
        .fixedSize()
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
    }

    /// The chip without its R/L badges — the narrow fallback.
    private func compactChip(icon: String, color: Color, usage: String) -> some View {
        metricsChip(icon: icon, color: color, usage: usage, requestPct: nil, limitPct: nil)
    }

    private func pctColor(_ p: Int) -> Color { Theme.pressure(p) }

    // MARK: - Phase icon & badge

    @ViewBuilder
    private var phaseIcon: some View {
        switch pod.phase.lowercased() {
        case "running":
            Image(systemName: pod.readyCount == pod.totalCount ? "circle.fill" : "circle.lefthalf.filled")
                .foregroundStyle(pod.readyCount == pod.totalCount ? .green : .yellow)
                .font(.system(size: 14))
        case "succeeded":
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.blue)
                .font(.system(size: 14))
        case "pending":
            Image(systemName: "clock.fill")
                .foregroundStyle(.yellow)
                .font(.system(size: 14))
        case "failed":
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 14))
        default:
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(.secondary)
                .font(.system(size: 14))
        }
    }

    private var phaseBadge: some View {
        // Short words like "Running"/"Succeeded" were free to hyphenate in a
        // narrow column, same as the service type badge did.
        Text(pod.isCrashLooping ? "CrashLoop" : pod.phase)
            .font(.system(.caption2, design: .monospaced, weight: .medium))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(pod.isCrashLooping ? Theme.bad : phaseColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((pod.isCrashLooping ? Theme.bad : phaseColor).opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    private var phaseColor: Color {
        switch pod.phase.lowercased() {
        case "running": return Theme.ok
        case "succeeded": return Theme.cpu
        case "pending": return Theme.warn
        case "failed": return Theme.bad
        default: return .secondary
        }
    }
}
