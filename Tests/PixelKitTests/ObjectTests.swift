import Foundation
import PixelKitProtocol
import Testing
@testable import PixelKit

@MainActor @Test func assetsAreFoundByNameInTheirFoldersAtTheTopFirstAndWhenAddedOrMoved() throws {
    let game = FileManager.default.temporaryDirectory.appending(path: "assets-\(UUID())")
    for path in ["Sprites/Enemies/bat.png", "Sprites/slime.png", "slime.png", "Maps/b/level.tilemap", "Maps/a/level.tilemap", ".hidden/x.png"] {
        try FileManager.default.createDirectory(at: game.appending(path: "Assets/\(path)").deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: game.appending(path: "Assets/\(path)"))
    }
    FileManager.default.changeCurrentDirectoryPath(game.path) // games load Assets/ relative to here
    #expect(assetURL("bat.png").path.hasSuffix("/Assets/Sprites/Enemies/bat.png"))
    #expect(assetURL("slime.png").path.hasSuffix("/Assets/slime.png")) // at the top first
    #expect(assetURL("level.tilemap").path.hasSuffix("/Assets/Maps/a/level.tilemap")) // then the first by path,
    #expect(assetIndex.withLock { $0.warned.contains("level.tilemap") }) // which the console mentions
    #expect(assetURL("x.png").path.hasSuffix("/Assets/x.png")) // hidden folders are the editor's

    try FileManager.default.createDirectory(at: game.appending(path: "Assets/Sounds"), withIntermediateDirectories: true)
    try Data().write(to: game.appending(path: "Assets/Sounds/coin.wav"))
    #expect(assetURL("coin.wav").path.hasSuffix("/Assets/coin.wav")) // looked for again at most once a second
    assetIndex.withLock { $0.built = .distantPast }
    #expect(assetURL("coin.wav").path.hasSuffix("/Assets/Sounds/coin.wav"))
    try FileManager.default.moveItem(at: game.appending(path: "Assets/Sprites/Enemies/bat.png"), to: game.appending(path: "Assets/Sprites/bat.png"))
    assetIndex.withLock { $0.built = .distantPast }
    #expect(assetURL("bat.png").path.hasSuffix("/Assets/Sprites/bat.png")) // moved while the game runs
}

@Test func objectFilesRoundTripAndAnEmptyOneIsAMarker() throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "villager-\(UUID()).object")
    try Data("{}".utf8).write(to: file)
    #expect(try ObjectFile(contentsOf: file) == ObjectFile())
    let villager = ObjectFile(sprite: "villager", animation: "idle", hitbox: .init(x: 3, y: 10, width: 10, height: 6), solid: true, class: "Villager",
                              properties: [.init(name: "name", value: "Ann"), .init(name: "to", type: .map), .init(name: "speed", type: .number, value: "40")])
    try villager.write(to: file)
    #expect(try ObjectFile(contentsOf: file) == villager)
    #expect(try String(contentsOf: file, encoding: .utf8).contains(#""class":"Villager""#))
}

@MainActor @Test func placedObjectsGetTheirDefinitionsSizeHitboxSpriteClassAndDefaults() {
    let frames = ["tree": Size(32, 48), "coin": Size(8, 8)]
    func object(_ placed: TilemapFile.Object, _ definition: ObjectFile?) -> Tilemap.Object {
        Tilemap.Object(placed, definition: definition, tileSize: 16) { frames[$0] }
    }
    let tree = object(.init(name: "oak", x: 4, y: 8), ObjectFile(sprite: "tree", animation: "sway", hitbox: .init(x: 11, y: 38, width: 10, height: 8),
                                                                    solid: true, class: "Tree"))
    #expect(tree.box == Rect(x: 4, y: 8, width: 32, height: 48) && tree.hitbox == Rect(x: 11, y: 38, width: 10, height: 8))
    #expect(tree.solid && tree.class == "Tree" && tree.sprite?.image == "tree" && tree.sprite?.animation == "sway")

    // A zone is its own size, or one tile, unless the map sized it; its hitbox is all of it.
    let door = ObjectFile(width: 16, height: 4, properties: [.init(name: "to", type: .map), .init(name: "locked", type: .toggle, value: "true"),
                                                             .init(name: "speed", type: .number, value: "40")])
    let placed = object(.init(name: "door", x: 0, y: 0, properties: ["to": "house", "speed": "12.5", "note": "x"], width: 32), door)
    #expect(placed.box == Rect(x: 0, y: 0, width: 32, height: 4) && placed.hitbox == Rect(x: 0, y: 0, width: 32, height: 4))
    #expect(placed.sprite == nil && !placed.solid && placed.class == nil)
    #expect(placed.properties == ["to": "house", "locked": "true", "speed": "12.5", "note": "x"]) // its own over the defaults
    #expect(placed.double("speed") == 12.5 && placed.double("to") == nil && placed.bool("locked") && !placed.bool("open"))
    #expect(object(.init(name: "start", x: 0, y: 0), ObjectFile()).box == Rect(x: 0, y: 0, width: 16, height: 16)) // a marker

    // Without a definition, as in older maps: the image named after it, or one tile, and nothing to make.
    let coin = object(.init(name: "coin", x: 1, y: 2, properties: ["value": "5"]), nil)
    #expect(coin.box == Rect(x: 1, y: 2, width: 8, height: 8) && coin.sprite == nil && coin.class == nil && coin.properties == ["value": "5"])
    #expect(object(.init(name: "spot", x: 0, y: 0), nil).box.width == 16)
}

