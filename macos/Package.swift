// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "K8Secret",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "K8Secret",
            path: "Sources/K8Secret"
        ),
    ]
)
