import Foundation
import PixelKitProtocol

/// A level, menu or screen: a tilemap plus the entities in it.
@MainActor open class Scene {
    /// The scene on screen. Assign a new one to switch scenes, or a fresh copy to restart.
    public static var current = Scene()

    public private(set) var entities: [Entity] = []
    public var tilemap: Tilemap?
    /// Top-left corner of the view, in world pixels.
    public var camera = Vector.zero
    /// Clear color as 0xRRGGBB.
    public var background: UInt32 = 0x1D2B53

    public init() {}

    public func add(_ entity: Entity, at position: Vector) {
        entity.position = position
        entity.scene = self
        entities.append(entity)
    }

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
    public var sprite: Sprite?
    public internal(set) weak var scene: Scene?
    var remainder = Vector.zero // sub-pixel movement not applied yet

    public init() {}

    open func update(_ dt: Double) {}

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
public struct Tilemap: Sendable {
    public var tileset: String
    public var tileSize: Int
    /// Size in tiles.
    public var width: Int
    public var height: Int
    /// Each layer's tiles row by row, `layers[layer][row * width + column]`; nil is empty. The first layer draws first.
    public var layers: [[Int?]]
    /// Tile numbers that block movement, in any layer.
    public var solid: Set<Int>

    /// Loads `Assets/<name>.tilemap`, made in the tilemap editor. The tile size and which tiles are solid
    /// come from the tileset's `.json`.
    public init(_ name: String) {
        let url = URL(fileURLWithPath: "Assets/\(name).tilemap")
        do {
            let map = try TilemapFile(contentsOf: url)
            let sheet = try SheetFile(contentsOf: URL(fileURLWithPath: "Assets/\(map.tileset).json"))
            (tileset, tileSize, width, height) = (map.tileset, sheet.frameWidth, map.width, map.height)
            layers = map.layers.map { $0.tiles.map { $0 < 0 ? nil : $0 } }
            solid = Set(sheet.solid ?? [])
        } catch {
            fatalError("PixelKit: can't load \(url.path): \(error.localizedDescription)")
        }
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

    /// Removes every `tile` from the map and returns where each one was (top-left corner, in pixels).
    /// Handy for tiles that only mark where things go, like coins or the player's start.
    public mutating func removeTiles(_ tile: Int) -> [Vector] {
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
