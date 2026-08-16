import SwiftUI

/// The window's front door: "is anything wrong?" answered before any drilling.
///
/// Deliberately spans every namespace regardless of the toolbar scope — a red
/// deployment hiding behind a namespace filter would make the summary lie.
struct OverviewView: View {
    @Environment(AppState.self) private var state

    private var deps: [K8sDeployment] { state.overviewDeployments }
    private var pods: [K8sPod] { state.overviewPods }

    private var depsReady: Int { deps.filter { $0.readyReplicas == $0.replicas && $0.replicas > 0 }.count }
    private var podsRunning: Int { pods.filter { $0.phase == "Running" }.count }

    private struct Attention: Identifiable {
        let id: String
        let name: String
        let namespace: String
        let why: String
        let type: ResourceType
    }

    private var needsAttention: [Attention] {
        var out: [Attention] = []
        for d in deps where d.readyReplicas < d.replicas {
            out.append(Attention(id: "d/\(d.id)", name: d.name, namespace: d.namespace,
                                 why: "\(d.readyReplicas)/\(d.replicas) ready", type: .deployments))
        }
        for p in pods where p.phase != "Running" && p.phase != "Succeeded" {
            out.append(Attention(id: "p/\(p.id)", name: p.name, namespace: p.namespace,
                                 why: p.phase, type: .pods))
        }
        for p in pods where p.restarts > 5 && p.phase == "Running" {
            out.append(Attention(id: "r/\(p.id)", name: p.name, namespace: p.namespace,
                                 why: "\(p.restarts) restarts", type: .pods))
        }
        return out
    }

    private var topCPU: [(pod: K8sPod, cpu: Int)] {
        pods.compactMap { pod in
            state.metrics(for: pod.name).map { (pod, $0.cpuMillis) }
        }
        .sorted { $0.1 > $1.1 }
        .prefix(5)
        .map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    StatCard(label: "Deployments ready", value: "\(depsReady) / \(deps.count)",
                             valueColor: depsReady < deps.count ? Theme.warn : nil)
                    StatCard(label: "Pods running", value: "\(podsRunning) / \(pods.count)",
                             valueColor: podsRunning < pods.count ? Theme.warn : nil)
                    StatCard(label: "Namespaces", value: "\(state.namespaces.count)")
                    StatCard(label: "Kubernetes", value: state.k8sVersion.isEmpty ? "—" : state.k8sVersion, mono: true)
                    if state.clusterCPUPercent > 0 {
                        StatCard(label: "Cluster CPU", value: "\(state.clusterCPUPercent)%",
                                 valueColor: Theme.pressure(state.clusterCPUPercent))
                    }
                    if state.clusterMemPercent > 0 {
                        StatCard(label: "Cluster memory", value: "\(state.clusterMemPercent)%",
                                 valueColor: Theme.pressure(state.clusterMemPercent))
                    }
                }

                section("Needs attention") {
                    if needsAttention.isEmpty {
                        Label("Everything is running.", systemImage: "checkmark.circle")
                            .font(.callout)
                            .foregroundStyle(Theme.ok)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(needsAttention) { item in
                                attentionRow(item)
                            }
                        }
                    }
                }

                if !topCPU.isEmpty {
                    section("Top CPU") {
                        VStack(spacing: 2) {
                            ForEach(topCPU, id: \.pod.id) { entry in
                                topCPURow(entry.pod, cpu: entry.cpu)
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Overview")
        .task { await state.loadOverview() }
        .refreshable { await state.loadOverview() }
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(.tertiary)
            content()
        }
    }

    private func attentionRow(_ item: Attention) -> some View {
        Button {
            jump(to: item)
        } label: {
            HStack(spacing: 9) {
                Circle().fill(Theme.bad).frame(width: 8, height: 8)
                Text(item.name)
                    .font(.system(.callout, weight: .semibold))
                    .lineLimit(1)
                StatusPill(text: item.why, color: Theme.bad)
                Spacer()
                NamespaceBadge(name: item.namespace)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Theme.soft(Theme.bad), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.bad.opacity(0.5), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.name) in \(item.namespace): \(item.why). Open.")
    }

    private func topCPURow(_ pod: K8sPod, cpu: Int) -> some View {
        Button {
            jump(to: Attention(id: pod.id, name: pod.name, namespace: pod.namespace, why: "", type: .pods))
        } label: {
            HStack(spacing: 9) {
                Circle()
                    .fill(pod.phase == "Running" ? Theme.ok : Theme.bad)
                    .frame(width: 7, height: 7)
                Text(pod.name)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                MetricChip(icon: "cpu", text: "\(cpu)m", hue: Theme.cpu)
                Spacer()
                NamespaceBadge(name: pod.namespace)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Jumping scopes into the item's namespace first, so the destination list
    /// and detail are always unambiguous — same rule as All Namespaces rows.
    private func jump(to item: Attention) {
        Task {
            if state.allNamespaces { await state.selectNamespaceScope(all: false) }
            if let ns = state.namespaces.first(where: { $0.name == item.namespace }) {
                state.selectedNamespace = ns
                await state.selectNamespace(ns)
            }
            await state.selectResourceType(item.type)
            switch item.type {
            case .deployments:
                state.selectedDeployment = state.deployments.first { $0.name == item.name }
            case .pods:
                state.selectedPod = state.pods.first { $0.name == item.name }
            default: break
            }
        }
    }
}
