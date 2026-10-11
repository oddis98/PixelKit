import Metal
import Testing
@testable import PixelKit

@Test func textFindsGlyphsStartsNewLinesAndMeasures() {
    let font = Font(glyph: Size(4, 6), characters: "AB?")
    // "b" draws as B, "!" isn't in the font so "?" stands in, and the space takes its place but draws nothing.
    #expect(font.layout("Ab\n! A").map { [$0.index, $0.x, $0.y] } == [[0, 0, 0], [1, 4, 0], [2, 0, 6], [0, 8, 6]])
    #expect(font.size(of: "Ab\n! A") == Size(12, 12))
    #expect(Font(glyph: Size(4, 6), characters: "AB").layout("!").isEmpty) // no "?" either: nothing
    #expect(Font.builtIn.index(of: "a") == Font.builtIn.index(of: "A") && Font.builtIn.index(of: "é") == Font.builtIn.index(of: "?"))
}

@MainActor @Test func textDrawsTintedGlyphsOfTheBuiltInFont() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let screen = Screen(size: Size(5, 7), device: device, format: .bgra8Unorm)
    let commands = try #require(device.makeCommandQueue()?.makeCommandBuffer())
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = screen.canvas
    pass.colorAttachments[0].loadAction = .clear // to black
    screen.begin(commands, pass)
    screen.text("A", x: 1, y: 1, color: 0xFF0000)
    screen.end()
    let pixels = try #require(device.makeBuffer(length: 5 * 7 * 4, options: .storageModeShared))
    let blit = try #require(commands.makeBlitCommandEncoder())
    blit.copy(from: screen.canvas, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(), sourceSize: MTLSize(width: 5, height: 7, depth: 1),
              to: pixels, destinationOffset: 0, destinationBytesPerRow: 5 * 4, destinationBytesPerImage: 5 * 7 * 4)
    blit.endEncoding()
    commands.commit()
    commands.waitUntilCompleted()
    let bgra = pixels.contents().bindMemory(to: UInt32.self, capacity: 5 * 7)
    let red = (0..<7).map { y in String((0..<5).map { bgra[y * 5 + $0] == 0xFFFF_0000 ? "#" : "." }) }
    #expect(red == [".....", "..#..", ".#.#.", ".###.", ".#.#.", ".#.#.", "....."])
}
