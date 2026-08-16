import SwiftUI

/// Small pieces every vNext row and detail pane shares. Centralised so a pod
/// row and a cronjob row can't drift apart — the design system lives in code
/// once, not per view.

// MARK: - Status pill

/// State as form before number: a tinted capsule with a leading dot. The dot
/// pulses only for in-progress states, so motion means "working", never
/// decoration.
struct StatusPill: View {
    let text: String
    let color: Color
    var pulses = false

    @State private var dim = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
                .opacity(pulses && dim ? 0.35 : 1)
            Text(text)
                .font(.system(size: 10.5, weight: .semibold))
                .lineLimit(1)
        }
        .fixedSize()
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 2.5)
        .background(Theme.soft(color), in: Capsule())
        .onAppear {
            guard pulses, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever()) { dim = true }
        }
        .accessibilityLabel(text)
    }
}

// MARK: - Metric chip

/// A metric on the row itself: hue answers "what is this number" (blue = CPU,
/// violet = memory) before the number is read; the optional pressure badge
/// answers "should I care".
struct MetricChip: View {
    let icon: String
    let text: String
    /// nil = neutral chip (schedules, hosts); otherwise the metric's hue.
    let hue: Color?
    var pressure: Int? = nil
    /// For unbounded dynamic strings (hostnames, cron schedules): the chip
    /// yields and middle-truncates instead of refusing compression.
    var truncates = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(text)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .truncationMode(truncates ? .middle : .tail)
            if let pressure {
                // Inside its own soft badge, "comfortably below requests" is
                // worth saying in green — unlike a bare number on the canvas,
                // which is where colouring the healthy case went wrong.
                let level = pressure > 85 ? Theme.bad : (pressure > 60 ? Theme.warn : Theme.ok)
                Text("R\(pressure)%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 0.5)
                    .foregroundStyle(level)
                    .background(Theme.soft(level), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .fixedSize(horizontal: !truncates, vertical: true)
        .foregroundStyle(hue ?? Color.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Theme.inset, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.line, lineWidth: 1))
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Namespace badge

/// Shown on rows only in All Namespaces scope — the one situation where a row
/// needs to say where it lives.
struct NamespaceBadge: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .foregroundStyle(.secondary)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
            .lineLimit(1)
    }
}

// MARK: - Stat card

/// The detail pane's summary row: label above, value below, big and tabular.
struct StatCard: View {
    let label: String
    let value: String
    /// The prototype's `<small>` inside the value — "3 / 5", where the total
    /// is context rather than the number you are reading.
    var suffix: String? = nil
    var mono = false
    var valueColor: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(Theme.text3)
            (Text(value)
                .font(.system(size: mono ? 15 : 19, weight: .bold, design: mono ? .monospaced : .default))
                .foregroundStyle(valueColor ?? Theme.text)
             + Text(suffix ?? "")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.text3))
                .kerning(-0.3)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 19)
        .padding(.vertical, 17)
        // No border: the prototype's stat is a raised pane on the canvas, and
        // a hairline around it turned it into a box.
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 14, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - List column chrome (the prototype's listhead / filterrow / rows)

/// Pane header: bold title, muted count subtitle, optional trailing action —
/// the prototype's `.listhead`, living inside the pane instead of the toolbar.
struct PaneHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    private var titleText: some View {
        Text(title)
            .font(.system(size: 26, weight: .medium))
            .kerning(-0.39)
            .foregroundStyle(Theme.text)
            .lineLimit(1)
    }

    private var subtitleText: some View {
        Text(subtitle)
            .font(.system(size: 13))
            .foregroundStyle(Theme.text3)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    var body: some View {
        // The prototype's `.listhead`: the pane's name is a heading, not a
        // label — 26px at medium weight, with the count beside it.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                titleText
                subtitleText
                Spacer(minLength: 4)
                trailing
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    titleText
                    Spacer(minLength: 4)
                    trailing
                }
                subtitleText
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .padding(.bottom, 10)
    }
}

extension PaneHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// The in-pane filter input — an inset well, not a toolbar item.
struct FilterField: View {
    @Environment(\.clusterAccent) private var accent
    let prompt: String
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        TextField(prompt, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .padding(.horizontal, 10)
            .padding(.vertical, 5.5)
            .background(Theme.inset, in: RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(focused ? accent : Theme.line, lineWidth: 1)
            )
            .focused($focused)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .motion(Motion.stateChange, value: focused)
    }
}

/// Row chrome with the prototype's three states: rest, hover (inset), and
/// selected (accent-soft). Applied to row *content*; the List's own selection
/// drawing is disabled with a clear listRowBackground.
struct VNextRow: ViewModifier {
    let isSelected: Bool
    var hoverKey: String? = nil
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                if let hoverKey,
                   ProcessInfo.processInfo.environment["K8SECRET_UITEST_HOVERROW"] == hoverKey {
                    hovering = true
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background {
                // Prototype selection grammar: sel-row fill + theme-aware
                // ring; hover is the recessed wash. Rounded 12 like the
                // prototype's cards-on-canvas rows.
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.selRow)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Theme.selRing, lineWidth: 1)
                        )
                } else if hovering {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.inset)
                }
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .motion(Motion.stateChange, value: hovering)
    }
}

