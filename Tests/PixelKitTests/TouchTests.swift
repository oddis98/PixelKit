import CoreGraphics
import Testing
@testable import PixelKit

@Test func touchControlsHoldTheButtonsUnderEachFinger() {
    let layout = TouchLayout(size: CGSize(width: 852, height: 393), left: 59, right: 59, bottom: 21) // an iPhone, landscape
    let (pad, r) = (layout.dpad, TouchLayout.pad)
    #expect(layout.buttons(at: CGPoint(x: pad.x + r * 0.8, y: pad.y + 3)) == [.right])
    #expect(layout.buttons(at: CGPoint(x: pad.x - r * 0.6, y: pad.y - r * 0.6)) == [.left, .up]) // between two: both
    #expect(layout.buttons(at: pad).isEmpty) // the middle holds nothing
    #expect(layout.buttons(at: layout.a) == [.a] && layout.buttons(at: layout.b) == [.b] && layout.buttons(at: layout.x) == [.x] && layout.buttons(at: layout.y) == [.y])
    #expect(layout.x.y < layout.a.y && layout.a.y == layout.y.y && layout.y.y < layout.b.y && layout.y.x < layout.x.x && layout.x.x < layout.a.x) // a diamond
    #expect(layout.buttons(at: CGPoint(x: (layout.a.x + layout.b.x) / 2, y: (layout.a.y + layout.b.y) / 2)) == [.a, .b]) // one thumb on two
    #expect(layout.buttons(at: CGPoint(x: 426, y: 100)).isEmpty) // the game itself
    #expect(pad.x - r > 59 && layout.a.x + TouchLayout.button < 852 - 59) // clear of the notch and the corners
}

@Test func inPortraitTheTouchControlsAreBelowTheGame() {
    let layout = TouchLayout(size: CGSize(width: 402, height: 874), left: 0, right: 0, bottom: 34) // an iPhone, portrait
    let game = 402 * 180 / 320.0 // the canvas's height at the top
    #expect(layout.dpad.y - TouchLayout.pad > game && [layout.a, layout.b, layout.x, layout.y].allSatisfy { $0.y - TouchLayout.button > game })
}

@Test func theControlsKeepTheFingersThatLandOnThemAndTheGameGetsTheRest() {
    let layout = TouchLayout(size: CGSize(width: 852, height: 393), left: 59, right: 59, bottom: 21) // an iPhone, landscape
    #expect(layout.covers(layout.dpad) && layout.covers(layout.middle)) // the D-pad's middle and the diamond's, which hold nothing
    #expect([layout.a, layout.b, layout.x, layout.y].allSatisfy(layout.covers))
    #expect(!layout.covers(CGPoint(x: 426, y: 100)) && !layout.covers(CGPoint(x: 426, y: 380))) // the game, up top and between them
}
