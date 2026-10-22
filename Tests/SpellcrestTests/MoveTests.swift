import Testing
@testable import Spellcrest

@MainActor @Test func entityLandsOnGroundAndStopsFlushAgainstWalls() {
    let scene = Scene()
    scene.tilemap = Tilemap("tiles", tileSize: 8, rows: [
        "....#",
        "....#",
        "#####",
    ], legend: ["#": 0])
    let box = Entity()
    box.hitbox = Rect(x: 0, y: 0, width: 8, height: 8)
    scene.add(box, at: [0, 0])

    // Falls onto the floor (top at y = 16) and rests on it.
    box.velocity = [0, 300]
    for _ in 0..<60 { box.move(1.0 / 60) }
    #expect(box.position == [0, 8] && box.onGround && box.velocity.y == 0)

    // Walks into the wall (left side at x = 32) and stops touching it.
    for _ in 0..<60 {
        box.velocity.x = 120
        box.move(1.0 / 60)
    }
    #expect(box.position == [24, 8] && box.velocity.x == 0)

    // Left of the map is open: cell math must round down for negative pixels, not alias into column 0.
    #expect(scene.tilemap!.cell(-1) == -1 && scene.tilemap!.cell(-8) == -1 && scene.tilemap!.cell(-9) == -2)
}

@MainActor @Test func goingStraightIntoACornerSlidesAroundItWhenItCatchesNoMoreThanCornerSlide() {
    for depth in 1...6 {
        let scene = Scene()
        scene.tilemap = Tilemap("tiles", tileSize: 8, rows: ["...", "..#"], legend: ["#": 0]) // a wall at x 16, from y 8
        let box = Entity()
        box.hitbox = Rect(x: 0, y: 0, width: 8, height: 8)
        box.cornerSlide = 4
        scene.add(box, at: [0, Double(depth)]) // its bottom `depth` pixels below the wall's top
        for _ in 0..<30 {
            box.velocity = [60, 0]
            box.move(1.0 / 60)
        }
        if depth <= 4 {
            #expect(box.position == [30 - Double(depth), 0]) // up past the corner, a pixel for each it was held up
        } else {
            #expect(box.position == [8, Double(depth)]) // flush against the wall
        }
    }
}

@MainActor @Test func cornersAreSlidAroundIntoADoorwayAndPastSolidEntitiesButNotDiagonallyNorByDefault() {
    let scene = Scene()
    scene.tilemap = Tilemap("tiles", tileSize: 8, rows: ["...", "...", "#.#", "..."], legend: ["#": 0]) // a doorway at x 8
    let box = Entity()
    box.hitbox = Rect(x: 0, y: 0, width: 8, height: 8)
    box.cornerSlide = 4
    scene.add(box, at: [11, 0]) // 3 pixels right of it
    func go(_ velocity: Vector, _ updates: Int) {
        for _ in 0..<updates {
            box.velocity = velocity
            box.move(1.0 / 60)
        }
    }
    go([0, 60], 24)
    #expect(box.position == [8, 21]) // down onto the wall, left into the doorway, and through it

    box.position = [11, 0]
    go([30, 60], 24)
    #expect(box.position.y == 8 && box.position.x > 11) // going diagonally, it stays on the wall, sliding along it

    (box.position, box.cornerSlide) = ([11, 0], 0)
    go([0, 60], 24)
    #expect(box.position == [11, 8]) // flush on the wall

    let open = Scene()
    let (walker, villager) = (Entity(), Entity())
    (walker.hitbox, villager.hitbox) = (Rect(x: 0, y: 0, width: 8, height: 8), Rect(x: 0, y: 0, width: 8, height: 8))
    (walker.cornerSlide, villager.solid) = (4, true)
    open.add(villager, at: [16, -6]) // its bottom 2 pixels in the walker's way
    open.add(walker, at: [0, 0])
    for _ in 0..<16 {
        walker.velocity = [60, 0]
        walker.move(1.0 / 60)
    }
    #expect(walker.position == [14, 2]) // down past its corner
}

@MainActor @Test func anEntityStoppedPartOfAPixelIntoAStepStaysPut() {
    let scene = Scene()
    let crab = Entity()
    scene.add(crab, at: [10, 10])
    crab.velocity = [30, 0] // half a pixel an update, which rounds to a whole one
    crab.move(1.0 / 60)
    crab.velocity = .zero
    let (position, drawn) = (crab.position, crab.position + crab.remainder)
    for _ in 0..<10 {
        crab.move(1.0 / 60)
        #expect(crab.position == position && crab.position + crab.remainder == drawn) // not a pixel back and forth
    }
}
