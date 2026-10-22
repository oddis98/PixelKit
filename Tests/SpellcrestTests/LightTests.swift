import Foundation
import Metal
import Testing
@testable import Spellcrest

/// A screen whose images are made in code, each its RGBA pixels and its width, one frame.
@MainActor func screen(_ size: Size, images: [String: (pixels: [UInt32], width: Int)]) throws -> Screen {
    let screen = try canvas(size)
    for (name, image) in images {
        screen.textures[name] = try texture(image.pixels, width: image.width)
        screen.sheets[name] = .some(nil)
    }
    return screen
}

/// A row of 1-pixel white tiles under a dark sky, an opaque one at `wall`, and a light with shadows at `from`.
@MainActor func darkRow(_ tiles: String, light: Vector, ySort: Bool = false) -> (Scene, Entity) {
    let scene = Scene()
    var map = Tilemap("tiles", tileSize: 1, rows: [tiles], legend: [".": 0, "#": 1], solid: [])
    map.opaque = [1]
    (scene.tilemap, scene.darkness, scene.ySort) = (map, 1, ySort)
    let lamp = Entity()
    lamp.hitbox = Rect(x: 0, y: 0, width: 1, height: 1)
    lamp.light = Light(radius: 12, shadows: true)
    scene.add(lamp, at: light)
    return (scene, lamp)
}

let white2 = (pixels: [UInt32](repeating: 0xFFFF_FFFF, count: 2), width: 2)

@MainActor @Test func lightStopsAtAnOpaqueTileButLightsItsFace() throws {
    let screen = try screen(Size(12, 1), images: ["tiles": white2])
    let (scene, lamp) = darkRow("....#.......", light: [1, 0])
    let reds = try render(screen) { scene.draw(screen) }.map { Int($0 >> 16 & 0xFF) }
    #expect(reds[0...3].allSatisfy { $0 > 0 } && reds[4] > 0) // up to the wall, and its face
    #expect(reds[5...].allSatisfy { $0 == 0 }) // behind it
    lamp.light?.shadows = false
    #expect(try render(screen) { scene.draw(screen) }.map { $0 >> 16 & 0xFF }[5...10].allSatisfy { $0 > 0 }) // past it, without shadows
    lamp.position = [4, 0] // inside the wall: a lantern on a post
    lamp.light?.shadows = true
    #expect(try render(screen) { scene.draw(screen) }.map { $0 >> 16 & 0xFF }[0...10].allSatisfy { $0 > 0 })
}

@MainActor @Test func anOpaqueEntityCastsAShadowAndOneStandingInItIsLitAsItsFeetAre() throws {
    let screen = try screen(Size(16, 8), images: ["tiles": white2, "tall": (Array(repeating: 0xFFFF_FFFF, count: 4), 1)])
    let (scene, _) = darkRow(String(repeating: ".", count: 16), light: [1, 6], ySort: true)
    scene.tilemap?.layers = [[Int?](repeating: 0, count: 16 * 8)]
    (scene.tilemap!.width, scene.tilemap!.height) = (16, 8)
    let post = Entity() // two pixels wide and tall, at the bottom
    (post.hitbox, post.opaque) = (Rect(x: 0, y: 0, width: 2, height: 2), true)
    scene.add(post, at: [5, 6])
    let walker = Entity() // four pixels tall, its feet behind the post
    (walker.sprite, walker.hitbox) = (Sprite("tall"), Rect(x: 0, y: 3, width: 1, height: 1))
    scene.add(walker, at: [11, 3])
    func red(_ x: Int, _ y: Int, _ pixels: [UInt32]) -> Int { Int(pixels[y * 16 + x] >> 16 & 0xFF) }
    let standing = try render(screen) { scene.draw(screen) }
    #expect(red(3, 6, standing) > 0 && red(9, 6, standing) == 0) // the ground lit before the post, dark behind it
    #expect((3...6).allSatisfy { red(11, $0, standing) == 0 }) // the walker in the dark, though light reaches its head
    scene.ySort = false // lit by each pixel instead
    let pixel = try render(screen) { scene.draw(screen) }
    #expect(red(11, 3, pixel) > 0 && red(11, 6, pixel) == 0)
}

