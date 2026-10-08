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

/// A picture from `Assets/<image>.png`, cut into equal frames (left to right, then top to bottom).
public struct Sprite: Sendable {
    public var image: String
    public var frameSize: Size
    /// Assigning a different animation restarts it; assigning the same one every frame doesn't.
    public var animation: Animation { didSet { if animation != oldValue { time = 0 } } }
    /// Mirrors the sprite horizontally, e.g. to face left.
    public var flipped = false
    var time = 0.0

    public init(_ image: String, frameSize: Size, animation: Animation = Animation(frames: [0], fps: 0)) {
        self.image = image
        self.frameSize = frameSize
        self.animation = animation
    }

    var frame: Int { animation.frames[Int(time * animation.fps) % animation.frames.count] }
}

public struct Animation: Sendable, Equatable {
    public var frames: [Int]
    public var fps: Double

    public init(frames: [Int], fps: Double) {
        precondition(!frames.isEmpty, "an animation needs at least one frame")
        self.frames = frames
        self.fps = fps
    }
}

/// A grid of tiles from `Assets/<image>.png` (cut into `tileSize` squares, numbered left to right, top to bottom).
public struct Tilemap: Sendable {
    public var image: String
    public var tileSize: Int
    /// `cells[row][column]` is a tile number, or nil for empty.
    public var cells: [[Int?]]
    /// Tile numbers that block movement.
    public var solid: Set<Int>

    /// Builds a map from text, one string per row. `legend` maps characters to tile numbers;
    /// any other character is empty. Every tile in the legend is solid unless you pass `solid`.
    public init(_ image: String, tileSize: Int, rows: [String], legend: [Character: Int], solid: Set<Int>? = nil) {
        self.image = image
        self.tileSize = tileSize
        cells = rows.map { $0.map { legend[$0] } }
        self.solid = solid ?? Set(legend.values)
    }

    /// Size in pixels.
    public var size: Size { Size((cells.map(\.count).max() ?? 0) * tileSize, cells.count * tileSize) }

    /// Whether any solid tile overlaps `box`. Outside the map is empty.
    func isSolid(_ box: Rect) -> Bool {
        for row in stride(from: cell(box.y), through: cell(box.y + box.height - 1), by: 1) where cells.indices.contains(row) {
            for column in stride(from: cell(box.x), through: cell(box.x + box.width - 1), by: 1)
            where cells[row].indices.contains(column) {
                if let tile = cells[row][column], solid.contains(tile) { return true }
            }
        }
        return false
    }

    /// Which cell a pixel is in, rounding toward -∞ so pixels left of or above the map get negative cells.
    func cell(_ pixel: Int) -> Int { pixel >= 0 ? pixel / tileSize : (pixel + 1) / tileSize - 1 }
}
