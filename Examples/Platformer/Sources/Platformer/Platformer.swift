import PixelKit

@main struct Platformer: Game {
    func start() -> Scene { Level() }
}

final class Level: Scene {
    let player = Player()
    var coins = 0
    var total = 0

    override init() {
        super.init()
        background = 0x29ADFF
        // Made in the tilemap editor. Tiles 3 and 4 only mark where coins and the player go.
        var map = Tilemap("level1")
        for position in map.removeTiles(4) { add(player, at: position) }
        for position in map.removeTiles(3) {
            add(Coin(), at: position)
            total += 1
        }
        tilemap = map
        Music.play("theme") // already on when the level restarts, so it keeps going
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
        let score = "COINS \(coins)/\(total)"
        screen.text(score, x: 5, y: 5, color: 0x1D2B53) // a shadow, so the text stands out against the sky
        screen.text(score, x: 4, y: 4)
    }
}

final class Player: Entity {
    override init() {
        super.init()
        sprite = Sprite("slime") // frames and animations come from Assets/slime.json
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
        sprite?.play(!onGround ? "jump" : direction != 0 ? "walk" : "idle")
    }
}

final class Coin: Entity {
    override init() {
        super.init()
        sprite = Sprite("coin")
        sprite?.play("spin")
        hitbox = Rect(x: 1, y: 1, width: 6, height: 6)
    }

    override func update(_ dt: Double) {
        guard let level = scene as? Level, overlaps(level.player) else { return }
        level.coins += 1
        level.remove(self)
        Sound.play("coin")
    }
}