@MainActor @Test func aLightOfBrightness1ChangesNothingByDayAndOneOf2Brightens() throws {
    let gray = (pixels: [UInt32](repeating: 0xFF80_8080, count: 2), width: 2)
    let screen = try screen(Size(9, 1), images: ["tiles": gray])
    let (scene, lamp) = darkRow(".........", light: [4, 0])
    scene.darkness = 0
    lamp.light = Light(radius: 4)
    let plain = try render(screen) { scene.draw(screen) }
    #expect(plain.allSatisfy { $0 == 0xFF80_8080 })
    lamp.light?.brightness = 2
    let bright = try render(screen) { scene.draw(screen) }
    #expect(bright[4] & 0xFF > 0xC0 && bright[0] == 0xFF80_8080) // brighter in the middle, as it was past the radius
    lamp.light?.brightness = -1 // taking light away
    let dark = try render(screen) { scene.draw(screen) }
    #expect(dark[4] & 0xFF < 0x40 && dark[3] & 0xFF < 0x80 && dark[0] == 0xFF80_8080)
    lamp.light = Light(radius: 4, color: 0x000000, gray: 1) // a light that only grays
    screen.textures["tiles"] = try texture([UInt32](repeating: 0xFF00_00FF, count: 2), width: 2) // red ground
    let grayed = try render(screen) { scene.draw(screen) }
    #expect(grayed[4] & 0xFF == grayed[4] >> 8 & 0xFF && grayed[0] == 0xFFFF_0000) // gray in the middle, red past it
}

@MainActor @Test func cloudsShadeAsMuchAsTheyCoverAndMoveWithTheWind() throws {
    let screen = try screen(Size(64, 64), images: ["tiles": white2])
    let (scene, lamp) = darkRow(String(repeating: ".", count: 64), light: [0, 0])
    scene.tilemap?.layers = [[Int?](repeating: 0, count: 64 * 64)]
    (scene.tilemap!.height, scene.darkness, lamp.light) = (64, 0, nil)
    func shaded(_ cover: Double) throws -> Int {
        scene.clouds = Clouds(cover: cover, shade: 0.5, size: 16, wind: [8, 0])
        return try render(screen) { scene.draw(screen) }.filter { $0 != 0xFFFF_FFFF }.count
    }
    let (none, some, all) = (try shaded(0), try shaded(0.5), try shaded(1))
    #expect(none == 0 && some > 0 && some < all && all == 64 * 64)
    let before = try render(screen) { scene.draw(screen) }
    scene.clock = 1 // blown 8 pixels to the right
    let after = try render(screen) { scene.draw(screen) }
    let moved = (0..<64 * 64).filter { $0 % 64 < 56 }.allSatisfy { (i: Int) -> Bool in before[i] == after[i + 8] }
    #expect(moved)
}

@MainActor @Test func cloudsAreSoftOrDitheredAndShadeTheDaylightButNotTheLights() throws {
    let (sky, row) = (try screen(Size(64, 64), images: ["tiles": white2]), try screen(Size(9, 1), images: ["tiles": white2]))
    let (scene, lamp) = darkRow(String(repeating: ".", count: 64), light: [0, 0])
    scene.tilemap?.layers = [[Int?](repeating: 0, count: 64 * 64)]
    (scene.tilemap!.height, scene.darkness, lamp.light) = (64, 0, nil)
    scene.clouds = Clouds(cover: 0.5, shade: 0.5, size: 16, smooth: false) // each pixel in shade or not
    #expect(Set(try render(sky) { scene.draw(sky) }).count == 2)
    scene.clouds?.smooth = true // and between
    #expect(Set(try render(sky) { scene.draw(sky) }).count > 10)

    // At dusk, under a cloud that halves the daylight, a light's middle is as bright as without it.
    let (dusk, fire) = darkRow(".........", light: [4, 0])
    (dusk.darkness, fire.light) = (0.5, Light(radius: 4))
    let clear = try render(row) { dusk.draw(row) }.map { Int($0 & 0xFF) }
    dusk.clouds = Clouds(cover: 1, shade: 0.5)
    let cloudy = try render(row) { dusk.draw(row) }.map { Int($0 & 0xFF) }
    #expect(clear[4] == 255 && cloudy[4] == 255 && abs(clear[0] - 128) <= 1 && abs(cloudy[0] - 64) <= 1)
}

