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
