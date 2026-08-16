import SwiftUI

/// The launch sequence: the node-cluster mark assembles from its three nodes,
/// settles into a slow breath, and names the cluster it is reaching. The app's
/// first frame should look like the app, not like a system spinner.
struct BootView: View {
    let context: String

    @State private var assembled = false
    @State private var breathing = false
    @State private var textIn = false
    @State private var spin = false
    @State private var sweep = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 26) {
            ZStack {
                // The glow the mark sits in.
                Circle()
                    .fill(
                        RadialGradient(colors: [Color(hex: 0x8E6BFF).opacity(breathing ? 0.34 : 0.16), .clear],
                                       center: .center, startRadius: 4, endRadius: 130)
                    )
                    .frame(width: 260, height: 260)

                // Each node flies in from its own direction, then holds.
                ForEach(0..<3, id: \.self) { i in
                    let angle = Double(i) * 120 - 90
                    BootCube()
                        .fill(
                            LinearGradient(colors: nodeColors(i),
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 46, height: 51)
                        .offset(x: cos(angle * .pi / 180) * (assembled ? 30 : 96),
                                y: sin(angle * .pi / 180) * (assembled ? 28 : 96))
                        .opacity(assembled ? 1 : 0)
                        .rotationEffect(.degrees(assembled ? 0 : -40))
                        .animation(.spring(response: 0.75, dampingFraction: 0.72)
                            .delay(Double(i) * 0.09), value: assembled)
                }

                // The core lands last — the cluster is whole.
                BootCube()
                    .fill(LinearGradient(colors: [.white, Color(hex: 0xC2C8D8)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 39, height: 44)
                    .scaleEffect(assembled ? 1 : 0.2)
                    .opacity(assembled ? 1 : 0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.68).delay(0.3), value: assembled)
            }
            .scaleEffect(breathing ? 1.04 : 1)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .overlay {
                // A light sweeping across the mark, like a scan pass.
                LinearGradient(colors: [.clear, .white.opacity(0.55), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 90)
                    .rotationEffect(.degrees(18))
                    .offset(x: sweep ? 170 : -170)
                    .blendMode(.plusLighter)
                    .mask(ClusterMark(size: 150))
                    .allowsHitTesting(false)
            }

            VStack(spacing: 6) {
                Text(context.isEmpty ? "Reaching your cluster" : "Reaching \(context)")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("reading the kubeconfig and verifying the API server")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text3)
            }
            .opacity(textIn ? 1 : 0)
            .offset(y: textIn ? 0 : 8)
            .animation(Theme.easeOut.delay(0.42), value: textIn)

            // Indeterminate hairline: motion that says "working", not a spinner.
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                Capsule()
                    .fill(LinearGradient(colors: [Color(hex: 0x63F0C8), Color(hex: 0x8E6BFF)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: 84)
                    .offset(x: sweep ? 116 : -116)
            }
            .frame(width: 200, height: 3)
            .opacity(textIn ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !reduceMotion else { assembled = true; textIn = true; return }
            assembled = true
            textIn = true
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                breathing = true
            }
            withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) {
                spin = true
            }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false).delay(0.6)) {
                sweep = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Connecting to \(context.isEmpty ? "cluster" : context)")
    }

    private func nodeColors(_ i: Int) -> [Color] {
        switch i {
        case 0: return [Color(hex: 0x7FB2FF), Color(hex: 0x2D5FD6)]
        case 1: return [Color(hex: 0x63F0C8), Color(hex: 0x1FA98C)]
        default: return [Color(hex: 0xF48FEF), Color(hex: 0xC136B9)]
        }
    }
}

/// The mark's cube silhouette, at boot scale.
private struct BootCube: Shape {
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
