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

    /// The hero's right half, the prototype's herocopy: tiered verdict,
    /// readiness sentence, and the three quick-action buttons.
    private var heroVerdict: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(healthPercent >= 100 ? "All systems running"
                 : (healthPercent >= 70 ? "Mostly healthy" : "Needs attention"))
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            Text("\(depsReady) of \(deps.count) deployments and \(podsRunning) of \(pods.count) pods are where they should be.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.text2)
                .lineLimit(2)

            // The prototype's heroactions: three doorways.
            VStack(alignment: .leading, spacing: 12) {
                heroAction(.resource(.deployments), title: "Review workloads",
                           sub: "deployments, pods and cronjobs")
                heroAction(.events, title: "Live events",
                           sub: "everything the cluster said recently")
                heroAction(.resource(.secrets), title: "Security check",
                           sub: "secrets, masking and exports")
            }
            .padding(.top, 14)
        }
    }

    private func heroAction(_ dest: AppDestination, title: String, sub: String) -> some View {
        HeroActionButton(destination: dest, title: title, sub: sub) {
            Task { await state.selectDestination(dest) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                // Pane header: crumbs + title, like every other pane.
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(state.context) · \(state.allNamespaces ? "all namespaces" : (state.selectedNamespace?.name ?? "—"))")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.text2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("Overview")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.text)
                }
                .padding(.top, 8)
                // The hero: CleanMyMac's Smart Care grammar — a glowing health
                // ring beside a huge light-weight verdict, on the hero canvas.
                ViewThatFits(in: .horizontal) {
                HStack(spacing: 34) {
                    HealthRing(percent: healthPercent)
                        .frame(width: 190, height: 190)
                    heroVerdict
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 18) {
                    HealthRing(percent: healthPercent)
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
                    StatCard(label: "Port forwards",
                             value: "\(PortForwardManager.shared.forwards.filter { $0.context == state.context }.count)")
                    if state.clusterCPUPercent > 0 {
                        StatCard(label: "Cluster CPU", value: "\(state.clusterCPUPercent)%",
                                 valueColor: Theme.pressure(state.clusterCPUPercent))
                    }
                    if state.clusterMemPercent > 0 {
                        StatCard(label: "Cluster memory", value: "\(state.clusterMemPercent)%",
                                 valueColor: Theme.pressure(state.clusterMemPercent))
                    }
                }

                // The prototype's standalone section, below the stats.
                section("Needs attention") {
                    if needsAttention.isEmpty {
                        Label("Everything is running.", systemImage: "checkmark.circle")
                            .font(.system(size: 12))
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

                // Room for the orb, which floats over this rather than
                // scrolling with it.
                Color.clear.frame(height: 132)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // The prototype's `position: sticky; bottom: 26px` — a re-scan control
        // that stays put while the overview scrolls under it.
        .overlay(alignment: .bottom) {
            ScanOrb {
                Task { await state.loadOverview() }
            }
            .padding(.bottom, 26)
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
                    .font(.system(size: 12, weight: .semibold))
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
                    .font(.system(size: 11, design: .monospaced))
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
    /// The ring counts up once on appear; after that it tracks `percent`
    /// directly. Mirroring the value into @State went stale whenever
    /// ViewThatFits swapped hero layouts — the ring kept saying 100%.
    @State private var appeared = false
    /// The sheen's angle. It turns once every 5.5 seconds, forever, like the
    /// prototype's conic highlight.
    @State private var sheen = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shown: Int { appeared ? percent : 0 }

    /// The prototype's tiers: green at 100, amber from 70, red below.
    private var tierColors: [Color] {
        if percent >= 100 { return [Color(hex: 0x2FC392), Color(hex: 0x63F0C8)] }
        if percent >= 70 { return [Color(hex: 0xE5A93D), Color(hex: 0xF5C468)] }
        return [Color(hex: 0xE5564F), Color(hex: 0xF58F8A)]
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(scheme == .dark ? 0.10 : 0.35), lineWidth: 13)
            Circle()
                .trim(from: 0, to: CGFloat(shown) / 100)
                .stroke(
                    AngularGradient(colors: tierColors, center: .center),
                    style: StrokeStyle(lineWidth: 13, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: tierColors[0].opacity(0.55), radius: 12)
            // The prototype's slow highlight travelling around the band: a
            // narrow white wedge in a conic gradient, turning once every 5.5s.
            Circle()
                .strokeBorder(
                    AngularGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .clear, location: 0.78),
                            .init(color: .white.opacity(scheme == .dark ? 0.20 : 0.34), location: 0.88),
                            .init(color: .clear, location: 0.96),
                            .init(color: .clear, location: 1),
                        ],
                        center: .center),
                    lineWidth: 13)
                .rotationEffect(.degrees(sheen ? 360 : 0))
                .allowsHitTesting(false)
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
            withAnimation(.easeOut(duration: 0.9)) { appeared = true }
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 5.5 * Motion.scale).repeatForever(autoreverses: false)) {
                sheen = true
            }
        }
        .animation(Theme.easeOut, value: percent)
        .accessibilityLabel("Cluster health \(percent) percent")
    }
}

/// The prototype's heroact: an icon chip beside a title and muted subtitle,
/// sliding right on hover.
struct HeroActionButton: View {
    let destination: AppDestination
    let title: String
    let sub: String
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                DimensionalIcon(destination: destination, size: 24)
                    .frame(width: 40, height: 40)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: 1))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(sub)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text3)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(hovering ? Theme.inset : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .offset(x: hovering ? 3 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .motion(Motion.stateChange, value: hovering)
        .frame(maxWidth: 380)
        .accessibilityLabel("\(title) — \(sub)")
    }
}

/// The prototype's scanorb: a pulsing, glowing circular Scan button that
/// re-reads cluster health on demand.
struct ScanOrb: View {
    let action: () -> Void
    @State private var pulsing = false
    @State private var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.clusterAccent) private var accent

    var body: some View {
        Button {
            action()
        } label: {
            Text("Scan")
                .font(.system(size: 16.5, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 112, height: 112)
                // The prototype's orb: a light source at 50% 32%, deepening to
                // the cluster's own accent rather than one fixed magenta.
                .background(
                    Circle().fill(
                        RadialGradient(
                            colors: [accent.opacity(0.95), accent, accent.blended(with: .black, 0.45)],
                            center: UnitPoint(x: 0.5, y: 0.32),
                            startRadius: 4, endRadius: 96))
                )
                // Three layers, as specified: a wide glow, a soft halo instead
                // of a hairline ring, and a drop shadow beneath.
                .overlay(Circle().strokeBorder(.white.opacity(0.10), lineWidth: 6).blur(radius: 3))
                .shadow(color: accent.opacity(pulsing ? 0.50 : 0.40), radius: pulsing ? 39 : 30)
                .shadow(color: accent.opacity(0.55), radius: 22, y: 16)
                .scaleEffect(pressed ? 0.96 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0, pressing: { down in
            withAnimation(.spring(response: 0.18, dampingFraction: 0.7)) { pressed = down }
        }, perform: {})
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
        .help("Re-scan cluster health")
        .accessibilityLabel("Scan cluster health")
    }
}