@MainActor @Test func aGlowingSpriteAddsToWhatsUnderItUnlit() throws {
    let screen = try screen(Size(2, 1), images: ["tiles": (pixels: [0xFF40_4040, 0xFF40_4040], width: 2), "spark": ([0xFF00_00FF], 1)])
    let (scene, lamp) = darkRow("..", light: [0, 0])
    lamp.light = nil
    let spark = Entity()
    spark.sprite = Sprite("spark")
    scene.add(spark, at: [1, 0])
    #expect(try render(screen) { scene.draw(screen) } == [0xFF00_0000, 0xFF00_0000]) // at night, dark
    spark.sprite?.glows = true
    #expect(try render(screen) { scene.draw(screen) } == [0xFF00_0000, 0xFFFF_0000]) // glowing, red on the dark
    scene.darkness = 0
    #expect(try render(screen) { scene.draw(screen) } == [0xFF40_4040, 0xFFFF_4040]) // by day, added to the gray
}

@MainActor @Test func overhangsDrawOverTheWorldAndUnderTheHUDAndBackdropsBehindIt() throws {
    final class Clearing: Scene {
        override func draw(_ screen: Screen) {
            super.draw(screen)
            screen.fill(Rect(x: 0, y: 0, width: 1, height: 1), color: 0x0000FF) // the HUD
        }
    }
    let screen = try screen(Size(4, 1), images: ["green": ([0xFF00_FF00], 1), "leaf": ([0xFF00_00FF, 0xFF00_00FF], 2), "sky": ([0xFFFF_0000], 1)])
    let scene = Clearing()
    let bush = Entity()
    bush.sprite = Sprite("green")
    scene.add(bush, at: [1, 0])
    scene.backdrops = [Parallax(image: ImageName("sky"), repeats: .both)] // blue behind everything
    scene.overhangs = [Parallax(image: ImageName("leaf"), offset: [0, 0])] // red over the first two
    #expect(colors(try render(screen) { scene.draw(screen) }, width: 4) == ["brbb"])
}

@MainActor @Test func aParallaxMovesAtItsOwnRateAndRepeatsOrNot() throws {
    for (scroll, origin) in [(0.0, Vector(0, 0)), (0.5, [-1, 0]), (1, [-2, 0]), (1.25, [-2.5, 0])] {
        #expect(Parallax(image: ImageName("strip"), scroll: scroll).origin(view: [2, 0]) == origin)
    }
    let screen = try screen(Size(4, 1), images: ["strip": ([0xFF00_00FF, 0xFF00_FF00], 2)]) // red, green
    func drawn(_ scroll: Double, _ repeats: Parallax.Repeats) throws -> String {
        let scene = Scene()
        (scene.camera, scene.backdrops, scene.background) = ([2, 0], [Parallax(image: ImageName("strip"), scroll: scroll, repeats: repeats)], 0)
        return colors(try render(screen) { scene.draw(screen) }, width: 4)[0]
    }
    #expect(try [0, 0.5, 1, 1.25].map { try drawn($0, []) } == ["rg..", "g...", "....", "...."])
    #expect(try [0, 0.5, 1, 1.25].map { try drawn($0, .across) } == ["rgrg", "grgr", "rgrg", "grgr"])
}

