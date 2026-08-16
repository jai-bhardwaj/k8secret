import AppKit
import Foundation

/// A debug-only scripted tour of the UI, used to verify pixel parity of every
/// interactive state without synthesized input (which macOS gates behind
/// Accessibility permission).
///
/// Driven entirely by environment variables, so it is inert in every normal
/// launch — nothing here can trigger from a user's environment:
///
///   K8SECRET_UITEST_TOUR=1        run the tour after connect
///   K8SECRET_UITEST_MARKS=/path   directory to write step-marker files into
///   K8SECRET_UITEST_NS=name       namespace the tour uses (default k8stest-ui)
///
/// Each step mutates the same AppState the real controls mutate, waits for the
/// UI to settle, then writes a marker file — an outside process watches the
/// markers and screenshots each state. The tour makes **no cluster writes**:
/// every step is navigation or presentation.
@MainActor
enum UITestTour {
    static func startIfRequested(state: AppState) {
        let env = ProcessInfo.processInfo.environment
        guard env["K8SECRET_UITEST_TOUR"] == "1",
              let marks = env["K8SECRET_UITEST_MARKS"] else { return }
        let ns = env["K8SECRET_UITEST_NS"] ?? "k8stest-ui"

        // Armed marker first: distinguishes "tour never started" from "stuck
        // waiting for connect" when diagnosing from outside.
        FileManager.default.createFile(
            atPath: (marks as NSString).appendingPathComponent("00-armed"), contents: nil)

        Task {
            func settle(_ seconds: Double = 1.2) async {
                try? await Task.sleep(for: .seconds(seconds))
            }
            func mark(_ name: String) {
                FileManager.default.createFile(
                    atPath: (marks as NSString).appendingPathComponent(name), contents: nil)
            }

            // Wait until connected and namespaces exist.
            while state.connectionState != .connected || state.namespaces.isEmpty {
                await settle(0.5)
            }
            mark("00-connected")

            // Window size override for responsive verification runs.
            if let spec = env["K8SECRET_UITEST_SIZE"] {
                let parts = spec.split(separator: "x").compactMap { Double($0) }
                if parts.count == 2, let w = NSApplication.shared.windows.first(where: { $0.isVisible }) {
                    w.setFrame(NSRect(x: 60, y: 80, width: parts[0], height: parts[1]), display: true)
                }
                await settle(0.8)
            }

            // 1. Scope to the seeded namespace.
            if let target = state.namespaces.first(where: { $0.name == ns }) {
                state.selectedNamespace = target
                await state.selectNamespace(target)
            }
            await settle(); mark("01-namespace")

            // 2. Pods list with rows (chips, pills, crashloop).
            await state.selectResourceType(.pods)
            await settle(); mark("02-pods-list")

            // 3. Select a pod → detail Overview (selected-row fill visible).
            if let pod = state.pods.first(where: { $0.phase == "Running" }) ?? state.pods.first {
                state.selectedPod = pod
                await state.selectPod(pod)
            }
            await settle(1.6); mark("03-pod-selected")

            // 4–5. Tabs: Logs (full height), then Events — underline moves.
            state.podDetailTab = .logs
            await settle(1.6); mark("04-pod-logs")
            state.podDetailTab = .events
            await settle(1.4); mark("05-pod-events")
            state.podDetailTab = .overview

            // 6. Toast, exactly as a copy action would fire it.
            state.showToast("API_TOKEN copied — clipboard clears in 30 s")
            await settle(0.8); mark("06-toast")
            await settle(2.5)   // let it dismiss

            // 7. Command palette overlay.
            state.paletteOpen = true
            await settle(); mark("07-palette")
            await settle(1.5)
            state.paletteOpen = false
            await settle(0.5)

            // 8. Settings sheet (tints, appearance, feedback).
            state.settingsOpen = true
            await settle(1.4); mark("08-settings")
            await settle(1.5)
            state.settingsOpen = false
            await settle(0.6)

            // 9. Secrets interior: masked rows.
            await state.selectResourceType(.secrets)
            if let secret = state.secrets.first {
                state.selectedSecret = secret
                await state.selectSecret(secret)
            }
            await settle(1.6); mark("09-secret-masked")

            // 10. Export sheet.
            state.secretExportOpen = true
            await settle(1.2); mark("10-export")
            await settle(1.5)
            state.secretExportOpen = false
            await settle(0.5)

            // 11. CronJobs view.
            await state.selectResourceType(.cronjobs)
            if let cj = state.cronJobs.first { state.selectedCronJob = cj }
            await settle(1.4); mark("11-cronjobs")

            // 12. Deployment detail with the crashloop banner + conditions.
            await state.selectResourceType(.deployments)
            if let dep = state.deployments.first(where: { $0.readyReplicas < $0.replicas }) ?? state.deployments.first {
                state.selectedDeployment = dep
            }
            await settle(1.4); mark("12-deployment")

            // 13. All Namespaces scope with badges.
            await state.selectNamespaceScope(all: true)
            await state.selectResourceType(.pods)
            await settle(1.6); mark("13-all-namespaces")

            // 13b–13e. The remaining destinations, each with a selection,
            // so every nav item's list + detail is screenshot-verified.
            await state.selectNamespaceScope(all: false)
            if let target = state.namespaces.first(where: { $0.name == ns }) {
                state.selectedNamespace = target
                await state.selectNamespace(target)
            }
            await state.selectResourceType(.services)
            if let svc = state.services.first { state.selectedService = svc; await state.selectService(svc) }
            await settle(1.4); mark("13b-services")

            await state.selectResourceType(.ingresses)
            if let ing = state.ingresses.first { state.selectedIngress = ing }
            await settle(1.4); mark("13c-ingresses")

            await state.selectResourceType(.configmaps)
            if let cm = state.configMaps.first { state.selectedConfigMap = cm; await state.selectConfigMap(cm) }
            await settle(1.4); mark("13d-configmaps")

            await state.selectDestination(.events)
            await settle(1.6); mark("13e-events")
            await state.selectDestination(.resource(.pods))
            await settle(0.6)

            // 14. Collapsed rail: the dimensional icons ARE the rail.
            state.sidebarCollapsed = true
            await settle(1.2); mark("14-collapsed-rail")
            await settle(1.5)   // hold for the capture
            state.sidebarCollapsed = false
            await settle(0.6)

            // 15. Confirm dialog — in-window luminous glass.
            state.confirmAction = AppState.ConfirmAction(
                title: "Restart web?",
                message: "A rolling restart replaces every pod with a fresh one, keeping the service up throughout.",
                confirmLabel: "Rolling restart",
                destructive: false,
                action: {})
            await settle(1.2); mark("15-confirm-dialog")
            await settle(1.5)
            state.confirmAction = nil
            await settle(0.5)

            // 16. Rose canvas — the prod tint painting the whole world.
            let originalTint = state.clusterTint
            state.clusterTint = .rose
            await settle(1.2); mark("16-tint-rose")
            await settle(1.5)
            state.clusterTint = originalTint
            await settle(0.5)

            // 17. Light appearance, then restore.
            let originalAppearance = NSApplication.shared.appearance
            NSApplication.shared.appearance = NSAppearance(named: .aqua)
            await settle(1.4); mark("17-light-mode")
            await settle(1.5)
            NSApplication.shared.appearance = originalAppearance
            await settle(0.5)

            // 18. Cluster switcher rising from the status bar.
            state.clusterSwitcherOpen = true
            await settle(1.2); mark("18-cluster-switcher")
            await settle(1.5)
            state.clusterSwitcherOpen = false
            await settle(0.4)

            mark("99-done")
        }
    }
}
