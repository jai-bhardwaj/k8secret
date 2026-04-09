import SwiftUI

struct DisconnectedView: View {
    @Environment(AppState.self) private var state
    let message: String

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "externaldrive.trianglebadge.exclamationmark")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)

            Text("Not Connected")
                .font(.system(.title, design: .monospaced, weight: .semibold))

            Text(message)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

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
                Label("Retry Connection", systemImage: "arrow.clockwise")
                    .font(.system(.body, design: .monospaced))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.accentColor)

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
