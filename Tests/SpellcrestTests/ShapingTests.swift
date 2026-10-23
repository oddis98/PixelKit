import Metal
import SpellcrestProtocol
import Testing
@testable import Spellcrest

/// A dark scene of one white sprite, 6 by 6 at (5, 1), lit only by a lamp far to its right, so evenly across it.
@MainActor func litFromTheRight(_ screen: Screen) throws -> (Scene, Entity) {
    screen.textures["ball"] = try texture(.init(repeating: 0xFFFF_FFFF, count: 36), width: 6)
    screen.sheets["ball"] = .some(nil)
    let scene = Scene()
    scene.darkness = 1
    let ball = Entity()
    ball.sprite = Sprite("ball")
    scene.add(ball, at: [5, 1])
    scene.lamps = [Lamp(at: [100, 4], light: Light(radius: 200))]
    return (scene, ball)
}

@MainActor @Test func aNormalMapTurnsASpriteTowardItsLightAndAScenesShapingSaysSo() throws {
    let screen = try canvas(Size(16, 8))
    let (scene, _) = try litFromTheRight(screen)
    let plain = try render(screen) { scene.draw(screen) }
    let (left, right) = (plain[3 * 16 + 6] & 0xFF, plain[3 * 16 + 9] & 0xFF)
    #expect(left > 0x80 && right > left && right - left < 10) // a lamp lights it, with no entity, nearly evenly from so far off
    // Its left half facing left, its right half right: red is right, as normal maps have it.
    screen.textures["ball.normal"] = try texture((0..<36).map { $0 % 6 < 3 ? 0xFF80_8000 : 0xFF80_80FF }, width: 6)
    #expect(try render(screen) { scene.draw(screen) } == plain) // not unless the scene shapes its light
    scene.shaping = .normals
    let shaped = try render(screen) { scene.draw(screen) }
    #expect(shaped[3 * 16 + 9] & 0xFF > right && shaped[3 * 16 + 6] & 0xFF < left / 2) // brighter toward it, darker away
    scene.lamps = [Lamp(at: [-90, 4], light: Light(radius: 200))] // from the left instead
    let other = try render(screen) { scene.draw(screen) }
    #expect(other[3 * 16 + 6] & 0xFF > other[3 * 16 + 9] & 0xFF)
    // Its top half facing up, its bottom half down, lit from above: green is down, as y is on the screen.
    screen.textures["ball.normal"] = try texture((0..<36).map { $0 / 6 < 3 ? 0xFF80_0080 : 0xFF80_FF80 }, width: 6)
    scene.lamps = [Lamp(at: [8, -90], light: Light(radius: 200))]
    let above = try render(screen) { scene.draw(screen) }
    #expect(above[2 * 16 + 7] & 0xFF > above[5 * 16 + 7] & 0xFF)
    scene.darkness = 0 // by day nothing's lit by it, so nothing shows its side
    scene.lamps = []
    #expect(try render(screen) { scene.draw(screen) }.allSatisfy { $0 == 0xFF00_0000 || $0 == 0xFFFF_FFFF })
}

@MainActor @Test func aSpriteWithoutANormalMapCatchesARimOnTheEdgesFacingItsLight() throws {
    let screen = try canvas(Size(16, 8))
    let (scene, _) = try litFromTheRight(screen)
    // Two frames side by side, both solid, so its right edge has the next frame beside it in the sheet.
    screen.textures["ball"] = try texture(.init(repeating: 0xFFFF_FFFF, count: 72), width: 12)
    screen.sheets["ball"] = SheetFile(frameWidth: 6, frameHeight: 6)
    let plain = try render(screen) { scene.draw(screen) }
    scene.shaping = .rim
    let rimmed = try render(screen) { scene.draw(screen) }
    let row = 3 * 16
    #expect(rimmed[row + 10] & 0xFF > plain[row + 10] & 0xFF) // its right edge, toward the light, though the next frame's there
    #expect(rimmed[row + 8] == plain[row + 8] && rimmed[row + 5] == plain[row + 5]) // inside, and the far edge, as they were
    scene.shaping = [.normals, .rim] // a normal map takes the place of the rim
    screen.textures["ball.normal"] = try texture(.init(repeating: 0xFFFF_8080, count: 72), width: 12) // all facing out of the screen
    let flat = try render(screen) { scene.draw(screen) }
    #expect(abs(Int(flat[row + 10] & 0xFF) - Int(plain[row + 10] & 0xFF)) < 3) // facing out of the screen, as it was
}

@MainActor @Test func aTileLightsByItsTilesetsPropertiesAndChangesAsItsTilesDo() throws {
    let assets = FileManager.default.temporaryDirectory.appending(path: "lit-\(UUID())/Assets")
    try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
    FileManager.default.changeCurrentDirectoryPath(assets.deletingLastPathComponent().path) // games load Assets/ relative to here
    let properties: [ObjectFile.Property] = [.init(name: "light", type: .number), .init(name: "lightColor", type: .color),
                                             .init(name: "lightFlicker", type: .number)]
    try SheetFile(frameWidth: 8, frameHeight: 8, properties: properties, tiles: [1: ["light": "24", "lightColor": "#FF8000", "lightFlicker": "0.1"]])
        .write(to: assets.appending(path: "torches.json"))
    var map = Tilemap("torches", tileSize: 8, rows: ["..#", "..."], legend: ["#": 1], solid: [])
    #expect(map.lamps.count == 1 && map.lamps[0].position == [20, 4]) // at its tile's middle
    #expect(map.lamps[0].light.radius == 24 && map.lamps[0].light.color == 0xFF8000 && map.lamps[0].light.flicker == 0.1)
    map.setTile(1, at: [4, 12], layer: 0)
    #expect(map.lamps.count == 2)
    map.setTile(nil, at: [20, 4], layer: 0)
    #expect(map.lamps.map(\.position) == [[4, 12]])

    let screen = try canvas(Size(24, 16))
    let scene = Scene()
    scene.darkness = 1
    screen.textures["ground"] = try texture(.init(repeating: 0xFFFF_FFFF, count: 24 * 16), width: 24)
    screen.sheets["ground"] = .some(nil)
    let ground = Entity()
    ground.sprite = Sprite("ground")
    scene.add(ground, at: .zero)
    let dark = try render(screen) { scene.draw(screen) }
    #expect(dark.allSatisfy { $0 == 0xFF00_0000 })
    scene.tilemap = map // the torch's light, with nothing of the map's own drawn in the dark: its tiles are black
    let lit = try render(screen) { scene.draw(screen) }
    #expect(lit[12 * 24 + 6] & 0xFF_0000 > 0x80_0000 && lit[12 * 24 + 6] & 0xFF == 0) // orange round it
}
