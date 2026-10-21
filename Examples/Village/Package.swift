// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Village",
    platforms: [.macOS(.v15), .iOS(.v18)],
    dependencies: [.package(name: "Spellcrest", path: "../..")],
    targets: [.executableTarget(name: "Village", dependencies: ["Spellcrest"])]
)