/// Made from objects that name it: its own `init()` runs, then it gets the object's sprite, hitbox and properties.
final class Bat: Entity, Placeable {
    var madeByInit = false
    lazy var speed = object?.double("speed") ?? 1

    override init() {
        super.init()
        madeByInit = true
        sprite = Sprite("own")
        hitbox = Rect(x: 0, y: 0, width: 1, height: 1)
    }
}

final class Stone: Entity {} // not Placeable

@MainActor @Test func addObjectsMakesEachAsItsClassOrAnEntityAndLeavesZonesAndMarkers() throws {
    let assets = FileManager.default.temporaryDirectory.appending(path: "objects-\(UUID())/Assets")
    try FileManager.default.createDirectory(at: assets.appending(path: "Objects"), withIntermediateDirectories: true)
    FileManager.default.changeCurrentDirectoryPath(assets.deletingLastPathComponent().path) // games load Assets/ relative to here
    try SheetFile(frameWidth: 8, frameHeight: 8).write(to: assets.appending(path: "tiles.json"))
    let definitions = [
        "bat": ObjectFile(sprite: "bat", hitbox: .init(x: 2, y: 2, width: 4, height: 4), class: "Bat", properties: [.init(name: "speed", type: .number, value: "20")]),
        "rock": ObjectFile(sprite: "rock", solid: true), "door": ObjectFile(width: 16, height: 4), "start": ObjectFile(),
        "ghost": ObjectFile(sprite: "ghost", class: "Ghost"), "stone": ObjectFile(class: "Stone"),
    ]
    for (name, definition) in definitions { try definition.write(to: assets.appending(path: "Objects/\(name).object")) }
    let names = ["bat", "rock", "door", "start", "ghost", "stone", "tree"] // the tree has no definition
    try TilemapFile(tileset: "tiles", width: 4, height: 4, layers: [.init(name: "Ground", tiles: .init(repeating: -1, count: 16))],
                    objects: names.enumerated().map { .init(name: $1, x: $0 * 8, y: 0, properties: $1 == "bat" ? ["speed": "30"] : nil) })
        .write(to: assets.appending(path: "level.tilemap"))

    let module = Scene.module
    Scene.module = "PixelKitTests"
    defer { Scene.module = module }
    let scene = Scene()
    scene.tilemap = Tilemap("level")
    let made = scene.addObjects()
    #expect(made.map(\.position.x) == [0, 8, 32, 40] && scene.entities.count == 4 && scene.tilemap?.objects.count == 7)
    let bat = try #require(made[0] as? Bat)
    #expect(bat.madeByInit && bat.sprite?.image == "bat" && bat.hitbox == Rect(x: 2, y: 2, width: 4, height: 4) && bat.speed == 30)
    #expect(type(of: made[1]) == Entity.self && made[1].sprite?.image == "rock" && made[1].solid && made[1].object?.name == "rock")
    #expect(type(of: made[2]) == Entity.self && made[2].sprite?.image == "ghost" && Scene.warned.contains("Ghost")) // missing
    #expect(type(of: made[3]) == Entity.self && Scene.warned.contains("Stone")) // not Placeable

    let rock = assets.appending(path: "Objects/rock.object") // changed in the editor while the game runs
    try ObjectFile(sprite: "boulder").write(to: rock)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 10)], ofItemAtPath: rock.path)
    scene.tilemap?.reloadIfChanged()
    #expect(scene.tilemap?.objects[1].sprite?.image == "boulder" && scene.tilemap?.objects[1].solid == false)
}