extension View {
    func vnextRow(isSelected: Bool, hoverKey: String? = nil) -> some View {
        modifier(VNextRow(isSelected: isSelected, hoverKey: hoverKey))
    }

    /// Arrow-key selection for the custom lists. The native List selection is
    /// deliberately unused — its focused state paints the system accent over
    /// the row, which is exactly the look the design forbids — so the pane
    /// takes focus itself and moves selection with ↑↓.
    func vnextKeyboardSelection<Item: Identifiable & Equatable>(
        items: @escaping @autoclosure () -> [Item],
        selection: Binding<Item?>
    ) -> some View {
        self
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.downArrow) {
                let list = items()
                guard !list.isEmpty else { return .ignored }
                let i = list.firstIndex { $0.id == selection.wrappedValue?.id }
                selection.wrappedValue = list[min(list.count - 1, (i ?? -1) + 1)]
                return .handled
            }
            .onKeyPress(.upArrow) {
                let list = items()
                guard !list.isEmpty else { return .ignored }
                let i = list.firstIndex { $0.id == selection.wrappedValue?.id }
                selection.wrappedValue = list[max(0, (i ?? 1) - 1)]
                return .handled
            }
    }

    /// The pane-level styling every vNext list column shares.
    func vnextListPane() -> some View {
        self
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.panel)
    }
}

/// Compact empty state — the prototype's small-icon center, not the giant
/// native ContentUnavailableView.
struct EmptyPane: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 13.5, weight: .bold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
        .background(Theme.panel)
    }
}

// MARK: - Underline tabs (the prototype's detail tabs)

struct UnderlineTabBar<Tab: Hashable>: View {
    let tabs: [(Tab, String)]
    @Binding var selection: Tab
    @Namespace private var underline

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.0) { tab, label in
                TabButton(
                    label: label,
                    isActive: selection == tab,
                    namespace: underline
                ) { selection = tab }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
        .motion(Motion.stateChange, value: selection)
    }

    private struct TabButton: View {
        @Environment(\.clusterAccent) private var accent
        let label: String
        let isActive: Bool
        let namespace: Namespace.ID
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                Text(label)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(isActive ? Color.primary : (hovering ? Color.secondary : Color.secondary.opacity(0.7)))
                    .padding(.horizontal, 13)
                    .padding(.top, 7)
                    .padding(.bottom, 9)
                    .overlay(alignment: .bottom) {
                        if isActive {
                            accent
                                .frame(height: 2)
                                .matchedGeometryEffect(id: "underline", in: namespace)
                        }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
        }
    }
}

/// The prototype's rollout ring: a determinate arc, not a spinner. A rollout
/// has a number — showing a spinner instead throws it away.
struct ProgressRing: View {
    let fraction: Double
    var size: CGFloat = 16
    var lineWidth: CGFloat = 3
    @Environment(\.clusterAccent) private var accent

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.soft(accent), lineWidth: lineWidth)
            Circle()
                // A sliver even at zero, so the ring reads as "started".
                .trim(from: 0, to: max(0.03, min(1, fraction)))
                .stroke(accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.5), value: fraction)
        .accessibilityHidden(true)
    }
}

/// "**api** rolling out — 197 of 300 replicas ready … 62%", to the prototype's
/// `.banner` spec: accent ring, accent border, accent-soft fill.
struct RolloutBanner: View {
    let name: String
    let ready: Int
    let total: Int
    var onDismiss: (() -> Void)? = nil
    @Environment(\.clusterAccent) private var accent

    private var fraction: Double { total > 0 ? Double(ready) / Double(total) : 0 }

    var body: some View {
        HStack(spacing: 10) {
            ProgressRing(fraction: fraction)

            (Text(name).bold() + Text(" rolling out — \(ready) of \(total) replicas ready"))
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Text("\(Int((fraction * 100).rounded()))%")
                .font(.system(size: 12.5, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(accent)
                .contentTransition(.numericText())

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.text3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Stop watching this rollout")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Theme.soft(accent), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(accent, lineWidth: 1)
        )
        // Replica counts arrive in steps from the poll; the banner moves
        // between them rather than snapping.
        .animation(.easeInOut(duration: 0.5), value: ready)
        .animation(.easeInOut(duration: 0.5), value: total)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name) rolling out, \(ready) of \(total) replicas ready")
    }
}

// MARK: - Detail chrome (the prototype's breadcrumb + SPEC grammar)

/// The line above every detail pane: `ctx / namespace / type` — where am I,
/// answered before the name.
struct DetailBreadcrumb: View {
    @Environment(AppState.self) private var state
    let type: String

    var body: some View {
        HStack(spacing: 5) {
            Text(state.context)
            Text("/").foregroundStyle(Theme.text3)
            Text(state.allNamespaces ? "all" : (state.selectedNamespace?.name ?? "—"))
            Text("/").foregroundStyle(Theme.text3)
            Text(type)
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.text3)
        .lineLimit(1)
    }
}

/// The prototype's SPEC/PLACEMENT row: muted label column, mono value.
struct KVDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text3)
                .frame(width: 170, alignment: .leading)
            Text(value)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3.5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
