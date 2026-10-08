// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hello",
    platforms: [.macOS(.v15)],
    dependencies: [.package(name: "PixelKit", path: "../..")],
    targets: [.executableTarget(name: "Hello", dependencies: ["PixelKit"])]
)
