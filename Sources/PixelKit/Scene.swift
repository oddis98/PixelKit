import Foundation
import PixelKitProtocol

/// A level, menu or screen: a tilemap plus the entities in it.
@MainActor open class Scene {
    /// The scene on screen. Assign a new one to switch scenes, or a fresh copy to restart.
    public static var current = Scene()

    /// Everything in the scene, in the order it updates and draws.
    public private(set) var entities: [Entity] = []
    /// The level's tiles, drawn behind the entities but for its layers `above` them. `Entity.move(_:)` stops against
    /// its solid ones.
    public var tilemap: Tilemap?
    /// Top-left corner of the view, in world pixels.
    public var camera = Vector.zero
    /// An entity the camera keeps in the middle of the view, never showing past the tilemap's edges. A map smaller
    /// than the view sits in the middle of it. It sets `camera` each time the scene draws.
    public var follow: Entity?
    /// Draws the entities from the top of the view down by their `sortY`, their feet, so they pass behind and in front
    /// of each other and of trees and houses: for top-down games. Off, they draw in the order they were added.
    public var ySort = false
    /// Clear color as 0xRRGGBB.
    public var background: UInt32 = 0x1D2B53
    /// How dark the scene is, from 0, lit (the default), to 1, as dark as `darknessColor`, where on black nothing shows
    /// but what the entities' `light`s light: for nights, caves and houses with the lights out. What's drawn after
    /// `super.draw`, like a HUD, stays lit.
    public var darkness = 0.0
    /// The color of the dark, 0xRRGGBB, which multiplies what it darkens: black (the default), or a night's deep blue.
    public var darknessColor: UInt32 = 0x000000

    public init() {}

    /// Switches to `next` through `color`: this scene stands still while the view fades to the color over the first
    /// half of `duration` seconds, then `next` becomes `current` and updates while it fades back in. It's
    /// `transition(to:duration:style:color:)`'s fade.
    public static func fade(to next: Scene, duration: Double = 0.5, color: UInt32 = 0x000000) {
        transition(to: next, duration: duration, style: .fade, color: color)
    }

    /// Switches to `next` over `duration` seconds in a `style`: a fade, a wipe or an iris goes through `color`, this
    /// scene standing still until the color covers the view, halfway, then `next` becoming `current` and updating as
    /// it's uncovered; a dissolve has `next` update from the start, under this scene's last frame as it breaks up. A
    /// transition covers everything, a HUD too, and pauses with the game. `Scene.current = next` switches at once.
    public static func transition(to next: Scene, duration: Double = 0.5, style: Transition = .fade, color: UInt32 = 0x000000) {
        guard duration > 0 else { return current = next }
        changing = Change(next: next, duration: duration, style: style, color: color)
    }

    /// The transition under way, if any.
    static var changing: Change?

    /// One update of the game: the current scene's, unless it's standing still for a transition.
    static func tick(_ dt: Double) {
        guard var change = changing else { return current.update(dt) }
        change.time += dt
        if let next = change.next, change.time >= change.switchTime { (current, change.next) = (next, nil) }
        changing = change.time < change.duration ? change : nil
        if change.next == nil { current.update(dt) }
    }

    /// Puts an entity in the scene with its top-left corner at `position`, in world pixels.
    public func add(_ entity: Entity, at position: Vector) {
        entity.position = position
        entity.scene = self
        entities.append(entity)
    }

    /// Takes an entity out of the scene, even from its own `update`.
    public func remove(_ entity: Entity) {
        entities.removeAll { $0 === entity }
        entity.scene = nil
    }

    /// Adds the tilemap's objects that are things in the world and returns them: each one whose definition names a
    /// class, made as that class (a `Placeable`), or that has sprites, as an `Entity`. Zones and markers stay in
    /// `tilemap.objects` for the game to read, like a door to step on or where the player starts.
    @discardableResult public func addObjects() -> [Entity] {
        (tilemap?.objects ?? []).compactMap { object in
            guard object.class != nil || object.sprite != nil || !object.parts.isEmpty else { return nil }
            let entity = Self.make(object)
            add(entity, at: object.position)
            return entity
        }
    }

    /// Makes the object `name` from its definition, `Assets/Objects/<name>.object`, as `addObjects()` makes a map's,
    /// as if placed at `position` with `properties` of its own over the definition's, and adds it: something the player
    /// builds, or a creature that comes out at night.
    @discardableResult public func add(_ name: ObjectName, at position: Vector, properties: [String: String] = [:]) -> Entity {
        add(name.name, at: position, properties: properties)
    }

    /// The same, with the object named in a string, like a den's `creature`. Without a definition it's an empty
    /// `Entity`, and the console says why, once.
    @_disfavoredOverload @discardableResult
    public func add(_ name: String, at position: Vector, properties: [String: String] = [:]) -> Entity {
        let url = assetURL("\(name).object")
        var definition: ObjectFile?
        do { definition = try ObjectFile(contentsOf: url) } catch {
            if Self.warned.insert("\(name).object").inserted { print("PixelKit: can't make \(name) from \(url.path): \(error.localizedDescription)") }
        }
        let placed = TilemapFile.Object(name: name, x: Int(position.x), y: Int(position.y), properties: properties)
        let entity = Self.make(Tilemap.Object(placed, definition: definition, tileSize: tilemap?.tileSize ?? 16, frame: frameSize))
        add(entity, at: position)
        return entity
    }

    /// The game's module, for finding its classes by name; `Game.main()` sets it.
    static var module = ""
    static var warned: Set<String> = [] // classes and objects the console said something about

