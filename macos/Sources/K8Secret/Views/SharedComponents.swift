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
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
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
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.separator.opacity(0.5), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
