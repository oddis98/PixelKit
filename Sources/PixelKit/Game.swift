#if os(macOS)
import AppKit
#else
import UIKit
#endif
import GameController
import PixelKitProtocol

/// A PixelKit game. Mark your conforming type `@main` and PixelKit opens a window and runs it (on iOS, the app's
/// screen, with touch controls over it).
@MainActor public protocol Game {
    init()
    /// Size of the pixel canvas. The window scales it up by whole numbers so pixels stay square and crisp.
    var resolution: Size { get }
    /// The scene the game starts in.
    func start() -> Scene
}

/// A position or velocity in pixels.
public typealias Vector = SIMD2<Double>

/// A width and height in pixels, like a game's `resolution`.
public struct Size: Sendable, Equatable {
    public var width, height: Int

    public init(_ width: Int, _ height: Int) {
        self.width = width
        self.height = height
    }
}

/// A rectangle in pixels: its top-left corner and its size, like an entity's `hitbox`.
public struct Rect: Sendable, Equatable {
    public var x, y, width, height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        (self.x, self.y, self.width, self.height) = (x, y, width, height)
    }

    /// True when the two overlap by a pixel or more.
    public func intersects(_ other: Rect) -> Bool {
        x < other.x + other.width && other.x < x + width && y < other.y + other.height && other.y < y + height
    }
}

public extension Game {
    var resolution: Size { Size(320, 180) }

    static func main() {
        setvbuf(stdout, nil, _IOLBF, 0) // print() reaches the editor console line by line, not when a buffer fills
        let game = Self()
        Scene.current = game.start()
        #if os(macOS)
        if let path = ProcessInfo.processInfo.environment[Message.environmentKey], let channel = Channel.connect(to: path) {
            runInEditor(game.resolution, channel)
        } else {
            runInWindow(game.resolution)
        }
        #else
        GameApp.resolution = game.resolution
        _ = UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(GameApp.self))
        #endif
    }
    #if os(macOS)

    /// Run by the editor: no window or Dock icon, the editor's preview shows the frames.
    private static func runInEditor(_ size: Size, _ channel: Channel) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        GCController.shouldMonitorBackgroundEvents = true // game controllers keep working while the editor is in front
        let host = EditorHost(resolution: size, channel: channel)
        channel.listen { message in
            DispatchQueue.main.async { MainActor.assumeIsolated { host.handle(message) } }
        } closed: {
            exit(0) // the editor stopped us or went away
        }
        Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { _ in MainActor.assumeIsolated { host.frame() } }
        app.run()
    }

    private static func runInWindow(_ size: Size) {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular) // the editor runs games as bare executables, which need this; harmless in an app
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit \(Self.self)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        app.mainMenu = NSMenu()
        app.mainMenu!.addItem(withTitle: "", action: nil, keyEquivalent: "").submenu = appMenu

        let view = GameView(resolution: size)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: size.width * 3, height: size.height * 3),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "\(Self.self)"
        window.contentMinSize = NSSize(width: size.width, height: size.height)
        window.contentView = view
        window.makeFirstResponder(view)
        let center = NotificationCenter.default
        center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            exit(0) // closing the window quits the game
        }
        center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated { Input.keys.removeAll() } // key-ups go elsewhere once we lose focus
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        app.activate()
        withExtendedLifetime(window) { app.run() }
    }
    #endif
}
