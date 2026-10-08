import AppKit

/// A PixelKit game. Mark your conforming type `@main` and PixelKit opens a window and runs it.
@MainActor public protocol Game {
    init()
    /// Size of the pixel canvas. The window scales it up by whole numbers so pixels stay square and crisp.
    var resolution: Size { get }
    /// Called every frame. Draw the whole frame here.
    func draw(_ screen: Screen)
}

public struct Size: Sendable {
    public var width, height: Int

    public init(_ width: Int, _ height: Int) {
        self.width = width
        self.height = height
    }
}

public extension Game {
    var resolution: Size { Size(320, 180) }

    static func main() {
        setvbuf(stdout, nil, _IOLBF, 0) // print() reaches the editor console line by line, not when a buffer fills
        let app = NSApplication.shared
        app.setActivationPolicy(.regular) // ponytail: games run as bare executables for now; a bundle (Phase 7) makes this unnecessary
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit \(Self.self)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        app.mainMenu = NSMenu()
        app.mainMenu!.addItem(withTitle: "", action: nil, keyEquivalent: "").submenu = appMenu

        let game = Self()
        let size = game.resolution
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: size.width * 3, height: size.height * 3),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "\(Self.self)"
        window.contentMinSize = NSSize(width: size.width, height: size.height)
        window.contentView = GameView(game: game)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            exit(0) // closing the window quits the game
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        app.activate()
        withExtendedLifetime(window) { app.run() }
    }
}
