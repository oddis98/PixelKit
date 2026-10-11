// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Platformer",
    platforms: [.macOS(.v15), .iOS(.v18)],
    dependencies: [.package(name: "PixelKit", path: "../..")],
    targets: [.executableTarget(name: "Platformer", dependencies: ["PixelKit"])]
)
