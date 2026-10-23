// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "OwlEye",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "OwlEye",
            path: "Sources/OwlEye",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
