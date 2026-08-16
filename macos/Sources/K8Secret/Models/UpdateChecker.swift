import Foundation
import AppKit
import CryptoKit

struct AppRelease: Codable {
    let version: String
    let url: String
    let notes: String
    let minOS: String?
    let date: String?
    /// SHA-256 of the DMG, published alongside the release. Updates without one
    /// are refused — an unverified binary is exactly the thing an attacker who
    /// can reach the manifest or the download would want us to install.
    let sha256: String?
}

@MainActor
@Observable
final class UpdateChecker {
    var latestRelease: AppRelease?
    var updateAvailable = false
    /// Set from the app menu; the frontmost cluster window presents the
    /// sheet so it can wear that window's canvas tint.
    var sheetRequested = false
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
            updateAvailable = Self.isNewer(release.version, than: AppConstants.version)
        } catch {
            self.error = "Update check failed: \(error.localizedDescription)"
        }
    }

    /// Whether a manifest entry may be installed, and what to install if so.
    ///
    /// Split out and made non-private so the refusals can be tested directly.
    /// These three checks are the whole reason an attacker who reaches the manifest
    /// or the download cannot get code onto the machine, so they need to stay
    /// covered rather than being implicit in a long async function.
    enum InstallDecision: Equatable {
        case allowed(url: URL, sha256: String)
        case refused(String)
    }

    nonisolated static func decide(_ release: AppRelease) -> InstallDecision {
        guard let url = URL(string: release.url) else {
            return .refused("Refusing update: the release URL is not a valid URL.")
        }

        // The manifest is remote data, so its URL is untrusted input: HTTPS only,
        // and only a host that publishes our releases.
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              AppConstants.releaseDownloadHosts.contains(host) else {
            return .refused("Refusing update: download URL is not a trusted HTTPS release URL.")
        }

        // Without a published digest there is nothing to verify the payload against.
        guard let digest = release.sha256?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              digest.count == 64,
              digest.allSatisfy(\.isHexDigit) else {
            return .refused("Refusing update: release manifest has no sha256 checksum.")
        }

        return .allowed(url: url, sha256: digest)
    }

    func downloadAndInstall() async {
        guard let release = latestRelease else { return }

        let url: URL
        let expectedDigest: String
        switch Self.decide(release) {
        case .refused(let reason):
            error = reason
            return
        case .allowed(let allowedURL, let digest):
            url = allowedURL
            expectedDigest = digest
        }

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
            defer { session.finishTasksAndInvalidate() }
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

            // Verify the payload BEFORE mounting it. Everything downstream — mount,
            // copy into /Applications, ad-hoc sign, strip quarantine — is equivalent
            // to executing this file, so this is the last point at which a tampered
            // or truncated download can still be rejected.
            let actualDigest = try Self.sha256Hex(ofFileAt: dmgPath)
            guard actualDigest == expectedDigest else {
                try? FileManager.default.removeItem(at: dmgPath)
                error = "Update rejected: checksum mismatch. Expected \(expectedDigest.prefix(12))…, got \(actualDigest.prefix(12))…"
                downloading = false
                return
            }

            // Mount the DMG (checksum verification left on)
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
                // A notarized build validates on its own — stripping quarantine and
                // re-signing it would throw away the assurance we just paid for, and
                // ad-hoc re-signing actually *replaces* a Developer ID signature.
                // Only fall back for ad-hoc builds, which Gatekeeper would block.
                if !passesGatekeeper(currentAppURL) {
                    removeQuarantine(currentAppURL)
                    try adHocSign(currentAppURL)
                }
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

    // MARK: - Integrity

    /// Streaming SHA-256 so a large DMG is never held in memory all at once.
    nonisolated static func sha256Hex(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - DMG helpers

    private func mountDMG(at path: URL) async throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        // -noverify was dropped: the DMG's own checksum is a second, cheap integrity
        // check on top of the sha256 we already matched against the manifest.
        process.arguments = ["attach", path.path, "-nobrowse", "-noautoopen", "-plist"]
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

    // MARK: - Gatekeeper

    /// True when macOS will launch this bundle on its own — i.e. it's signed with a
    /// Developer ID and notarized.
    private func passesGatekeeper(_ url: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/spctl")
        process.arguments = ["--assess", "--type", "execute", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
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
        process.arguments = ["--force", "--sign", "-", appURL.path]
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

        // Launch new instance after a short delay so the old process can exit.
        // The path is passed as a positional argument rather than interpolated into
        // the script, so a bundle path containing shell metacharacters can't run.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", #"sleep 1; open "$1""#, "--", appURL.path]
        try? process.run()

        // Quit immediately
        NSApplication.shared.terminate(nil)
    }

    func dismiss() {
        updateAvailable = false
        latestRelease = nil
    }

    // MARK: - Version comparison

    /// Pure, and deliberately `nonisolated` + non-private so it can be unit tested.
    nonisolated static func isNewer(_ remote: String, than local: String) -> Bool {
        // Drop any pre-release suffix ("1.2.0-rc1" → "1.2.0") before comparing, and
        // treat a non-numeric component as 0 rather than dropping it — the old
        // `compactMap` silently turned "1.x.5" into [1, 5], making it compare as 1.5.
        func components(_ v: String) -> [Int] {
            v.split(separator: "-", maxSplits: 1).first
                .map { $0.split(separator: ".").map { Int($0) ?? 0 } } ?? []
        }

        let r = components(remote)
        let l = components(local)

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
