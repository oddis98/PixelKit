import Foundation
import PixelKitProtocol
import Testing
@testable import PixelKit

@MainActor @Test func tilemapFilesLoadWithSolidTilesFromTheTilesetMarkersAndObjects() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "tilemap-\(UUID())")
    try FileManager.default.createDirectory(at: folder.appending(path: "Assets"), withIntermediateDirectories: true)
    FileManager.default.changeCurrentDirectoryPath(folder.path) // games load Assets/ relative to here
    try SheetFile(frameWidth: 8, frameHeight: 8, solid: [0]).write(to: folder.appending(path: "Assets/tiles.json"))
    try TilemapFile(tileset: "tiles", width: 3, height: 2, layers: [
        .init(name: "Ground", tiles: [-1, -1, -1, 0, 1, 0]),
        .init(name: "Things", tiles: [5, -1, 5, -1, -1, -1]),
    ], objects: [
        .init(name: "coin", x: 3, y: 4), .init(name: "door", x: 16, y: 0, properties: ["to": "level2"]), .init(name: "coin", x: 20, y: 9),
    ]).write(to: folder.appending(path: "Assets/level.tilemap"))

    var map = Tilemap("level")
    #expect(map.size == Size(24, 16))
    #expect(map.isSolid(Rect(x: 0, y: 8, width: 8, height: 8)))  // tile 0 is solid
    #expect(!map.isSolid(Rect(x: 8, y: 8, width: 8, height: 8))) // tile 1 isn't
    #expect(map.removeTiles(5) == [[0, 0], [16, 0]])
    #expect(map.layers[1].allSatisfy { $0 == nil })
    #expect(map.objects(named: "coin") == [[3, 4], [20, 9]])
    #expect(map.objects.first { $0.name == "door" }?.properties == ["to": "level2"])
}

@Test func tilemapFilesFromBeforeObjectsStayTheSame() throws {
    let old = #"{"height":1,"layers":[{"name":"Ground","tiles":[-1]}],"tileset":"tiles","width":1}"#
    let file = FileManager.default.temporaryDirectory.appending(path: "old-\(UUID()).tilemap")
    try Data(old.utf8).write(to: file)
    var map = try TilemapFile(contentsOf: file)
    #expect(map.objects == nil)
    try map.write(to: file)
    #expect(try String(contentsOf: file, encoding: .utf8) == old)

    map.objects = [.init(name: "coin", x: 1, y: 2, properties: ["value": "5"]), .init(name: "start", x: 0, y: 0)]
    try map.write(to: file)
    #expect(try TilemapFile(contentsOf: file) == map)
}
