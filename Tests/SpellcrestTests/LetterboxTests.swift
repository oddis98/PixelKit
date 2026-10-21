import Metal
import Testing
@testable import Spellcrest

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

@Test func onAPhoneTheCanvasReachesTheEdgesAtTheTopInPortrait() {
    // Portrait: the whole width, at the top, leaving the bottom to the touch controls.
    let portrait = fit(Size(320, 180), in: CGSize(width: 1206, height: 2622))
    #expect([portrait.originX, portrait.originY, portrait.width] == [0, 0, 1206])
    #expect(abs(portrait.height - 678.375) < 0.001)
    // Landscape: the whole height, centered.
    let landscape = fit(Size(320, 180), in: CGSize(width: 2622, height: 1206))
    #expect(abs(landscape.width - 2144) < 0.001 && landscape.height == 1206 && landscape.originY == 0 && abs(landscape.originX - 239) < 0.001)
}

@Test func pointsInTheWindowAndOnAPhoneAreCanvasPixels() {
    let canvas = Size(320, 180)
    let window = letterbox(canvas, in: CGSize(width: 1000, height: 600)) // 3x, from (20, 30)
    #expect(pixel(at: CGPoint(x: 20, y: 30), in: window, canvas: canvas) == [0, 0])
    #expect(pixel(at: CGPoint(x: 979.9, y: 569.9), in: window, canvas: canvas) == [319, 179])
    #expect(pixel(at: CGPoint(x: 19, y: 30), in: window, canvas: canvas) == [-1, 0]) // the letterbox is off the canvas
    let phone = fit(canvas, in: CGSize(width: 402, height: 874)) // portrait, at the top, 1.25625 points a pixel
    #expect(pixel(at: CGPoint(x: 201, y: 100), in: phone, canvas: canvas) == [160, 79])
    #expect(pixel(at: CGPoint(x: 201, y: 500), in: phone, canvas: canvas).y > 179) // below the game, where the controls are
}
