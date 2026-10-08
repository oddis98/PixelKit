// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PixelKit",
    platforms: [.macOS(.v15)],
    products: [.library(name: "PixelKit", targets: ["PixelKit"])],
    targets: [
        .target(name: "PixelKit"),
        .testTarget(name: "PixelKitTests", dependencies: ["PixelKit"]),
    ]
)