@Test func theLightMapsLieUnderTheViewFromThePixelItsCornerIsIn() {
    #expect(lightMaps(under: [10.5, 3.25], game: Size(320, 180)) == (Vector(10, 3), Size(321, 181)))
    #expect(lightMaps(under: [-0.5, -2], game: Size(240, 135)).origin == [-1, -2])
}

@Test func aShakesTraumaDecaysToNone() {
    var shake = Shake()
    #expect(shake.offset(at: 1) == .zero)
    shake.add(0.6)
    shake.add(0.6)
    #expect(shake.trauma == 1) // no more than 1
    let offsets = (0..<60).map { shake.offset(at: Double($0) / 60) }
    #expect(offsets.allSatisfy { abs($0.x) <= 8 && abs($0.y) <= 8 } && Set(offsets).count == 60) // up to 8 pixels, moving
    for _ in 0..<30 { shake.decay(Loop.step) }
    #expect(abs(shake.trauma - 0.5) < 1e-9 && offsets.indices.allSatisfy { i in
        let half = shake.offset(at: Double(i) / 60)
        return abs(half.x) <= 2 && abs(half.y) <= 2 // a quarter as much at half the trauma
    })
    for _ in 0..<31 { shake.decay(Loop.step) }
    #expect(shake.trauma == 0 && shake.offset(at: 0.5) == .zero)
}

@Test func aBoltIsTheSameForItsSeedAndStaysNearItsEnds() {
    let (start, end): (Vector, Vector) = ([100, 0], [140, 160])
    let bolt = boltLines(from: start, to: end, seed: 7)
    #expect(bolt == boltLines(from: start, to: end, seed: 7) && bolt != boltLines(from: start, to: end, seed: 8))
    #expect(bolt.count == 2 && bolt[0].first == start && bolt[0].last == end && bolt[0].count == 65) // and a fork
    let reach = length(end - start) // its line's pushes add up to 36% of it, a fork's reach to 45% more
    #expect(bolt.joined().allSatisfy { $0.x >= 100 - reach && $0.x <= 140 + reach && $0.y >= -reach && $0.y <= 160 + reach })
    #expect(pixels(from: [0, 0], to: [3, 1]) == [[0, 0], [1, 0], [2, 1], [3, 1]] && pixels(from: [2, 5], to: [2, 3]) == [[2, 5], [2, 4], [2, 3]])
}

