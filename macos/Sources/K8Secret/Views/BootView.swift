import SwiftUI

/// The launch sequence, ported from the approved prototype (transition A).
///
/// The mark assembles from its three nodes, the checklist ticks as `connect`
/// actually progresses, and then the mark **flies into the sidebar** and
/// becomes the Overview icon — the splash resolves into the app rather than
/// being replaced by it.
///
/// The flight uses `matchedGeometryEffect`, so the landing position and size
/// are correct by construction at any window size, in compact mode, and with
/// the rail collapsed or expanded — no coordinate measuring, and none of the
/// "lands slightly off" bugs that class of code invites.
struct BootView: View {
    let context: String
    let phase: Int
    /// Shared with the sidebar's Overview icon; the mark travels between them.
    let namespace: Namespace.ID
    /// True once the app owns the mark — the launch stops drawing it then.
    let handedOff: Bool

    @State private var assembled = false
    @State private var lit = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let steps = ["Reading kubeconfig", "Verifying API server", "Fetching namespaces"]

    var body: some View {
        VStack(spacing: 30) {
            ZStack {
                // Atmosphere: a deep bloom and two soft lights, no ring.
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: 0x8E6BFF).opacity(lit ? 0.22 : 0.10), .clear],
                                         center: .center, startRadius: 6, endRadius: 210))
                    .frame(width: 420, height: 420)
                    .blur(radius: 10)

                if !handedOff {
                    ClusterMark(size: 168)
                        .matchedGeometryEffect(id: "appMark", in: namespace, isSource: true)
                        .scaleEffect(assembled ? 1 : 0.42)
                        .opacity(assembled ? 1 : 0)
                        .blur(radius: assembled ? 0 : 7)
                        .shadow(color: .black.opacity(0.45), radius: 22, y: 16)
                        .overlay {
                            // The strike: a hot core flare at the moment it locks.
                            Circle()
                                .fill(RadialGradient(colors: [.white.opacity(0.9), .clear],
                                                     center: .center, startRadius: 0, endRadius: 60))
                                .frame(width: 120, height: 120)
                                .blur(radius: 2)
                                .opacity(lit ? 0 : 0)
                        }
                }
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
                                                  : (phase == i ? Color(hex: 0x8E6BFF) : Theme.line),
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
            .opacity(assembled ? 1 : 0)
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
