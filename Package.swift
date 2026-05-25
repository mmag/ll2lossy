// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ll2lossy",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/arthenica/ffmpeg-kit", from: "6.0.2")
    ],
    targets: [
        .executableTarget(
            name: "ll2lossy",
            dependencies: [
                .product(name: "ffmpegkit", package: "ffmpeg-kit")
            ],
            path: "Sources/ll2lossy"
        )
    ]
)
