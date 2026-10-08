import Testing
@testable import PixelKit

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