    /// An object made as its class, or as an `Entity` if it names none, or one that's missing or isn't `Placeable`
    /// (the console says why, once).
    static func make(_ object: Tilemap.Object) -> Entity {
        guard let name = object.class else { return Entity(object) }
        let found: AnyClass? = NSClassFromString(name.contains(".") ? name : "\(module).\(name)")
        if let type = found as? any Placeable.Type { return type.init(object) }
        if warned.insert(name).inserted {
            print(found == nil ? "PixelKit: \(object.name).object names the class \(name), which \(module) doesn't have, so it's an Entity"
                               : "PixelKit: \(name) isn't Placeable, so \(object.name) is an Entity. Mark it: final class \(name): Entity, Placeable")
        }
        return Entity(object)
    }

    /// Runs 60 times a second. Call super to update the entities.
    open func update(_ dt: Double) {
        for entity in entities {
            entity.update(dt)
            entity.sprite?.time += dt
            for i in entity.parts.indices { entity.parts[i].sprite.time += dt }
            entity.light?.time += dt
        }
        tilemap?.time += dt
    }

    /// Call super to draw the tilemap and entities, then draw anything on top (like a HUD) in screen pixels. The
    /// map's layers above and the entities' parts above draw over the entities, in that order, and then, if the scene
    /// is dark, its `darkness` over them all, but where `light`s light it.
    open func draw(_ screen: Screen) {
        if let follow { camera = Self.camera(following: follow.box(at: follow.position), view: screen.size, map: tilemap?.size) }
        screen.offset = camera.rounded(.down)
        if let tilemap { screen.draw(tilemap, layers: tilemap.layers.indices.filter { !tilemap.above.contains($0) }) }
        let order = drawOrder
        for entity in order { entity.draw(screen) }
        if let tilemap, !tilemap.above.isEmpty { screen.draw(tilemap, layers: tilemap.above.sorted()) }
        for entity in order { entity.draw(screen, above: true) }
        if darkness > 0 {
            let lights = entities.compactMap { entity in
                entity.light.map { (screen.middle(of: entity), $0.radius(seed: ObjectIdentifier(entity).hashValue), $0.color) }
            }
            screen.light(lights, darkness: darkness, color: darknessColor)
        }
        screen.offset = .zero
    }

    /// The order the entities draw in: as they were added, or with `ySort` by `sortY`, ties as they were added.
    var drawOrder: [Entity] {
        guard ySort else { return entities }
        return entities.enumerated().sorted { ($0.element.sortY, $0.offset) < ($1.element.sortY, $1.offset) }.map(\.element)
    }

    /// The camera that puts `box` in the middle of a `view`, kept inside a `map` of that size, or in the middle of a
    /// map smaller than the view. Whole pixels, so sprites don't shimmer against the tiles.
    nonisolated static func camera(following box: Rect, view: Size, map: Size?) -> Vector {
        func axis(_ middle: Int, _ view: Int, _ map: Int?) -> Double {
            guard let map else { return Double(middle - view / 2) }
            return Double(map < view ? (map - view) / 2 : min(max(middle - view / 2, 0), map - view))
        }
        return [axis(box.x + box.width / 2, view.width, map?.width), axis(box.y + box.height / 2, view.height, map?.height)]
    }
}

/// How `Scene.transition(to:duration:style:color:)` goes from one scene to the next.
public enum Transition: Sendable, Equatable {
    /// The view fades to the color and back.
    case fade
    /// The color sweeps over the view from a side, then on off the other, the next scene coming in behind it.
    case wipe(from: Side)
    /// The view closes to the color in a circle around the entity the camera follows (`Scene.follow`), or the middle
    /// of the view, then opens around the next scene's.
    case iris
    /// The scene breaks up into the next one, its pixels going in a pattern, with no color between them.
    case dissolve

    /// Where a wipe comes in.
    public enum Side: Sendable { case left, right, top, bottom }
}

/// A switch to another scene under way, from `Scene.transition(to:duration:style:color:)`.
struct Change {
    var next: Scene? // until the switch
    let duration: Double
    let style: Transition
    let color: UInt32
    var time = 0.0
    var snapped = false // a dissolve's copy of the last frame, taken as it draws first

    /// When `next` becomes current: once the color covers the view, halfway, or for a dissolve at once.
    var switchTime: Double { style == .dissolve ? 0 : duration / 2 }

    /// How much the color covers: from none to all of the view at the switch, then back. A fade's opacity.
    var cover: Double { max(0, 1 - abs(time / duration * 2 - 1)) }

    /// How much of the old scene a dissolve keeps: all of it, then none.
    var kept: Double { max(0, 1 - time / duration) }

    /// What a wipe from `side` covers: growing from that side until the switch, then shrinking off the other.
    func wiped(from side: Transition.Side, view: Size) -> Rect {
        let across = side == .left || side == .right
        let length = across ? view.width : view.height
        let covered = Int((cover * Double(length)).rounded())
        var start = time < duration / 2 ? 0 : length - covered // from the side it comes in at
        if side == .right || side == .bottom { start = length - start - covered }
        return across ? Rect(x: start, y: 0, width: covered, height: view.height) : Rect(x: 0, y: start, width: view.width, height: covered)
    }

    /// The radius of an iris around `center`, in canvas pixels: from the view's farthest corner to nothing at the
    /// switch, then back.
    func radius(around center: Vector, view: Size) -> Double {
        let (width, height) = (Double(view.width), Double(view.height))
        let corners: [Vector] = [[0, 0], [width, 0], [0, height], [width, height]]
        return corners.map { (($0 - center) * ($0 - center)).sum().squareRoot() }.max()! * (1 - cover)
    }

