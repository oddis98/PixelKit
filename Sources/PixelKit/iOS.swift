#if os(iOS)
import GameController
import UIKit
#endif
import CoreGraphics

/// Where the touch controls go in a view of `size` points: a D-pad at the bottom left, and A, B, X and Y at the bottom
/// right in a diamond, as on a Super Nintendo's pad (A right, B below, X above, Y left), clear of the safe area's
/// `left`, `right` and `bottom` insets (rounded corners, the notch).
struct TouchLayout {
    static let pad = 50.0, button = 26.0 // radii, in points
    static let spread = button * 1.6 // from the diamond's middle to each button's
    let dpad, a, b, x, y: CGPoint

    init(size: CGSize, left: Double, right: Double, bottom: Double) {
        let floor = size.height - max(bottom, 12) - 16
        dpad = CGPoint(x: left + 24 + Self.pad, y: floor - Self.pad)
        let middle = CGPoint(x: size.width - right - 24 - Self.button - Self.spread, y: floor - Self.button - Self.spread)
        a = CGPoint(x: middle.x + Self.spread, y: middle.y)
        b = CGPoint(x: middle.x, y: middle.y + Self.spread)
        x = CGPoint(x: middle.x, y: middle.y - Self.spread)
        y = CGPoint(x: middle.x - Self.spread, y: middle.y)
    }

    /// The buttons a finger at `point` holds. Between two of the D-pad's directions, it holds both.
    func buttons(at point: CGPoint) -> Set<Button> {
        var held: Set<Button> = []
        let (dx, dy) = (point.x - dpad.x, point.y - dpad.y)
        let distance = (dx * dx + dy * dy).squareRoot()
        if distance > Self.pad * 0.2, distance < Self.pad * 1.6 { // some slack all round: fingers are big
            if abs(dx) > distance * 0.38 { held.insert(dx < 0 ? .left : .right) } // 0.38 ≈ sin 22.5°: eight directions
            if abs(dy) > distance * 0.38 { held.insert(dy < 0 ? .up : .down) }
        }
        for (center, button) in [(a, Button.a), (b, .b), (x, .x), (y, .y)] where hypot(point.x - center.x, point.y - center.y) < Self.button * 1.4 {
            held.insert(button) // between two, both: one thumb can press two
        }
        return held
    }
}

#if os(iOS)
/// The iOS app around a game. UIKit makes one of these as the app's delegate, and another for its window's scene.
final class GameApp: UIResponder, UIApplicationDelegate, UIWindowSceneDelegate {
    static var resolution = Size(320, 180)
    var window: UIWindow?

    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = GameApp.self
        return configuration
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        window = UIWindow(windowScene: scene)
        window?.rootViewController = GameViewController()
        window?.makeKeyAndVisible()
    }
}

/// The game scaled up to the screen's edges, with the touch controls over it, or below it when the screen is portrait.
final class GameViewController: UIViewController {
    override func loadView() {
        let game = GameView(resolution: GameApp.resolution)
        let controls = TouchControls(frame: game.bounds)
        controls.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        game.addSubview(controls)
        view = game
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }

    // A keyboard's keys, as UIKit has them: GCKeyboard misses the ones the editor's preview sends a simulator.
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) { press(presses, down: true) }
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) { press(presses, down: false) }
    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) { press(presses, down: false) }

    private func press(_ presses: Set<UIPress>, down: Bool) {
        for case let key? in presses.map(\.key) {
            let code = GCKeyCode(rawValue: key.keyCode.rawValue)
            if down { Input.keys.insert(code) } else { Input.keys.remove(code) }
        }
    }
}

/// A D-pad and A, B, X and Y buttons, drawn over the game. Every finger on them holds the buttons under it.
final class TouchControls: UIView {
    private var held: Set<Button> = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        isMultipleTouchEnabled = true
        contentMode = .redraw // the layout depends on the size
    }

    required init?(coder: NSCoder) { fatalError("TouchControls is created in code") }

    private var layout: TouchLayout {
        TouchLayout(size: bounds.size, left: safeAreaInsets.left, right: safeAreaInsets.right, bottom: safeAreaInsets.bottom)
    }

    override func safeAreaInsetsDidChange() { setNeedsDisplay() }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { update(event) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { update(event) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { update(event) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { update(event) }

    private func update(_ event: UIEvent?) {
        let layout = layout
        let fingers = (event?.allTouches ?? []).filter { $0.phase != .ended && $0.phase != .cancelled }
        let now = fingers.reduce(into: Set<Button>()) { $0.formUnion(layout.buttons(at: $1.location(in: self))) }
        guard now != held else { return }
        held = now
        Input.touched = now
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        let layout = layout
        func circle(_ center: CGPoint, _ radius: Double, pressed: Bool) {
            UIColor(white: 1, alpha: pressed ? 0.55 : 0.25).setFill()
            UIBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()
        }
        circle(layout.dpad, TouchLayout.pad, pressed: false)
        for (button, dx, dy) in [(Button.left, -1.0, 0.0), (.right, 1, 0), (.up, 0, -1), (.down, 0, 1)] {
            let center = CGPoint(x: layout.dpad.x + dx * TouchLayout.pad * 0.6, y: layout.dpad.y + dy * TouchLayout.pad * 0.6)
            circle(center, TouchLayout.pad * 0.32, pressed: held.contains(button))
        }
        for (button, center, name) in [(Button.a, layout.a, "A"), (.b, layout.b, "B"), (.x, layout.x, "X"), (.y, layout.y, "Y")] {
            circle(center, TouchLayout.button, pressed: held.contains(button))
            let label = NSAttributedString(string: name, attributes: [.font: UIFont.boldSystemFont(ofSize: 18),
                                                                      .foregroundColor: UIColor(white: 1, alpha: 0.75)])
            label.draw(at: CGPoint(x: center.x - label.size().width / 2, y: center.y - label.size().height / 2))
        }
    }
}
#endif
