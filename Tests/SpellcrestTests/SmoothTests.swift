import Metal
import Testing
@testable import Spellcrest

@Test func theCanvasIsDrawnAtTheScreensScale() {
    // In a window, the whole number it's scaled by, so it reaches the screen pixel for pixel.
    #expect(canvasScale(Size(320, 180), in: CGSize(width: 1000, height: 600), fill: false) == 3)
    #expect(canvasScale(Size(320, 180), in: CGSize(width: 100, height: 100), fill: false) == 1)
    // On an iPhone 16 Pro, the nearest to how big it fits: 8.93 sideways and 5.025 upright.
    #expect(canvasScale(Size(240, 135), in: CGSize(width: 2622, height: 1206), fill: true) == 9)
    #expect(canvasScale(Size(240, 135), in: CGSize(width: 1206, height: 2622), fill: true) == 5)
    #expect(canvasScale(Size(240, 135), in: .zero, fill: true) == 1) // before the view is laid out
}

@MainActor @Test func atAScaleCornersLandOnItsFractionsOfAPixel() throws {
    let screen = try canvas(Size(16, 2))
    screen.resize(to: 4)
    #expect(screen.canvas.width == 64 && screen.spare.width == 64 && screen.snapshot.height == 8)
    let red = try texture([0xFF00_00FF], width: 1) // RGBA bytes, red first
    let pixels = try render(screen) { screen.quad(red, x: 10.25, y: 0, source: Rect(x: 0, y: 0, width: 1, height: 1)) }
    #expect(colors(pixels, width: 64)[0] == String(repeating: ".", count: 41) + "rrrr" + String(repeating: ".", count: 19))
    screen.resize(to: 1) // a whole pixel, as before
    let whole = try render(screen) { screen.quad(red, x: 10.25, y: 0, source: Rect(x: 0, y: 0, width: 1, height: 1)) }
    #expect(colors(whole, width: 16)[0] == "..........r.....")
}

@MainActor @Test func tilesUnderACameraBetweenPixelsMeetWithoutSeams() throws {
    let screen = try canvas(Size(4, 1))
    screen.resize(to: 2)
    let (r, g, b) = (try texture([0xFF00_00FF], width: 1), try texture([0xFF00_FF00], width: 1), try texture([0xFFFF_0000], width: 1))
    let pixels = try render(screen) {
        screen.offset = [0.5, 0]
        for (x, color) in [r, g, b, r, g].enumerated() { screen.quad(color, x: Double(x), y: 0, source: Rect(x: 0, y: 0, width: 1, height: 1)) }
        screen.offset = .zero
    }
    #expect(colors(pixels, width: 8)[0] == "rggbbrrg") // each two pixels wide but the halves at the edges
}

@MainActor @Test func anEntityIsDrawnWhereItIsBetweenPixelsWhileItMovesInWholeOnes() {
    let walker = Entity()
    walker.velocity = [45, 0] // 0.75 a pixel an update
    var steps: [Double] = [], drawn: [Double] = []
    for _ in 0..<8 {
        let x = walker.position.x
        walker.move(Loop.step)
        walker.place(1)
        steps.append(walker.position.x - x)
        drawn.append(walker.drawnAt.x)
    }
    #expect(steps == [1, 1, 0, 1, 1, 1, 0, 1]) // whole pixels, so a stop every fourth update
    #expect(drawn == [0.75, 1.5, 2.25, 3, 3.75, 4.5, 5.25, 6]) // evenly
}

@MainActor @Test func betweenUpdatesAnEntityIsDrawnPartOfTheWayButNotAcrossAJump() {
    let walker = Entity()
    walker.before = [10, 0]
    walker.position = [12, 0]
    walker.place(0.25)
    #expect(walker.drawnAt == [10.5, 0])
    walker.place(1)
    #expect(walker.drawnAt == [12, 0])
    walker.position = [40, 0] // through a door
    walker.place(0.25)
    #expect(walker.drawnAt == [40, 0])
    walker.before = nil // added since the last update
    walker.position = [12, 0]
    walker.place(0.5)
    #expect(walker.drawnAt == [12, 0])
}

@MainActor @Test func aFollowedEntityStaysPutOnTheCanvasAsTheCameraFollowsIt() throws {
    let scene = Scene()
    let walker = Entity()
    walker.hitbox = Rect(x: 0, y: 0, width: 4, height: 4)
    walker.velocity = [45, 30]
    scene.add(walker, at: [100, 100])
    scene.follow = walker
    let screen = try canvas(Size(64, 36))
    screen.resize(to: 8)
    var places: Set<Vector> = []
    for _ in 0..<12 {
        walker.move(Loop.step)
        _ = try render(screen) { scene.draw(screen) }
        places.insert(walker.drawnAt - scene.camera)
    }
    #expect(places == [[30, 16]]) // its middle in the view's, (32, 18)
}
