import SwiftUI

/// The launch sequence, ported from the approved prototype (transition A).
///
/// The mark assembles from its three nodes, the checklist ticks as `connect`
/// actually progresses, and then the mark **flies into the sidebar** and
/// becomes the Overview icon — the splash resolves into the app rather than
/// being replaced by it.
///
/// Neither end draws the mark. Both publish the rectangle it should occupy
/// (`MarkSlot.launch` here, `MarkSlot.rail` in the sidebar) and one single
/// mark, owned by `ContentView`, moves between those measured rectangles.
/// That is what makes the landing exact: there is never a second copy to
/// cross-fade with, and the target is the icon's real frame at that instant —
/// any window size, compact or not, rail collapsed or expanded.
struct BootView: View {
    let context: String
    let phase: Int
    /// The words leave before the app arrives.
    var copyGone = false

    @State private var assembled = false
    @State private var lit = false
    @Environment(\.clusterAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let steps = ["Reading kubeconfig", "Verifying API server", "Fetching namespaces"]

    var body: some View {
        VStack(spacing: 30) {
            ZStack {
                // Atmosphere: a deep bloom and two soft lights, no ring.
                Circle()
                    .fill(RadialGradient(colors: [accent.opacity(lit ? 0.22 : 0.10), .clear],
                                         center: .center, startRadius: 6, endRadius: 210))
                    .frame(width: 420, height: 420)
                    .blur(radius: 10)
                    .opacity(copyGone ? 0 : 1)

                // The mark's place in the composition — published, not drawn.
                Color.clear
                    .frame(width: 168, height: 168)
                    .markSlot(.launch)
            }
            .frame(height: 200)

            VStack(spacing: 8) {
                Text("Reaching \(context.isEmpty ? "your cluster" : context)")
                    .font(.system(size: 29, weight: .light))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(Self.steps.enumerated()), id: \.offset) { i, title in
                        HStack(spacing: 9) {
                            ZStack {
                                Circle()
                                    .strokeBorder(phase > i ? Color(hex: 0x3FD9B4)
                                                  : (phase == i ? accent : Theme.line),
                                                  lineWidth: 1.5)
                                    .background(Circle().fill(phase > i ? Color(hex: 0x3FD9B4) : .clear))
                                    .frame(width: 13, height: 13)
                                if phase > i {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundStyle(Color(hex: 0x062018))
                                }
                            }
                            Text(title)
                                .font(.system(size: 11.5, weight: .medium))
                                .kerning(0.3)
                                .foregroundStyle(phase > i ? Theme.text : Theme.text3)
                        }
                        .animation(Theme.easeOut, value: phase)
                    }
                }
            }
            .opacity(copyGone ? 0 : (assembled ? 1 : 0))
            .offset(y: assembled ? 0 : 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !reduceMotion else { assembled = true; lit = true; return }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.68)) { assembled = true }
            withAnimation(.easeOut(duration: 0.5).delay(0.45)) { lit = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Connecting to \(context.isEmpty ? "cluster" : context)")
    }
}


/// The two ends of the launch flight. Each publishes a rectangle; the mark
/// itself is drawn once, above both, and animates between them.
enum MarkSlot: Hashable {
    case launch
    case rail
}

struct MarkSlotKey: PreferenceKey {
    static let defaultValue: [MarkSlot: Anchor<CGRect>] = [:]
    static func reduce(value: inout [MarkSlot: Anchor<CGRect>],
                       nextValue: () -> [MarkSlot: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Publish this view's bounds as one end of the launch flight. Attach it
    /// to the mark-sized view itself, never to a padded wrapper — the flight
    /// lands on exactly the rectangle reported here.
    func markSlot(_ slot: MarkSlot) -> some View {
        anchorPreference(key: MarkSlotKey.self, value: .bounds) { [slot: $0] }
    }
}

/// Toolbar controls exist from the first frame — the window's top inset comes
/// with the toolbar, so removing it during the launch would move the content.
/// They are hidden the only way that costs no layout.
struct LaunchHidden: ViewModifier {
    let shown: Bool
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .disabled(!shown)
            .accessibilityHidden(!shown)
    }
}

/// Whether this session has already played the launch. Per-process, so a new
/// window is instant while a relaunch is still an occasion.
@MainActor
enum LaunchCeremony {
    static var played = false
}
