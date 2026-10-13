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

/// A map to walk around in: the village, or inside the house. Its objects, placed in the map editor and defined in
/// Assets/Objects, say what's where: trees, the house's front and the villager, doors with where they lead (`to`) and
/// where you come out (`at`), and where the game starts.
final class Place: Scene {
    let map: MapName
    let progress: Progress
    let player = Entity()
    var facing: Vector = [0, 1]
    var doors: [Tilemap.Object] = []
    /// What's being said, a page at a time, and how much of the first page is typed out.
    var words: [String] = []
    var letters = 0.0

    init(_ map: MapName, _ progress: Progress, at spot: ObjectName = .start, position: Vector? = nil) {
        (self.map, self.progress) = (map, progress)
        super.init()
        ySort = true // things draw by where their feet are
        follow = player
        background = 0x000000
        var tiles = Tilemap(map)
        for point in progress.cut[map.name] ?? [] { tiles.setTile(Tile.stump, at: point, layer: 0) }
        tilemap = tiles
        addObjects() // the trees and the house, solid at their base, and the villager
        doors = tiles.objects.filter { $0.name == .door }
        player.sprite = Sprite(.player)
        player.hitbox = Rect(x: 3, y: 10, width: 10, height: 6) // the feet, so the head can pass in front of things
        add(player, at: position ?? tiles.objects(named: spot).first ?? .zero)
        Music.play(SoundName(map.name), fade: 0.5) // each place's music is named after its map
    }

    override func update(_ dt: Double) {
        super.update(dt)
        guard let page = words.first else { return walk(dt) }
        letters = min(letters + dt * 40, Double(page.count)) // 40 letters a second
        if Input.pressed(.a) || Input.pressed(.pointer) { // a click or tap too: the rest of the page, then the next one
            if letters < Double(page.count) { letters = Double(page.count) } else { (words, letters) = (Array(words.dropFirst()), 0) }
        }
    }

    /// The D-pad walks; A talks to whoever's in front, X cuts a bush there, and doors lead on.
    func walk(_ dt: Double) {
        func axis(_ back: Button, _ on: Button) -> Double { (Input.held(on) ? 1 : 0) - (Input.held(back) ? 1 : 0) }
        let direction: Vector = [axis(.left, .right), axis(.up, .down)]
        player.velocity = direction * 60
        player.move(dt)
        let (size, feet) = (tilemap!.size, player.hitbox) // the map's edges are walls
        player.position.x = min(max(player.position.x, Double(-feet.x)), Double(size.width - feet.x - feet.width))
        player.position.y = min(max(player.position.y, Double(-feet.y)), Double(size.height - feet.y - feet.height))
        if direction.y != 0 { facing = [0, direction.y] } else if direction.x != 0 { facing = [direction.x, 0] }
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
        if let door = doors.first(where: { player.overlaps($0.box) }), let to = door.map("to") {
            let next = Place(to, progress, at: door.object("at") ?? .start)
            if next.map == .village { // coming out of the house saves the game
                progress.place = next.player.position
                Save.write(progress, to: "progress")
            }
            Scene.fade(to: next)
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

/// Stands in the way, and talks when you press A in front of them: a page for each of their words, a list in
/// Assets/Objects/villager.object that each villager placed in a map can change. Their sprite, hitbox and solidity are
/// there too.
final class Villager: Entity, Placeable {
    lazy var words = object?.list("words", of: String.self) ?? []
}
