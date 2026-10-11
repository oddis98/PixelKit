// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PixelKit",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "PixelKit", targets: ["PixelKit"])],
    targets: [
        .target(name: "PixelKit", dependencies: ["PixelKitProtocol"]),
        // File formats the editor writes and games read.
        .target(name: "PixelKitProtocol"),
        .testTarget(name: "PixelKitTests", dependencies: ["PixelKit"]),
    ]
)
