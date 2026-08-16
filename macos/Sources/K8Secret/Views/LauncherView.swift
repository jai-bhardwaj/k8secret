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
                    Text("Open a cluster")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(Theme.text)
                    Text("Every window is one cluster — its color follows it everywhere.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.text2)
                }
                .padding(.top, 14)

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
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 8) {
                            ForEach(contexts) { ctx in
                                ContextCardRow(
                                    card: ctx,
                                    isCurrent: ctx.id == currentContext
                                ) {
                                    // A fresh ref every time, so opening the
                                    // same cluster twice gives two windows.
                                    openWindow(id: "cluster-ctx",
                                               value: ClusterRef.next(ctx.id))
                                    dismissWindow(id: "launcher")
                                }
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
        .task { load() }
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
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // The tint as an object, not a dot: a small glowing orb.
                Circle()
                    .fill(card.tint.color)
                    .frame(width: 14, height: 14)
                    .shadow(color: card.tint.color.opacity(0.7), radius: hovering ? 7 : 4)
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
                    .opacity(hovering ? 1 : 0)
                    .offset(x: hovering ? 0 : -4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(hovering ? Color.white.opacity(scheme == .dark ? 0.10 : 0.55)
                                   : Theme.raised)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(hovering ? Theme.lineStrong : Theme.line, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .motion(Motion.stateChange, value: hovering)
        .accessibilityLabel("Open cluster \(card.id)\(isCurrent ? ", current context" : "")")
    }
}
