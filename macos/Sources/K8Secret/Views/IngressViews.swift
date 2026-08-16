import SwiftUI

// MARK: - List

struct IngressesListView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
        PaneHeader(
            title: "Ingresses",
            subtitle: "\(state.ingresses.count) \(state.allNamespaces ? "across all namespaces" : "in " + (state.selectedNamespace?.name ?? "—"))")
        FilterField(prompt: "Filter ingresses…", text: $state.ingressSearch)
        List(state.filteredIngresses) { ing in
            IngressRow(ingress: ing, showNamespace: state.allNamespaces)
                .vnextRow(isSelected: state.selectedIngress?.id == ing.id)
                .onTapGesture { state.selectedIngress = ing }
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(Theme.line)
                .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
        }
        .vnextKeyboardSelection(items: state.filteredIngresses, selection: $state.selectedIngress)
        .overlay {
            if state.isInitialLoad {
                ProgressView()
            } else if state.ingresses.isEmpty {
                EmptyPane(icon: "globe", title: "No Ingresses",
                          message: state.allNamespaces ? "No ingresses in any namespace." : "No ingresses in this namespace.")
            } else if state.filteredIngresses.isEmpty {
                EmptyPane(icon: "magnifyingglass", title: "No matches",
                          message: "No results for “\(state.ingressSearch)”.")
            }
        }
        }
        .vnextListPane()
        .motion(Motion.listChange, value: state.ingresses)
    }
}

struct IngressRow: View {
    let ingress: K8sIngress
    var showNamespace = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(ingress.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                if showNamespace { NamespaceBadge(name: ingress.namespace) }
                Spacer(minLength: 4)
                StatusPill(text: ingress.tls ? "TLS" : "no TLS",
                           color: ingress.tls ? Theme.ok : Theme.warn)
                Text(ingress.age)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            MetricChip(icon: "globe", text: ingress.primaryHost, hue: nil, truncates: true)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ingress.name), host \(ingress.primaryHost)\(ingress.tls ? ", TLS" : ", no TLS")")
    }
}

// MARK: - Detail

struct IngressDetailView: View {
    @Environment(AppState.self) private var state

    enum DetailTab: String, CaseIterable { case overview = "Overview", yaml = "YAML" }
    @State private var tab = DetailTab.overview

    var body: some View {
        if let ing = state.selectedIngress {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    DetailBreadcrumb(type: "ingresses")
                    HStack(spacing: 10) {
                        Text(ing.name)
                            .font(.system(size: 17, weight: .bold, design: .monospaced))
                            .kerning(-0.25)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        StatusPill(text: ing.tls ? "TLS terminated" : "no TLS",
                                   color: ing.tls ? Theme.ok : Theme.warn)
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)

                UnderlineTabBar(tabs: DetailTab.allCases.map { ($0, $0.rawValue) }, selection: $tab)
                    .padding(.top, 6)

                switch tab {
                case .yaml:
                    ResourceYAMLView(type: .ingresses, namespace: ing.namespace, name: ing.name)
                case .overview:
                    ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section("Routing") {
                        KVGrid(rows: [
                            ("Host", ing.primaryHost, true),
                            ("Class", ing.className.isEmpty ? "—" : ing.className, false),
                            ("TLS", ing.tls ? "Terminated at ingress — \(ing.tlsHosts.joined(separator: ", "))" : "None", false),
                            ("Age", ing.age, false),
                        ])
                    }

                    section("Paths") {
                        pathsTable(ing)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .navigationTitle(ing.name)
        } else {
            ContentUnavailableView {
                Label("No Ingress Selected", systemImage: "globe")
            } description: {
                Text("Choose an ingress to see its hosts and paths.")
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(.tertiary)
            content()
        }
    }

    private func pathsTable(_ ing: K8sIngress) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("HOST").frame(maxWidth: 200, alignment: .leading)
                Text("PATH").frame(maxWidth: .infinity, alignment: .leading)
                Text("SERVICE")
            }
            .font(.system(size: 9.5, weight: .semibold))
            .kerning(0.5)
            .foregroundStyle(Theme.text3)
            .padding(.bottom, 6)
            ForEach(Array(ing.rules.enumerated()), id: \.offset) { i, rule in
                if i > 0 { Divider() }
                HStack(spacing: 12) {
                    Text(rule.host)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(rule.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    Spacer()
                    // The backend service is a link, not a label: routing
                    // questions end at the service, so take the user there.
                    Button {
                        jumpToService(rule.serviceName)
                    } label: {
                        Text("\(rule.serviceName):\(String(rule.servicePort))")
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Open service \(rule.serviceName)")
                }
                .padding(.vertical, 7)
            }
            if ing.rules.isEmpty {
                Text("No rules — this ingress routes nothing.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.warn)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 7)
            }
        }
    }

    private func jumpToService(_ name: String) {
        Task {
            await state.selectResourceType(.services)
            if let svc = state.services.first(where: { $0.name == name }) {
                state.selectedService = svc
            }
        }
    }
}

/// Label/value rows for detail panes — the prototype's `.kv` grid.
struct KVGrid: View {
    /// (label, value, monospaced)
    let rows: [(String, String, Bool)]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 7) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    Text(row.0)
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                        .gridColumnAlignment(.leading)
                    Text(row.1)
                        .font(row.2 ? .system(.callout, design: .monospaced) : .callout)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }
}
