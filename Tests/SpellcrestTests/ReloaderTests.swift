import Foundation
import ObjectiveC
import Testing
@testable import Spellcrest

// Versions of one class, as a recompiled game would bring them.
final class OldSlime: Entity {
    var hp = 3
    override func update(_ dt: Double) { position.x += 1 }
}

final class NewSlime: Entity {
    var hp = 3
    override func update(_ dt: Double) { position.x -= 1 }
}

final class ArmoredSlime: Entity {
    var hp = 3
    var armor = 1
}

@MainActor @Test func reloadMovesLiveObjectsToTheNewClassAndKeepsTheirState() {
    let scene = Scene()
    let slime = OldSlime()
    slime.hp = 7
    scene.add(slime, at: [10, 0])
    Scene.current = scene
    defer { Scene.current = Scene() }
    #expect(Reloader.liveObjects().contains { $0 === slime })

    // A stored property was added: nothing switches, since old memory wouldn't fit.
    let refused = Reloader.swap(Reloader.liveObjects(), to: [NSStringFromClass(OldSlime.self): ArmoredSlime.self])
    #expect(refused.hasPrefix("Can't reload") && object_getClass(slime) == OldSlime.self)

    // Only code changed: the slime switches, keeps its state, and runs the new update.
    #expect(Reloader.swap(Reloader.liveObjects(), to: [NSStringFromClass(OldSlime.self): NewSlime.self]) == "Reloaded NewSlime")
    #expect(object_getClass(slime) == NewSlime.self)
    scene.update(1)
    #expect(slime.position.x == 9 && (slime as AnyObject as? NewSlime)?.hp == 7)
}
