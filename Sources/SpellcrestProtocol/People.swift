import Foundation

/// A kit of parts that people are built from, `Assets/Parts/kit.json`, as a game's character creator builds them. A
/// part is an image, `Assets/Parts/<slot>/<name>.png`, drawn in the first ramp of each material its slot wears, and
/// every part has the kit's frames, laid out alike, so a frame of one lies on the same frame of the others.
public struct KitFile: AssetFile, Equatable, Sendable {
    /// The size of every part's frames.
    public var frameWidth: Int
    public var frameHeight: Int
    /// The animations the frames make, by name, which every person made from the kit has.
    public var animations: [String: SheetFile.Animation]?
    /// Back to front: the order a person's parts are stacked in.
    public var slots: [Slot]
    /// What parts are drawn in that a person can wear in other shades, like cloth or hair.
    public var materials: [Material]

    public struct Slot: Codable, Equatable, Sendable {
        public var name: String
        /// The materials its parts are drawn in that a person wears in shades of its own; nil is none, as drawn.
        public var materials: [String]?

        public init(name: String, materials: [String]? = nil) { (self.name, self.materials) = (name, materials) }
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

    public init(frameWidth: Int, frameHeight: Int, animations: [String: SheetFile.Animation]? = nil, slots: [Slot], materials: [Material]) {
        (self.frameWidth, self.frameHeight, self.animations, self.slots, self.materials) = (frameWidth, frameHeight, animations, slots, materials)
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
    /// The person's pixels, 0xRRGGBBAA with straight alpha: its parts stacked back to front in the kit's order, each
    /// over the ones behind it, in the shades the person wears of its slot's materials. `part` gives a part's pixels;
    /// every part has as many.
    func compose(_ kit: KitFile, part: (_ slot: String, _ name: String) throws -> [UInt32]) throws -> [UInt32] {
        for slot in parts.keys.sorted() where !kit.slots.contains(where: { $0.name == slot }) {
            throw PersonError("the kit has no slot called \(slot)")
        }
        let swaps = try swaps(kit)
        var stacked: [UInt32]?
        var first = ""
        for slot in kit.slots {
            guard let name = parts[slot.name] else { continue }
            var pixels = try part(slot.name, name)
            let swap = (slot.materials ?? []).reduce(into: [UInt32: UInt32]()) { all, material in all.merge(swaps[material] ?? [:]) { a, _ in a } }
            if !swap.isEmpty {
                for i in pixels.indices where pixels[i] & 0xFF != 0 {
                    if let worn = swap[pixels[i] >> 8] { pixels[i] = worn << 8 | pixels[i] & 0xFF }
                }
            }
            guard var below = stacked else {
                (stacked, first) = (pixels, "\(slot.name)/\(name)")
                continue
            }
            guard pixels.count == below.count else {
                throw PersonError("\(slot.name)/\(name) has \(pixels.count) pixels, and \(first) \(below.count): every part has the kit's frames, laid out alike")
            }
            for i in pixels.indices where pixels[i] & 0xFF != 0 { below[i] = over(pixels[i], below[i]) }
            stacked = below
        }
        guard let stacked else { throw PersonError("a person wears a part in one slot at least") }
        return stacked
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
