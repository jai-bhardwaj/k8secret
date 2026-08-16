import SwiftUI

// MARK: - Dimensional module icons
//
// The prototype's MODICON set: nine miniature illustrations, one per
// destination, drawn with gradients and a soft ground shadow so they read as
// free-floating objects (CleanMyMac's icon grammar) rather than glyphs.

struct DimensionalIcon: View {
    let destination: AppDestination
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            // Ground shadow: the "it's an object" cue.
            Ellipse()
                .fill(Color.black.opacity(0.30))
                .frame(width: size * 0.72, height: size * 0.16)
                .blur(radius: 1.6)
                .offset(y: size * 0.46)
            art
        }
        .frame(width: size + 8, height: size + 8)
    }

    private func grad(_ a: UInt32, _ b: UInt32) -> LinearGradient {
        LinearGradient(colors: [Color(hex: a), Color(hex: b)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    @ViewBuilder
    private var art: some View {
        switch destination {
        case .overview:
            // Pink monitor on a stand.
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                    .fill(grad(0xF48FEF, 0xC136B9))
                    .frame(width: size * 0.94, height: size * 0.62)
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                            .strokeBorder(.white.opacity(0.35), lineWidth: 0.8)
                    )
                Rectangle().fill(grad(0xD9DCE8, 0xAAB0C4))
                    .frame(width: size * 0.10, height: size * 0.16)
                Capsule().fill(grad(0xEDEFF6, 0xC2C8D8))
                    .frame(width: size * 0.44, height: size * 0.10)
            }
        case .resource(.deployments):
            // Blue faceted cube.
            CubeShape()
                .fill(grad(0x7FB2FF, 0x2D5FD6))
                .overlay(CubeTopShape().fill(.white.opacity(0.32)))
                .frame(width: size * 0.92, height: size * 0.98)
        case .resource(.pods):
            // Teal stacked layers.
            VStack(spacing: -size * 0.18) {
                ForEach(0..<3, id: \.self) { i in
                    RhombusShape()
                        .fill(grad(i == 0 ? 0x63F0C8 : (i == 1 ? 0x35D3A6 : 0x179C79),
                                   i == 0 ? 0x2FC392 : (i == 1 ? 0x18A47E : 0x0D7258)))
                        .frame(width: size * 0.96, height: size * 0.44)
                }
            }
        case .resource(.cronjobs):
            // Amber clock sphere.
            ZStack {
                Circle().fill(grad(0xFFCF7D, 0xDF8A18))
                Circle().fill(
                    RadialGradient(colors: [.white.opacity(0.55), .clear],
                                   center: UnitPoint(x: 0.32, y: 0.26),
                                   startRadius: 0, endRadius: size * 0.5))
                // hands
                Rectangle().fill(Color(hex: 0x6B3E05))
                    .frame(width: size * 0.07, height: size * 0.26).offset(y: -size * 0.11)
                Rectangle().fill(Color(hex: 0x6B3E05))
                    .frame(width: size * 0.22, height: size * 0.07)
                    .offset(x: size * 0.09)
            }
            .frame(width: size * 0.92, height: size * 0.92)
        case .resource(.services):
            // Violet opposing arrows.
            VStack(spacing: size * 0.10) {
                ArrowShape().fill(grad(0xC0A6FF, 0x7B4FE8))
                    .frame(width: size * 0.95, height: size * 0.34)
                ArrowShape().fill(grad(0x9E7BFF, 0x5F32C8))
                    .frame(width: size * 0.95, height: size * 0.34)
                    .scaleEffect(x: -1)
            }
        case .resource(.ingresses):
            // Blue globe with meridians.
            ZStack {
                Circle().fill(grad(0x8FD0FF, 0x2E7BC8))
                Circle().strokeBorder(.white.opacity(0.55), lineWidth: 0.8)
                Ellipse().strokeBorder(.white.opacity(0.5), lineWidth: 0.8)
                    .frame(width: size * 0.45, height: size * 0.92)
                Rectangle().fill(.white.opacity(0.5)).frame(height: 0.8)
            }
            .frame(width: size * 0.92, height: size * 0.92)
        case .resource(.secrets):
            // Pink padlock.
            VStack(spacing: -size * 0.05) {
                RoundedRectangle(cornerRadius: size * 0.18)
                    .strokeBorder(grad(0xF7B3C8, 0xD8577E), lineWidth: size * 0.11)
                    .frame(width: size * 0.46, height: size * 0.42)
                RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                    .fill(grad(0xF585A8, 0xC22D5B))
                    .frame(width: size * 0.78, height: size * 0.58)
                    .overlay(Circle().fill(Color(hex: 0x7A1030)).frame(width: size * 0.14))
            }
        case .resource(.configmaps):
            // Green sliders box.
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                .fill(grad(0xAEE07C, 0x5D9A22))
                .frame(width: size * 0.92, height: size * 0.80)
                .overlay(
                    VStack(spacing: size * 0.14) {
                        ForEach(0..<2, id: \.self) { i in
                            HStack(spacing: 2) {
                                Capsule().fill(.white.opacity(0.85)).frame(height: size * 0.08)
                                Circle().fill(.white).frame(width: size * 0.14)
                                    .offset(x: i == 0 ? -size * 0.18 : size * 0.12)
                            }
                            .padding(.horizontal, size * 0.14)
                        }
                    }
                )
        case .events:
            // Coral pulse orb.
            ZStack {
                Circle().fill(grad(0xFFAB8F, 0xE05430))
                Circle().fill(
                    RadialGradient(colors: [.white.opacity(0.5), .clear],
                                   center: UnitPoint(x: 0.3, y: 0.25),
                                   startRadius: 0, endRadius: size * 0.5))
                PulseShape()
                    .stroke(.white, style: StrokeStyle(lineWidth: size * 0.08, lineCap: .round, lineJoin: .round))
                    .frame(width: size * 0.62, height: size * 0.34)
            }
            .frame(width: size * 0.92, height: size * 0.92)
        }
    }
}