@MainActor @Test func aGamesShadersColorASpriteAndThePictureAndABrokenOneLeavesItPlain() async throws {
    let game = FileManager.default.temporaryDirectory.appending(path: "shaders-\(UUID())")
    let shaders = game.appending(path: "Assets/Shaders")
    try FileManager.default.createDirectory(at: shaders, withIntermediateDirectories: true)
    func write(_ name: String, _ text: String) throws { try text.write(to: shaders.appending(path: "\(name).metal"), atomically: true, encoding: .utf8) }
    try write("blue", "half4 blue(float2 position, half4 color, Values values) { return half4(mix(color.rgb, half3(0, 0, 1), half(values[0])), color.a); }")
    try write("swap", "half4 swap(float2 position, Layer layer, Values values) { half4 c = layer.sample(position); return half4(c.b, c.g, c.r, c.a); }")
    try write("broken", "half4 broken(float2 position, half4 color, Values values) {\n    return sinn(color);\n}")
    let screen = try screen(Size(3, 1), images: ["dot": ([0xFF00_00FF, 0, 0xFF00_FF00], 3)]) // red, clear, green
    screen.sheets["dot"] = .some(nil)
    func compiled() async throws {
        for _ in 0..<250 where screen.shaders.isEmpty || screen.shaders.values.contains(where: \.compiling) { try await Task.sleep(for: .milliseconds(20)) }
    }
    FileManager.default.changeCurrentDirectoryPath(game.path) // games load Assets/ relative to here
    var sprite = Sprite("dot")
    sprite.shader = Shader("blue", [1])
    #expect(colors(try render(screen) { screen.draw(sprite, x: 0, y: 0) }, width: 3) == ["r.g"]) // plain until it has compiled
    try await compiled()
    #expect(colors(try render(screen) { screen.draw(sprite, x: 0, y: 0) }, width: 3) == ["b.b"])
    FileManager.default.changeCurrentDirectoryPath(game.path)
    sprite.shader = Shader("broken")
    _ = try render(screen) { screen.draw(sprite, x: 0, y: 0) }
    try await compiled()
    #expect(colors(try render(screen) { screen.draw(sprite, x: 0, y: 0) }, width: 3) == ["r.g"])
    #expect(screen.shaders[ShaderKey(name: "broken", kind: .color)]?.failed == true)
    FileManager.default.changeCurrentDirectoryPath(game.path) // fixed, it compiles again
    try write("broken", "half4 broken(float2 position, half4 color, Values values) { return half4(0, 0, 1, color.a); }")
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: shaders.appending(path: "broken.metal").path)
    screen.reloadChangedShaders()
    try await compiled()
    #expect(colors(try render(screen) { screen.draw(sprite, x: 0, y: 0) }, width: 3) == ["b.b"])
    #expect(screen.shaders[ShaderKey(name: "broken", kind: .color)]?.failed == false)

    let scene = Scene()
    let entity = Entity()
    entity.sprite = Sprite("dot")
    scene.add(entity, at: .zero)
    scene.effects = [Shader("swap")]
    FileManager.default.changeCurrentDirectoryPath(game.path)
    _ = try render(screen) { scene.draw(screen) }
    try await compiled()
    #expect(colors(try render(screen) { scene.draw(screen) }, width: 3) == ["b.g"]) // red and blue swapped on the picture

    // Saved again, it compiles again, and draws as it now says.
    FileManager.default.changeCurrentDirectoryPath(game.path)
    try write("swap", "half4 swap(float2 position, Layer layer, Values values) { return half4(1, 0, 0, 1); }")
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: shaders.appending(path: "swap.metal").path)
    screen.reloadChangedShaders()
    try await compiled()
    #expect(colors(try render(screen) { scene.draw(screen) }, width: 3) == ["rrr"])
}

@Test func aShadersFileCountsItsOwnLinesSoItsErrorsNameThem() throws {
    let text = "half4 ripple(float2 position, Layer layer, Values values) {\n    return layer.sample(position + sinn(values.time));\n}"
    let source = shaderSource(text, name: "ripple", path: "/Game/Assets/Shaders/ripple.metal", kind: .layer)
    #expect(source.hasPrefix(shaderCommon) && source.contains("#line 1 \"/Game/Assets/Shaders/ripple.metal\"\n" + text))
    #expect(shaderKind(text, name: "ripple") == .layer && shaderKind("half4 tint(float2 p, half4 color, Values v) {}", name: "tint") == .color)
    let device = try #require(MTLCreateSystemDefaultDevice())
    let error = #expect(throws: (any Error).self) { try device.makeLibrary(source: source, options: nil) }
    #expect(error?.localizedDescription.contains("/Game/Assets/Shaders/ripple.metal:2:36: error: use of undeclared identifier 'sinn'") == true)
}

@MainActor @Test func entitiesAreNumberedAsTheyreAddedSoAFlickerIsTheSameEachRunAndTheShakeSaysHowFar() {
    func flickers() -> [Double] {
        let scene = Scene()
        return (0..<3).map { _ in
            let torch = Entity()
            torch.light = Light(radius: 40, flicker: 0.3)
            torch.light?.time = 0.7
            scene.add(torch, at: .zero)
            return torch.light!.radius(seed: torch.number)
        }
    }
    #expect(flickers() == flickers() && Set(flickers()).count == 3) // alike in two scenes made alike, and apart from each other
    let scene = Scene()
    #expect(scene.shakeOffset == .zero)
    scene.shake(1)
    #expect(scene.shakeOffset != .zero && scene.shakeOffset == scene.shaking.offset(at: scene.clock))
}
