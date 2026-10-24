import Foundation

/// A kit of parts that people are built from, `Assets/Parts/kit.json`, as a game's character creator builds them. A
/// part is an image, `Assets/Parts/<slot>/<name>.png`, drawn in the first ramp of each material its slot wears. It has
/// the kit's every frame, laid out alike, so a frame of one lies on the same frame of the others; or, in a slot that
/// follows an anchor, like the head, it's one frame, drawn as it sits in frame 0 and moved with the anchor.
public struct KitFile: AssetFile, Equatable, Sendable {
    /// The size of every part's frames.
    public var frameWidth: Int
    public var frameHeight: Int
    /// How many frames a person has, and how many to a row of their image; nil takes the first part with every frame's.
    public var frames: Int?
    public var columns: Int?
    /// The animations the frames make, by name, which every person made from the kit has.
    public var animations: [String: SheetFile.Animation]?
    /// Back to front: the order a person's parts are stacked in.
    public var slots: [Slot]
    /// What parts are drawn in that a person can wear in other shades, like cloth or hair.
    public var materials: [Material]
    /// Points that move from frame to frame, by name, like the head or the hand that holds a weapon: for each frame,
    /// how far a part drawn once, as it sits in frame 0, moves to be there; nil in a frame without it, as a hand that
    /// casts holds no sword.
    public var anchors: [String: [Offset?]]?
    /// A part with every frame, `Parts/<front>.png`, whose pixels are where the body is in front of the head, as an arm
    /// raised before a hat's brim: there, parts that follow an anchor leave what's behind them.
    public var front: String?

    public struct Slot: Codable, Equatable, Sendable {
        public var name: String
        /// The materials its parts are drawn in that a person wears in shades of its own; nil is none, as drawn.
        public var materials: [String]?
        /// The anchor its parts of one frame follow; nil when its parts have every frame.
        public var follows: String?

        public init(name: String, materials: [String]? = nil, follows: String? = nil) {
            (self.name, self.materials, self.follows) = (name, materials, follows)
        }
    }

    /// How far, in pixels, as `[x, y]` in the file.
    public struct Offset: Codable, Equatable, Sendable {
        public var x, y: Int

        public init(_ x: Int, _ y: Int) { (self.x, self.y) = (x, y) }

        public init(from decoder: Decoder) throws {
            var pair = try decoder.unkeyedContainer()
            (x, y) = (try pair.decode(Int.self), try pair.decode(Int.self))
        }

        public func encode(to encoder: Encoder) throws {
            var pair = encoder.unkeyedContainer()
            try pair.encode(x)
            try pair.encode(y)
        }
    }

    public struct Material: Codable, Equatable, Sendable {
        public var name: String
        /// Its sets of shades. Parts are drawn in the first; each has as many shades as it.
        public var ramps: [Ramp]

        public init(name: String, ramps: [Ramp]) { (self.name, self.ramps) = (name, ramps) }
    }

    /// A set of a material's shades, darkest first, as "#RRGGBB", like "blue" for cloth.
    public struct Ramp: Codable, Equatable, Sendable {
        public var name: String
        public var colors: [String]

        public init(name: String, colors: [String]) { (self.name, self.colors) = (name, colors) }
    }

    public init(frameWidth: Int, frameHeight: Int, frames: Int? = nil, columns: Int? = nil, animations: [String: SheetFile.Animation]? = nil,
                slots: [Slot], materials: [Material], anchors: [String: [Offset?]]? = nil, front: String? = nil) {
        (self.frameWidth, self.frameHeight, self.frames, self.columns, self.animations) = (frameWidth, frameHeight, frames, columns, animations)
        (self.slots, self.materials, self.anchors, self.front) = (slots, materials, anchors, front)
    }

    /// How a person's image is cut up: the kit's frames and animations.
    public var sheet: SheetFile { SheetFile(frameWidth: frameWidth, frameHeight: frameHeight, animations: animations) }

    public func material(_ name: String) -> Material? { materials.first { $0.name == name } }
}

/// Someone made of a kit's parts, `<name>.person`, anywhere in `Assets` but `Parts`: the part in each of the kit's
/// slots and the shades worn of each material. It's made into `<name>.png` and `<name>.json` beside it, which the game
/// draws as it draws any sprite.
public struct PersonFile: AssetFile, Equatable, Sendable {
    /// The part in each slot, by its name in the slot's folder, like "hat": "witch"; a slot not here is empty.
    public var parts: [String: String]
    /// The ramp worn of each material, by name, like "cloth": "black"; a material not here is worn as drawn.
    public var wears: [String: String]?

    public init(parts: [String: String], wears: [String: String]? = nil) { (self.parts, self.wears) = (parts, wears) }
}

/// Why a person can't be made, saying what to change.
public struct PersonError: Error, Equatable, CustomStringConvertible {
    public let description: String

    public init(_ description: String) { self.description = description }
}

