import Foundation
import Metal
import Testing
@testable import Spellcrest

@MainActor @Test func changedPNGsReloadAndUnreadableOnesKeepTheOldTexture() throws {
    let examples = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "Examples/Platformer/Assets/Sprites")
    let folder = FileManager.default.temporaryDirectory.appending(path: "spellcrest-\(UUID())")
    try FileManager.default.createDirectory(at: folder.appending(path: "Assets"), withIntermediateDirectories: true)
    FileManager.default.changeCurrentDirectoryPath(folder.path) // games load Assets/ relative to here
    let file = folder.appending(path: "Assets/a.png")
    func replace(with data: Data, secondsLater: Double) throws {
        try data.write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: secondsLater)], ofItemAtPath: file.path)
    }

    try replace(with: Data(contentsOf: examples.appending(path: "coin.png")), secondsLater: 0) // 24 x 8
    let screen = Screen(size: Size(8, 8), device: MTLCreateSystemDefaultDevice()!, format: .bgra8Unorm)
    #expect(screen.texture("a").width == 24)

    try replace(with: Data(contentsOf: examples.appending(path: "slime.png")), secondsLater: 10) // 48 x 16
    screen.reloadChangedAssets()
    #expect(screen.texture("a").width == 48)

    try replace(with: Data("not a png".utf8), secondsLater: 20)
    screen.reloadChangedAssets()
    #expect(screen.texture("a").width == 48)
}
