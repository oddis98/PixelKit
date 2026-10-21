import PixelKit

@main struct Village: Game {
    func start() -> Scene {
        let progress = Save.read(Progress.self, from: "progress") ?? Progress()
        return Place(.village, progress, position: progress.place)
    }
}

/// What the player has done. Each place hands it to the next, so hot reload keeps it (a `static var` would start
/// over), and coming out of the house saves it.
final class Progress: Codable {
    /// Where the player was in the village when the game was saved.
    var place: Vector?
    /// The bushes cut in each map, by a pixel of each.
    var cut: [String: [Vector]] = [:]
}

/// Tiles of Assets/Tilesets/tiles.png, numbered left to right, then top to bottom.
enum Tile {
    static let bush = 4, stump = 5
}

/// A map to walk around in: the village, with clouds drifting over it; inside the house, which is dark but for its
/// fire; or the wood through the gap in the hedge, at dusk under its canopy, lit by the player's lantern. Its objects,
/// placed in the map editor and defined in Assets/Objects, say what's where: trees, whose trunks stop light, the house's
/// front, its fireplace and the villager, doors with where they lead (`to`) and where you come out (`at`), and where
/// the game starts.
final class Place: Scene {
    let map: MapName
    let progress: Progress
    let player = Entity()
    var facing: Vector = [0, 1]
    /// Where a click or a tap sent the player, around what's in the way.
    var route: [Vector] = []
    var doors: [Tilemap.Object] = []
    /// What's being said, a page at a time, and how much of the first page is typed out.
    var words: [String] = []
    var letters = 0.0

    init(_ map: MapName, _ progress: Progress, at spot: ObjectName = .start, position: Vector? = nil) {
        (self.map, self.progress) = (map, progress)
        super.init()
        ySort = true // things draw by where their feet are
        follow = player // the camera keeps them in the middle, and a door's iris closes on them
        background = 0x000000
        if map == .house { (darkness, darknessColor) = (0.85, 0x1D2B53) } // a night's blue where the fire doesn't reach
        if map == .village { clouds = Clouds(cover: 0.4, shade: 0.3, size: 70, wind: [12, 5]) }
        if map == .wood { // dusk under the trees, their leaves hanging over the view and swaying, fog drifting between them
            (darkness, darknessColor, vignette) = (0.75, 0x1A1030, 0.7)
            fog = Fog(color: 0x8C8FA6, thickness: 0.35)
            overhangs = [Parallax(image: .canopy, offset: [-20, -16], sway: 1.4)]
            player.light = Light(radius: 100, color: 0xFFC27A, flicker: 0.05, shadows: true) // a lantern, which the trunks stop
        }
        var tiles = Tilemap(map)
        for point in progress.cut[map.name] ?? [] { tiles.setTile(Tile.stump, at: point, layer: 0) }
        tilemap = tiles
        addObjects() // the trees and the house, solid at their base, the villager and the fireplace
        doors = tiles.objects.filter { $0.name == .door }
        player.sprite = Sprite(.player)
        player.hitbox = Rect(x: 3, y: 10, width: 10, height: 6) // the feet, so the head can pass in front of things
        player.cornerSlide = 4 // slides around a tree or into a doorway it's a few pixels off
        player.solid = true // so the villager waits for them
        add(player, at: position ?? tiles.objects(named: spot).first ?? .zero)
        Music.play(map == .wood ? .village : SoundName(map.name), fade: 0.5) // each place's music is named after its map
    }

    override func update(_ dt: Double) {
        super.update(dt)
        guard let page = words.first else { return walk(dt) }
        letters = min(letters + dt * 40, Double(page.count)) // 40 letters a second
        if Input.pressed(.a) || Input.pressed(.pointer) { // a click or tap too: the rest of the page, then the next one
            if letters < Double(page.count) { letters = Double(page.count) } else { (words, letters) = (Array(words.dropFirst()), 0) }
        }
    }

    /// The D-pad walks, and so does a click or a tap, to where it points; A talks to whoever's in front, X cuts a bush
    /// there, Y calls lightning down a little way ahead and B casts a gloom there, and doors lead on.
    func walk(_ dt: Double) {
        func axis(_ back: Button, _ on: Button) -> Double { (Input.held(on) ? 1 : 0) - (Input.held(back) ? 1 : 0) }
        var direction: Vector = [axis(.left, .right), axis(.up, .down)]
        if Input.pressed(.pointer), let point = Input.pointer { route = player.path(to: point + camera, diagonals: true) ?? [] }
        if direction == .zero, !route.isEmpty {
            player.walk(dt, along: &route, speed: 60)
            direction = player.velocity
        } else {
            route = [] // the D-pad takes over
            player.velocity = direction * 60
            player.move(dt)
        }
        let (size, feet) = (tilemap!.size, player.hitbox) // the map's edges are walls
        player.position.x = min(max(player.position.x, Double(-feet.x)), Double(size.width - feet.x - feet.width))
        player.position.y = min(max(player.position.y, Double(-feet.y)), Double(size.height - feet.y - feet.height))
        if direction != .zero { facing = heading(direction) }
        let looks = facing.y < 0 ? "up" : facing.y > 0 ? "down" : "side"
        player.sprite?.play(direction == .zero ? looks : "walk-\(looks)")
        player.sprite?.flipped = facing.x < 0

        let front = player.position + [8, 13] + facing * 10 // just ahead of the feet
        let reach = Rect(x: Int(front.x) - 4, y: Int(front.y) - 4, width: 8, height: 8)
        if Input.pressed(.a), let villager = entities.lazy.compactMap({ $0 as? Villager }).first(where: { $0.overlaps(reach) }) {
            words = villager.words
        }
        if Input.pressed(.x), tilemap?.tile(at: front, layer: 0) == Tile.bush {
            tilemap?.setTile(Tile.stump, at: front, layer: 0)
            progress.cut[map.name, default: []].append(front)
            Sound.play(.cut)
        }
        let ahead = player.middle + facing * 48
        if Input.pressed(.y) {
            add(Strike(), at: ahead - [1, 1])
            shake(0.9)
        }
        if Input.pressed(.b) { add(Gloom(), at: ahead - [1, 1]) }
        effects = entities.compactMap { ($0 as? Strike)?.shock(camera) } // its ripple spreading over the picture
        if let door = doors.first(where: { player.overlaps($0.box) }), let to = door.map("to") {
            let next = Place(to, progress, at: door.object("at") ?? .start)
            if next.map == .village { // coming out of the house saves the game
                progress.place = next.player.position
                Save.write(progress, to: "progress")
            }
            Scene.transition(to: next, duration: 0.8, style: .iris)
        }
    }