    /// Draws it over everything the scene drew: the color, or the old scene's last frame breaking up.
    @MainActor func draw(_ screen: Screen, over scene: Scene) {
        let view = screen.size
        screen.offset = .zero
        switch style {
        case .fade:
            screen.fill(Rect(x: 0, y: 0, width: view.width, height: view.height), color: color, opacity: cover)
        case let .wipe(side):
            screen.fill(wiped(from: side, view: view), color: color)
        case .iris:
            let center = scene.follow.map { screen.middle(of: $0) - scene.camera.rounded(.down) } ?? [Double(view.width) / 2, Double(view.height) / 2]
            let radius = radius(around: center, view: view)
            for y in 0..<view.height { // the row's pixels left and right of the circle
                let dy = Double(y) + 0.5 - center.y
                let half = radius > abs(dy) ? (radius * radius - dy * dy).squareRoot() : 0
                let (left, right) = (Int((center.x - half).rounded()), Int((center.x + half).rounded()))
                screen.fill(Rect(x: 0, y: y, width: min(max(left, 0), view.width), height: 1), color: color)
                screen.fill(Rect(x: max(right, 0), y: y, width: view.width - min(max(right, 0), view.width), height: 1), color: color)
            }
        case .dissolve:
            screen.quad(screen.snapshot, x: 0, y: 0, source: Rect(x: 0, y: 0, width: view.width, height: view.height), keep: kept)
        }
    }
}

/// Anything that lives in a scene: the player, enemies, pickups.
@MainActor open class Entity {
    /// Top-left corner, in world pixels.
    public var position = Vector.zero
    /// Pixels per second, applied by `move(_:)`.
    public var velocity = Vector.zero
    /// The solid part of the entity, relative to `position`.
    public var hitbox = Rect(x: 0, y: 0, width: 16, height: 16)
    /// What it looks like, drawn at `position`; nil draws nothing.
    public var sprite: Sprite?
    /// More sprites it's drawn with, each at an offset: a tree's crown, a house's roof, a hat. Those `above` draw over
    /// every entity, as a roof the player walks under does; the rest draw with it, after `sprite`.
    public var parts: [Part] = []
    /// Blocks other entities' `move(_:)`, as solid tiles do: villagers, chests, tree trunks.
    public var solid = false
    /// The scene it's in, from `Scene.add(_:at:)`.
    public internal(set) weak var scene: Scene?
    /// The map's object it was made from, for its properties. It's set after `init()` runs, so read it in a `lazy var`:
    /// `lazy var speed = object?.double("speed") ?? 40`.
    public var object: Tilemap.Object?
    /// The light it gives off in a dark scene (`Scene.darkness`), from its middle, like a torch's; nil gives none.
    public var light: Light?
    /// How deep a corner can be, in pixels, for `move(_:)` to nudge the entity around it instead of stopping: going
    /// straight left, right, up or down into something that catches no more of its hitbox than that, it slides sideways
    /// past, as top-down games since Zelda do. About 4 for a top-down game's player. 0, the default, stops it flush, as
    /// a platformer wants: its player would slip off a ledge it lands on by a few pixels.
    public var cornerSlide = 0
    var remainder = Vector.zero // sub-pixel movement not applied yet

    public init() {}

    /// Makes an entity from an object placed in a map, as `Scene.addObjects()` does: `init()` runs, then it takes the
    /// object's place, hitbox and solidity, and its sprites if it has any, and keeps the object in `object`. A subclass
    /// that overrides `init()`, or declares no initializers, inherits this.
    public convenience init(_ object: Tilemap.Object) {
        self.init()
        (self.object, position, hitbox, solid) = (object, object.position, object.hitbox, object.solid)
        if let sprite = object.sprite { self.sprite = sprite }
        if !object.parts.isEmpty { parts = object.parts }
    }

    /// A sprite an entity is drawn with besides its `sprite`.
    public struct Part: Sendable {
        public var sprite: Sprite
        /// From the entity's `position`, in pixels.
        public var offset: Vector
        /// Draws over every entity, and over the map's layers above them.
        public var above: Bool

        public init(_ sprite: Sprite, offset: Vector = .zero, above: Bool = false) { (self.sprite, self.offset, self.above) = (sprite, offset, above) }
    }

    /// Runs 60 times a second; `dt` is the time since the last update, in seconds. Override it to move and react.
    open func update(_ dt: Double) {}

    /// Draws the sprite and the parts that aren't above. Override it to draw more, in world pixels, and call super to
    /// keep them.
    open func draw(_ screen: Screen) {
        if let sprite { screen.draw(sprite, x: position.x, y: position.y) }
        draw(screen, above: false)
    }

    /// Draws the parts that are, or aren't, above: the scene draws those above after the rest.
    func draw(_ screen: Screen, above: Bool) {
        for part in parts where part.above == above {
            screen.draw(part.sprite, x: position.x + part.offset.x, y: position.y + part.offset.y)
        }
    }

    /// Where it draws when the scene's `ySort` is on, in world pixels: the bottom of its hitbox, its feet, so the
    /// hitbox of a tree is its trunk. Override it for something always under the rest, like a shadow (`-.infinity`),
    /// or over it, like a bird.
    open var sortY: Double { Double(box(at: position).y + hitbox.height) }

    /// Moves by `velocity * dt` one pixel at a time, stopping flush against solid tiles and solid entities (but not
    /// those it already overlaps, so two that start on top of each other can walk apart), or with `cornerSlide` sliding
    /// around their corners. Hitting something zeroes that part of the velocity.
    public func move(_ dt: Double) {
        let straight = velocity.x == 0 || velocity.y == 0 // only that slides around corners, not a diagonal
        remainder += velocity * dt
        let pixels = remainder.rounded(.toNearestOrAwayFromZero)
        remainder -= pixels
        for axis in 0..<2 where !slide(Int(pixels[axis]), axis: axis, aroundCorners: straight) {
            velocity[axis] = 0
            remainder[axis] = 0
        }
    }

    /// The middle of its hitbox, in whole world pixels: where it walks from and to on a path, and where another
    /// entity heads to reach it: `enemy.path(to: player.middle)`.
    public var middle: Vector {
        let box = box(at: position)
        return [Double(box.x + box.width / 2), Double(box.y + box.height / 2)]
    }

