import Foundation
import AppKit

struct AppRelease: Codable {
    let version: String
    let url: String
    let notes: String
    let minOS: String?
    let date: String?
}

@MainActor
@Observable
final class UpdateChecker {
    var latestRelease: AppRelease?
    var updateAvailable = false
    var checking = false
    var downloadProgress: Double = 0
    var downloading = false
    var error: String?

    private var downloadTask: URLSessionDownloadTask?

    static let shared = UpdateChecker()

    func checkForUpdates() async {
        guard !checking else { return }
        checking = true
        error = nil

        defer { checking = false }

        guard let manifestURL = URL(string: AppConstants.updateManifestURL) else {
            error = "Invalid update URL"
            return
        }

        do {
            var request = URLRequest(url: manifestURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                error = "Failed to fetch update info"
                return
            }

            let release = try JSONDecoder().decode(AppRelease.self, from: data)
            latestRelease = release
            updateAvailable = isNewer(release.version, than: AppConstants.version)
        } catch {
            self.error = "Update check failed: \(error.localizedDescription)"
        }
    }

    func downloadAndInstall() async {
        guard let release = latestRelease, let url = URL(string: release.url) else { return }

        downloading = true
        downloadProgress = 0
        error = nil

        do {
            let delegate = DownloadDelegate { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress = progress
                }
            }

            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let (tempURL, response) = try await session.download(from: url)

            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                error = "Download failed (server returned \((response as? HTTPURLResponse)?.statusCode ?? 0))"
                downloading = false
                return
            }

            // Save DMG to a temp location with proper extension
            let dmgPath = FileManager.default.temporaryDirectory.appendingPathComponent("K8Secret-update.dmg")
            try? FileManager.default.removeItem(at: dmgPath)
            try FileManager.default.moveItem(at: tempURL, to: dmgPath)

            // Mount the DMG silently
            let mountPoint = try await mountDMG(at: dmgPath)

            // Find the .app inside the mounted volume
            let contents = try FileManager.default.contentsOfDirectory(atPath: mountPoint)
            guard let appName = contents.first(where: { $0.hasSuffix(".app") }) else {
                try? await unmountDMG(at: mountPoint)
                error = "No .app found in update DMG"
                downloading = false
                return
            }

            let sourceApp = URL(fileURLWithPath: mountPoint).appendingPathComponent(appName)

            // Determine where the current app lives
            let currentAppURL = currentAppBundleURL()

            // Replace the app: move old to trash, copy new in place
            let backupURL = currentAppURL.deletingLastPathComponent()
                .appendingPathComponent(".K8Secret-old.app")
            try? FileManager.default.removeItem(at: backupURL)
            try FileManager.default.moveItem(at: currentAppURL, to: backupURL)

            do {
                try FileManager.default.copyItem(at: sourceApp, to: currentAppURL)
                // Remove quarantine flag so Gatekeeper doesn't block
                removeQuarantine(currentAppURL)
                // Ad-hoc sign so macOS doesn't block the replaced app
                try adHocSign(currentAppURL)
            } catch {
                // Rollback: restore the old app
                try? FileManager.default.moveItem(at: backupURL, to: currentAppURL)
                try? await unmountDMG(at: mountPoint)
                self.error = "Failed to install update: \(error.localizedDescription)"
                downloading = false
                return
            }

            // Cleanup
            try? FileManager.default.removeItem(at: backupURL)
            try? await unmountDMG(at: mountPoint)
            try? FileManager.default.removeItem(at: dmgPath)

            downloading = false
            downloadProgress = 1.0

            // Relaunch the app
            relaunch(at: currentAppURL)
        } catch {
            self.error = "Update failed: \(error.localizedDescription)"
            downloading = false
        }
    }

    // MARK: - DMG helpers

    private func mountDMG(at path: URL) async throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["attach", path.path, "-nobrowse", "-noverify", "-noautoopen", "-plist"]
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()

        // Parse plist output to find mount point
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]] else {
            throw UpdateError.mountFailed
        }

        for entity in entities {
            if let mountPoint = entity["mount-point"] as? String {
                return mountPoint
            }
        }

        throw UpdateError.mountFailed
    }

    private func unmountDMG(at mountPoint: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["detach", mountPoint, "-quiet"]
        try process.run()
        process.waitUntilExit()
    }

    // MARK: - App bundle location

    private func currentAppBundleURL() -> URL {
        // Walk up from the executable to find the .app bundle
        var url = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        while url.pathExtension != "app" && url.path != "/" {
            url = url.deletingLastPathComponent()
        }
        if url.pathExtension == "app" {
            return url
        }
        // Fallback: standard install location
        return URL(fileURLWithPath: "/Applications/K8Secret.app")
    }

    // MARK: - Quarantine

    private func removeQuarantine(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-cr", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    // MARK: - Code signing

    private func adHocSign(_ appURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--deep", "--sign", "-", appURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.signFailed
        }
    }

    // MARK: - Relaunch

    private func relaunch(at appURL: URL) {
        // Close all windows first
        for window in NSApplication.shared.windows {
            window.close()
        }

        // Launch new instance after a short delay so the old process can exit
        let script = """
        sleep 1; open "\(appURL.path)"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]
        try? process.run()

        // Quit immediately
        NSApplication.shared.terminate(nil)
    }

    func dismiss() {
        updateAvailable = false
        latestRelease = nil
    }

    // MARK: - Version comparison

    private func isNewer(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }
}

enum UpdateError: LocalizedError {
    case mountFailed
    case noAppFound
    case signFailed

    var errorDescription: String? {
        switch self {
        case .mountFailed: return "Failed to mount update DMG"
        case .noAppFound: return "No app found in update"
        case .signFailed: return "Failed to sign updated app"
        }
    }
}

// MARK: - Download progress delegate

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let onProgress: (Double) -> Void

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Handled by the async download call
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        onProgress(progress)
    }
}
