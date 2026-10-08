import Foundation
import PixelKitProtocol
import Testing
@testable import PixelKit

@MainActor @Test func tilemapFilesLoadWithSolidTilesFromTheTilesetAndMarkers() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "tilemap-\(UUID())")
    try FileManager.default.createDirectory(at: folder.appending(path: "Assets"), withIntermediateDirectories: true)
    FileManager.default.changeCurrentDirectoryPath(folder.path) // games load Assets/ relative to here
    try SheetFile(frameWidth: 8, frameHeight: 8, solid: [0]).write(to: folder.appending(path: "Assets/tiles.json"))
    try TilemapFile(tileset: "tiles", width: 3, height: 2, layers: [
        .init(name: "Ground", tiles: [-1, -1, -1, 0, 1, 0]),
        .init(name: "Things", tiles: [5, -1, 5, -1, -1, -1]),
    ]).write(to: folder.appending(path: "Assets/level.tilemap"))

    var map = Tilemap("level")
    #expect(map.size == Size(24, 16))
    #expect(map.isSolid(Rect(x: 0, y: 8, width: 8, height: 8)))  // tile 0 is solid
    #expect(!map.isSolid(Rect(x: 8, y: 8, width: 8, height: 8))) // tile 1 isn't
    #expect(map.removeTiles(5) == [[0, 0], [16, 0]])
    #expect(map.layers[1].allSatisfy { $0 == nil })
}
