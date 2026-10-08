import PixelKit

@main struct Hello: Game {
    func draw(_ screen: Screen) {
        screen.draw("hero", x: 152, y: 82) // 16x16 sprite, centered on the 320x180 canvas
    }
}
