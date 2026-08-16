import SwiftUI

/// ⌘N's destination: a cluster chooser, the way Postico opens with favorites
/// and Terminal offers profiles — pick the context first, then get a window
/// connected to exactly that cluster. Lives on the canvas like everything
/// else; each context card wears its saved tint dot, so prod is rose before
/// it's even opened.
struct LauncherView: View {
    @Environment(\.openWindow) private var openWindow
    // dismissWindow, not dismiss: plain dismiss is the presentation action
    // (sheets, popovers) and silently does nothing in a window root — the
    // launcher stayed open after picking a cluster.
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.colorScheme) private var scheme

    @State private var contexts: [ContextCard] = []
    @State private var currentContext = ""
    @State private var loadError: String?
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var searchFocused: Bool

    /// Same rule as the status-bar switcher: search appears when the list
    /// stops fitting in a glance, and the recently-used clusters lead.
    private var searchable: Bool { contexts.count > 4 }

    private var ordered: [ContextCard] {
        guard contexts.count > 8 else { return contexts }
        let recents = AppState.recentContexts
        var lead: [ContextCard] = []
        if let current = contexts.first(where: { $0.id == currentContext }) { lead.append(current) }
        for name in recents where name != currentContext {
            if let hit = contexts.first(where: { $0.id == name }) { lead.append(hit) }
        }
        let leadIDs = Set(lead.map(\.id))
        return lead + contexts.filter { !leadIDs.contains($0.id) }
    }

    private var matches: [ContextCard] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return ordered }
        return ordered.filter { $0.id.lowercased().contains(q) || $0.server.lowercased().contains(q) }
    }

    struct ContextCard: Identifiable {
        let id: String
        let server: String
        let tint: Theme.ClusterTint
    }

    var body: some View {
        ZStack {
            Theme.CanvasBackground(tint: .ocean, hero: false)

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Open a cluster")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(Theme.text)
                        Spacer()
                        if contexts.count > 1 {
                            Text(query.isEmpty
                                 ? "\(contexts.count)"
                                 : "\(matches.count) of \(contexts.count)")
                                .font(.system(size: 11.5))
                                .monospacedDigit()
                                .foregroundStyle(Theme.text3)
                        }
                    }
                    Text("Every window is one cluster — its color follows it everywhere.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.text2)
                }
                .padding(.top, 14)

                if searchable && loadError == nil {
                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.text3)
                        TextField("Filter clusters…", text: $query)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .focused($searchFocused)
                            .onSubmit { openHighlighted() }
                            .onChange(of: query) { _, _ in highlighted = 0 }
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(Theme.inset, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
                }

                if let loadError {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Can't read your kubeconfig", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.warn)
                        Text(loadError)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(Theme.text2)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.soft(Theme.warn), in: RoundedRectangle(cornerRadius: 12))
                } else if matches.isEmpty {
                    Text("No cluster matches “\(query)”.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text2)
                        .padding(.top, 6)
                } else {
                    ScrollViewReader { scroller in
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 8) {
                                ForEach(Array(matches.enumerated()), id: \.element.id) { index, ctx in
                                    ContextCardRow(
                                        card: ctx,
                                        isCurrent: ctx.id == currentContext,
                                        isHighlighted: searchable && index == highlighted
                                    ) {
                                        open(ctx)
                                    }
                                    .id(ctx.id)
                                }
                            }
                        }
                        .onChange(of: highlighted) { _, new in
                            guard matches.indices.contains(new) else { return }
                            withAnimation(Motion.stateChange) {
                                scroller.scrollTo(matches[new].id, anchor: .center)
                            }
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
        }
        .frame(width: 480, height: 520)
        .task {
            load()
            searchFocused = searchable
        }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onExitCommand { dismissWindow(id: "launcher") }
    }

    private func move(_ delta: Int) {
        guard !matches.isEmpty else { return }
        highlighted = min(max(0, highlighted + delta), matches.count - 1)
    }

    private func openHighlighted() {
        guard matches.indices.contains(highlighted) else { return }
        open(matches[highlighted])
    }

    private func open(_ card: ContextCard) {
        // A fresh ref every time, so opening the same cluster twice gives two
        // windows rather than re-focusing the first.
        openWindow(id: "cluster-ctx", value: ClusterRef.next(card.id))
        dismissWindow(id: "launcher")
    }

    private func load() {
        do {
            let config = try KubeConfig.load()
            currentContext = config.currentContext
            contexts = config.contexts.map { entry in
                let raw = UserDefaults.standard.string(forKey: "clusterTint.\(entry.name)") ?? ""
                let server = config.clusters.first(where: { $0.name == entry.cluster })?.server ?? ""
                return ContextCard(
                    id: entry.name,
                    server: server
                        .replacingOccurrences(of: "https://", with: "")
                        .replacingOccurrences(of: "http://", with: ""),
                    tint: Theme.ClusterTint(rawValue: raw) ?? .default
                )
            }
            // Current context floats to the top, the rest stay kubeconfig-ordered.
            contexts.sort { a, b in
                (a.id == currentContext ? 0 : 1, a.id) < (b.id == currentContext ? 0 : 1, b.id)
            }
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct ContextCardRow: View {
    let card: LauncherView.ContextCard
    let isCurrent: Bool
    var isHighlighted = false
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    /// Hover and keyboard selection read the same, so arrowing through the
    /// list feels like moving the pointer down it.
    private var lit: Bool { hovering || isHighlighted }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // The tint as an object, not a dot: a small glowing orb.
                Circle()
                    .fill(card.tint.color)
                    .frame(width: 14, height: 14)
                    .shadow(color: card.tint.color.opacity(0.7), radius: lit ? 7 : 4)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(card.id)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if isCurrent {
                            Text("current")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(Theme.text2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Theme.raised, in: Capsule())
                                .overlay(Capsule().strokeBorder(Theme.lineStrong, lineWidth: 1))
                        }
                    }
                    if !card.server.isEmpty {
                        Text(card.server)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.text3)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.text3)
                    .opacity(lit ? 1 : 0)
                    .offset(x: lit ? 0 : -4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(lit ? Color.white.opacity(scheme == .dark ? 0.10 : 0.55)
                                   : Theme.raised)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(lit ? Theme.lineStrong : Theme.line, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .motion(Motion.stateChange, value: hovering)
        .accessibilityLabel("Open cluster \(card.id)\(isCurrent ? ", current context" : "")")
    }
}
