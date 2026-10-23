import Metal
import Testing
@testable import Spellcrest

@MainActor @Test func aBloomSpreadsWhatGlowsPastItsPixelsAndNothingElse() throws {
    let screen = try canvas(Size(16, 5))
    screen.textures["dot"] = try texture([0xFFFF_FFFF], width: 1)
    screen.sheets["dot"] = .some(nil)
    let scene = Scene()
    let spark = Entity()
    spark.sprite = Sprite("dot")
    spark.sprite?.glows = true
    scene.add(spark, at: [8, 2])
    let plain = try render(screen) { scene.draw(screen) }
    #expect(plain.enumerated().allSatisfy { $0.element == ($0.offset == 2 * 16 + 8 ? 0xFFFF_FFFF : 0xFF00_0000) }) // a white pixel
    scene.bloom = Bloom(strength: 1, radius: 1)
    let bloomed = try render(screen) { scene.draw(screen) }
    #expect(bloomed[2 * 16 + 8] == 0xFFFF_FFFF && bloomed[2 * 16 + 10] & 0xFF > 0 && bloomed[1 * 16 + 8] & 0xFF > 0) // spread round it
    #expect(bloomed[2 * 16 + 9] & 0xFF > bloomed[2 * 16 + 10] & 0xFF && bloomed[2 * 16 + 15] == 0xFF00_0000) // fading, gone further off

    spark.sprite?.glows = false // nothing glows: drawn as it is without a bloom
    let still = try render(screen) { scene.draw(screen) }
    scene.bloom = nil
    #expect(try render(screen) { scene.draw(screen) } == still)
}

@MainActor @Test func lightPastDaylightBloomsEvenOverBlack() throws {
    let screen = try canvas(Size(24, 9))
    let scene = Scene()
    scene.darkness = 1 // nothing drawn, so the light lights only black
    let flash = Entity()
    flash.hitbox = Rect(x: 0, y: 0, width: 2, height: 2) // its middle: (12, 4)
    flash.light = Light(radius: 4, brightness: 3)
    scene.add(flash, at: [11, 3])
    #expect(try render(screen) { scene.draw(screen) }.allSatisfy { $0 == 0xFF00_0000 })
    scene.bloom = Bloom(radius: 1, light: 1)
    let bloomed = try render(screen) { scene.draw(screen) }
    #expect(bloomed[4 * 24 + 12] & 0xFF > 0x80 && bloomed[4 * 24 + 16] & 0xFF > 0 && bloomed[4 * 24 + 23] == 0xFF00_0000) // round it
    scene.bloom = Bloom(radius: 1, light: 0)
    #expect(try render(screen) { scene.draw(screen) }.allSatisfy { $0 == 0xFF00_0000 }) // unless it says so
}

@MainActor @Test func aBendMovesThePictureWithinItsRadiusAndNowhereElse() throws {
    for (side, radius) in [(64, 6.0), (24, 10.0)] { // a little of the view, its boxes drawn where they are; most of it, all drawn through
        let screen = try canvas(Size(side, side))
        screen.textures["stripes"] = try texture((0..<side * side).map { $0 % side % 2 == 0 ? 0xFF00_00FF : 0xFFFF_0000 }, width: side)
        screen.sheets["stripes"] = .some(nil)
        let scene = Scene()
        let wall = Entity()
        wall.sprite = Sprite("stripes")
        scene.add(wall, at: .zero)
        let still = try render(screen) { scene.draw(screen) }
        let middle = Vector(Double(side) / 2, Double(side) / 2)
        scene.bends = [Bend(.swirl, at: middle, radius: radius, strength: 2)]
        let bent = try render(screen) { scene.draw(screen) }
        var inside = 0
        for y in 0..<side {
            for x in 0..<side where bent[y * side + x] != still[y * side + x] {
                let d = ((Double(x) + 0.5 - middle.x) * (Double(x) + 0.5 - middle.x) + (Double(y) + 0.5 - middle.y) * (Double(y) + 0.5 - middle.y)).squareRoot()
                #expect(d < radius, "(\(x), \(y)) moved, \(d) from the middle")
                inside += 1
            }
        }
        #expect(inside > 4) // the stripes turn near the middle
        scene.bends = [Bend(.ring(progress: 1), at: middle, radius: radius, strength: 2)] // a ring at its end has gone
        #expect(try render(screen) { scene.draw(screen) } == still)
    }
}
