import SwiftUI

/// First run and post-update moments — the two times the app should introduce
/// itself. Both are in-window glass panels on the canvas, like every other
/// floating surface, so the first thing a new user sees is the design.
enum Welcome {
    /// Bumped whenever the "what's new" copy below changes.
    static let seenVersionKey = "welcome.lastSeenVersion"
    static let firstRunKey = "welcome.completedFirstRun"

    /// What this build should announce after an update.
    static let highlights: [(String, String)] = [
        ("A new world", "One luminous canvas per cluster — the color you pick paints the whole window, so prod is unmistakable."),
        ("Overview that answers first", "A health ring, what needs attention, and the busiest pods, before you drill in."),
        ("⌘N picks the cluster", "New Window opens a chooser; the status bar switches context in place."),
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
    let onDone: () -> Void

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
                            .fill(Theme.accent)
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

            HStack {
                Spacer()
                Button("Continue") { onDone() }
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

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let angle = Double(i) * 120 - 90
                MarkCube()
                    .fill(LinearGradient(colors: colors(i), startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: size * 0.40, height: size * 0.44)
                    .offset(x: cos(angle * .pi / 180) * size * 0.26,
                            y: sin(angle * .pi / 180) * size * 0.24)
            }
            MarkCube()
                .fill(LinearGradient(colors: [.white, Color(hex: 0xC2C8D8)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size * 0.34, height: size * 0.38)
        }
        .frame(width: size, height: size)
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
