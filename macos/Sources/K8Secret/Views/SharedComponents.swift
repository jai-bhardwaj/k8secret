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
        }
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

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(text)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            if let pressure {
                Text("R\(pressure)%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 0.5)
                    .foregroundStyle(Theme.pressure(pressure))
                    .background(Theme.soft(Theme.pressure(pressure)), in: RoundedRectangle(cornerRadius: 4))
            }
        }
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
    var mono = false
    var valueColor: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .kerning(0.7)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: mono ? 14 : 18, weight: .bold, design: mono ? .monospaced : .default))
                .foregroundStyle(valueColor ?? .primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.line, lineWidth: 1))
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

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
            Text(subtitle)
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 4)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.top, 13)
        .padding(.bottom, 9)
    }
}

extension PaneHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// The in-pane filter input — an inset well, not a toolbar item.
struct FilterField: View {
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
                    .strokeBorder(focused ? Theme.accent : Theme.line, lineWidth: 1)
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
            .padding(.vertical, 2)
            .background(
                isSelected ? Theme.soft(Theme.accent) : (hovering ? Theme.inset : Color.clear),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .motion(Motion.stateChange, value: hovering)
    }
}

extension View {
    func vnextRow(isSelected: Bool, hoverKey: String? = nil) -> some View {
        modifier(VNextRow(isSelected: isSelected, hoverKey: hoverKey))
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
                            Theme.accent
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
