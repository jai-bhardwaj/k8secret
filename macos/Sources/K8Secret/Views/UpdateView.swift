import SwiftUI

struct UpdateBannerView: View {
    @Bindable var checker: UpdateChecker
    @State private var showDetails = false

    var body: some View {
        if checker.updateAvailable, let release = checker.latestRelease {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Update Available — v\(release.version)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))

                        if let date = release.date {
                            Text(date)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if checker.downloading {
                        ProgressView(value: checker.downloadProgress)
                            .frame(width: 100)
                        Text(verbatim: "\(Int(checker.downloadProgress * 100))%")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .trailing)
                    } else {
                        Button("Details") {
                            showDetails.toggle()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)

                        Button("Update") {
                            Task { await checker.downloadAndInstall() }
                        }
                        .buttonStyle(Theme.PrimaryPill())
                        .controlSize(.small)

                        Button {
                            checker.dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                if showDetails {
                    Divider()
                    ScrollView {
                        Text(release.notes)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(maxHeight: 120)
                }
            }
            .background(.blue.opacity(0.06))
            .overlay(alignment: .bottom) { Divider() }
        }

        if let error = checker.error {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    checker.error = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.orange.opacity(0.06))
            .overlay(alignment: .bottom) { Divider() }
        }
    }
}

struct UpdateSheetView: View {
    @Environment(AppState.self) private var state
    @Bindable var checker: UpdateChecker
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            if checker.checking {
                ProgressView("Checking for updates...")
                    .padding(40)
            } else if let release = checker.latestRelease, checker.updateAvailable {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.blue)

                    Text("K8Secret v\(release.version)")
                        .font(.system(size: 17, weight: .bold, design: .monospaced))

                    Text("You're on v\(AppConstants.version)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Divider()

                    ScrollView {
                        Text(release.notes)
                            .font(.system(size: 12.5, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)

                    if checker.downloading {
                        VStack(spacing: 4) {
                            ProgressView(value: checker.downloadProgress)
                            Text("Downloading... \(Int(checker.downloadProgress * 100))%")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Button("Later") { dismiss() }
                            .keyboardShortcut(.cancelAction)

                        Spacer()

                        Button("Download & Install") {
                            Task { await checker.downloadAndInstall() }
                        }
                        .buttonStyle(Theme.PrimaryPill())
                        .disabled(checker.downloading)
                        .keyboardShortcut(.defaultAction)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.green)

                    Text("You're up to date!")
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))

                    Text("K8Secret v\(AppConstants.version) is the latest version.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Button("OK") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                        .padding(.top, 8)
                }
            }

            if let error = checker.error {
                Text(error)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.red)
            }
        }
        .padding(24)
        .frame(width: 400)
        .background(Theme.CanvasBackground(tint: state.clusterTint, hero: false))
    }
}