    /// The way to `point`, in world pixels, around the map's solid tiles and the scene's other solid entities: the
    /// middle of each cell of the map to walk through, from the one after the cell its `middle` is in to the one
    /// `point` is in, for `walk(_:along:speed:)`. Steps go to a cell beside, above or below, or with `diagonals` to one
    /// at a corner too, but never past the corner of a cell that's in the way. Nil when there's no way there: `point`
    /// is in a solid tile, either is off the map, or there's no tilemap. A cell is in the way when a solid entity is
    /// in it, but for the one `point` is in, so the way can lead to another entity, like a solid player being chased.
    /// A hitbox no bigger than a tile, walked by its middle, fits through every cell on the way.
    public func path(to point: Vector, diagonals: Bool = false) -> [Vector]? {
        guard let scene, let map = scene.tilemap else { return nil }
        let (size, goal) = (map.tileSize, map.cell(at: point))
        var taken: Set<SIMD2<Int>> = [] // cells solid entities are in
        for other in scene.entities where other.solid && other !== self {
            let box = other.box(at: other.position)
            for row in stride(from: map.cell(box.y), through: map.cell(box.y + box.height - 1), by: 1) {
                for column in stride(from: map.cell(box.x), through: map.cell(box.x + box.width - 1), by: 1) { taken.insert([column, row]) }
            }
        }
        taken.remove(goal)
        let cells = map.route(from: map.cell(at: middle), to: goal, diagonals: diagonals) { cell in
            !taken.contains(cell) && !map.isSolid(Rect(x: cell.x * size, y: cell.y * size, width: size, height: size))
        }
        return cells?.map { [Double($0.x * size + size / 2), Double($0.y * size + size / 2)] }
    }

    /// Walks along `path`, points in world pixels like those `path(to:)` finds, at `speed` pixels a second: heads for
    /// the first until its `middle` is there, takes it off and heads for the next, and stops, its velocity zero, once
    /// there are none. It moves as `move(_:)` does, so something solid in the way holds it up until it's gone. Call it
    /// in each update instead of `move(_:)`: `walk(dt, along: &route, speed: 40)`.
    public func walk(_ dt: Double, along path: inout [Vector], speed: Double) {
        func reached(_ point: Vector) -> Bool { ((point - middle) * (point - middle)).sum() < 1 } // within a pixel
        while let point = path.first, reached(point) { path.removeFirst() }
        guard let point = path.first else { return velocity = .zero }
        let way = point - middle, distance = (way * way).sum().squareRoot()
        if distance <= speed * dt { (velocity, remainder) = (way / dt, .zero) } // there in this update, not past it
        else { velocity = way / distance * speed }
        move(dt)
        guard reached(point) else { return }
        path.removeFirst()
        if path.isEmpty { velocity = .zero }
    }

    /// Standing on a solid tile or entity.
    public var onGround: Bool { blocked(at: position + [0, 1]) }

    /// True when the two hitboxes overlap.
    public func overlaps(_ other: Entity) -> Bool { box(at: position).intersects(other.box(at: other.position)) }

    /// True when the hitbox overlaps `box`, in world pixels, like a door's from `Tilemap.Object.box`.
    public func overlaps(_ box: Rect) -> Bool { self.box(at: position).intersects(box) }

    /// True when `point`, in world pixels, is in the hitbox, like the pointer plus the scene's camera:
    /// `if Input.pressed(.pointer), let point = Input.pointer, chest.contains(point + camera)`.
    public func contains(_ point: Vector) -> Bool { box(at: position).contains(point) }

    /// Moves `pixels` along `axis` (0 for x, 1 for y) a pixel at a time, or around a corner a pixel sideways for each
    /// pixel it's held up; false once it can do neither.
    func slide(_ pixels: Int, axis: Int, aroundCorners: Bool) -> Bool {
        let step = Double(pixels.signum())
        for _ in 0..<abs(pixels) {
            var next = position
            next[axis] += step
            if !blocked(at: next) {
                position = next
            } else if aroundCorners, let side = side(around: axis, step) {
                position[1 - axis] += side
            } else {
                return false
            }
        }
        return true
    }

    /// Which way across `axis`, -1 or 1, it gets past what holds it up going `step` along it, by moving no more than
    /// `cornerSlide` pixels sideways first, the nearer way if both do; nil if neither does, as at a wall.
    func side(around axis: Int, _ step: Double) -> Double? {
        var sides: [Double] = [-1, 1]
        for depth in stride(from: 1.0, through: Double(cornerSlide), by: 1) {
            for side in sides {
                var aside = position
                aside[1 - axis] += side * depth
                if blocked(at: aside) { // a wall that way too
                    sides.removeAll { $0 == side }
                    continue
                }
                aside[axis] += step
                if !blocked(at: aside) { return side }
            }
        }
        return nil
    }

    /// Whether a solid tile, or a solid entity it doesn't overlap already, is in the way at `position`.
    // ponytail: scans every entity each pixel step; a grid of cells when a level holds thousands of solid things
    func blocked(at position: Vector) -> Bool {
        let (box, here) = (box(at: position), box(at: self.position))
        if scene?.tilemap?.isSolid(box) == true { return true }
        return scene?.entities.contains { other in
            guard other.solid, other !== self else { return false }
            let theirs = other.box(at: other.position)
            return theirs.intersects(box) && !theirs.intersects(here)
        } ?? false
    }

    func box(at position: Vector) -> Rect {
        let p = position.rounded(.down)
        return Rect(x: Int(p.x) + hitbox.x, y: Int(p.y) + hitbox.y, width: hitbox.width, height: hitbox.height)
    }
}

/// An entity class that objects placed in maps are made as, named in their definition's Class. A `final` class needs
/// nothing more than this mark, since it inherits `Entity.init(_:)`, which runs its `init()` and then gives it the
/// object's sprite, hitbox and properties: `final class Villager: Entity, Placeable`. A class that isn't final makes it
/// `required` (`required convenience init(_ object: Tilemap.Object) { … }`).
@MainActor public protocol Placeable: Entity {
    init(_ object: Tilemap.Object)
}