    override func draw(_ screen: Screen) {
        super.draw(screen)
        guard let page = words.first else { return }
        let box = Rect(x: 8, y: screen.size.height - 48, width: screen.size.width - 16, height: 40)
        screen.panel(.textbox, in: box) // Assets/Sprites/textbox.png, stretched
        // Wrapped first, so a word doesn't jump to the next line as it's typed.
        let typed = screen.wrap(page, width: box.width - 16).prefix(Int(letters))
        screen.text(String(typed), x: Double(box.x + 8), y: Double(box.y + 8))
        if letters == Double(page.count) { screen.text(">", x: Double(box.x + box.width - 10), y: Double(box.y + box.height - 10)) }
    }
}

/// Up, down, left or right, whichever `way` is most, up or down when it's as much one as the other.
func heading(_ way: Vector) -> Vector { abs(way.y) >= abs(way.x) ? [0, way.y < 0 ? -1 : 1] : [way.x < 0 ? -1 : 1, 0] }

/// Stands in the way, strolls to each of their spots in turn and back, around the hedge or through it once it's cut,
/// and talks when you press A in front of them: a page for each of their words. Both are lists in
/// Assets/Objects/villager.object that each villager placed in a map can change: spots are points chosen on the map.
/// Their sprite, hitbox and solidity are there too.
final class Villager: Entity, Placeable {
    lazy var words = object?.list("words", of: String.self) ?? []
    /// Where they go next, then after: their spots, and back where they were placed.
    lazy var spots = (object?.list("spots", of: Vector.self) ?? []) + [middle]
    var route: [Vector] = []
    var rest = 4.0 // seconds before they set off again
    var held = 0.0 // seconds someone's been in their way

    override func update(_ dt: Double) {
        if (scene as? Place)?.words.isEmpty == false || spots.count < 2 { // they stop to talk
            velocity = .zero
        } else if !route.isEmpty || rest <= 0 {
            if route.isEmpty { // off to the next spot, the way as it is now
                route = path(to: spots[0]) ?? []
                spots.append(spots.removeFirst())
                rest = 4
            }
            let from = position
            walk(dt, along: &route, speed: 30)
            held = position == from ? held + dt : 0
            if held > 1, let spot = route.last { (route, held) = (path(to: spot) ?? [], 0) } // around them
        } else {
            rest -= dt
        }
        let way = heading(velocity), looks = way.y < 0 ? "up" : way.y > 0 ? "down" : "side"
        sprite?.play(velocity == .zero ? "idle" : "walk-\(looks)")
        sprite?.flipped = velocity != .zero && way.x < 0
    }
}

/// Lightning striking: its bolt crackling down from the sky for a moment, its flash lighting everything past daylight
/// and throwing long shadows from the trunks, then fading; the place shakes the view and ripples the picture with it.
final class Strike: Entity {
    var age = 0.0

    override init() {
        super.init()
        hitbox = Rect(x: 0, y: 0, width: 2, height: 2)
        light = Light(radius: 220, color: 0xDDE4FF, brightness: 2.4, shadows: true)
    }

    override func update(_ dt: Double) {
        age += dt
        light?.brightness = age < 0.1 ? 2.4 : 2.4 * max(0, 1 - (age - 0.1) / 0.5) // a flash, then fading
        if age > 0.7 { scene?.remove(self) }
    }

    override func draw(_ screen: Screen) {
        guard age < 0.25 else { return }
        let crackle = Int(age * 24) // a new bolt every few frames
        screen.bolt(from: position + [Double(crackle % 3) * 9 - 24, -220], to: position + [1, 1], seed: crackle)
    }

    /// Its shock on the picture: `ripple.metal` spreading from where it struck, in the view's pixels.
    func shock(_ camera: Vector) -> Shader? {
        age < 0.7 ? Shader(.ripple, [middle.x - camera.x, middle.y - camera.y, age]) : nil
    }
}

/// A gloom: a swirl that turns, taking the light and the color from around it, growing for half a second, lasting three,
/// then fading.
final class Gloom: Entity {
    var age = 0.0

    override init() {
        super.init()
        hitbox = Rect(x: 0, y: 0, width: 2, height: 2)
        light = Light(radius: 45, color: 0xD9FFB3, brightness: 0, image: .swirl)
    }

    override func update(_ dt: Double) {
        age += dt
        let strength = min(age / 0.5, 1, max(0, 4 - age))
        light?.radius = 45 + 30 * strength
        light?.brightness = -1.3 * strength
        light?.gray = 0.9 * strength
        light?.angle += dt * 1.6
        if age > 4 { scene?.remove(self) }
    }
}

/// The house's fire, which lights it in the dark, flickering as flames do.
final class Fireplace: Entity, Placeable {
    override init() {
        super.init()
        light = Light(radius: 80, color: 0xFFA300, flicker: 0.1)
    }
}
