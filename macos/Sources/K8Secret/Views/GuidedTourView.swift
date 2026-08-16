import SwiftUI

/// The guided tour: five coach marks over the real interface.
///
/// Nothing here is a screenshot or a mock — each stop spotlights the actual
/// control by measuring it (`TourSpotKey`), so the tour cannot drift out of
/// sync with the app the way a hand-drawn onboarding always eventually does.
/// A stop whose control isn't on screen (rail collapsed, window compact) is
/// simply skipped rather than pointing at nothing.
enum TourSpot: Hashable, CaseIterable {
    case rail, namespaceScope, search, secrets, clusterChip
}

struct TourSpotKey: PreferenceKey {
    static let defaultValue: [TourSpot: Anchor<CGRect>] = [:]
    static func reduce(value: inout [TourSpot: Anchor<CGRect>],
                       nextValue: () -> [TourSpot: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Publish this control's bounds so the tour can spotlight it.
    func tourSpot(_ spot: TourSpot) -> some View {
        anchorPreference(key: TourSpotKey.self, value: .bounds) { [spot: $0] }
    }

    /// The same, for one item inside a loop.
    @ViewBuilder
    func tourSpotIf(_ condition: Bool, _ spot: TourSpot) -> some View {
        if condition { tourSpot(spot) } else { self }
    }
}

struct TourStep {
    let spot: TourSpot
    let title: String
    let body: String
    /// Toolbar controls are hosted by NSToolbar, outside SwiftUI's preference
    /// tree, so they cannot be measured — but they also sit *above* the tour's
    /// scrim, so they stay lit on their own. For those stops the card simply
    /// parks under the control's side of the titlebar instead of pretending to
    /// know a rectangle it can't see.
    var titlebar: HorizontalEdge? = nil
}

let tourSteps: [TourStep] = [
    TourStep(spot: .rail,
             title: "Your cluster, by shape",
             body: "Workloads, network and config each keep their own place, and the counts follow whatever scope you're in."),
    TourStep(spot: .namespaceScope,
             title: "One namespace, or all of them",
             body: "The pill above sets your scope. Everything downstream — lists, counts, events, the health ring — follows it.",
             titlebar: .leading),
    TourStep(spot: .search,
             title: "Jump straight to anything",
             body: "⌘K finds a pod, a secret or a namespace by name, wherever in the cluster it lives, and takes you there.",
             titlebar: .trailing),
    TourStep(spot: .secrets,
             title: "Secrets stay covered",
             body: "Values are masked until you ask for them, and nothing leaves the window without you saying so."),
    TourStep(spot: .clusterChip,
             title: "Every window is one cluster",
             body: "Switch clusters here — the color follows the cluster — or press ⌘N to open another one beside this."),
]

/// The overlay itself. Sits above the app, dims everything except the control
/// it is talking about, and moves between stops in one continuous motion.
struct GuidedTourView: View {
    @Binding var step: Int?
    let spots: [TourSpot: Anchor<CGRect>]
    let proxy: GeometryProxy

    @Environment(\.colorScheme) private var scheme

    /// Stops that can be shown here: either their control was measured, or
    /// they live in the titlebar and don't need to be.
    private var visibleSteps: [TourStep] {
        let usable = tourSteps.filter { spots[$0.spot] != nil || $0.titlebar != nil }
        return usable.isEmpty ? tourSteps : usable
    }

    private var current: TourStep? {
        guard let step else { return nil }
        return visibleSteps[min(max(0, step), visibleSteps.count - 1)]
    }

    private var rect: CGRect? {
        guard let current, current.titlebar == nil, let anchor = spots[current.spot] else { return nil }
        return proxy[anchor].insetBy(dx: -8, dy: -8)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let current {
                // The scrim, with the spotlight punched out of it.
                Rectangle()
                    .fill(.black.opacity(0.55))
                    .overlay(alignment: .topLeading) {
                        if let rect {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .frame(width: rect.width, height: rect.height)
                                .offset(x: rect.minX, y: rect.minY)
                                .blendMode(.destinationOut)
                        }
                    }
                    .compositingGroup()
                    .ignoresSafeArea()
                    .onTapGesture { advance(1) }

                if let rect {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.55), lineWidth: 1.5)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .shadow(color: .white.opacity(0.28), radius: 12)
                        .allowsHitTesting(false)
                }

                card(current)
                    .offset(x: cardOrigin.x, y: cardOrigin.y)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: step)
        .onExitCommand { finish() }
    }

    private func card(_ stepModel: TourStep) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(stepModel.title)
                .font(.system(size: 15.5, weight: .semibold))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)

            Text(stepModel.body)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    ForEach(visibleSteps.indices, id: \.self) { i in
                        Circle()
                            .fill(i == (step ?? 0) ? Theme.text : Theme.text3.opacity(0.45))
                            .frame(width: 5, height: 5)
                    }
                }
                Spacer(minLength: 12)
                if (step ?? 0) > 0 {
                    Button("Back") { advance(-1) }
                        .buttonStyle(Theme.SoftPill())
                }
                Button((step ?? 0) == visibleSteps.count - 1 ? "Done" : "Next") { advance(1) }
                    .buttonStyle(Theme.PrimaryPill())
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(width: Self.cardWidth, alignment: .leading)
        .popGlass(radius: 16)
        .shadow(color: .black.opacity(0.35), radius: 26, y: 12)
    }

    private static let cardWidth: CGFloat = 300

    /// Put the card beside the spotlight, on whichever side has room, and keep
    /// it inside the window no matter how small the window is.
    private var cardOrigin: CGPoint {
        let size = proxy.size
        if let edge = current?.titlebar {
            // Just under the titlebar, on the control's own side.
            let x = edge == .leading ? 18 : max(18, size.width - Self.cardWidth - 18)
            return CGPoint(x: x, y: 16)
        }
        guard let rect else {
            return CGPoint(x: (size.width - Self.cardWidth) / 2, y: size.height / 2 - 90)
        }
        let gap: CGFloat = 16
        let estimatedHeight: CGFloat = 170
        var x = rect.maxX + gap
        if x + Self.cardWidth > size.width - 12 {
            x = rect.minX - gap - Self.cardWidth        // flip to the left
        }
        if x < 12 {                                      // no room either side
            x = min(max(12, rect.midX - Self.cardWidth / 2), size.width - Self.cardWidth - 12)
        }
        var y = rect.midY - estimatedHeight / 2
        if rect.maxY > size.height - estimatedHeight { y = rect.minY - estimatedHeight - gap }
        y = min(max(12, y), max(12, size.height - estimatedHeight - 12))
        return CGPoint(x: x, y: y)
    }

    private func advance(_ delta: Int) {
        let next = (step ?? 0) + delta
        if next < 0 { return }
        if next >= visibleSteps.count { finish(); return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { step = next }
    }

    private func finish() {
        Welcome.completeTour()
        withAnimation(Theme.easeOut) { step = nil }
    }
}
