import Foundation

enum AppConstants {
    static let version = "0.6.4"
    static let appName = "K8Secret"

    // Auto-update: release manifest served from the repo via GitHub raw.
    // No CDN / cloud account required — manifest is versioned with the code.
    static let updateManifestURL = "https://raw.githubusercontent.com/jai-bhardwaj/k8secret/main/release/latest.json"

    /// Hosts an update payload may be downloaded from. The manifest is remote data,
    /// so its `url` is validated against this list before anything is fetched.
    static let releaseDownloadHosts: Set<String> = [
        "github.com",
        "objects.githubusercontent.com",  // where GitHub redirects release asset downloads
    ]
}
