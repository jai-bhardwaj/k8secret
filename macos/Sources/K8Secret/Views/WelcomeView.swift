import SwiftUI

/// First run and post-update moments — the two times the app should introduce
/// itself. Both are in-window glass panels on the canvas, like every other
/// floating surface, so the first thing a new user sees is the design.
enum Welcome {
    /// Bumped whenever the "what's new" copy below changes.
    static let seenVersionKey = "welcome.lastSeenVersion"
    static let firstRunKey = "welcome.completedFirstRun"
    /// The release whose tour was taken. A flag was enough while the tour
    /// only ever ran once; a feature release changes what there is to show.
    static let tourVersionKey = "welcome.tourVersion"
    static let tourKey = "welcome.completedTour"   // legacy flag, read-only

    /// What this build should announce after an update.
    static let highlights: [(String, String)] = [
        ("A window per cluster",
         "Every window is one cluster, painted in its own color — ⌘N opens as many as you need, each with its own namespace, scope and selection."),
        ("It opens like an app",
         "A launch that assembles and hands the window over, a first run that asks which cluster, and a guided tour that points at the real controls rather than pictures of them."),
        ("YAML, a tab away",
         "Every resource shows its live manifest from the API server. Secret values stay covered there — opening a tab is not asking to see them."),
        ("Search wherever you pick",
         "Filter clusters and namespaces by name, with counts beside them and the ones you actually use on top. ⌘K still jumps anywhere in the cluster."),
        ("Fixed: browsing all namespaces",
         "Scoped to every namespace, the app was discarding what it had already fetched — secrets read as empty, logs never arrived, and saving a secret did nothing at all. It works."),
        ("Shown, not just told",
         "This panel now offers the tour, and a release that adds things worth pointing at brings it back. Settings has it whenever you want it again."),
    ]

    static var needsFirstRun: Bool {
        !UserDefaults.standard.bool(forKey: firstRunKey)
    }

    /// True when this build is newer than the one whose notes were seen — and
    /// never on a fresh install, where first run does the introducing.
    static var needsWhatsNew: Bool {
        guard !needsFirstRun else { return false }
        let seen = UserDefaults.standard.string(forKey: seenVersionKey) ?? ""
        return seen != AppConstants.version
    }

    /// The guided tour is offered after the first cluster is chosen, and again
    /// after a feature release — a release that adds things to point at.
    /// Patches don't replay it: nobody wants a five-stop tour for a bug fix.
    static var needsTour: Bool {
        guard let taken = UserDefaults.standard.string(forKey: tourVersionKey) else { return true }
        return featureLine(of: taken) != featureLine(of: AppConstants.version)
    }

    static func completeTour() {
        UserDefaults.standard.set(AppConstants.version, forKey: tourVersionKey)
    }

    /// "0.6.1" → "0.6". The tour replays when this changes, so 0.6.0 → 0.6.1
    /// is quiet and 0.6.x → 0.7.0 is not.
    static func featureLine(of version: String) -> String {
        version.split(separator: ".").prefix(2).joined(separator: ".")
    }

    static func completeFirstRun() {
        UserDefaults.standard.set(true, forKey: firstRunKey)
        UserDefaults.standard.set(AppConstants.version, forKey: seenVersionKey)
    }

    static func markVersionSeen() {
        UserDefaults.standard.set(AppConstants.version, forKey: seenVersionKey)
    }
}

/// First launch: the mark, what the app is, and the contexts it can see —
/// the prototype's first-run screen, connecting straight from a card.
struct FirstRunView: View {
    @Environment(\.clusterAccent) private var accent
    let contexts: [String]
    let onPick: (String) -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            ClusterMark(size: 76)

