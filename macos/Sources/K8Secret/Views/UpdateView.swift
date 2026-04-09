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
                            .font(.system(.caption, design: .monospaced, weight: .semibold))

                        if let date = release.date {
                            Text(date)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if checker.downloading {
                        ProgressView(value: checker.downloadProgress)
                            .frame(width: 100)
                        Text("\(Int(checker.downloadProgress * 100))%")
                            .font(.system(.caption2, design: .monospaced, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .trailing)
                    } else {
                        Button("Details") {
                            showDetails.toggle()
                        }
                        .buttonStyle(.plain)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)

                        Button("Update") {
                            Task { await checker.downloadAndInstall() }
                        }
                        .buttonStyle(.borderedProminent)
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
                            .font(.system(.caption, design: .monospaced))
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
                    .font(.system(.caption, design: .monospaced))
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
                        .font(.system(.title2, design: .monospaced, weight: .bold))

                    Text("You're on v\(AppConstants.version)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Divider()

                    ScrollView {
                        Text(release.notes)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)

                    if checker.downloading {
                        VStack(spacing: 4) {
                            ProgressView(value: checker.downloadProgress)
                            Text("Downloading... \(Int(checker.downloadProgress * 100))%")
                                .font(.system(.caption, design: .monospaced))
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
                        .buttonStyle(.borderedProminent)
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
                        .font(.system(.title3, design: .monospaced, weight: .semibold))

                    Text("K8Secret v\(AppConstants.version) is the latest version.")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Button("OK") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                        .padding(.top, 8)
                }
            }

            if let error = checker.error {
                Text(error)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.red)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}
