import PixelKit

@main struct Platformer: Game {
    func start() -> Scene { Level() }
}

/// # grass, = dirt, B block, o coin, P player start. Each character is an 8x8 tile.
let map = [
    "................................................................",
    "................................................................",
    "................................................................",
    "................................................................",
    "................................................................",
    "................................................................",
    "................................................................",
    ".................................o.o............................",
    "................................................................",
    "................................BBBBB...........................",
    ".......................o.o.o....................................",
    "................................................................",
    "......................BBBBBB....................................",
    ".............o.o................................................",
    "..................................................oo............",
    "............BBBBBB..............................................",
    "..........................................oo......BB............",
    ".....................oo...........................BB............",
    "..P.....BB....................BB..................BB....o.o.o...",
    "........BB....................BB..................BB............",
    "####################....################......##################",
    "====================....================......==================",
    "====================....================......==================",
]

final class Level: Scene {
    let player = Player()
    var coins = 0

    override init() {
        super.init()
        background = 0x29ADFF
        tilemap = Tilemap("tiles", tileSize: 8, rows: map, legend: ["#": 0, "=": 1, "B": 2])
        for (row, line) in map.enumerated() {
            for (column, character) in line.enumerated() {
                let position = Vector(Double(column * 8), Double(row * 8))
                if character == "P" { add(player, at: position) }
                if character == "o" { add(Coin(), at: position) }
            }
        }
    }

    override func update(_ dt: Double) {
        super.update(dt)
        let size = tilemap!.size
        player.position.x = min(max(player.position.x, 0), Double(size.width - 16)) // the level's sides are walls
        if player.position.y > Double(size.height) { Scene.current = Level() } // fell in a pit: start over
        camera = [min(max(player.position.x - 152, 0), Double(size.width - 320)), Double(size.height - 180)]
    }

    override func draw(_ screen: Screen) {
        super.draw(screen)
        for i in 0..<coins { screen.draw(Coin.icon, x: Double(4 + i * 9), y: 4) }
    }
}

final class Player: Entity {
    static let idle = Animation(frames: [0, 1], fps: 2)
    static let walk = Animation(frames: [0, 1], fps: 8)
    static let jump = Animation(frames: [2], fps: 0)

    override init() {
        super.init()
        sprite = Sprite("slime", frameSize: Size(16, 16), animation: Self.idle)
        hitbox = Rect(x: 1, y: 3, width: 14, height: 12)
    }

    override func update(_ dt: Double) {
        let direction = (Input.held(.right) ? 1.0 : 0) - (Input.held(.left) ? 1 : 0)
        velocity.x = direction * 90
        velocity.y = min(velocity.y + 600 * dt, 300) // gravity, up to a top falling speed
        if Input.pressed(.a), onGround {
            velocity.y = -230
            Sound.play("jump")
        }
        move(dt)
        if direction != 0 { sprite?.flipped = direction < 0 }
        sprite?.animation = !onGround ? Self.jump : direction != 0 ? Self.walk : Self.idle
    }
}

final class Coin: Entity {
    static let icon = Sprite("coin", frameSize: Size(8, 8))

    override init() {
        super.init()
        sprite = Sprite("coin", frameSize: Size(8, 8), animation: Animation(frames: [0, 1, 2, 1], fps: 8))
        hitbox = Rect(x: 1, y: 1, width: 6, height: 6)
    }

    override func update(_ dt: Double) {
        guard let level = scene as? Level, overlaps(level.player) else { return }
        level.coins += 1
        level.remove(self)
        Sound.play("coin")
    }
}
