#if os(macOS)
import Carbon.HIToolbox // kVK_ key codes
#endif
import GameController

/// A virtual gamepad. Keyboard: arrows or WASD, Z or Space = a, X = b, C = x, V = y, Return = start.
/// Game controllers: d-pad or left stick, A, B, X, Y, Menu. On iOS, also the touch controls over the game.
/// And the pointer's press: the mouse's button, or a finger on the game.
public enum Button: Sendable, CaseIterable {
    case left, right, up, down, a, b, x, y, start
    /// The mouse's button down on the game, or on iOS a finger on it that didn't land on the touch controls;
    /// `Input.pointer` says where.
    case pointer
}

/// The virtual gamepad and the pointer, read in `update`: `Input.held(.right)`, `Input.pressed(.a)`,
/// `Input.pressed(.pointer)`.
@MainActor public enum Input {
    /// True while the button is down.
    public static func held(_ button: Button) -> Bool { now.contains(button) }

    /// True only on the update when the button goes down.
    public static func pressed(_ button: Button) -> Bool { now.contains(button) && !before.contains(button) }

    /// Where the mouse is over the game, or the finger that's the pointer, in canvas pixels from the top-left corner;
    /// nil when there's none. Dragged past the canvas's edge, it stays on the edge until it lets go. Add the scene's
    /// `camera` for world pixels: `if Input.pressed(.pointer), let point = Input.pointer, chest.contains(point + camera)`.
    public private(set) static var pointer: Vector?

    static var now: Set<Button> = []
    static var before: Set<Button> = []

    static var canvas = Size(320, 180) // the game's resolution, from its loop
    static var mouse: Vector? // the pointer as its last event left it
    static var down = false // held on the canvas, or dragged off it
    static var click: Vector? // where it went down, until an update sees it, so a click between two updates counts

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
    static var hardware = false // a keyboard or controller held something in the last update, so the touch controls hide

    static let keyMap: [GCKeyCode: Button] = [ // an iPad's keyboard, or the Mac's in the editor's preview
        .leftArrow: .left, .keyA: .left, .rightArrow: .right, .keyD: .right, .upArrow: .up, .keyW: .up,
        .downArrow: .down, .keyS: .down, .keyZ: .a, .spacebar: .a, .keyX: .b, .keyC: .x, .keyV: .y, .returnOrEnter: .start,
    ]
    #endif

    /// The mouse or the pointer's finger at `pixel`, which may be off the canvas, with its button or the finger `down`,
    /// or nil once it's gone. It's held while down on the canvas, and a drag off it stays held, on its edge.
    static func point(_ pixel: Vector?, down isDown: Bool) {
        let edge: Vector = [Double(canvas.width - 1), Double(canvas.height - 1)]
        let inside = pixel.map { all($0 .>= Vector.zero .& $0 .<= edge) } ?? false
        if isDown, !down, inside { click = pixel }
        down = isDown && pixel != nil && (down || inside)
        mouse = down ? pixel?.clamped(lowerBound: .zero, upperBound: edge) : inside ? pixel : nil
    }

    /// Runs before each update. ponytail: a key tapped between two updates (1/60 s) is missed; queue key events if that
    /// bites. Clicks aren't missed (`click`): a trackpad's tap-to-click goes down and up at once.
    static func poll() {
        before = now
        var pad: Set<Button> = [] // a game controller's
        if let gamepad = GCController.current?.extendedGamepad {
            let (x, y) = (gamepad.leftThumbstick.xAxis.value, gamepad.leftThumbstick.yAxis.value)
            if gamepad.dpad.left.isPressed || x < -0.5 { pad.insert(.left) }
            if gamepad.dpad.right.isPressed || x > 0.5 { pad.insert(.right) }
            if gamepad.dpad.up.isPressed || y > 0.5 { pad.insert(.up) }
            if gamepad.dpad.down.isPressed || y < -0.5 { pad.insert(.down) }
            if gamepad.buttonA.isPressed { pad.insert(.a) }
            if gamepad.buttonB.isPressed { pad.insert(.b) }
            if gamepad.buttonX.isPressed { pad.insert(.x) }
            if gamepad.buttonY.isPressed { pad.insert(.y) }
            if gamepad.buttonMenu.isPressed { pad.insert(.start) }
        }
        #if os(macOS)
        now = pad.union(keys.compactMap { keyMap[$0] })
        #else
        hardware = !keys.isEmpty || !pad.isEmpty
        now = pad.union(touched).union(keys.compactMap { keyMap[$0] })
        #endif
        pointer = click ?? mouse
        if down || click != nil { now.insert(.pointer) }
        click = nil
    }
}