            VStack(spacing: 7) {
                Text("Welcome to K8Secret")
                    .font(.system(size: 27, weight: .light))
                    .foregroundStyle(Theme.text)
                Text("Pick a kubeconfig context to connect. You can switch any time from the status bar.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if contexts.isEmpty {
                Text("No contexts found in ~/.kube/config.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.warn)
            } else {
                VStack(spacing: 8) {
                    ForEach(contexts.prefix(6), id: \.self) { ctx in
                        Button { onPick(ctx) } label: {
                            HStack(spacing: 10) {
                                Circle().fill(Theme.ClusterTint.default.color).frame(width: 9, height: 9)
                                Text(ctx)
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 12)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.text3)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Theme.line, lineWidth: 1))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text("Secrets are decoded on your Mac and never leave it. No account, no telemetry.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text3)
                .multilineTextAlignment(.center)

            Button("Start with the current context") { onSkip() }
                .buttonStyle(Theme.PrimaryPill())
        }
        .padding(30)
        .frame(width: 460)
        .popGlass(radius: 22)
    }
}

/// After an update: what changed, in three lines, dismissed forever.
struct WhatsNewView: View {
    @Environment(\.clusterAccent) private var accent
    /// `true` when the reader asked to be shown around — a major release is
    /// worth walking through, not just reading about.
    let onDone: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                ClusterMark(size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("What's new")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(Theme.text)
                    Text("K8Secret \(AppConstants.version)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.text3)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Welcome.highlights, id: \.0) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(accent)
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.0)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(Theme.text)
                            Text(item.1)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.text2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Spacer()
                Button("Not now") { onDone(false) }
                    .buttonStyle(Theme.SoftPill())
                Button("Show me around") { onDone(true) }
                    .buttonStyle(Theme.PrimaryPill())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 440)
        .popGlass(radius: 22)
    }
}

/// The app's mark, drawn at any size: three nodes around a bright core.
struct ClusterMark: View {
    var size: CGFloat = 64
    /// 0 = the three nodes are still out on their own axes, 1 = locked
    /// together around the core. Only the launch drives this; everywhere the
    /// mark is just an icon it stays assembled.
    var assembly: Double = 1

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let angle = Double(i) * 120 - 90
                let radians = angle * .pi / 180
                let progress = nodeProgress(i)
                // Each node travels in along the axis it will settle on, so
                // the mark builds itself out of three arrivals instead of
                // growing as one piece.
                let travel = (1 - progress) * size * 0.85
                MarkCube()
                    .fill(LinearGradient(colors: colors(i), startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: size * 0.40, height: size * 0.44)
                    .rotationEffect(.degrees((1 - progress) * -18))
                    .offset(x: cos(radians) * (size * 0.26 + travel),
                            y: sin(radians) * (size * 0.24 + travel))
                    .opacity(progress)
                    .blur(radius: (1 - progress) * size * 0.03)
            }
            // The core lights last: the moment the three lock together.
            MarkCube()
                .fill(LinearGradient(colors: [.white, Color(hex: 0xC2C8D8)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size * 0.34, height: size * 0.38)
                .scaleEffect(0.55 + 0.45 * coreProgress)
                .opacity(coreProgress)
        }
        .frame(width: size, height: size)
    }

    /// Staggered, so the nodes arrive one after another rather than together.
    private func nodeProgress(_ i: Int) -> Double {
        let delay = Double(i) * 0.14
        return min(1, max(0, (assembly - delay) / (1 - delay)))
    }

    private var coreProgress: Double {
        min(1, max(0, (assembly - 0.45) / 0.55))
    }

    private func colors(_ i: Int) -> [Color] {
        switch i {
        case 0: return [Color(hex: 0x7FB2FF), Color(hex: 0x2D5FD6)]
        case 1: return [Color(hex: 0x63F0C8), Color(hex: 0x1FA98C)]
        default: return [Color(hex: 0xF48FEF), Color(hex: 0xC136B9)]
        }
    }
}

private struct MarkCube: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let third = r.height * 0.28
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + third))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - third))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - third))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + third))
        p.closeSubpath()
        return p
    }
}
