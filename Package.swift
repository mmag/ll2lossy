// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ll2lossy",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ll2lossy",
            path: "Sources/ll2lossy",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