private struct CubeShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let midX = r.midX, topY = r.minY, third = r.height * 0.28
        p.move(to: CGPoint(x: midX, y: topY))
        p.addLine(to: CGPoint(x: r.maxX, y: topY + third))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - third))
        p.addLine(to: CGPoint(x: midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - third))
        p.addLine(to: CGPoint(x: r.minX, y: topY + third))
        p.closeSubpath()
        return p
    }
}

private struct CubeTopShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let midX = r.midX, third = r.height * 0.28
        p.move(to: CGPoint(x: midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + third))
        p.addLine(to: CGPoint(x: midX, y: r.minY + third * 2))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + third))
        p.closeSubpath()
        return p
    }
}

private struct RhombusShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.midY))
        p.closeSubpath()
        return p
    }
}

private struct ArrowShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let shaftH = r.height * 0.44, headW = r.width * 0.34
        let y0 = r.midY - shaftH / 2, y1 = r.midY + shaftH / 2
        p.move(to: CGPoint(x: r.minX, y: y0))
        p.addLine(to: CGPoint(x: r.maxX - headW, y: y0))
        p.addLine(to: CGPoint(x: r.maxX - headW, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX - headW, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - headW, y: y1))
        p.addLine(to: CGPoint(x: r.minX, y: y1))
        p.closeSubpath()
        return p
    }
}

private struct PulseShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.width * 0.25, y: r.midY))
        p.addLine(to: CGPoint(x: r.width * 0.40, y: r.minY))
        p.addLine(to: CGPoint(x: r.width * 0.60, y: r.maxY))
        p.addLine(to: CGPoint(x: r.width * 0.75, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        return p
    }
}

// MARK: - Sidebar rail
//
// The prototype's sideslot: 208pt expanded, 56pt collapsed rail of floating
// icons; hovering the collapsed rail opens a 216pt glass flyout OVER the
// content (the rail keeps its 56pt layout width — the flyout is an overlay).
// Zone separation is a whisper wash plus a ghost-white hairline that fades
// out before the corners; there are no borders anywhere (transparent borders
// seam on Retina — the flyout's edge ring is an inner shadow line).

struct VNextSidebar: View {
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var scheme
    @State private var flyout = false
    @State private var hoverGen = 0

