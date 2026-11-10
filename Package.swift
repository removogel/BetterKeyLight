// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BetterKeyLight",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "BetterKeyLight", path: "Sources/BetterKeyLight")
    ]
)
