import Carbon.HIToolbox // kVK_ key codes
import Testing
@testable import Spellcrest

@MainActor @Test func aButtonIsLetGoOnTheUpdateItGoesUpAndATapBetweenTwoUpdatesStillCounts() {
    (Input.keys, Input.pushed) = ([], [])
    Input.poll()
    Input.keys = [kVK_ANSI_Z]
    Input.poll()
    #expect(Input.pressed(.a) && Input.held(.a) && !Input.released(.a))
    Input.poll()
    #expect(Input.held(.a) && !Input.pressed(.a) && !Input.released(.a))
    Input.keys = []
    Input.poll()
    #expect(Input.released(.a) && !Input.held(.a))
    Input.poll()
    #expect(!Input.released(.a))
    // Down and up again before an update, as a quick tap can be: pressed at the next, let go at the one after.
    Input.keys = [kVK_Space]
    Input.keys = []
    Input.poll()
    #expect(Input.pressed(.a) && Input.pressed(key: .space))
    Input.poll()
    #expect(Input.released(.a) && Input.released(key: .space) && !Input.held(.a))
    // A controller's button heard between two updates, as its handler hears it, counts too.
    Input.pushed = [.b]
    Input.poll()
    #expect(Input.pressed(.b) && Input.using == .controller)
    Input.poll()
    #expect(Input.released(.b))
}

@MainActor @Test func theKeyboardsOwnKeysReadByNameAndEscapePressesStart() {
    (Input.keys, Input.pushed) = ([], [])
    Input.poll()
    Input.keys = [kVK_Escape, kVK_ANSI_1, kVK_RightShift, kVK_ANSI_Q]
    Input.poll()
    #expect(Input.pressed(key: .escape) && Input.pressed(.start) && Input.held(key: .one) && Input.held(key: .shift) && Input.held(key: .q))
    #expect(!Input.held(key: .two) && !Input.held(.a) && Input.using == .keyboard) // Q is no button
    Input.keys = []
    Input.poll()
    #expect(Input.released(key: .escape) && Input.released(.start) && !Input.held(key: .shift))
    #expect(Input.Key.allCases.allSatisfy { key in Input.keyNames.values.contains(key) }) // every key has its key code
    #expect(Input.shiftBits[kVK_Shift] == 0x2 && Input.shiftBits[kVK_RightShift] == 0x4) // NX_DEVICELSHIFTKEYMASK, NX_DEVICERSHIFTKEYMASK
}

@MainActor @Test func theDirectionIsOneLongEveryWayAndTheStickGoesFromItsDeadZoneToItsRim() {
    #expect(Input.direction(stick: .zero, buttons: [.right]) == [1, 0])
    let diagonal = Input.direction(stick: .zero, buttons: [.left, .down])
    #expect(abs(diagonal.x + 0.5.squareRoot()) < 0.0001 && abs(diagonal.y - 0.5.squareRoot()) < 0.0001)
    #expect(Input.direction(stick: .zero, buttons: [.left, .right]) == .zero && Input.direction(stick: .zero, buttons: [.a]) == .zero)
    #expect(Input.direction(stick: [0.1, 0], buttons: [.up]) == [0, -1]) // a stick in its dead zone leaves it to the D-pad
    let half = Input.direction(stick: [0.6, 0], buttons: [.left]) // half way from its dead zone to its rim, the D-pad left aside
    #expect(abs(half.x - 0.5) < 0.0001 && half.y == 0)
    #expect(abs(Input.length(Input.direction(stick: [0.9, 0.9], buttons: [])) - 1) < 0.0001) // no longer than 1 at a square's corner

    // From the keys, through an update.
    (Input.keys, Input.pushed) = ([], [])
    Input.poll()
    Input.keys = [kVK_RightArrow, kVK_UpArrow]
    Input.poll()
    #expect(abs(Input.length(Input.direction) - 1) < 0.0001 && Input.direction.x > 0 && Input.direction.y < 0)
    Input.keys = []
    Input.poll()
    #expect(Input.direction == .zero)
}

@MainActor @Test func whatsInUseIsWhatLastPressedAButtonOrMovedThePointer() {
    (Input.keys, Input.pushed) = ([], [])
    Input.poll()
    Input.pushed = [.a] // a controller's button
    Input.poll()
    #expect(Input.using == .controller)
    Input.poll()
    #expect(Input.using == .controller) // until something else is used
    Input.keys = [kVK_ANSI_C]
    #expect(Input.using == .keyboard)
    Input.keys = []
    Input.pushed = [.x]
    Input.poll()
    Input.point([10, 10], down: false) // the mouse, on a Mac
    #expect(Input.using == .keyboard)
    Input.point(nil, down: false)
    Input.poll()
    Input.poll()
}
