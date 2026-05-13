import Foundation

enum AppConstants {
    static let version = "0.5.2"
    static let appName = "K8Secret"

    // Auto-update: release manifest served from the repo via GitHub raw.
    // No CDN / cloud account required — manifest is versioned with the code.
    static let updateManifestURL = "https://raw.githubusercontent.com/jai-bhardwaj/k8secret/main/release/latest.json"
}
