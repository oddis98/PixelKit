import Foundation

/// A JSON file the editor writes and games read. Both use these types, so the two sides can't drift apart.
public protocol AssetFile: Codable {}

public extension AssetFile {
    init(contentsOf url: URL) throws {
        self = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    /// Writes the file in one step, so a running game never reads half of it.
    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

/// How `Assets/<image>.png` is cut up, stored in `Assets/<image>.json`: into frames for animations, into tiles
/// when the image is a tileset, or into glyphs when it's a font. Frames are numbered left to right, then top to bottom.
public struct SheetFile: AssetFile, Equatable, Sendable {
    public var frameWidth: Int
    public var frameHeight: Int
    /// Animations by name, e.g. "walk".
    public var animations: [String: Animation]?
    /// Tilesets only: tile numbers that block movement.
    public var solid: [Int]?
    /// Fonts only: the characters the frames show, in order.
    public var characters: String?

    public struct Animation: Codable, Equatable, Sendable {
        public var frames: [Int]
        public var fps: Double

        public init(frames: [Int], fps: Double) {
            self.frames = frames
            self.fps = fps
        }
    }

    public init(frameWidth: Int, frameHeight: Int, animations: [String: Animation]? = nil, solid: [Int]? = nil, characters: String? = nil) {
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        self.animations = animations
        self.solid = solid
        self.characters = characters
    }
}

/// A level from the tilemap editor, stored in `Assets/<name>.tilemap`.
public struct TilemapFile: AssetFile, Equatable, Sendable {
    /// The image the tiles come from. Its `SheetFile` gives the tile size and which tiles are solid.
    public var tileset: String
    /// Size in tiles.
    public var width: Int
    public var height: Int
    /// The first layer draws first.
    public var layers: [Layer]
    /// Things placed in the level, like coins or where the player starts.
    public var objects: [Object]?

    public struct Layer: Codable, Equatable, Sendable {
        public var name: String
        /// Tile numbers row by row; -1 is empty.
        public var tiles: [Int]
        /// Draws over the objects and entities, like roofs and treetops; nil is false.
        public var above: Bool?

        public init(name: String, tiles: [Int], above: Bool? = nil) {
            (self.name, self.tiles, self.above) = (name, tiles, above)
        }
    }

    public struct Object: Codable, Equatable, Sendable {
        public var name: String
        /// Top-left corner, in pixels.
        public var x: Int
        public var y: Int
        /// Settings for the game, like "speed": "40".
        public var properties: [String: String]?
        /// Size in pixels, for zones like doors; nil is as big as the image named after it, or one tile.
        public var width: Int?
        public var height: Int?

        public init(name: String, x: Int, y: Int, properties: [String: String]? = nil, width: Int? = nil, height: Int? = nil) {
            (self.name, self.x, self.y, self.properties, self.width, self.height) = (name, x, y, properties, width, height)
        }
    }

    public init(tileset: String, width: Int, height: Int, layers: [Layer], objects: [Object]? = nil) {
        self.tileset = tileset
        self.width = width
        self.height = height
        self.layers = layers
        self.objects = objects
    }
}

/// An object maps place, defined once in `Assets/Objects/<name>.object`: what it's drawn with, its size, the part that
/// collides, the game's class it's made as and its properties with their types and defaults. Every field is optional,
/// so `{}` is a marker, like where the player starts.
public struct ObjectFile: AssetFile, Equatable, Sendable {
    /// The sprite it's drawn with; nil makes it a zone, like a door, which the map editor draws as a box.
    public var sprite: String?
    /// The animation the sprite plays; nil shows its first frame.
    public var animation: String?
    /// A zone's size in pixels; nil is one tile. With a sprite, it's the sprite's frame.
    public var width: Int?
    public var height: Int?
    /// The part that collides, from its top-left corner; nil is all of it.
    public var hitbox: Hitbox?
    /// Blocks solid movers, as `Entity.solid` does; nil is false.
    public var solid: Bool?
    /// The game's class it's made as, by name: a `Placeable` entity.
    public var `class`: String?
    /// Settings for the game, in order, each with its type and default. A map's objects can change them.
    public var properties: [Property]?

    public struct Hitbox: Codable, Equatable, Sendable {
        public var x, y, width, height: Int

        public init(x: Int, y: Int, width: Int, height: Int) { (self.x, self.y, self.width, self.height) = (x, y, width, height) }
    }

    public struct Property: Codable, Equatable, Sendable {
        public var name: String
        /// nil is text.
        public var type: PropertyType?
        /// The default, as text like all values; nil is none.
        public var value: String?

        public init(name: String, type: PropertyType? = nil, value: String? = nil) { (self.name, self.type, self.value) = (name, type, value) }
    }

    /// What a property holds. Values are text in the files either way: "40", "true", a map's or an object's name.
    public enum PropertyType: String, Codable, CaseIterable, Sendable {
        case text, number, toggle, map, object
    }

    public init(sprite: String? = nil, animation: String? = nil, width: Int? = nil, height: Int? = nil, hitbox: Hitbox? = nil, solid: Bool? = nil,
                class: String? = nil, properties: [Property]? = nil) {
        (self.sprite, self.animation, self.width, self.height, self.hitbox) = (sprite, animation, width, height, hitbox)
        (self.solid, self.class, self.properties) = (solid, `class`, properties)
    }
}

public extension TilemapFile.Object {
    /// Its size in pixels: as the map sized it, or else as its definition says, a zone's size or its sprite's frame.
    /// Without a definition, as in maps from before objects had them, it's the frame of the image named after it.
    /// One tile when nothing says. `frame` gives an image's frame size.
    func size(_ definition: ObjectFile?, tileSize: Int, frame: (String) -> (width: Int, height: Int)?) -> (width: Int, height: Int) {
        let natural = definition.map { $0.sprite.flatMap(frame) ?? ($0.width ?? tileSize, $0.height ?? tileSize) } ?? frame(name) ?? (tileSize, tileSize)
        return (width ?? natural.width, height ?? natural.height)
    }

    /// Its properties: its own, over its definition's defaults.
    func properties(_ definition: ObjectFile?) -> [String: String] {
        (definition?.properties ?? []).reduce(into: properties ?? [:]) { all, property in
            if all[property.name] == nil, let value = property.value { all[property.name] = value }
        }
    }
}
