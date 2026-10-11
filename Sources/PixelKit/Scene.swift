import Foundation
import PixelKitProtocol

/// A level, menu or screen: a tilemap plus the entities in it.
@MainActor open class Scene {
    /// The scene on screen. Assign a new one to switch scenes, or a fresh copy to restart.
    public static var current = Scene()

    /// Everything in the scene, in the order it updates and draws.
    public private(set) var entities: [Entity] = []
    /// The level's tiles, drawn behind the entities. `Entity.move(_:)` stops against its solid ones.
    public var tilemap: Tilemap?
    /// Top-left corner of the view, in world pixels.
    public var camera = Vector.zero
    /// Clear color as 0xRRGGBB.
    public var background: UInt32 = 0x1D2B53

    public init() {}

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
    }

    /// Call super to draw the tilemap and entities, then draw anything on top (like a HUD) in screen pixels.
    open func draw(_ screen: Screen) {
        screen.offset = camera.rounded(.down)
        if let tilemap { screen.draw(tilemap) }
        for entity in entities { entity.draw(screen) }
        screen.offset = .zero
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

    /// Moves by `velocity * dt` one pixel at a time, stopping flush against solid tiles.
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

    /// Standing on a solid tile.
    public var onGround: Bool { solid(at: position + [0, 1]) }

    /// True when the two hitboxes overlap.
    public func overlaps(_ other: Entity) -> Bool { box(at: position).intersects(other.box(at: other.position)) }

    func slide(_ pixels: Int, axis: Int) -> Bool {
        for _ in 0..<abs(pixels) {
            var next = position
            next[axis] += Double(pixels.signum())
            if solid(at: next) { return false }
            position = next
        }
        return true
    }

    func solid(at position: Vector) -> Bool { scene?.tilemap?.isSolid(box(at: position)) ?? false }

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
    /// Tile numbers that block movement, in any layer.
    public var solid: Set<Int>
    /// Things placed in the level with the map editor's Objects tool, like coins or where the player starts.
    public var objects: [Object] = []
    var name: String? // the .tilemap it came from
    var modified: [Date?] = [] // when it and the tileset's .json were last changed, as loaded
    var removed: Set<Int> = [] // what removeTiles took out, kept out when the map reloads

    /// Something placed in the level with the map editor's Objects tool.
    public struct Object: Sendable {
        /// What it is, like "coin" or "player"; `objects(named:)` finds them by it.
        public var name: String
        /// Top-left corner, in pixels.
        public var position: Vector
        /// Settings typed for it, like "speed": "40".
        public var properties: [String: String]
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
        solid = Set(sheet.solid ?? [])
        objects = (map.objects ?? []).map { Object(name: $0.name, position: [Double($0.x), Double($0.y)], properties: $0.properties ?? [:]) }
        (self.name, modified) = (name, [modificationDate(url), modificationDate(sheetURL)])
        for tile in removed { _ = removeTiles(tile) }
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
