import SwiftUI

/// Shared motion vocabulary.
///
/// Two reasons this is central rather than sprinkled through the views. Values
/// arrive on their own here — a watch stream inserts and removes rows while the
/// user is reading — so the motion telling them what changed has to be
/// consistent, not per-view improvisation. And every one of these has to honour
/// Reduce Motion: animation in a tool people keep open all day is a liability if
/// it can't be turned off.
enum Motion {
    /// Rows appearing or leaving a list.
    static let listChange = Animation.easeOut(duration: 0.22 * scale)
    /// Small state flips — a spinner, a badge, a reveal.
    static let stateChange = Animation.easeOut(duration: 0.15 * scale)
    /// Panels and banners entering or leaving.
    static let panel = Animation.easeInOut(duration: 0.25 * scale)

    /// Debug-only: stretches every duration so a 250ms transition can be
    /// inspected frame by frame. Inert without the environment variable, same
    /// contract as the UI test hooks.
    static let scale: Double = {
        Double(ProcessInfo.processInfo.environment["K8SECRET_UITEST_SLOWMO"] ?? "") ?? 1
    }()
}

extension View {
    /// Animate `value`, unless the user has asked the system for less motion.
    ///
    /// SwiftUI does not apply Reduce Motion to `.animation` automatically, so
    /// without this every transition would keep playing for someone who has
    /// explicitly turned motion off.
    func motion<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(MotionModifier(animation: animation, value: value))
    }
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}
