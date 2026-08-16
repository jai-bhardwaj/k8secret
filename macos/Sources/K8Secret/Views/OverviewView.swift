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

    /// Cluster health as one number: ready deployments and running pods as a
    /// fraction of everything that should be. The hero ring renders it.
    private var healthPercent: Int {
        let total = deps.count + pods.count
        guard total > 0 else { return 100 }
        return Int((Double(depsReady + podsRunning) / Double(total) * 100).rounded())
    }

    /// The hero's right half: verdict headline, scope line, attention rows.
    private var heroVerdict: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(needsAttention.isEmpty
                 ? "Everything is running."
                 : "\(needsAttention.count) thing\(needsAttention.count == 1 ? "" : "s") need\(needsAttention.count == 1 ? "s" : "") attention")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            Text(state.allNamespaces
                 ? "Across all namespaces in \(state.context)."
                 : "In \(state.selectedNamespace?.name ?? "—") on \(state.context).")
                .font(.system(size: 13))
                .foregroundStyle(Theme.text2)
                .lineLimit(1)
                .truncationMode(.middle)
            if !needsAttention.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(needsAttention.prefix(3)) { item in
                        attentionRow(item)
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                // The hero: CleanMyMac's Smart Care grammar — a glowing health
                // ring beside a huge light-weight verdict, on the hero canvas.
                ViewThatFits(in: .horizontal) {
                HStack(spacing: 34) {
                    HealthRing(percent: healthPercent,
                               troubled: !needsAttention.isEmpty)
                        .frame(width: 190, height: 190)
                    heroVerdict
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 18) {
                    HealthRing(percent: healthPercent,
                               troubled: !needsAttention.isEmpty)
                        .frame(width: 150, height: 150)
                    heroVerdict
                }
                }
                .padding(.top, 18)

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

                if needsAttention.count > 3 {
                    section("Also needs attention") {
                        VStack(spacing: 6) {
                            ForEach(needsAttention.dropFirst(3)) { item in
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

/// The hero health ring: a trimmed arc with a soft glow, counting up on
/// appear (numeric content transition). Green while healthy, amber when
/// anything needs attention — the color answers before the number does.
struct HealthRing: View {
    let percent: Int
    let troubled: Bool
    @State private var shown = 0
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(scheme == .dark ? 0.10 : 0.35), lineWidth: 13)
            Circle()
                .trim(from: 0, to: CGFloat(shown) / 100)
                .stroke(
                    AngularGradient(
                        colors: troubled
                            ? [Color(hex: 0xE5A93D), Color(hex: 0xF5C468)]
                            : [Color(hex: 0x2FC392), Color(hex: 0x63F0C8)],
                        center: .center),
                    style: StrokeStyle(lineWidth: 13, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: (troubled ? Color(hex: 0xE5A93D) : Color(hex: 0x2FC392)).opacity(0.55),
                        radius: 12)
            VStack(spacing: 2) {
                Text("\(shown)%")
                    .font(.system(size: 44, weight: .light))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText(value: Double(shown)))
                Text("healthy")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text3)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) { shown = percent }
        }
        .onChange(of: percent) { _, new in
            withAnimation(Theme.easeOut) { shown = new }
        }
        .accessibilityLabel("Cluster health \(percent) percent")
    }
}
