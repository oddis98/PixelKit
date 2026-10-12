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

    public init() {}

    /// Switches to `next` through `color`: this scene stands still while the view fades to the color over the first
    /// half of `duration` seconds, then `next` becomes `current` and updates while it fades back in. The fade covers
    /// everything, a HUD too, and pauses with the game. `Scene.current = next` switches at once instead.
    public static func fade(to next: Scene, duration: Double = 0.5, color: UInt32 = 0x000000) {
        guard duration > 0 else { return current = next }
        fading = Fade(next: next, duration: duration, color: color)
    }

    /// The fade under way, if any.
    static var fading: Fade?

    /// One update of the game: the current scene's, unless it's fading out.
    static func tick(_ dt: Double) {
        guard var fade = fading else { return current.update(dt) }
        fade.time += dt
        if let next = fade.next, fade.time >= fade.duration / 2 { (current, fade.next) = (next, nil) }
        fading = fade.time < fade.duration ? fade : nil
        if fade.next == nil { current.update(dt) }
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

    /// Runs 60 times a second. Call super to update the entities.
    open func update(_ dt: Double) {
        for entity in entities {
            entity.update(dt)
            entity.sprite?.time += dt
        }
        tilemap?.time += dt
    }

    /// Call super to draw the tilemap and entities, then draw anything on top (like a HUD) in screen pixels.
    open func draw(_ screen: Screen) {
        if let follow { camera = Self.camera(following: follow.box(at: follow.position), view: screen.size, map: tilemap?.size) }
        screen.offset = camera.rounded(.down)
        if let tilemap { screen.draw(tilemap, layers: tilemap.layers.indices.filter { !tilemap.above.contains($0) }) }
        for entity in drawOrder { entity.draw(screen) }
        if let tilemap, !tilemap.above.isEmpty { screen.draw(tilemap, layers: tilemap.above.sorted()) }
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

/// A switch to another scene through a color, from `Scene.fade(to:duration:color:)`.
struct Fade {
    var next: Scene? // until the switch, halfway through
    let duration: Double
    let color: UInt32
    var time = 0.0

    /// How much of the color covers the view: from none to all of it at the switch, then back.
    var opacity: Double { max(0, 1 - abs(time / duration * 2 - 1)) }
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
    /// Blocks other entities' `move(_:)`, as solid tiles do: villagers, chests, tree trunks.
    public var solid = false
    /// The scene it's in, from `Scene.add(_:at:)`.
    public internal(set) weak var scene: Scene?
    var remainder = Vector.zero // sub-pixel movement not applied yet

    public init() {}

    /// Runs 60 times a second; `dt` is the time since the last update, in seconds. Override it to move and react.
    open func update(_ dt: Double) {}

    /// Draws the sprite. Override it to draw more, in world pixels, and call super to keep the sprite.
    open func draw(_ screen: Screen) {
        if let sprite { screen.draw(sprite, x: position.x, y: position.y) }
    }

    /// Where it draws when the scene's `ySort` is on, in world pixels: the bottom of its hitbox, its feet, so the
    /// hitbox of a tree is its trunk. Override it for something always under the rest, like a shadow (`-.infinity`),
    /// or over it, like a bird.
    open var sortY: Double { Double(box(at: position).y + hitbox.height) }

    /// Moves by `velocity * dt` one pixel at a time, stopping flush against solid tiles and solid entities (but not
    /// those it already overlaps, so two that start on top of each other can walk apart).
    /// Hitting something zeroes that part of the velocity.
    public func move(_ dt: Double) {
        remainder += velocity * dt
        let pixels = remainder.rounded(.toNearestOrAwayFromZero)
        remainder -= pixels
        for axis in 0..<2 where !slide(Int(pixels[axis]), axis: axis) {
            velocity[axis] = 0
            remainder[axis] = 0
        }
    }

    /// Standing on a solid tile or entity.
    public var onGround: Bool { blocked(at: position + [0, 1]) }

    /// True when the two hitboxes overlap.
    public func overlaps(_ other: Entity) -> Bool { box(at: position).intersects(other.box(at: other.position)) }

    /// True when the hitbox overlaps `box`, in world pixels, like a door's from `Tilemap.Object.box`.
    public func overlaps(_ box: Rect) -> Bool { self.box(at: position).intersects(box) }

    func slide(_ pixels: Int, axis: Int) -> Bool {
        for _ in 0..<abs(pixels) {
            var next = position
            next[axis] += Double(pixels.signum())
            if blocked(at: next) { return false }
            position = next
        }
        return true
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

/// A picture from `Assets/<image>.png`. If `Assets/<image>.json` (written by the pixel editor) cuts it into frames,
/// `play(_:)` runs one of its animations; without it, the whole image is one frame.
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
    var time = 0.0

    public init(_ image: String) { self.image = image }

    /// Starts the named animation. Playing the one that's already running keeps it going, so it's fine every frame.
    public mutating func play(_ animation: String) {
        if animation != self.animation { (self.animation, time) = (animation, 0) }
    }
}

/// A grid of tiles from a tileset, `Assets/<tileset>.png`, cut into `tileSize` squares numbered left to right,
/// then top to bottom.
///
/// While the game runs, the scene's tilemap reloads when its `.tilemap` (or the tileset's `.json`) changes, so tiles
/// painted in the editor show up live. Entities already in the scene stay as they are: objects moved or added in
/// the editor show up the next time the game builds the level.
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
    /// Things placed in the level with the map editor's Objects tool, like coins or where the player starts.
    public var objects: [Object] = []
    var name: String? // the .tilemap it came from
    var modified: [Date?] = [] // when it and the tileset's .json were last changed, as loaded
    var removed: Set<Int> = [] // what removeTiles took out, kept out when the map reloads
    var edits: [SIMD3<Int>: Int?] = [:] // what setTile put down, by layer, column and row, kept when the map reloads
    var time = 0.0 // for animated tiles, advanced by the scene's updates

    /// Something placed in the level with the map editor's Objects tool.
    public struct Object: Sendable {
        /// What it is, like "coin" or "player"; `objects(named:)` finds them by it.
        public var name: String
        /// Top-left corner, in pixels.
        public var position: Vector
        /// Settings typed for it, like "speed": "40".
        public var properties: [String: String]
        var size: Size

        /// Where it is and how big, in pixels: the size it was given in the map editor, or else, as the editor shows
        /// it, the size of the image it's named after, or one tile. For zones like doors: `player.overlaps(door.box)`.
        public var box: Rect { Rect(x: Int(position.x), y: Int(position.y), width: size.width, height: size.height) }
    }

    /// Loads `Assets/<name>.tilemap`, made in the tilemap editor. The tile size and which tiles are solid
    /// come from the tileset's `.json`.
    public init(_ name: String) {
        (tileset, tileSize, width, height, layers, solid) = ("", 0, 0, 0, [], [])
        do { try load(name) } catch {
            fatalError("PixelKit: can't load \(assetURL("\(name).tilemap").path): \(error.localizedDescription)")
        }
    }

    mutating func load(_ name: String) throws {
        let url = assetURL("\(name).tilemap")
        let map = try TilemapFile(contentsOf: url)
        let sheetURL = assetURL("\(map.tileset).json")
        let sheet = try SheetFile(contentsOf: sheetURL)
        (tileset, tileSize, width, height) = (map.tileset, sheet.frameWidth, map.width, map.height)
        layers = map.layers.map { $0.tiles.map { $0 < 0 ? nil : $0 } }
        above = Set(map.layers.indices.filter { map.layers[$0].above == true })
        solid = Set(sheet.solid ?? [])
        var images: [String: Size?] = [:] // the frame size of each name's image, read once
        objects = (map.objects ?? []).map { object in
            if images[object.name] == nil { images[object.name] = .some(frameSize(object.name)) }
            let size = images[object.name]! ?? Size(tileSize, tileSize)
            return Object(name: object.name, position: [Double(object.x), Double(object.y)], properties: object.properties ?? [:],
                          size: Size(object.width ?? size.width, object.height ?? size.height))
        }
        (self.name, modified) = (name, [modificationDate(url), modificationDate(sheetURL)])
        for tile in removed { _ = removeTiles(tile) }
        for (cell, tile) in edits where layers.indices.contains(cell.x) && (0..<width).contains(cell.y) && (0..<height).contains(cell.z) {
            layers[cell.x][cell.z * width + cell.y] = tile
        }
    }

    /// Loads the map again if its files changed. One that can't be read keeps the map as it is.
    mutating func reloadIfChanged() {
        guard let name else { return }
        let dates = [modificationDate(assetURL("\(name).tilemap")), modificationDate(assetURL("\(tileset).json"))]
        guard dates != modified else { return }
        modified = dates // so a broken file is tried again only once it changes again
        try? load(name)
    }

    /// Builds a one-layer map from text, one string per row. `legend` maps characters to tile numbers;
    /// any other character is empty. Every tile in the legend is solid unless you pass `solid`.
    public init(_ tileset: String, tileSize: Int, rows: [String], legend: [Character: Int], solid: Set<Int>? = nil) {
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
    public func objects(named name: String) -> [Vector] { objects.filter { $0.name == name }.map(\.position) }

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
}
