import SwiftUI

struct DisconnectedView: View {
    @Environment(AppState.self) private var state
    let message: String

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)

            Text("Can't reach the cluster")
                .font(.system(size: 16, weight: .bold))

            // The raw error in the prototype's errbox: mono, red hairline —
            // the actual message is the debugging clue, so it gets the frame.
            Text(message)
                .font(.system(size: 12, design: .monospaced))
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: 440)
                .background(Theme.soft(Theme.bad), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.bad, lineWidth: 1))
                .textSelection(.enabled)

            // Context picker — lets the user choose which cluster to connect to
            if !state.availableContexts.isEmpty {
                VStack(spacing: 10) {
                    Text("Select a context to connect")
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 4) {
                        ForEach(state.availableContexts, id: \.self) { ctx in
                            Button {
                                Task { await state.connect(toContext: ctx) }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "server.rack")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 20)

                                    Text(ctx)
                                        .font(.system(.callout, design: .monospaced, weight: .medium))
                                        .lineLimit(1)
                                        .truncationMode(.middle)

                                    Spacer()

                                    Image(systemName: "arrow.right.circle")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .frame(maxWidth: 380)
                }
                .padding()
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 8) {
                hintRow(icon: "terminal", text: "kubectl config use-context <name>")
                hintRow(icon: "doc.text", text: "Check ~/.kube/config exists")
                hintRow(icon: "network", text: "Ensure the cluster is reachable")
            }
            .padding()
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

            Button {
                Task { await state.connect() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(Theme.PrimaryPill())
            .controlSize(.large)
            .tint(Theme.accent)

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func hintRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}
