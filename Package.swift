// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KeyLightBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "KeyLightBar", path: "Sources/KeyLightBar")
    ]
)