/// A picture from `<image>.png` in `Assets` or a folder in it, like `Assets/Sprites`. If `<image>.json` beside it
/// (written by the pixel editor) cuts it into frames, `play(_:)` runs one of its animations; without it, the whole
/// image is one frame.
public struct Sprite: Sendable {
    /// The image's name in Assets, without ".png".
    public var image: String
    /// The animation playing, by name; nil shows the first frame.
    public private(set) var animation: String?
    /// Mirrors the sprite horizontally, e.g. to face left.
    public var flipped = false
    /// Multiplies the sprite's pixels, as 0xRRGGBB: red (0xFF0000) for a hurt flash, or a color variant of light art.
    /// White, the default, leaves them as they are.
    public var color: UInt32 = 0xFFFFFF
    /// From 0, invisible, to 1, the default: for ghosts, or things that fade out.
    public var opacity = 1.0
    /// Mixes the sprite's pixels toward white, keeping its shape: from 0, as they are (the default), to 1, all white.
    /// Set it to 1 when something's hit, and lower it in each update for a flash that fades:
    /// `sprite.flash = max(0, sprite.flash - dt * 8)`.
    public var flash = 0.0
    var time = 0.0

    /// A sprite of one of the game's images: `Sprite(.slime)`.
    public init(_ image: ImageName) { self.image = image.name }

    /// A sprite of an image named in a string, like one that comes from data.
    @_disfavoredOverload public init(_ image: String) { self.image = image }

    /// Starts the named animation. Playing the one that's already running keeps it going, so it's fine every frame.
    public mutating func play(_ animation: String) {
        if animation != self.animation { (self.animation, time) = (animation, 0) }
    }
}

/// The light an entity gives off in a dark scene (`Scene.darkness`), from its middle: a torch, a fireplace, a lantern
/// or a glowing mushroom. Where lights meet, they add up.
public struct Light: Sendable {
    /// How far it reaches, in pixels: it's brightest in the middle and fades to nothing there.
    public var radius: Double
    /// Its color, 0xRRGGBB: white, or a fire's orange. A darker color is a dimmer light.
    public var color: UInt32
    /// How much its radius wavers, from 0, steady, to 1: about 0.1 for a torch.
    public var flicker: Double
    var time = 0.0 // advanced by the scene's updates, so a paused game's flames stand still

    public init(radius: Double, color: UInt32 = 0xFFFFFF, flicker: Double = 0) {
        (self.radius, self.color, self.flicker) = (radius, color, flicker)
    }

    /// The radius now: smaller by up to `flicker` of it, wavering a few times a second. `seed` sets lights apart, so two
    /// torches don't flicker as one.
    func radius(seed: Int) -> Double {
        let phase = Double(seed % 1000)
        let wave = (sin(time * 13 + phase) + sin(time * 31 + phase * 2)) / 4 + 0.5 // 0 to 1, two waves that hardly repeat
        return radius * (1 - flicker * wave)
    }
}

/// A grid of tiles from a tileset, `<tileset>.png` in `Assets` or a folder in it, cut into `tileSize` squares numbered
/// left to right, then top to bottom.
///
/// While the game runs, the scene's tilemap reloads when its `.tilemap` (or the tileset's `.json`, or one of its
/// objects' definitions) changes, so tiles painted in the editor show up live. Entities already in the scene stay as
/// they are: objects moved or added in the editor show up the next time the game builds the level.
public struct Tilemap: Sendable {
    /// The tileset image's name in Assets, without ".png".
    public var tileset: String
    /// The width and height of a tile, in pixels.
    public var tileSize: Int
    /// Size in tiles.
    public var width, height: Int
    /// Each layer's tiles row by row, `layers[layer][row * width + column]`; nil is empty. The first layer draws first.
    public var layers: [[Int?]]
    /// The layers that draw over the entities, like roofs and treetops, by their index in `layers`.
    public var above: Set<Int> = []
    /// Tile numbers that block movement, in any layer.
    public var solid: Set<Int>
    /// What the tileset says of its tiles, for `properties(at:layer:)`.
    var sheet: SheetFile?
    /// Things placed in the level with the map editor's Objects tool, like coins or where the player starts.
    public var objects: [Object] = []
    var name: String? // the .tilemap it came from
    var watched: [String] = [] // it, the tileset's .json and its objects' definitions
    var modified: [Date?] = [] // when each was last changed, as loaded
    var removed: Set<Int> = [] // what removeTiles took out, kept out when the map reloads
    var edits: [SIMD3<Int>: Int?] = [:] // what setTile put down, by layer, column and row, kept when the map reloads
    var time = 0.0 // for animated tiles, advanced by the scene's updates

    /// Something placed in the level with the map editor's Objects tool. What it is comes from its definition,
    /// `Assets/Objects/<name>.object`, if it has one: its sprites, its hitbox, whether it's solid, its class, and its
    /// properties' defaults.
    public struct Object: Properties, Sendable {
        /// What it is, like "coin" or "player", and its definition's file name; `objects(named:)` finds them by it.
        public var name: String
        /// Top-left corner, in pixels.
        public var position: Vector
        /// Settings for the game, like "speed": "40": its own, over its definition's defaults. `double(_:)`, `map(_:)`
        /// and the others read them as what they are.
        public var properties: [String: String]
        /// What it's drawn with, playing its definition's animation; nil for a zone, a marker, or an object without a
        /// definition.
        public var sprite: Sprite?
        /// The other sprites its definition draws it with.
        public var parts: [Entity.Part]
        /// The part that collides, from its top-left corner: its definition's, or all of it.
        public var hitbox: Rect
        /// Blocks solid movers, as `Entity.solid` does.
        public var solid: Bool
        /// The game's class it's made as by `Scene.addObjects()`, by name.
        public var `class`: String?
        var size: Size

