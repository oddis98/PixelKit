import CoreGraphics
import Testing
@testable import PixelKit

@Test func touchControlsHoldTheButtonsUnderEachFinger() {
    let layout = TouchLayout(size: CGSize(width: 852, height: 393), left: 59, right: 59, bottom: 21) // an iPhone, landscape
    let (pad, r) = (layout.dpad, TouchLayout.pad)
    #expect(layout.buttons(at: CGPoint(x: pad.x + r * 0.8, y: pad.y + 3)) == [.right])
    #expect(layout.buttons(at: CGPoint(x: pad.x - r * 0.6, y: pad.y - r * 0.6)) == [.left, .up]) // between two: both
    #expect(layout.buttons(at: pad).isEmpty) // the middle holds nothing
    #expect(layout.buttons(at: layout.a) == [.a] && layout.buttons(at: layout.b) == [.b])
    #expect(layout.buttons(at: CGPoint(x: 426, y: 100)).isEmpty) // the game itself
    #expect(pad.x - r > 59 && layout.a.x + TouchLayout.button < 852 - 59) // clear of the notch and the corners
}
