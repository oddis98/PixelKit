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

Games read the mouse and fingers too, for menus, puzzles and anything tapped or dragged: `Input.pointer` is where the mouse is over the game, or a finger on it, in canvas pixels (nil when there's none), and `Input.pressed(.pointer)` is a click or a tap, as `Input.pressed(.a)` is a button. Add the scene's `camera` for world pixels: `if Input.pressed(.pointer), let point = Input.pointer, chest.contains(point + camera)`.

Next, give it a sprite: put a PNG in `Assets/Sprites/` (say `Assets/Sprites/player.png`), and add an `Entity` whose `sprite = Sprite("player")` (or `Sprite(.player)` once the editor has named your assets, below). Games find assets by name in any folder of `Assets`, so sprites, tilesets, maps, objects and sounds each get a folder of their own. [`Examples/Platformer`](Examples/Platformer) shows a whole game: a level, animations, collisions and sounds. [`Examples/Village`](Examples/Village) is a top-down one: walking behind trees and under roofs (`ySort` and layers above), a camera that follows, a door that closes in an iris into a house lit by its fire, a villager in a text box that a click or a tap moves on, and saves.

For effects, a sprite's `flash` whitens it when it's hit, `Scene.transition(to:style:)` changes scenes with a fade, a wipe, an iris or a dissolve, and a scene's `darkness` dims all but what its entities' lights light: `torch.light = Light(radius: 48, color: 0xFFA300, flicker: 0.1)`.

## The editor

```bash
swift run Editor
```

The code editor uses your Xcode theme, light and dark, and colors names the way Xcode does: your game's own in the project colors, PixelKit's and Apple's in the others.

It edits and navigates like Xcode too: completions with placeholders you Tab between, Quick Help (⌥-click), a column selected with ⌥-drag, Open Quickly (⇧⌘O), Go Back and Forward (⌃⌘← ⌃⌘→), the Issue navigator (⌘5, and ⌘' for the next issue), with each issue's notes folded under it, in any file, and Editor ▸ Structure's shortcuts (⌘/ ⌘[ ⌘] ⌥⌘[ ⌥⌘] ⌃I). Return and Re-Indent indent as Xcode does, chains, continued lines and arguments included, and a long line wraps indented. Make Swift files and folders with ⌘N and ⌥⌘N or from the Project navigator's context menu, and rename one with Return or a second click on its name; a new file's classes work from your other files right away. Menu items that can't do anything grey out.

And it runs like Xcode: pick My Mac, your iPhone or iPad, or an iPhone simulator in the middle of the toolbar and press ⌘R. The activity view beside it shows the build's progress and its errors and warnings, which open the Issue navigator. While a game runs on the Mac, ⌘R switches it to your latest code and keeps its state, and Build (⌘B) leaves it running. The console shows the game's output, or the build log. Product ▸ Clean Build Folder (⇧⌘K) starts the next build from scratch. Editor ▸ Canvas zooms the preview, past the size that fits, which then scrolls, and Zoom to 100% is ⌃⌘=.

The pixel and map editors pick tools from the keyboard, with Aseprite's letters: B pencil (the map's paint), E eraser, G fill, L line, U rectangle, I picker, M select, and O for the map's objects. As in Aseprite, the right button (or a ⌃-click) erases with the tools that draw. A layer's context menu puts it Above Objects, for roofs and treetops, and a running game shows newly painted tiles right away. Double-click a layer to rename it. Resize… changes the size of each frame of an image, scaling the art or adding and cropping pixels around it, and Add Tiles… grows a tileset by whole tiles, renumbering the tiles of the maps that use it when it adds columns.

A game's objects (a coin, a tree, a villager, a door, where the player starts) are defined once, in `Assets/Objects`: the sprite each is drawn with, and any more it has, each at an offset and drawn with it or over everything, like a tree's crown; the part that collides, whether it's solid, its properties with their types and defaults, and the Swift class it's made as, any `final class Villager: Entity, Placeable`. The object editor sets all that, with the hitbox and the other sprites dragged on the sprite. Its Class popup offers the game's `Placeable` classes, and a class renamed in your code is renamed in the objects made as it. Properties are text, numbers, toggles, colors, points, the game's sprites, sounds, maps or objects, or a list of any of those, and code reads them as what they are: `door.map("to")` is a `MapName?` that `Tilemap(_:)` takes, and `guard.list("path", of: Vector.self)` the points of a patrol. The map editor puts objects down from its list, or dragged from the Library (⇧⌘L, or + above the map), as Xcode's Library puts views on a storyboard, snapping to the tiles (hold ⌥ to place them freely), with a control for each property's type, and a point chosen with a click on the map; drag an object's corner to size it, for doors and other zones. A scene's `addObjects()` then makes each object placed in its map as its class, which reads the map's settings for it from `object`. Tiles carry properties too, like water or damage: the map editor gives a tileset's tiles typed properties beside Solid, and a game reads the tile under a point's, `tilemap.properties(at: feet, layer: 0).bool("water")`. Renaming a sprite, map, object or sound in the Project navigator renames it in the maps and objects that name it, their parts and properties included.

Your code names assets the way an app names its images in Xcode: `Sprite(.slime)`, `Tilemap(.level1)`, `Sound.play(.jump)`, `screen.panel(.textbox, in: box)`, `objects(named: .start)`. The editor writes a Swift name for each image, map, sound and object in `Sources/<Game>/AssetNames.swift` and again whenever they change, so completion offers them after the dot, one made a moment ago included, and a typo, or an asset renamed or deleted, is an error where it's used instead of a crash when the game gets there. An object's property that names a map, object, sprite or sound reads as a name too: `door.map("to")`. Strings still work, for names that come from elsewhere: `Tilemap("level2")`, or `MapName(text)` to pass one on as a name. Renaming an asset in the Project navigator renames its uses in your code too, as Xcode's Refactor ▸ Rename does: in the file you're editing, where Undo takes it back, and in the others. Names in strings stay as they are, and completion offers them in `Sprite("`, `Tilemap("`, `Sound.play("` and the others. A game made before PixelKit named its assets gets them after File ▸ Packages ▸ Update to Latest Package Versions, which updates its PixelKit.

Drag art from Finder onto the Project navigator to copy it in: onto `Assets`, each file goes into its kind's folder, a name that's taken gets a number, and JPEGs, GIFs and other images become PNGs. A sheet exported from Aseprite comes in with its animations when its `.json` comes along: one for each tag, played in its direction, each frame held as long as Aseprite holds it. Art dropped on a map goes into `Assets/Sprites` and onto the map as a new object drawn with it, and art dropped into the pixel editor is pasted where it's let go.

The toolbar's New menu, like File ▸ New, makes a sprite, tileset, map or object in its folder, and Organize Assets, in the `Assets` folder's context menu, sorts an older game's files into those folders without renaming anything.

New Game (⇧⌘N) writes a starter game that gets PixelKit from this repo on GitHub. Export App… makes it a Mac app, whose icon is the game's `Assets/AppIcon.png` if it has one: square pixel art, drawn right to the edges, since macOS rounds the corners (see Shipping, below).

To bundle the editor as an app:

```bash
BUNDLE_ID=app.pixelkit.editor CATEGORY=public.app-category.developer-tools scripts/make-app.sh . "PixelKit Editor.app" Editor
```

To work on the engine itself, start the editor with `PIXELKIT_LOCAL` set to your checkout, and new games use it instead of GitHub:

```bash
PIXELKIT_LOCAL="$PWD" swift run Editor
```

## iPhone and iPad

Games run in the iOS Simulator too, reaching the screen's edges, with a D-pad and A, B, X and Y buttons drawn over the game, or below it when the phone is upright; game controllers and iPad keyboards work as well, and the buttons hide while they're used, coming back with a touch. A finger on the game that isn't on the buttons is its pointer. Add `.iOS(.v18)` to your game's `platforms` (New Game does), then choose an iPhone simulator in the editor's toolbar and press ⌘R. The simulator's screen shows in the preview, in Xcode's frame for the device: click and drag to touch it, click it to type, and press Home or Rotate in its bar (and Fold or Unfold on iPhone Duo). Or, from this repo:

```bash
scripts/make-ios-app.sh path/to/MyGame MyGame.app
```

```bash
xcrun simctl install booted MyGame.app && xcrun simctl launch booted games.pixelkit.MyGame
```

To play on your own iPhone or iPad, choose it under iOS Devices in the toolbar and press ⌘R: the editor builds the game, signs it, installs it there and shows its output in the console, and Stop ends it. It signs with the development profile Xcode makes for your team, so sign in to your Apple Account in Xcode's Accounts settings and run any app on the device from Xcode once, which registers it. The device needs Developer Mode on, in its Settings under Privacy & Security. With more than one team, choose the one that signs games in the editor's Settings (⌘,). From this repo, give the script that profile and one of its signing identities:

```bash
PROFILE=path/to/profile.mobileprovision IDENTITY="Apple Development: …" scripts/make-ios-app.sh path/to/MyGame MyGame.app
```

```bash
xcrun devicectl device install app --device <udid> MyGame.app && xcrun devicectl device process launch --device <udid> --console games.pixelkit.MyGame
```

## Shipping

Choose the game at the top of the Project navigator for its settings, as Xcode shows a project's: its name on the home screen, bundle identifier, version and build, kept in an `Info.plist` beside its `Package.swift`, and its capabilities, Game Center and iCloud (key-value storage), kept in its `.entitlements` there. Give it a bundle identifier of your own before you distribute it. Its icon is `Assets/AppIcon.png`, square pixel art scaled up without smoothing, on iPhone and iPad too (Draw App Icon there makes one).

Product ▸ Archive builds the game for iPhones and iPads, signed by your team, into Xcode's archives, where Xcode's Organizer lists it too, and offers Distribute App, which signs it for App Store Connect and uploads it, as the Organizer does. Create the app in App Store Connect first, with the same bundle identifier; once Apple has processed the build, TestFlight has it. Xcode makes the App ID, profiles and distribution certificate it needs with the account you're signed in with in its Accounts settings, and the same goes for a game with capabilities the first time it runs on your device.

Export App… signs the Mac app with your team's Developer ID once you add a Developer ID Application certificate in Xcode's Accounts settings (Manage Certificates). To notarize it too, so it opens on other Macs without a warning, store your credentials once, then enter the profile's name (here, `PixelKit`) in the editor's Settings (⌘,):

```bash
xcrun notarytool store-credentials PixelKit
```

## More

- [ROADMAP.md](ROADMAP.md): how PixelKit works and what's done
- [ROADMAP-NEXT.md](ROADMAP-NEXT.md): what's next

Before 1.0, a minor version (0.2, 0.3, …) may change the API.

PixelKit is released under the [MIT License](LICENSE).
