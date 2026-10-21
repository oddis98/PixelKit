import Testing
@testable import Spellcrest

@MainActor @Test func thePointerIsPressedOnTheUpdateItGoesDownOnTheCanvasAndStaysOnItWhileHeld() {
    Input.canvas = Size(320, 180)
    Input.point([10, 20], down: false) // hovering
    Input.poll()
    #expect(Input.pointer == [10, 20] && !Input.held(.pointer))
    Input.point([12, 20], down: true)
    Input.poll()
    #expect(Input.pressed(.pointer) && Input.pointer == [12, 20])
    Input.point([400, -5], down: true) // dragged off the canvas: on its edge
    Input.poll()
    #expect(Input.held(.pointer) && !Input.pressed(.pointer) && Input.pointer == [319, 0])
    Input.point([400, -5], down: false) // let go there
    Input.poll()
    #expect(!Input.held(.pointer) && Input.pointer == nil)
    Input.point([-1, 50], down: true) // down in the letterbox
    Input.poll()
    #expect(!Input.held(.pointer) && Input.pointer == nil)
    Input.point([30, 40], down: true) // a tap between two updates counts, once, where it went down
    Input.point(nil, down: false)
    Input.poll()
    #expect(Input.pressed(.pointer) && Input.pointer == [30, 40])
    Input.poll()
    #expect(!Input.held(.pointer) && Input.pointer == nil)
}

@MainActor @Test func entitiesContainThePointsInTheirHitbox() {
    let chest = Entity()
    chest.hitbox = Rect(x: 2, y: 8, width: 12, height: 8)
    chest.position = [100, 50]
    #expect(chest.contains([102, 58]) && chest.contains([113.5, 65.9]))
    #expect(!chest.contains([101, 58]) && !chest.contains([114, 60]) && !chest.contains([105, 66]))
}
