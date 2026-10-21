import Foundation

/// An image behind a scene's map (`Scene.backdrops`) or over its world (`Scene.overhangs`), moving at its own rate as
/// the camera moves: a sky, far hills, a canopy of leaves hanging over the view. It's darkened by the scene's daylight,
/// its darkness and clouds, but not lit by its lights.
public struct Parallax: Sendable {
    /// The image, `Assets/<image>.png`.
    public var image: ImageName
    /// How many pixels it moves for each one the camera moves: 0 stays with the view, under 1 is farther off than the
    /// world, 1 moves with it, and over 1 is nearer.
    public var scroll: Double
    /// Where its top-left corner is while the camera is at (0, 0), in pixels.
    public var offset: Vector
    /// Which ways it repeats to fill the view; none shows it once.
    public var repeats: Repeats
    /// How many pixels its rows sway, each a little after the one above, as leaves do in a wind; 0 holds it still.
    public var sway: Double

    public init(image: ImageName, scroll: Double = 0, offset: Vector = .zero, repeats: Repeats = [], sway: Double = 0) {
        (self.image, self.scroll, self.offset, self.repeats, self.sway) = (image, scroll, offset, repeats, sway)
    }

    /// Which ways a `Parallax` repeats.
    public struct Repeats: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        /// Left and right, as far hills do.
        public static let across = Repeats(rawValue: 1)
        /// Up and down.
        public static let down = Repeats(rawValue: 2)
        /// Both ways, as a sky of stars does.
        public static let both: Repeats = [.across, .down]
    }

    /// Where its top-left corner is in the view when the view's top-left corner is at `view` in the world.
    func origin(view: Vector) -> Vector { offset - view * scroll }
}

/// A shake of the view (`Scene.shake(_:)`): trauma from 0 to 1 that decays in about a second, moving the view up to
/// 8 pixels times its square through smooth noise, as Squirrel Eiserloh's cameras shake.
struct Shake {
    var trauma = 0.0

    mutating func add(_ amount: Double) { trauma = min(max(trauma + amount, 0), 1) }
    mutating func decay(_ dt: Double) { trauma = max(trauma - dt, 0) }

    /// How far it moves the view at `time`, in pixels.
    func offset(at time: Double) -> Vector {
        guard trauma > 0 else { return .zero }
        return [wobble(time * 24), wobble(time * 24 + 57.3)] * 8 * trauma * trauma
    }
}

/// Smooth noise from -1 to 1 along `t`, changing about once a unit.
func wobble(_ t: Double) -> Double {
    func hash(_ i: Double) -> Double {
        let x = sin(i * 127.1) * 43758.5453
        return x - x.rounded(.down)
    }
    let (i, f) = (t.rounded(.down), t - t.rounded(.down))
    return (hash(i) + (hash(i + 1) - hash(i)) * f * f * (3 - 2 * f)) * 2 - 1
}

public extension Screen {
    /// Draws a line a pixel wide from one point to another, in whole pixels: a rope, a laser, a crack.
    func line(from start: Vector, to end: Vector, color: UInt32, opacity: Double = 1) {
        for pixel in pixels(from: start, to: end) { fill(Rect(x: pixel.x, y: pixel.y, width: 1, height: 1), color: color, opacity: opacity) }
    }

    /// Draws a lightning bolt from one point to another, glowing (as `Sprite.glows` does): its line split again and
    /// again, each middle pushed aside less each time, with a fork from partway along, a pixel wide in `color` with
    /// `glow` around it. The same `seed` draws the same bolt; a new one every few frames makes it crackle.
    func bolt(from start: Vector, to end: Vector, seed: Int = 0, color: UInt32 = 0xFFFFFF, glow: UInt32 = 0x6C8CFF) {
        var core = Set<SIMD2<Int>>(), around = Set<SIMD2<Int>>()
        for line in boltLines(from: start, to: end, seed: seed) {
            for (a, b) in zip(line, line.dropFirst()) {
                for pixel in pixels(from: a, to: b) {
                    core.insert(pixel)
                    for dx in -1...1 { for dy in -1...1 { around.insert(pixel &+ [dx, dy]) } }
                }
            }
        }
        let dot = Rect(x: 0, y: 0, width: 1, height: 1)
        for pixel in around.subtracting(core) { quad(white, x: Double(pixel.x), y: Double(pixel.y), source: dot, color: glow, glows: true, state: glowing) }
        for pixel in core { quad(white, x: Double(pixel.x), y: Double(pixel.y), source: dot, color: color, glows: true, state: glowing) }
    }
}

/// A lightning bolt's lines from `start` to `end`: the line split again and again, each middle pushed aside by up to
/// half as much as the time before, from 18% of its length; and a fork from a third to two thirds along it, a third as
/// long, off to one side. The same seed gives the same bolt.
func boltLines(from start: Vector, to end: Vector, seed: Int) -> [[Vector]] {
    var random = Seeded(state: UInt64(bitPattern: Int64(seed)))
    func split(_ a: Vector, _ b: Vector, times: Int) -> [Vector] {
        var points = [a, b]
        var push = length(b - a) * 0.18
        for _ in 0..<times {
            var next = [points[0]]
            for (p, q) in zip(points, points.dropFirst()) {
                let normal = Vector(p.y - q.y, q.x - p.x) / max(length(q - p), 0.001)
                next += [(p + q) / 2 + normal * Double.random(in: -push...push, using: &random), q]
            }
            (points, push) = (next, push / 2)
        }
        return points
    }
    let main = split(start, end, times: 6)
    let from = main[Int.random(in: main.count / 3...main.count * 2 / 3, using: &random)]
    let turn = Double.random(in: 0.4...0.8, using: &random) * (Bool.random(using: &random) ? 1 : -1)
    let way = (end - start) / 3
    let fork = from + Vector(way.x * cos(turn) - way.y * sin(turn), way.x * sin(turn) + way.y * cos(turn))
    return [main, split(from, fork, times: 5)]
}

func length(_ v: Vector) -> Double { (v * v).sum().squareRoot() }

/// The pixels on a line from `a` to `b`, Bresenham's way.
func pixels(from a: Vector, to b: Vector) -> [SIMD2<Int>] {
    var (x, y) = (Int(a.x.rounded(.down)), Int(a.y.rounded(.down)))
    let (x1, y1) = (Int(b.x.rounded(.down)), Int(b.y.rounded(.down)))
    let (dx, dy, sx, sy) = (abs(x1 - x), -abs(y1 - y), x < x1 ? 1 : -1, y < y1 ? 1 : -1)
    var (error, pixels) = (dx + dy, [SIMD2<Int>]())
    while true {
        pixels.append([x, y])
        if x == x1 && y == y1 { return pixels }
        let twice = 2 * error // before either step changes it
        if twice >= dy {
            error += dy
            x += sx
        }
        if twice <= dx {
            error += dx
            y += sy
        }
    }
}

/// Random numbers that come out the same for a seed (SplitMix64).
struct Seeded: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension Screen {
    /// Draws a backdrop or an overhang over the view, lit as `lighting` says.
    func draw(_ layer: Parallax) {
        let origin = layer.origin(view: offset)
        queue(texture(layer.image.name), [0, 0, Float(size.width), Float(size.height)], effects: [Float(origin.x), Float(origin.y), Float(layer.sway), Float(time)],
              more: [layer.repeats.contains(.across) ? 1 : 0, layer.repeats.contains(.down) ? 1 : 0, lighting.rawValue, 0], state: parallax)
    }
}
