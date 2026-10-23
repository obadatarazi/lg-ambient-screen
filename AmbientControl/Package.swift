// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "AmbientControl",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "AmbientControl",
            path: "Sources/AmbientControl",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