    var body: some View {
        let collapsed = state.sidebarCollapsed
        ZStack(alignment: .topLeading) {
            // Layout slot: reserves rail width only.
            railContent(collapsed: collapsed)
                .frame(width: collapsed ? 56 : 208)
        }
        .frame(width: collapsed ? 56 : 208)
        .background(alignment: .leading) { zoneWash }
        .overlay(alignment: .trailing) { hairline }
        .overlay(alignment: .topLeading) {
            if collapsed && flyout {
                flyoutPanel
                    .onHover { setFlyout($0) }
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .onHover { inside in
            guard state.sidebarCollapsed else { return }
            setFlyout(inside)
        }
        .animation(Theme.easeOut, value: collapsed)
        .zIndex(20)
    }

    /// Rail and panel share one intent: the flyout stays open while the
    /// pointer is over EITHER. Closing waits a beat so crossing the gap
    /// between rail and panel never flickers it shut (the prototype's
    /// "closing randomly while hovering" bug, pre-fixed here).
    private func setFlyout(_ inside: Bool) {
        hoverGen += 1
        let gen = hoverGen
        if inside {
            withAnimation(Theme.easeOut) { flyout = true }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                // A newer hover event (re-entry) supersedes this close.
                guard gen == hoverGen else { return }
                withAnimation(Theme.easeOut) { flyout = false }
            }
        }
    }

    // The whisper zone wash: barely darker than the canvas, fading right.
    private var zoneWash: some View {
        LinearGradient(
            stops: [
                .init(color: washInk.opacity(scheme == .dark ? 0.08 : 0.05), location: 0),
                .init(color: washInk.opacity(scheme == .dark ? 0.04 : 0.025), location: 0.7),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading, endPoint: .trailing
        )
        .allowsHitTesting(false)
    }

    private var washInk: Color { scheme == .dark ? .black : Color(hex: 0x2E1E4E) }

    // Ghost-white light-catch line: 1pt, fades at both tips, never touches
    // the window corners (52pt top / 88pt bottom insets from the prototype).
    private var hairline: some View {
        Rectangle()
            .fill(scheme == .dark ? Color.white.opacity(0.12) : Color(hex: 0x2A1A4F).opacity(0.09))
            .frame(width: 1)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.18),
                        .init(color: .black, location: 0.82),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom)
            )
            .padding(.top, 52)
            .padding(.bottom, 88)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func railContent(collapsed: Bool) -> some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: collapsed ? .center : .leading, spacing: collapsed ? 8 : 2) {
                    ForEach(NavGroup.all) { group in
                        if let label = group.label, !collapsed {
                            Text(label.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .kerning(0.9)
                                .foregroundStyle(Theme.text3)
                                .padding(.horizontal, 12)
                                .padding(.top, 12)
                                .padding(.bottom, 4)
                        }
                        ForEach(group.items, id: \.self) { item in
                            if collapsed {
                                CollapsedChip(destination: item,
                                              isSelected: state.selectedDestination == item) {
                                    Task { await state.selectDestination(item) }
                                }
                            } else {
                                ExpandedNavRow(destination: item,
                                               isSelected: state.selectedDestination == item,
                                               count: count(for: item)) {
                                    Task { await state.selectDestination(item) }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, collapsed ? 0 : 8)
                .padding(.top, collapsed ? 14 : 6)
                .frame(maxWidth: .infinity)
            }
            Spacer(minLength: 0)
            if !collapsed { PortForwardsFooter() }
        }
    }

    // The 216pt glass flyout, floating over content while the rail stays 56pt.
    private var flyoutPanel: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(NavGroup.all) { group in
                        if let label = group.label {
                            Text(label.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .kerning(0.9)
                                .foregroundStyle(Theme.text3)
                                .padding(.horizontal, 12)
                                .padding(.top, 12)
                                .padding(.bottom, 4)
                        }
                        ForEach(group.items, id: \.self) { item in
                            ExpandedNavRow(destination: item,
                                           isSelected: state.selectedDestination == item,
                                           count: count(for: item)) {
                                Task { await state.selectDestination(item) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)
            }
            PortForwardsFooter()
        }
        .frame(width: 216)
        .frame(maxHeight: .infinity)
        .floatGlass(radius: 16)
        .overlay(alignment: .trailing) {
            // Edge ring as an inner line, not a border (Retina seam rule).
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 16, topTrailingRadius: 16)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                          bottomTrailingRadius: 16, topTrailingRadius: 16))
    }

    private func count(for destination: AppDestination) -> Int? {
        guard case .resource(let t) = destination else { return nil }
        switch t {
        case .deployments: return state.deployments.count
        case .pods: return state.pods.count
        case .cronjobs: return state.cronJobs.count
        case .services: return state.services.count
        case .ingresses: return state.ingresses.count
        case .secrets: return state.secrets.count
        case .configmaps: return state.configMaps.count
        }
    }
}

