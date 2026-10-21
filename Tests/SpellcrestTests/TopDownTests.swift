import Foundation
import Metal
import SpellcrestProtocol
import Testing
@testable import Spellcrest

@MainActor @Test func withYSortEntitiesDrawByTheirFeetAndTiesAsTheyWereAdded() {
    final class Bird: Entity { override var sortY: Double { .infinity } } // always over the rest
    let scene = Scene()
    let (bird, tree, player, villager) = (Bird(), Entity(), Entity(), Entity())
    tree.hitbox = Rect(x: 12, y: 40, width: 8, height: 6) // the trunk: its feet are at 46
    scene.add(bird, at: [0, 0])
    scene.add(tree, at: [0, 0])
    scene.add(player, at: [0, 31]) // a 16x16 hitbox: feet at 47
    scene.add(villager, at: [5, 30.5]) // feet at 46 too, so after the tree, added before it
    func order() -> [ObjectIdentifier] { scene.drawOrder.map(ObjectIdentifier.init) }
    #expect(order() == [bird, tree, player, villager].map(ObjectIdentifier.init)) // off: as added
    scene.ySort = true
    #expect(order() == [tree, villager, player, bird].map(ObjectIdentifier.init))
    player.position.y = 20 // behind the tree
    #expect(order() == [player, tree, villager, bird].map(ObjectIdentifier.init))
    #expect(scene.entities.map(ObjectIdentifier.init) == [bird, tree, player, villager].map(ObjectIdentifier.init)) // updates as added
}

@MainActor @Test func entitiesStopAtSolidOnesButWalkOutOfOnesTheyOverlap() {
    let scene = Scene()
    let (player, villager, ghost) = (Entity(), Entity(), Entity())
    villager.solid = true
    scene.add(ghost, at: [20, 0]) // not solid: walked through
    scene.add(villager, at: [40, 0])
    scene.add(player, at: [0, 0])
    player.velocity = [600, 0]
    player.move(0.1)
    #expect(player.position == [24, 0] && player.velocity.x == 0) // flush against the villager

    villager.position = [10, 0] // on top of the player
    player.velocity = [-200, 0]
    player.move(0.1)
    #expect(player.position == [4, 0]) // walks out through it
    player.velocity = [200, 0]
    player.move(0.1)
    #expect(player.position == [24, 0]) // and on, while they overlap
    player.velocity = [-300, 0]
    player.move(0.1)
    #expect(player.position == [-6, 0]) // out the other side
    player.velocity = [100, 0]
    player.move(0.1)
    #expect(player.position == [-6, 0] && player.velocity.x == 0) // apart, it's in the way again
}

@Test func theCameraKeepsItsEntityInTheMiddleInsideTheMapOrCentersASmallMap() {
    func camera(_ x: Double, _ y: Double, map: Size? = Size(640, 360)) -> Vector {
        Scene.camera(following: [x + 8, y + 8], view: Size(320, 180), map: map) // a 16x16 box's middle
    }
    #expect(camera(300, 200) == [148, 118]) // its middle, (308, 208), in the view's
    #expect(camera(10, 10) == [0, 0] && camera(630, 350) == [320, 180]) // at the edges, the map's
    #expect(camera(300, 10) == [148, 0])
    #expect(camera(50, 40, map: Size(128, 96)) == [-96, -42]) // a house smaller than the view sits in the middle of it
    #expect(camera(300, 200, map: nil) == [148, 118])
    #expect(camera(300.25, 200.75) == [148.25, 118.75]) // between pixels, as the entity is drawn
}

@MainActor @Test func savesRoundTripAndOnesThatNoLongerDecodeReadAsNil() {
    struct Progress: Codable, Equatable { var place: Vector, cut: [Int] }
    struct Renamed: Codable { var spot: Vector }
    let folder = Save.folder
    Save.folder = FileManager.default.temporaryDirectory.appending(path: "saves-\(UUID())/Game")
    defer { Save.folder = folder }
    #expect(Save.read(Progress.self, from: "save") == nil)
    Save.write(Progress(place: [32, 48], cut: [3, 7]), to: "save")
    #expect(Save.read(Progress.self, from: "save") == Progress(place: [32, 48], cut: [3, 7]))
    #expect(Save.read(Renamed.self, from: "save") == nil) // its type changed
}

