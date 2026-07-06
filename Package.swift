// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "atoll-indicator",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/Ebullioscopic/AtollExtensionKit.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "atoll-indicator",
            dependencies: [
                .product(name: "AtollExtensionKit", package: "AtollExtensionKit"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/atoll-indicator",
            exclude: ["Info.plist"]
        )
    ]
)
