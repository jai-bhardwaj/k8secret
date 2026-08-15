import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        return VStack(spacing: 0) {
            UpdateBannerView(checker: UpdateChecker.shared)

            ZStack {
                switch state.connectionState {
                case .connecting:
                    connectingView
                case .disconnected(let message):
                    DisconnectedView(message: message)
                case .connected:
                    mainView
                }

                // Toast overlay
                if let msg = state.toastMessage {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            ToastView(message: msg, isError: state.toastIsError)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 40)
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeOut(duration: 0.2), value: state.toastMessage)
                }
            }
            .frame(maxHeight: .infinity)

            StatusBarView()
        }
        .task {
            await state.connect()
            await UpdateChecker.shared.checkForUpdates()
        }
        // Single confirmation surface for every irreversible action, so a new
        // destructive operation can't ship without one by simply forgetting to add
        // an alert to its own view.
        .alert(
            state.confirmAction?.title ?? "",
            isPresented: Binding(
                get: { state.confirmAction != nil },
                set: { if !$0 { state.confirmAction = nil } }
            ),
            presenting: state.confirmAction
        ) { action in
            Button("Cancel", role: .cancel) { state.confirmAction = nil }
            Button(action.confirmLabel, role: action.destructive ? .destructive : nil) {
                let work = action.action
                state.confirmAction = nil
                Task { await work() }
            }
        } message: { action in
            Text(action.message)
        }
    }

    private var connectingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Connecting to cluster...")
                .foregroundStyle(.secondary)
                .font(.body)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mainView: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            contentColumn
        } detail: {
            detailColumn
        }
    }

    @ViewBuilder
    private var contentColumn: some View {
        switch state.selectedResourceType {
        case .secrets:
            SecretsListView()
        case .deployments:
            DeploymentsListView()
        case .pods:
            PodsListView()
        case .services:
            ServicesListView()
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        switch state.selectedResourceType {
        case .secrets:
            SecretDetailView()
        case .deployments:
            DeploymentDetailView()
        case .pods:
            PodDetailView()
        case .services:
            ServiceDetailView()
        }
    }
}

struct ToastView: View {
    let message: String
    let isError: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? .red : .green)
            Text(message)
                .font(.system(.caption, design: .monospaced))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}