@MainActor @Test func fillsBlendAndPanelsStretchTheirEdgesAndMiddle() throws {
    let screen = try canvas(Size(9, 4))
    // Corners red, edges green, the middle blue, as in a 3x3 text box.
    screen.textures["box"] = try texture([0xFF00_00FF, 0xFF00_FF00, 0xFF00_00FF, 0xFF00_FF00, 0xFFFF_0000, 0xFF00_FF00, 0xFF00_00FF, 0xFF00_FF00, 0xFF00_00FF], width: 3)
    screen.sheets["box"] = .some(nil)
    let pixels = try render(screen) {
        screen.panel("box", in: Rect(x: 0, y: 0, width: 5, height: 4))
        screen.panel("box", in: Rect(x: 6, y: 0, width: 3, height: 3)) // as it is
        screen.fill(Rect(x: 6, y: 3, width: 3, height: 1), color: 0xFF0000, opacity: 0.5)
    }
    #expect(colors(pixels, width: 9) == ["rgggr.rgr", "gbbbg.gbg", "gbbbg.rgr", "rgggr.???"])
    #expect((127...128).contains(pixels[3 * 9 + 6] >> 16 & 0xFF) && pixels[3 * 9 + 6] & 0xFFFF == 0) // half red on black
}

@MainActor @Test func layersAboveDrawOverTheEntities() throws {
    let screen = try canvas(Size(6, 2))
    screen.textures["tiles"] = try texture([0xFF00_00FF, 0xFF00_00FF, 0xFF00_FF00, 0xFF00_FF00, 0xFF00_00FF, 0xFF00_00FF, 0xFF00_FF00, 0xFF00_FF00], width: 4)
    screen.textures["dot"] = try texture(.init(repeating: 0xFFFF_0000, count: 4), width: 2) // blue
    (screen.sheets["tiles"], screen.sheets["dot"]) = (.some(nil), .some(nil))
    let scene = Scene()
    var map = Tilemap("tiles", tileSize: 2, rows: ["###"], legend: ["#": 0]) // red ground
    map.layers.append([nil, 1, nil]) // a green roof over the middle
    map.above = [1]
    scene.tilemap = map
    for x in [2.0, 4] {
        let entity = Entity()
        entity.sprite = Sprite("dot")
        scene.add(entity, at: [x, 0])
    }
    #expect(colors(try render(screen) { scene.draw(screen) }, width: 6) == ["rrggbb", "rrggbb"])
}

/// A screen of `size` to draw on in tests.
@MainActor func canvas(_ size: Size) throws -> Screen {
    Screen(size: size, device: try #require(MTLCreateSystemDefaultDevice()), format: .bgra8Unorm)
}

/// A texture of RGBA pixels, row by row.
@MainActor func texture(_ pixels: [UInt32], width: Int) throws -> MTLTexture {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let texture = try #require(device.makeTexture(descriptor: .texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width,
                                                                                      height: pixels.count / width, mipmapped: false)))
    texture.replace(region: MTLRegionMake2D(0, 0, width, pixels.count / width), mipmapLevel: 0, withBytes: pixels, bytesPerRow: width * 4)
    return texture
}

/// What `draw` draws on the screen's canvas, cleared to black, as 0xAARRGGBB: `scale` pixels for each of the game's.
@MainActor func render(_ screen: Screen, _ draw: () -> Void) throws -> [UInt32] {
    let (width, height) = (screen.canvas.width, screen.canvas.height)
    let commands = try #require(screen.device.makeCommandQueue()?.makeCommandBuffer())
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = screen.canvas
    pass.colorAttachments[0].loadAction = .clear
    screen.begin(commands, pass)
    draw()
    screen.end()
    let pixels = try #require(screen.device.makeBuffer(length: width * height * 4, options: .storageModeShared))
    let blit = try #require(commands.makeBlitCommandEncoder())
    blit.copy(from: screen.canvas, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(), sourceSize: MTLSize(width: width, height: height, depth: 1),
              to: pixels, destinationOffset: 0, destinationBytesPerRow: width * 4, destinationBytesPerImage: width * height * 4)
    blit.endEncoding()
    commands.commit()
    commands.waitUntilCompleted()
    return Array(UnsafeBufferPointer(start: pixels.contents().bindMemory(to: UInt32.self, capacity: width * height), count: width * height))
}

/// Each row as letters: r, g and b for those colors, "." for black and "?" for anything else.
func colors(_ pixels: [UInt32], width: Int) -> [String] {
    let names: [UInt32: Character] = [0xFFFF_0000: "r", 0xFF00_FF00: "g", 0xFF00_00FF: "b", 0xFF00_0000: "."]
    return stride(from: 0, to: pixels.count, by: width).map { String(pixels[$0..<$0 + width].map { names[$0] ?? "?" }) }
}
