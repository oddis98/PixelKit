#if os(macOS)
import Carbon.HIToolbox // kVK_ key codes
#endif
import GameController

/// A virtual gamepad. Keyboard: arrows or WASD, Z or Space = a, X = b, C = x, V = y, Return = start.
/// Game controllers: d-pad or left stick, A, B, X, Y, Menu. On iOS, also the touch controls over the game.
public enum Button: Sendable, CaseIterable {
    case left, right, up, down, a, b, x, y, start
}

/// The virtual gamepad, read in `update`: `Input.held(.right)`, `Input.pressed(.a)`.
@MainActor public enum Input {
    /// True while the button is down.
    public static func held(_ button: Button) -> Bool { now.contains(button) }

    /// True only on the update when the button goes down.
    public static func pressed(_ button: Button) -> Bool { now.contains(button) && !before.contains(button) }

    static var now: Set<Button> = []
    static var before: Set<Button> = []

    #if os(macOS)
    static var keys: Set<Int> = [] // key codes held right now, fed by GameView or the editor's preview

    static let keyMap: [Int: Button] = [
        kVK_LeftArrow: .left, kVK_ANSI_A: .left, kVK_RightArrow: .right, kVK_ANSI_D: .right,
        kVK_UpArrow: .up, kVK_ANSI_W: .up, kVK_DownArrow: .down, kVK_ANSI_S: .down,
        kVK_ANSI_Z: .a, kVK_Space: .a, kVK_ANSI_X: .b, kVK_ANSI_C: .x, kVK_ANSI_V: .y, kVK_Return: .start,
    ]
    #else
    static var touched: Set<Button> = [] // held on the touch controls
    static var keys: Set<GCKeyCode> = [] // held on a keyboard, fed by GameViewController

    static let keyMap: [GCKeyCode: Button] = [ // an iPad's keyboard, or the Mac's in the editor's preview
        .leftArrow: .left, .keyA: .left, .rightArrow: .right, .keyD: .right, .upArrow: .up, .keyW: .up,
        .downArrow: .down, .keyS: .down, .keyZ: .a, .spacebar: .a, .keyX: .b, .keyC: .x, .keyV: .y, .returnOrEnter: .start,
    ]
    #endif

    /// Runs before each update. ponytail: a tap shorter than one update (1/60 s) is missed; queue key events if that bites.
    static func poll() {
        before = now
        #if os(macOS)
        now = Set(keys.compactMap { keyMap[$0] })
        #else
        now = touched.union(keys.compactMap { keyMap[$0] })
        #endif
        guard let pad = GCController.current?.extendedGamepad else { return }
        let (x, y) = (pad.leftThumbstick.xAxis.value, pad.leftThumbstick.yAxis.value)
        if pad.dpad.left.isPressed || x < -0.5 { now.insert(.left) }
        if pad.dpad.right.isPressed || x > 0.5 { now.insert(.right) }
        if pad.dpad.up.isPressed || y > 0.5 { now.insert(.up) }
        if pad.dpad.down.isPressed || y < -0.5 { now.insert(.down) }
        if pad.buttonA.isPressed { now.insert(.a) }
        if pad.buttonB.isPressed { now.insert(.b) }
        if pad.buttonX.isPressed { now.insert(.x) }
        if pad.buttonY.isPressed { now.insert(.y) }
        if pad.buttonMenu.isPressed { now.insert(.start) }
    }
}
