import SwiftUI

struct PodsListView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        Group {
            if state.selectedNamespace == nil {
                ContentUnavailableView {
                    Label("Select a Namespace", systemImage: "sidebar.left")
                } description: {
                    Text("Choose a namespace to view its pods.")
                }
            } else if state.loadingPods {
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
        .navigationTitle(state.selectedNamespace?.name ?? "Pods")
    }

    private var podsList: some View {
        @Bindable var state = state

        return List(state.filteredPods, selection: $state.selectedPod) { pod in
            PodRow(pod: pod, metrics: state.metrics(for: pod.name))
                .tag(pod)
        }
        .searchable(text: $state.podSearch, prompt: "Filter pods")
        .overlay {
            if state.pods.isEmpty {
                ContentUnavailableView {
                    Label("No Pods", systemImage: "circle.hexagongrid")
                } description: {
                    Text("This namespace has no pods.")
                }
            } else if state.filteredPods.isEmpty {
                ContentUnavailableView.search(text: state.podSearch)
            }
        }
        .onChange(of: state.selectedPod) { _, newValue in
            if let pod = newValue {
                Task { await state.selectPod(pod) }
            }
        }
    }
}

struct PodRow: View {
    let pod: K8sPod
    let metrics: PodMetrics?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Row 1: phase icon, name, phase badge, age
            HStack(spacing: 8) {
                phaseIcon
                    .frame(width: 18)

                Text(pod.name)
                    .font(.system(.body, design: .monospaced, weight: .medium))
                    .lineLimit(1)

                Spacer()

                phaseBadge

                Text(pod.age)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            // Row 2: metrics chips (only for running pods with metrics)
            if let m = metrics, pod.phase.lowercased() == "running" {
                HStack(spacing: 12) {
                    metricsChip(
                        icon: "cpu",
                        color: .blue,
                        usage: m.totalCPU,
                        requestPct: m.cpuPercent(pod: pod),
                        limitPct: m.cpuLimitPercent(pod: pod)
                    )

                    metricsChip(
                        icon: "memorychip",
                        color: .purple,
                        usage: m.totalMemory,
                        requestPct: m.memPercent(pod: pod),
                        limitPct: m.memLimitPercent(pod: pod)
                    )

                    Spacer()

                    // Ready + restarts + containers inline
                    podInfoChips
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
                    Text("\(pod.restarts)")
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9))
                }
                .foregroundStyle(pod.restarts > 5 ? .red : .orange)
            }

            if pod.containers.count > 1 {
                HStack(spacing: 3) {
                    Text("\(pod.containers.count)")
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
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 3))
            }
        }
        .font(.system(.caption2, design: .monospaced))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
    }

    private func pctColor(_ p: Int) -> Color {
        p > 90 ? .red : p > 70 ? .orange : .green
    }

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
        Text(pod.phase)
            .font(.system(.caption2, design: .monospaced, weight: .medium))
            .foregroundStyle(phaseColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(phaseColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    private var phaseColor: Color {
        switch pod.phase.lowercased() {
        case "running": return .green
        case "succeeded": return .blue
        case "pending": return .yellow
        case "failed": return .red
        default: return .secondary
        }
    }
}
