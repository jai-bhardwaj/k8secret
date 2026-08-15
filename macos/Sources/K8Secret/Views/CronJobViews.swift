import SwiftUI

// MARK: - List

struct CronJobsListView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        List(state.filteredCronJobs, selection: $state.selectedCronJob) { cj in
            CronJobRow(cronJob: cj, showNamespace: state.allNamespaces)
                .tag(cj)
        }
        .searchable(text: $state.cronJobSearch, prompt: "Filter cronjobs")
        .navigationTitle("CronJobs")
        .overlay {
            if state.isInitialLoad {
                ProgressView()
            } else if state.cronJobs.isEmpty {
                ContentUnavailableView {
                    Label("No CronJobs", systemImage: "clock")
                } description: {
                    Text(state.allNamespaces
                         ? "No cronjobs in any namespace."
                         : "No cronjobs in this namespace.")
                }
            } else if state.filteredCronJobs.isEmpty {
                ContentUnavailableView.search(text: state.cronJobSearch)
            }
        }
        .motion(Motion.listChange, value: state.cronJobs)
    }
}

struct CronJobRow: View {
    let cronJob: K8sCronJob
    var showNamespace = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Circle()
                    .fill(cronJob.suspended ? Theme.warn : (cronJob.lastRunSucceeded ? Theme.ok : Theme.bad))
                    .frame(width: 8, height: 8)
                Text(cronJob.name)
                    .font(.system(.body, weight: .semibold))
                    .lineLimit(1)
                if showNamespace {
                    NamespaceBadge(name: cronJob.namespace)
                }
                Spacer(minLength: 4)
                statusPill
                Text(cronJob.age)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            HStack(spacing: 6) {
                MetricChip(icon: "clock", text: cronJob.schedule, hue: nil)
                Spacer(minLength: 4)
                Text("last \(cronJob.lastRun)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(cronJob.name), \(cronJob.schedule), last run \(cronJob.lastRun)\(cronJob.suspended ? ", suspended" : "")")
    }

    @ViewBuilder
    private var statusPill: some View {
        if cronJob.suspended {
            StatusPill(text: "Suspended", color: Theme.warn)
        } else if cronJob.active > 0 {
            StatusPill(text: "Running", color: Theme.accent, pulses: true)
        } else if cronJob.lastRunSucceeded {
            StatusPill(text: "Idle", color: Theme.ok)
        } else {
            StatusPill(text: "LastFailed", color: Theme.bad)
        }
    }
}

// MARK: - Detail

struct CronJobDetailView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if let cj = state.selectedCronJob {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(cj)
                    statGrid(cj)
                    scheduleNote(cj)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(cj.name)
        } else {
            ContentUnavailableView {
                Label("No CronJob Selected", systemImage: "clock")
            } description: {
                Text("Choose a cronjob to see its schedule and trigger runs.")
            }
        }
    }

    private func header(_ cj: K8sCronJob) -> some View {
        HStack(spacing: 10) {
            Text(cj.name)
                .font(.title2.weight(.bold))
                .lineLimit(1)
            if cj.suspended { StatusPill(text: "Suspended", color: Theme.warn) }
            Spacer()
            Button(cj.suspended ? "Resume" : "Suspend") {
                toggleSuspend(cj)
            }
            Button("Run now") {
                runNow(cj)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(cj.suspended)
            .help(cj.suspended ? "Resume the schedule before running" : "Start a job outside the schedule")
        }
    }

    private func statGrid(_ cj: K8sCronJob) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
            StatCard(label: "Schedule", value: cj.schedule, mono: true)
            StatCard(label: "Last run", value: cj.lastRun,
                     valueColor: cj.lastRunSucceeded ? nil : Theme.bad)
            StatCard(label: "Active now", value: "\(cj.active)")
            StatCard(label: "Age", value: cj.age)
        }
    }

    private func scheduleNote(_ cj: K8sCronJob) -> some View {
        Text(cj.suspended
             ? "Suspended — scheduled runs are skipped until you resume. Anything already running finishes normally."
             : "Run now starts a job outside the schedule; the scheduled runs are unaffected.")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }

    private func toggleSuspend(_ cj: K8sCronJob) {
        if cj.suspended {
            // Resuming restores what the user already chose; no confirmation.
            Task { await state.setCronJobSuspended(cj, suspended: false) }
        } else {
            state.confirm(
                title: "Suspend \(cj.name)?",
                message: "Scheduled runs stop until you resume. Nothing currently running is affected.",
                confirmLabel: "Suspend",
                destructive: false
            ) { [state] in
                await state.setCronJobSuspended(cj, suspended: true)
            }
        }
    }

    private func runNow(_ cj: K8sCronJob) {
        state.confirm(
            title: "Run \(cj.name) now?",
            message: "Starts a job outside its \(cj.schedule) schedule. The scheduled runs are unaffected.",
            confirmLabel: "Run now",
            destructive: false
        ) { [state] in
            await state.runCronJobNow(cj)
        }
    }

}