        /// Where it is and how big, in pixels: the size it was given in the map editor, or else a zone's size or its
        /// sprite's frame, or without a definition the frame of the image it's named after, or one tile. For zones
        /// like doors: `player.overlaps(door.box)`.
        public var box: Rect { Rect(x: Int(position.x), y: Int(position.y), width: size.width, height: size.height) }

        init(_ placed: TilemapFile.Object, definition: ObjectFile?, tileSize: Int, frame: (String) -> Size?) {
            let size = placed.size(definition, tileSize: tileSize) { frame($0).map { ($0.width, $0.height) } }
            (name, position, properties) = (placed.name, [Double(placed.x), Double(placed.y)], placed.properties(definition))
            func playing(_ image: String, _ animation: String?) -> Sprite {
                var sprite = Sprite(image)
                if let animation { sprite.play(animation) }
                return sprite
            }
            sprite = definition?.sprite.map { playing($0, definition?.animation) }
            parts = (definition?.parts ?? []).map { .init(playing($0.sprite, $0.animation), offset: [Double($0.x), Double($0.y)], above: $0.above == true) }
            hitbox = definition?.hitbox.map { Rect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
                ?? Rect(x: 0, y: 0, width: size.width, height: size.height)
            (solid, `class`, self.size) = (definition?.solid ?? false, definition?.class, Size(size.width, size.height))
        }
    }

    /// Loads `<name>.tilemap` from `Assets` or a folder in it, like `Assets/Maps`, made in the tilemap editor. The tile
    /// size and which tiles are solid come from the tileset's `.json`, and what its objects are from their definitions.
    public init(_ map: MapName) { self.init(map.name) }

    /// Loads a map named in a string, like a door's `to`.
    @_disfavoredOverload public init(_ name: String) {
        (tileset, tileSize, width, height, layers, solid) = ("", 0, 0, 0, [], [])
        do { try load(name) } catch {
            fatalError("PixelKit: can't load \(assetURL("\(name).tilemap").path): \(error.localizedDescription)")
        }
    }

    mutating func load(_ name: String) throws {
        let map = try TilemapFile(contentsOf: assetURL("\(name).tilemap"))
        let sheet = try SheetFile(contentsOf: assetURL("\(map.tileset).json"))
        (tileset, tileSize, width, height) = (map.tileset, sheet.frameWidth, map.width, map.height)
        layers = map.layers.map { $0.tiles.map { $0 < 0 ? nil : $0 } }
        above = Set(map.layers.indices.filter { map.layers[$0].above == true })
        solid = Set(sheet.solid ?? [])
        self.sheet = sheet
        let names = Set((map.objects ?? []).map(\.name)).sorted()
        var definitions: [String: ObjectFile] = [:]
        for name in names {
            let url = assetURL("\(name).object")
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do { definitions[name] = try ObjectFile(contentsOf: url) } catch { print("PixelKit: can't read \(url.path): \(error.localizedDescription)") }
        }
        var frames: [String: Size?] = [:] // each image's frame size, read once
        objects = (map.objects ?? []).map { placed in
            Object(placed, definition: definitions[placed.name], tileSize: tileSize) { image in
                if frames[image] == nil { frames[image] = .some(frameSize(image)) }
                return frames[image]!
            }
        }
        // Watched for changes: the map, its tileset's .json and its objects' definitions.
        self.name = name
        watched = ["\(name).tilemap", "\(map.tileset).json"] + names.map { "\($0).object" }
        modified = watched.map { modificationDate(assetURL($0)) }
        for tile in removed { _ = removeTiles(tile) }
        for (cell, tile) in edits where layers.indices.contains(cell.x) && (0..<width).contains(cell.y) && (0..<height).contains(cell.z) {
            layers[cell.x][cell.z * width + cell.y] = tile
        }
    }

    /// Loads the map again if its files changed. One that can't be read keeps the map as it is.
    mutating func reloadIfChanged() {
        guard let name else { return }
        let dates = watched.map { modificationDate(assetURL($0)) }
        guard dates != modified else { return }
        modified = dates // so a broken file is tried again only once it changes again
        try? load(name)
    }

    /// Builds a one-layer map from text, one string per row. `legend` maps characters to tile numbers;
    /// any other character is empty. Every tile in the legend is solid unless you pass `solid`.
    public init(_ tileset: ImageName, tileSize: Int, rows: [String], legend: [Character: Int], solid: Set<Int>? = nil) {
        self.init(tileset.name, tileSize: tileSize, rows: rows, legend: legend, solid: solid)
    }

    /// The same, with the tileset named in a string.
    @_disfavoredOverload public init(_ tileset: String, tileSize: Int, rows: [String], legend: [Character: Int], solid: Set<Int>? = nil) {
        let width = rows.map(\.count).max() ?? 0
        (self.tileset, self.tileSize, self.width, height) = (tileset, tileSize, width, rows.count)
        layers = [rows.flatMap { row in row.map { legend[$0] } + Array(repeating: nil, count: width - row.count) }]
        self.solid = solid ?? Set(legend.values)
    }

    /// Size in pixels.
    public var size: Size { Size(width * tileSize, height * tileSize) }

    /// The tile at world pixel `point` in `layer`, or nil for an empty cell or outside the map: what's under the
    /// player's feet, or in front of them.
    public func tile(at point: Vector, layer: Int) -> Int? {
        guard let i = index(point), layers.indices.contains(layer) else { return nil }
        return layers[layer][i]
    }

    /// The properties of the tile at world pixel `point` in `layer`, which the map editor sets for each of the
    /// tileset's tiles: water, ice, damage, a footstep's sound. `bool(_:)`, `double(_:)` and the others read them, as an
    /// object's: `tilemap.properties(at: feet, layer: 0).bool("water")`. An empty cell, or outside the map, has none.
    public func properties(at point: Vector, layer: Int) -> TileProperties {
        TileProperties(properties: tile(at: point, layer: layer).flatMap { sheet?.properties(of: $0) } ?? [:])
    }

