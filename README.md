# PixelKit

A Swift engine for 2D pixel art games on the Mac, iPhone and iPad.

Games are Swift packages that depend on PixelKit. They run on macOS 15 or later and iOS 18 or later, and building them needs Xcode or the Swift toolchain (developed with Swift 6.4).

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

## How a game works

- **A game** is the `@main` type that conforms to `Game`. It gives the size of its canvas (`resolution`, 320×180 unless it says otherwise), which the window scales up by whole numbers so pixels stay square, and the `Scene` it starts in.
- **A scene** updates 60 times a second (`update(_:)`) and draws its tilemap, its entities and whatever else it draws on the `Screen` (`draw(_:)`), through a `camera` that can `follow` an entity. `Scene.transition(to:style:)` goes to the next scene with a fade, a wipe, an iris or a dissolve.
- **Entities** are what moves: a position, a velocity, a hitbox and a `Sprite`. `move(dt)` moves one by its velocity, stopping it flush against solid tiles and other solid entities, and `path(to:)` finds a way around walls that `walk(_:along:speed:)` follows.
- **Sprites** are PNGs, cut into frames and animations by a `.json` beside them: `Sprite("player")`, then `sprite.play("walk")`. They tint, fade, and `flash` white when hit.
- **Tilemaps** are levels: layers of tiles from a tileset, some drawn above the entities (roofs, treetops), with solid tiles, properties on tiles, and objects placed on them. A scene's `addObjects()` makes each object as its Swift class (`final class Coin: Entity, Placeable`), which reads the object's properties as what they are: `door.map("to")`. `add(.chest, at: point)` makes one in code from its definition, for what the player builds or what comes out at night.
- **Assets** live in the game's `Assets` folder, in `Sprites`, `Tilesets`, `Maps`, `Objects`, `Sounds` and `Shaders`, and are found by name. For names the compiler checks, extend `ImageName`, `MapName`, `SoundName`, `ObjectName` and `ShaderName` (`static let player = ImageName("player")`) and write `Sprite(.player)`.
- **Input** is one gamepad, the D-pad, A, B, X, Y and Start, from the keyboard, game controllers, and on iPhone and iPad touch controls drawn over the game: `Input.pressed(.a)`. The mouse or a finger is the pointer: `Input.pointer` is where it is, in canvas pixels, and `Input.pressed(.pointer)` a click or a tap.
- **Sound and music:** `Sound.play(.jump)` for effects, and `Music.play(.theme, fade: 1)`, which loops and pauses with the game. `Sound.volume` and `Music.volume` turn each down, for a game's settings.
- **Text:** `screen.text` writes with a built-in 3×5 font or one drawn as an image, and `screen.panel` draws text boxes that stretch.
- **Light:** a scene's `darkness` dims the world toward a color, and the `Light`s its entities carry light it again: a torch, a fire, a lantern. A light with `shadows` stops at the tiles a tileset marks opaque and at opaque entities' hitboxes (`opaque`), so trunks and walls cast shadows; one brighter than 1 lights past daylight, like a flash of lightning by day, and one below 0 takes light away, like a gloom, its `gray` draining color too. An `image` shapes a light, turned by its `angle`. The light is worked out at the game's pixels before the world is drawn, each pixel lit as a whole, as its art is, so it's sharp and costs the same at any size; what's drawn after `super.draw`, like a HUD, stays lit.
- **Weather and mood:** `clouds` drift over a scene, shading its daylight; `fog` drifts over its world, lit as the ground is; both are soft unless they're `smooth: false`, when their edges are dithered as pixel art's are; `vignette` darkens the view's corners, and `gray` drains the world's color. `backdrops` (a sky, far hills) and `overhangs` (a canopy of leaves) are images behind the map and over the world that move at their own rate as the camera does, repeat and sway. `shake(_:)` shakes the view, and `screen.bolt` draws a lightning bolt; a sprite that `glows` is added to what's under it, so it shines in the dark.
- **Shaders:** a game can write its own in Metal, `Assets/Shaders/<name>.metal`, a function named as its file, as SwiftUI's are. A color shader, `half4 name(float2 position, half4 color, Values values)`, goes on a sprite (`sprite.shader = Shader(.shimmer, [0.5])`); a layer shader, `half4 name(float2 position, Layer layer, Values values)`, goes on the picture (`scene.effects = [Shader(.ripple, [x, y, t])]`) and reads it with `layer.sample(position)`. They compile while the game runs, again when their file is saved, and print their errors with the file and line.
- **Saves:** `Save.write(progress, to: "progress")` and `Save.read(Progress.self, from: "progress")` keep `Codable` values between launches.

## Examples

- [`Examples/Platformer`](Examples/Platformer): a level to run and jump through, with coins, animations, collisions and sounds.
- [`Examples/Village`](Examples/Village): a top-down game. Walk behind trees and under roofs as clouds drift over, through a door into a house lit by its fire, and through a gap in the hedge into a wood at dusk, under a canopy of leaves, lit by your lantern; talk to a villager who walks around a hedge to the garden; call lightning down with Y (V on a keyboard) and a gloom with B (X). It saves where you are.

Run one with `cd Examples/Platformer && swift run`.

## Versions

Before 1.0, a minor version (0.2, 0.3, …) may change the API.

PixelKit is released under the [MIT License](LICENSE).
