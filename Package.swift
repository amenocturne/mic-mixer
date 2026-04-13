// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MicMixer",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "MicMixer",
            path: "Sources/MicMixer",
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("AVFAudio"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AppKit"),
            ]
        )
    ]
)