    /// A tile's properties, from `properties(at:layer:)`.
    public struct TileProperties: Properties, Sendable {
        public let properties: [String: String]
    }

    /// Puts `tile` at world pixel `point` in `layer`, or empties the cell with nil: cut a bush, till soil, build a
    /// wall. Outside the map it does nothing. The change stays when the map reloads as it's edited in the editor.
    public mutating func setTile(_ tile: Int?, at point: Vector, layer: Int) {
        guard let i = index(point), layers.indices.contains(layer) else { return }
        layers[layer][i] = tile
        edits.updateValue(tile, forKey: [layer, i % width, i / width]) // not `edits[…] = tile`, which removes it when nil
    }

    /// The cell world pixel `point` is in, as an index into a layer; nil outside the map.
    private func index(_ point: Vector) -> Int? {
        let (column, row) = (cell(Int(point.x.rounded(.down))), cell(Int(point.y.rounded(.down))))
        return (0..<width).contains(column) && (0..<height).contains(row) ? row * width + column : nil
    }

    /// The frame each animated tile shows now: an animation in the tileset's `.json` named after a tile's number
    /// ("12") plays wherever that tile is, for water, flowers and torches.
    func frames(_ animations: [String: SheetFile.Animation]?) -> [Int: Int] {
        (animations ?? [:]).reduce(into: [:]) { frames, animation in
            if let tile = Int(animation.key), let frame = animation.value.frame(at: time) { frames[tile] = frame }
        }
    }

    /// Where each object called `name` is (its top-left corner, in pixels).
    public func objects(named name: ObjectName) -> [Vector] { objects(named: name.name) }

    /// The same, with the object named in a string, like a door's `at`.
    @_disfavoredOverload public func objects(named name: String) -> [Vector] { objects.filter { $0.name == name }.map(\.position) }

    /// Removes every `tile` from the map and returns where each one was (top-left corner, in pixels).
    /// Handy for tiles that only mark where things go, like coins or the player's start.
    public mutating func removeTiles(_ tile: Int) -> [Vector] {
        removed.insert(tile)
        var found: [Vector] = []
        for layer in layers.indices {
            for i in layers[layer].indices where layers[layer][i] == tile {
                layers[layer][i] = nil
                found.append([Double(i % width * tileSize), Double(i / width * tileSize)])
            }
        }
        return found
    }

    /// Whether a solid tile in any layer overlaps `box`. Outside the map is empty.
    func isSolid(_ box: Rect) -> Bool {
        for row in stride(from: cell(box.y), through: cell(box.y + box.height - 1), by: 1) where (0..<height).contains(row) {
            for column in stride(from: cell(box.x), through: cell(box.x + box.width - 1), by: 1) where (0..<width).contains(column) {
                if layers.contains(where: { $0[row * width + column].map(solid.contains) ?? false }) { return true }
            }
        }
        return false
    }

    /// Which cell a pixel is in, rounding toward -∞ so pixels left of or above the map get negative cells.
    func cell(_ pixel: Int) -> Int { pixel >= 0 ? pixel / tileSize : (pixel + 1) / tileSize - 1 }

    /// The cell, its column and row, that world pixel `point` is in.
    func cell(at point: Vector) -> SIMD2<Int> { [cell(Int(point.x.rounded(.down))), cell(Int(point.y.rounded(.down)))] }

