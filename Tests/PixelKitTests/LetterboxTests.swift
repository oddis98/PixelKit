import Metal
import Testing
@testable import PixelKit

@Test func canvasScalesByWholeNumbersAndCenters() {
    // 1000x600 fits 320x180 three times (960x540), leaving 20px / 30px bars.
    let v = letterbox(Size(320, 180), in: CGSize(width: 1000, height: 600))
    #expect([v.originX, v.originY, v.width, v.height] == [20, 30, 960, 540])

    // Height limits the scale here: 2x, not 4x.
    let tall = letterbox(Size(320, 180), in: CGSize(width: 1280, height: 400))
    #expect([tall.width, tall.height] == [640, 360])

    // Never below 1x.
    let tiny = letterbox(Size(320, 180), in: CGSize(width: 100, height: 100))
    #expect([tiny.width, tiny.height] == [320, 180])
}