public extension PersonFile {
    /// The person's pixels, 0xRRGGBBAA with straight alpha, and how wide their image is: their parts stacked back to
    /// front in the kit's order, each over the ones behind it, in the shades the person wears of its slot's materials.
    /// A part of one frame in a slot that follows an anchor is drawn at the anchor in each frame. `part` gives an
    /// image in `Parts`, by its path there without `.png`, like "hat/witch", and its width.
    func compose(_ kit: KitFile, part: (_ path: String) throws -> (pixels: [UInt32], width: Int)) throws -> (pixels: [UInt32], width: Int) {
        for slot in parts.keys.sorted() where !kit.slots.contains(where: { $0.name == slot }) {
            throw PersonError("the kit has no slot called \(slot)")
        }
        let swaps = try swaps(kit)
        let worn = try kit.slots.compactMap { slot in try parts[slot.name].map { (slot, "\(slot.name)/\($0)", try part("\(slot.name)/\($0)")) } }
        guard !worn.isEmpty else { throw PersonError("a person wears a part in one slot at least") }
        let (fw, fh) = (kit.frameWidth, kit.frameHeight)
        func isFrame(_ image: (pixels: [UInt32], width: Int)) -> Bool { image.width == fw && image.pixels.count == fw * fh }
        // The image's size: as the kit lays it out, or as its first part with every frame is.
        let whole = worn.first { $0.0.follows == nil || !isFrame($0.2) }
        let (width, height): (Int, Int)
        if let frames = kit.frames, let columns = kit.columns {
            (width, height) = (columns * fw, (frames + columns - 1) / columns * fh)
        } else if let whole {
            (width, height) = (whole.2.width, whole.2.pixels.count / max(whole.2.width, 1))
        } else {
            (width, height) = (fw, fh)
        }
        let columns = max(width / fw, 1), count = columns * (height / fh)
        let front = try kit.front.map { name -> [UInt32] in
            let mask = try part(name)
            guard mask.width == width, mask.pixels.count == width * height else {
                throw PersonError("\(name) is \(mask.width) pixels wide, and a person \(width): it has every frame, laid out as theirs")
            }
            return mask.pixels
        }
        var stacked = [UInt32](repeating: 0, count: width * height)
        for (slot, path, image) in worn {
            var pixels = image.pixels
            let swap = (slot.materials ?? []).reduce(into: [UInt32: UInt32]()) { all, material in all.merge(swaps[material] ?? [:]) { a, _ in a } }
            if !swap.isEmpty {
                for i in pixels.indices where pixels[i] & 0xFF != 0 {
                    if let worn = swap[pixels[i] >> 8] { pixels[i] = worn << 8 | pixels[i] & 0xFF }
                }
            }
            if image.width == width, pixels.count == width * height {
                for i in pixels.indices where pixels[i] & 0xFF != 0 { stacked[i] = over(pixels[i], stacked[i]) }
            } else if isFrame(image), let anchor = slot.follows {
                guard let offsets = kit.anchors?[anchor] else { throw PersonError("the kit's \(slot.name) follows \(anchor), which isn't among its anchors") }
                for frame in 0..<min(count, offsets.count) {
                    guard let offset = offsets[frame] else { continue }
                    let (left, top) = (frame % columns * fw, frame / columns * fh)
                    for y in 0..<fh {
                        for x in 0..<fw where pixels[y * fw + x] & 0xFF != 0 {
                            let (fx, fy) = (x + offset.x, y + offset.y)
                            guard (0..<fw).contains(fx), (0..<fh).contains(fy) else { continue }
                            let i = (top + fy) * width + left + fx
                            if let front, front[i] & 0xFF != 0 { continue } // an arm in front of the head
                            stacked[i] = over(pixels[y * fw + x], stacked[i])
                        }
                    }
                }
            } else {
                throw PersonError("\(path) is \(image.width) pixels wide and a person \(width): a part has every frame, laid out as theirs"
                                  + (slot.follows == nil ? "" : ", or one frame to follow the \(slot.follows!)"))
            }
        }
        return (stacked, width)
    }

    /// For each material the person wears in other shades than drawn, its drawn colors to the worn ones, 0xRRGGBB.
    private func swaps(_ kit: KitFile) throws -> [String: [UInt32: UInt32]] {
        var swaps: [String: [UInt32: UInt32]] = [:]
        for (name, rampName) in (wears ?? [:]).sorted(by: { $0.key < $1.key }) {
            guard let material = kit.material(name) else { throw PersonError("the kit has no material called \(name)") }
            guard let drawn = material.ramps.first else { throw PersonError("the kit's \(name) has no ramps") }
            guard let worn = material.ramps.first(where: { $0.name == rampName }) else {
                throw PersonError("the kit's \(name) has no ramp called \(rampName), only \(material.ramps.map(\.name).joined(separator: ", "))")
            }
            guard worn.colors.count == drawn.colors.count else {
                throw PersonError("\(name)'s \(worn.name) has \(worn.colors.count) shades, and \(drawn.name), which its parts are drawn in, has \(drawn.colors.count)")
            }
            let (from, to) = (try drawn.colors.map(rgb), try worn.colors.map(rgb))
            swaps[name] = Dictionary(zip(from, to)) { a, _ in a }
        }
        return swaps
    }
}

/// "#RRGGBB" as 0xRRGGBB.
func rgb(_ color: String) throws -> UInt32 {
    let hex = color.hasPrefix("#") ? color.dropFirst() : color[...]
    guard hex.count == 6, let value = UInt32(hex, radix: 16) else { throw PersonError("\(color) isn't a color like #1560C8") }
    return value
}

/// `top` drawn over `bottom`, both 0xRRGGBBAA with straight alpha, as the pixel editor paints.
func over(_ top: UInt32, _ bottom: UInt32) -> UInt32 {
    let (ta, ba) = (Double(top & 0xFF) / 255, Double(bottom & 0xFF) / 255)
    if ta == 1 || ba == 0 { return ta == 0 ? 0 : top }
    if ta == 0 { return bottom }
    let alpha = ta + ba * (1 - ta)
    func channel(_ shift: UInt32) -> UInt32 {
        UInt32(((Double(top >> shift & 0xFF) * ta + Double(bottom >> shift & 0xFF) * ba * (1 - ta)) / alpha).rounded()) << shift
    }
    return channel(24) | channel(16) | channel(8) | UInt32((alpha * 255).rounded())
}
