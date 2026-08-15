import SwiftUI

/// The cross-cutting event feed: everything the cluster said recently, newest
/// first, with warnings separable — the view the per-resource Events tabs
/// can't give.
struct EventsFeedView: View {
    @Environment(AppState.self) private var state
    @State private var warningsOnly = false

    private var shown: [K8sEvent] {
        warningsOnly ? state.clusterEvents.filter { $0.type != "Normal" } : state.clusterEvents
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Events").font(.title3.weight(.bold))
                    Text("all namespaces · newest first")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Toggle("Warnings only", isOn: $warningsOnly)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            if state.loadingClusterEvents && state.clusterEvents.isEmpty {
                Spacer(); ProgressView().frame(maxWidth: .infinity); Spacer()
            } else if shown.isEmpty {
                ContentUnavailableView {
                    Label(warningsOnly ? "No warnings" : "No events",
                          systemImage: warningsOnly ? "checkmark.circle" : "waveform.path.ecg")
                } description: {
                    Text(warningsOnly ? "Nothing needs attention right now."
                                      : "The cluster hasn't reported anything recently.")
                }
            } else {
                List(shown) { event in
                    EventFeedRow(event: event)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Events")
        .task { await state.loadClusterEvents() }
        .refreshable { await state.loadClusterEvents() }
        .motion(Motion.listChange, value: state.clusterEvents)
    }
}

struct EventFeedRow: View {
    let event: K8sEvent

    private var isWarning: Bool { event.type != "Normal" }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(event.lastSeen.map { formatAge($0) + " ago" } ?? "—")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 64, alignment: .leading)
                .padding(.top, 1)

            RoundedRectangle(cornerRadius: 2)
                .fill(isWarning ? Theme.warn : Theme.ok)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(event.reason.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .kerning(0.5)
                        .foregroundStyle(isWarning ? Theme.warn : Color.secondary)
                    if event.count > 1 {
                        Text("×\(event.count)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(event.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isWarning ? "Warning" : "Event"): \(event.reason), \(event.message)")
    }
}