/// Expanded row: dimensional icon + label; selected wears a hue-gradient pill
/// with the theme-aware ring; hover is the item-hover wash.
struct ExpandedNavRow: View {
    let destination: AppDestination
    let isSelected: Bool
    let count: Int?
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                DimensionalIcon(destination: destination, size: 20)
                    .scaleEffect(hovering && !isSelected ? 1.12 : 1)
                Text(destination.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.text : Theme.text2)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text3)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6.5)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [hue.opacity(0.30), Color.white.opacity(scheme == .dark ? 0.11 : 0.40)],
                                startPoint: .leading, endPoint: .trailing)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Theme.selRing, lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.25), radius: 11, y: 3)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(hoverWash)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .onAppear {
            if ProcessInfo.processInfo.environment["K8SECRET_UITEST_HOVER"] == destination.title {
                hovering = true
            }
        }
        .motion(Motion.stateChange, value: hovering)
        .accessibilityLabel(count.map { "\(destination.title), \($0)" } ?? destination.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var hue: Color { Theme.moduleHue(destination.moduleKey, scheme: scheme) }
    private var hoverWash: Color {
        scheme == .dark ? Color.white.opacity(0.07) : Color(hex: 0x3A2A5E).opacity(0.07)
    }
}

/// Collapsed rail chip: 44pt, the dimensional icon IS the rail; the selected
/// one sits on a white-glass pill with a lit top edge.
struct CollapsedChip: View {
    let destination: AppDestination
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            DimensionalIcon(destination: destination, size: 22)
                .scaleEffect(hovering && !isSelected ? 1.14 : 1)
                .offset(y: hovering && !isSelected ? -1 : 0)
                .frame(width: 44, height: 44)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(Color.white.opacity(scheme == .dark ? 0.14 : 0.72))
                            .overlay(
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .strokeBorder(
                                        scheme == .dark ? Color.white.opacity(0.12)
                                                        : Color(hex: 0x3A2A5E).opacity(0.19),
                                        lineWidth: 1)
                            )
                            .overlay(alignment: .top) {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(.white.opacity(scheme == .dark ? 0.2 : 0.9))
                                    .frame(height: 1)
                                    .padding(.horizontal, 4)
                            }
                            .shadow(color: .black.opacity(0.15), radius: 9, y: 3)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .motion(Motion.stateChange, value: hovering)
        .accessibilityLabel(destination.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(destination.title)
    }
}

/// The prototype's sidebar anchor: active forwards always visible.
struct PortForwardsFooter: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let mine = PortForwardManager.shared.forwards.filter { $0.context == state.context }
        VStack(alignment: .leading, spacing: 4) {
            Text("PORT FORWARDS")
                .font(.system(size: 9.5, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(Theme.text3)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            if mine.isEmpty {
                Text("None active")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.text3)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            } else {
                ForEach(mine) { fwd in
                    PortForwardChip(forward: fwd)
                }
                Spacer().frame(height: 8)
            }
        }
    }
}

struct PortForwardChip: View {
    let forward: PortForward
    @State private var hovering = false
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(forward.status == .active ? Theme.ok : Theme.warn)
                .frame(width: 6, height: 6)
                .opacity(pulse ? 0.35 : 1)
            Text(":\(String(forward.localPort)) → \(forward.displayName)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.text2)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                PortForwardManager.shared.stop(id: forward.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(hovering ? Theme.bad : Theme.text3)
            }
            .buttonStyle(.borderless)
            .help("Stop forwarding \(forward.displayName)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(hovering ? Theme.inset : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        .padding(.horizontal, 8)
        .onHover { hovering = $0 }
        .onAppear {
            guard forward.status == .active, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.0).repeatForever()) { pulse = true }
        }
    }
}

extension AppDestination {
    /// Key into Theme.moduleHue.
    var moduleKey: String {
        switch self {
        case .overview: return "overview"
        case .events: return "events"
        case .resource(let t):
            switch t {
            case .deployments: return "deployments"
            case .pods: return "pods"
            case .cronjobs: return "cronjobs"
            case .services: return "services"
            case .ingresses: return "ingresses"
            case .secrets: return "secrets"
            case .configmaps: return "configmaps"
            }
        }
    }
}
