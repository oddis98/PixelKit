# PixelKit

A Swift engine for 2D pixel art games, plus an editor for macOS with a code editor, pixel art and tilemap tools, a live game preview with hot reload, and one-click export to a Mac app.

Games are Swift packages. They run on macOS 15 or later, and building them needs Xcode or the Swift toolchain (developed with Swift 6.4).

## Five-minute start

In an empty folder, make `Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hello",
    platforms: [.macOS(.v15)],
    dependencies: [.package(url: "https://github.com/oddis98/PixelKit.git", from: "0.1.0")],
    targets: [.executableTarget(name: "Hello", dependencies: [.product(name: "PixelKit", package: "PixelKit")])]
)
```

and `Sources/Hello/Hello.swift`:

```swift
import PixelKit

@main struct Hello: Game {
    func start() -> Scene { Title() }
}

final class Title: Scene {
    override func update(_ dt: Double) {
        super.update(dt)
        if Input.pressed(.a) { background = .random(in: 0...0xFFFFFF) } // Space or Z
    }
}
```

Then `swift run`. A window opens on a 320×180 canvas; press Space for a new color.

Next, give it a sprite: put a PNG in `Assets/` (say `Assets/player.png`), and add an `Entity` whose `sprite = Sprite("player")`. [`Examples/Platformer`](Examples/Platformer) shows a whole game: a level, animations, collisions and sounds.

## The editor

```bash
swift run Editor
```

New Game (⌘N) writes a starter game that gets PixelKit from this repo on GitHub. Export App… makes it a Mac app, whose icon is the game's `Assets/AppIcon.png` if it has one: square pixel art, drawn right to the edges, since macOS rounds the corners.

To bundle the editor as an app:

```bash
BUNDLE_ID=app.pixelkit.editor CATEGORY=public.app-category.developer-tools scripts/make-app.sh . "PixelKit Editor.app" Editor
```

To work on the engine itself, start the editor with `PIXELKIT_LOCAL` set to your checkout, and new games use it instead of GitHub:

```bash
PIXELKIT_LOCAL="$PWD" swift run Editor
```

## iPhone and iPad

Games run in the iOS Simulator too, with a D-pad and A and B buttons drawn over the game; game controllers and iPad keyboards work as well. Add `.iOS(.v18)` to your game's `platforms` (New Game does), then click Run on iPhone Simulator in the editor. Or, from this repo:

```bash
scripts/make-ios-app.sh path/to/MyGame MyGame.app
```

```bash
xcrun simctl install booted MyGame.app && xcrun simctl launch booted games.pixelkit.MyGame
```

## More

- [ROADMAP.md](ROADMAP.md): how PixelKit works and what's done
- [ROADMAP-NEXT.md](ROADMAP-NEXT.md): what's next

Before 1.0, a minor version (0.2, 0.3, …) may change the API.

PixelKit is released under the [MIT License](LICENSE).
