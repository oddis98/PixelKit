import Foundation
import Metal
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

@MainActor @Test func tilemapsReloadWhenTheirFilesChangeKeepingRemovedTilesOut() throws {
    let assets = FileManager.default.temporaryDirectory.appending(path: "reload-\(UUID())/Assets")
    try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
    FileManager.default.changeCurrentDirectoryPath(assets.deletingLastPathComponent().path) // games load Assets/ relative to here
    func save(_ file: some AssetFile, as name: String, secondsLater: Double) throws {
        try file.write(to: assets.appending(path: name))
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: secondsLater)], ofItemAtPath: assets.appending(path: name).path)
    }
    try save(SheetFile(frameWidth: 8, frameHeight: 8), as: "tiles.json", secondsLater: 0)
    try save(TilemapFile(tileset: "tiles", width: 2, height: 1, layers: [.init(name: "Ground", tiles: [5, -1])]), as: "level.tilemap", secondsLater: 0)
    var map = Tilemap("level")
    _ = map.removeTiles(5) // a marker, like where a coin goes

    try save(TilemapFile(tileset: "tiles", width: 2, height: 1, layers: [.init(name: "Ground", tiles: [5, 1])]), as: "level.tilemap", secondsLater: 10)
    map.reloadIfChanged()
    #expect(map.layers == [[nil, 1]]) // the new tile is in, and the marker stays out
    try save(SheetFile(frameWidth: 8, frameHeight: 8, solid: [1]), as: "tiles.json", secondsLater: 20)
    map.reloadIfChanged()
    #expect(map.solid == [1])
    try Data("{".utf8).write(to: assets.appending(path: "level.tilemap")) // can't be read: the map stays
    map.reloadIfChanged()
    #expect(map.layers == [[nil, 1]])
}

@MainActor @Test func mapsQueueOnlyTheTilesInView() throws {
    let screen = Screen(size: Size(16, 16), device: try #require(MTLCreateSystemDefaultDevice()), format: .bgra8Unorm)
    screen.textures["tiles"] = screen.builtInFont // any image does as a tileset
    let map = Tilemap("tiles", tileSize: 8, rows: Array(repeating: "#####", count: 3), legend: ["#": 0]) // 5x3 tiles on a 2x2-tile canvas
    func tiles(at camera: Vector) -> Int {
        (screen.offset, screen.vertices) = (camera, [])
        screen.draw(map)
        return screen.vertices.count / 6
    }
    #expect(tiles(at: [0, 0]) == 4)
    #expect(tiles(at: [12, 4]) == 9) // between tiles: 3 columns and 3 rows show a part
    #expect(screen.vertices[0][0] == -4 && screen.vertices[0][1] == -4) // the first, column 1 and row 0, half off the canvas
    #expect(tiles(at: [-4, -4]) == 4 && tiles(at: [36, 20]) == 1) // past the top-left and bottom-right corners
    #expect(tiles(at: [100, 0]) == 0)
}
