import SwiftUI

/// ⌘K: jump to any resource in any namespace, or run an action, from one
/// search field. The Raycast front-door pattern — the fastest path between
/// "I'm thinking about the payments api" and looking at it.
///
/// Search spans the all-namespace arrays the Overview keeps warm, plus
/// everything loaded in the current scope, plus namespaces and actions — so a
/// hit can move scope, type, and selection in one keystroke.
struct CommandPaletteView: View {
    @Environment(AppState.self) private var state
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var fieldFocused: Bool

    struct Item: Identifiable {
        let id: String
        let icon: String
        let title: String
        let subtitle: String
        let run: @MainActor (AppState) async -> Void
    }

    private var items: [Item] {
        let q = query.lowercased()
        var out: [Item] = []

        func add(_ item: Item) {
            guard out.count < 12 else { return }
            guard !out.contains(where: { $0.id == item.id }) else { return }
            out.append(item)
        }

        // Resources: all-namespace deployment/pod arrays; scoped others.
        if !q.isEmpty {
            for d in state.overviewDeployments where d.name.lowercased().contains(q) {
                add(Item(id: "dep/\(d.id)", icon: ResourceType.deployments.icon,
                         title: d.name, subtitle: d.namespace) { s in
                    await Self.jump(s, ns: d.namespace, type: .deployments) {
                        s.selectedDeployment = s.deployments.first { $0.name == d.name }
                    }
                })
            }
            for p in state.overviewPods where p.name.lowercased().contains(q) {
                add(Item(id: "pod/\(p.id)", icon: ResourceType.pods.icon,
                         title: p.name, subtitle: p.namespace) { s in
                    await Self.jump(s, ns: p.namespace, type: .pods) {
                        s.selectedPod = s.pods.first { $0.name == p.name }
                    }
                })
            }
            for sec in state.secrets where sec.name.lowercased().contains(q) {
                add(Item(id: "sec/\(sec.id)", icon: ResourceType.secrets.icon,
                         title: sec.name, subtitle: sec.namespace) { s in
                    await Self.jump(s, ns: sec.namespace, type: .secrets) {
                        if let hit = s.secrets.first(where: { $0.name == sec.name }) {
                            s.selectedSecret = hit
                            await s.selectSecret(hit)
                        }
                    }
                })
            }
            for svc in state.services where svc.name.lowercased().contains(q) {
                add(Item(id: "svc/\(svc.id)", icon: ResourceType.services.icon,
                         title: svc.name, subtitle: svc.namespace) { s in
                    await Self.jump(s, ns: svc.namespace, type: .services) {
                        s.selectedService = s.services.first { $0.name == svc.name }
                    }
                })
            }
            for ns in state.namespaces where ns.name.lowercased().contains(q) {
                add(Item(id: "ns/\(ns.id)", icon: "folder",
                         title: ns.name, subtitle: "namespace") { s in
                    s.selectedNamespace = ns
                    await s.selectNamespace(ns)
                })
            }
        }

        // Destinations + actions always match on empty query, filtered otherwise.
        let destinations: [(AppDestination, String)] = [(.overview, "overview"), (.events, "events")]
            + ResourceType.allCases.map { (.resource($0), $0.rawValue.lowercased()) }
        for (dest, keyword) in destinations where q.isEmpty || keyword.contains(q) {
            add(Item(id: "go/\(keyword)", icon: dest.icon,
                     title: "Go to \(dest.title)", subtitle: "") { s in
                await s.selectDestination(dest)
            })
        }
        for ctx in state.availableContexts where ctx != state.context && (q.isEmpty || ctx.lowercased().contains(q)) {
            add(Item(id: "ctx/\(ctx)", icon: "arrow.triangle.2.circlepath",
                     title: "Switch context → \(ctx)", subtitle: "") { s in
                await s.switchContext(ctx)
            })
        }
        return out
    }

    @MainActor
    private static func jump(_ s: AppState, ns: String, type: ResourceType,
                             then: @MainActor () async -> Void) async {
        if s.allNamespaces { await s.selectNamespaceScope(all: false) }
        if let target = s.namespaces.first(where: { $0.name == ns }) {
            s.selectedNamespace = target
            await s.selectNamespace(target)
        }
        await s.selectResourceType(type)
        await then()
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search resources, namespaces and actions…", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(16)
                .focused($fieldFocused)
                .onSubmit { runHighlighted() }
                .onChange(of: query) { _, _ in highlighted = 0 }

            Divider()

            if items.isEmpty {
                Text("No matches.")
                    .foregroundStyle(.secondary)
                    .padding(20)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            row(item, isHighlighted: index == highlighted)
                                .onTapGesture { run(item) }
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 320)
            }
        }
        .frame(width: 520)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator, lineWidth: 1))
        .shadow(radius: 30, y: 10)
        .onAppear {
            fieldFocused = true
            // Warm the all-namespace arrays so pods/deployments anywhere match.
            Task { await state.loadOverview() }
        }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.escape) { state.paletteOpen = false; return .handled }
    }

    private func row(_ item: Item, isHighlighted: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 13))
                .frame(width: 20)
                .foregroundStyle(isHighlighted ? Theme.accent : Color.secondary)
            Text(item.title)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if !item.subtitle.isEmpty {
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHighlighted ? Theme.soft(Theme.accent) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    private func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        highlighted = max(0, min(items.count - 1, highlighted + delta))
    }

    private func runHighlighted() {
        guard items.indices.contains(highlighted) else { return }
        run(items[highlighted])
    }

    private func run(_ item: Item) {
        state.paletteOpen = false
        Task { await item.run(state) }
    }
}