    /// The shortest way from cell `start` to cell `goal` through the map's cells that are `free`, by A*: the cells
    /// after `start` to `goal`, or nil when there's none, or `goal` isn't free or is off the map. Steps go to a cell
    /// beside, above or below, or with `diagonals` to one at a corner when both cells beside that corner are free too.
    /// Of the shortest ways, it takes one that turns the fewest times, as someone walking would.
    // ponytail: arrays of the map's size times its steps for each search; a dictionary of the states it looks at if
    // maps get so big that filling them is slow.
    func route(from start: SIMD2<Int>, to goal: SIMD2<Int>, diagonals: Bool, free: (SIMD2<Int>) -> Bool) -> [SIMD2<Int>]? {
        func inside(_ x: Int, _ y: Int) -> Bool { (0..<width).contains(x) && (0..<height).contains(y) }
        guard inside(start.x, start.y), inside(goal.x, goal.y), free(goal) else { return nil }
        var known = [UInt8](repeating: 0, count: width * height) // each cell's `free`, asked once: 1 free, 2 not
        func open(_ x: Int, _ y: Int) -> Bool {
            guard inside(x, y) else { return false }
            if known[y * width + x] == 0 { known[y * width + x] = free([x, y]) ? 1 : 2 }
            return known[y * width + x] == 1
        }
        let steps = [(1, 0), (0, 1), (-1, 0), (0, -1)] + (diagonals ? [(1, 1), (-1, 1), (-1, -1), (1, -1)] : [])
        // A state is a cell and the step into it (the start's is none, `steps.count`), so a turn can cost something: 1,
        // where a step costs 10,000 across and 14,000 diagonally, so turns only choose among the shortest ways.
        let ways = steps.count + 1
        func estimate(_ x: Int, _ y: Int) -> Int {
            let (x, y) = (abs(x - goal.x), abs(y - goal.y))
            return (diagonals ? 10 * max(x, y) + 4 * min(x, y) : 10 * (x + y)) * 1000
        }
        var cost = [Int](repeating: .max, count: width * height * ways), came = [Int](repeating: -1, count: width * height * ways)
        // The least each cell costs to reach, from any side. A state that costs more is left out: going on from the
        // cheapest instead costs at most a turn more, and that's no more.
        var least = [Int](repeating: .max, count: width * height)
        let first = (start.y * width + start.x) * ways + steps.count
        (cost[first], least[start.y * width + start.x]) = (0, 0)
        // A binary heap of states to go on from: the one whose way through it, as estimated, is shortest, then the one
        // nearer the goal, then the one added last (`rest`: the estimate in the high bits, less the count added before).
        var heap = [(f: estimate(start.x, start.y), rest: estimate(start.x, start.y) << 32, state: first)]
        func before(_ a: Int, _ b: Int) -> Bool { heap[a].f < heap[b].f || heap[a].f == heap[b].f && heap[a].rest < heap[b].rest }
        var added = 0, found: Int?
        while !heap.isEmpty {
            heap.swapAt(0, heap.count - 1)
            let (f, _, state) = heap.removeLast()
            var i = 0
            while true { // sift down
                var next = i
                if 2 * i + 1 < heap.count, before(2 * i + 1, next) { next = 2 * i + 1 }
                if 2 * i + 2 < heap.count, before(2 * i + 2, next) { next = 2 * i + 2 }
                if next == i { break }
                heap.swapAt(i, next)
                i = next
            }
            let (x, y) = (state / ways % width, state / ways / width)
            guard f - estimate(x, y) == cost[state], cost[state] <= least[y * width + x] else { continue } // bettered since
            if x == goal.x, y == goal.y {
                found = state
                break
            }
            for way in steps.indices {
                let (dx, dy) = steps[way], (nx, ny) = (x + dx, y + dy)
                guard open(nx, ny), dx == 0 || dy == 0 || open(nx, y) && open(x, ny) else { continue } // no corner cut
                let turn = state % ways == way || state % ways == steps.count ? 0 : 1
                let total = cost[state] + (dx != 0 && dy != 0 ? 14_000 : 10_000) + turn
                let after = (ny * width + nx) * ways + way
                guard total < cost[after], total <= least[ny * width + nx] else { continue }
                (cost[after], came[after], least[ny * width + nx]) = (total, state, total)
                added += 1
                heap.append((total + estimate(nx, ny), estimate(nx, ny) << 32 - added, after))
                var j = heap.count - 1
                while j > 0, before(j, (j - 1) / 2) { // sift up
                    heap.swapAt(j, (j - 1) / 2)
                    j = (j - 1) / 2
                }
            }
        }
        guard var state = found else { return nil }
        var cells: [SIMD2<Int>] = []
        while came[state] >= 0 {
            cells.append([state / ways % width, state / ways / width])
            state = came[state]
        }
        return cells.reversed()
    }
}

/// What has properties from the editor, typed there and kept as text: a map's objects, and its tiles
/// (`Tilemap.properties(at:layer:)`). These read them as what they are, so `door.map("to")` is a `MapName` that
/// `Tilemap(_:)` takes. Each is nil (false for `bool`, empty for `list`) when there's none, when it isn't of its type,
/// or when it's empty, as a popup's None over a default is.
public protocol Properties {
    var properties: [String: String] { get }
}

public extension Properties {
    /// A number, like "speed": "40".
    func double(_ name: String) -> Double? { value(name) }

    /// A toggle, "true" or "false"; false if there's none.
    func bool(_ name: String) -> Bool { properties[name] == "true" }

    /// A color, "#FF004D", as 0xRRGGBB, like `Sprite.color` takes.
    func color(_ name: String) -> UInt32? { properties[name]?.hasPrefix("#") == true ? value(name) : nil }

    /// A point in world pixels, "12,34", like where a guard walks to.
    func point(_ name: String) -> Vector? { value(name) }

    /// One of the game's maps, by name: `Tilemap(door.map("to")!)`.
    func map(_ name: String) -> MapName? { value(name) }

    /// One of the game's objects, by name: `tilemap.objects(named: door.object("at") ?? .start)`.
    func object(_ name: String) -> ObjectName? { value(name) }

    /// One of the game's images, by name: `Sprite(chest.sprite("open")!)`.
    func sprite(_ name: String) -> ImageName? { value(name) }

    /// One of the game's sounds, by name: `Sound.play(step.sound("footstep")!)`.
    func sound(_ name: String) -> SoundName? { value(name) }

    /// A list, its values read as `Value`s, leaving out any that aren't one: `villager.list("words", of: String.self)`,
    /// `guard.list("path", of: Vector.self)`.
    func list<Value: PropertyValue>(_ name: String, of type: Value.Type = Value.self) -> [Value] {
        (properties[name] ?? "").split(separator: "\n").compactMap { Value(property: String($0)) }
    }

    private func value<Value: PropertyValue>(_ name: String) -> Value? { properties[name].flatMap(Value.init(property:)) }
}

/// What a property's text can be read as, for `Properties.list(_:of:)`: text, numbers, toggles, colors, points and the
/// game's asset names.
public protocol PropertyValue {
    init?(property text: String)
}

extension String: PropertyValue {
    public init?(property text: String) { self = text }
}

extension Double: PropertyValue {
    public init?(property text: String) { self.init(text) }
}

extension Int: PropertyValue {
    public init?(property text: String) { self.init(text) }
}

extension Bool: PropertyValue {
    public init?(property text: String) { self.init(text) }
}

extension UInt32: PropertyValue {
    /// A color, "#FF004D", or a whole number.
    public init?(property text: String) {
        if text.hasPrefix("#") { self.init(text.dropFirst(), radix: 16) } else { self.init(text) }
    }
}

extension SIMD2: PropertyValue where Scalar == Double {
    /// A point, "12,34".
    public init?(property text: String) {
        let numbers = text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard numbers.count == 2 else { return nil }
        self.init(numbers[0], numbers[1])
    }
}

extension ImageName: PropertyValue {
    public init?(property text: String) { if text.isEmpty { return nil } else { self.init(text) } }
}

extension MapName: PropertyValue {
    public init?(property text: String) { if text.isEmpty { return nil } else { self.init(text) } }
}

extension ObjectName: PropertyValue {
    public init?(property text: String) { if text.isEmpty { return nil } else { self.init(text) } }
}

extension SoundName: PropertyValue {
    public init?(property text: String) { if text.isEmpty { return nil } else { self.init(text) } }
}
