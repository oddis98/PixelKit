import ImageIO
import Metal
import PixelKitProtocol
import Testing
@testable import PixelKit

@Test func textIsSpacedByEachGlyphsWidthWithDigitsAllAsWide() {
    // A, B and ? fill 3 of their 4 columns, "." only its second, and the digit 1 its second while 2 fills 3.
    let font = Font(glyph: Size(4, 6), characters: "AB?.12", columns: [0...2, 0...2, 0...2, 1...1, 1...1, 0...2])
    // "b" draws as B, "!" isn't in the font so "?" stands in, and the space takes up half a frame but draws nothing.
    #expect(font.layout("Ab\n! A").map { [$0.index, $0.x, $0.y] } == [[0, 0, 0], [1, 4, 0], [2, 0, 6], [0, 6, 6]])
    #expect(font.size(of: "Ab\n! A") == Size(10, 12))
    // "." takes up 1 column and its space, its frame starting a column left so its pixel lands right after A's space.
    #expect(font.layout("A.B").map(\.x) == [0, 3, 6])
    #expect(font.layout("A.BA").last?.x == font.size(of: "A.B").width) // the size ends where the next glyph would go
    // Digits take up the widest one's 3 columns, so "1" is centered in them, and "12" is as wide as "22".
    #expect(font.layout("12").map(\.x) == [0, 4] && font.size(of: "12") == font.size(of: "22"))
    #expect(Font(glyph: Size(4, 6), characters: "AB", columns: [0...2, 0...2]).layout("!").isEmpty) // no "?" either: nothing
    #expect(Font.builtIn.index(of: "a") == Font.builtIn.index(of: "A") && Font.builtIn.index(of: "é") == Font.builtIn.index(of: "?"))
}

@Test func textWrapsAtSpacesAndBreaksWordsWiderThanTheWidth() {
    let font = Font.builtIn // letters advance 4 pixels, the space 2
    #expect(font.lines("AB CD EF", width: 18) == ["AB CD", "EF"]) // "AB CD" is 18 wide
    #expect(font.lines("AB CD EF", width: 17) == ["AB", "CD", "EF"])
    #expect(font.lines("ABCDEFGH I", width: 14) == ["ABC", "DEF", "GH I"]) // too wide for a line: broken where it stops fitting
    #expect(font.lines("AB\n\nCD EF", width: 100) == ["AB", "", "CD EF"] && font.lines("A", width: 1) == ["A"])
    #expect(font.size(of: "AB CD EF", width: 18) == Size(18, 12) && font.size(of: "AB CD EF") == Size(28, 6))
    #expect(font.layout("AB CD EF", width: 18).last.map { [$0.x, $0.y] } == [4, 6]) // F, second on the second line
}

@MainActor @Test func glyphsAreMeasuredInTheBuiltInArtAndInFontImagesAgainWhenTheyChange() throws {
    let builtIn = Font.builtIn
    #expect(builtIn.columns[builtIn.index(of: ".")!] == 1...1 && builtIn.columns[builtIn.index(of: "A")!] == 0...2)
    #expect(builtIn.columns[0] == nil && builtIn.digits == 3) // the space
    #expect(builtIn.size(of: "COINS 3/10").width == 38) // letters and digits as before, the space 2 narrower

    let assets = FileManager.default.temporaryDirectory.appending(path: "font-\(UUID())/Assets")
    try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
    FileManager.default.changeCurrentDirectoryPath(assets.deletingLastPathComponent().path) // games load Assets/ relative to here
    try SheetFile(frameWidth: 4, frameHeight: 6, characters: "AB.C").write(to: assets.appending(path: "tiny.json"))
    // Two rows of two 4x6 frames: A, an empty B, then "." and C below.
    func save(_ rows: [String], secondsLater: Double) throws {
        let context = try #require(CGContext(data: nil, width: 8, height: 12, bitsPerComponent: 8, bytesPerRow: 32,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let pixels = try #require(context.data?.assumingMemoryBound(to: UInt32.self))
        for (y, row) in rows.enumerated() { for (x, pixel) in row.enumerated() where pixel == "#" { pixels[y * 8 + x] = 0xFFFF_FFFF } }
        let file = assets.appending(path: "tiny.png")
        let png = try #require(CGImageDestinationCreateWithURL(file as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(png, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(png))
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: secondsLater)], ofItemAtPath: file.path)
    }
    let a = ["###.....", "#.#.....", "###.....", "#.#.....", "#.#.....", "........"]
    try save(a + [".#......", "......##"], secondsLater: 0)
    let screen = Screen(size: Size(8, 8), device: try #require(MTLCreateSystemDefaultDevice()), format: .bgra8Unorm)
    #expect(screen.font("tiny").1.columns == [0...2, nil, 1...1, 2...3])
    try save(a.map { $0.prefix(7) + "#" } + [".#......", "......##"], secondsLater: 10) // a B of one column, at the right
    screen.reloadChangedAssets()
    #expect(screen.font("tiny").1.columns == [0...2, 3...3, 1...1, 2...3])
}

@MainActor @Test func textAndSpritesDrawTinted() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let screen = Screen(size: Size(8, 7), device: device, format: .bgra8Unorm)
    let white = try #require(device.makeTexture(descriptor: .texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 2, height: 2, mipmapped: false)))
    white.replace(region: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0, withBytes: [UInt32](repeating: 0xFFFF_FFFF, count: 4), bytesPerRow: 8)
    screen.textures["dot"] = white // a 2x2 sprite, one frame since there's no dot.json
    let commands = try #require(device.makeCommandQueue()?.makeCommandBuffer())
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = screen.canvas
    pass.colorAttachments[0].loadAction = .clear // to black
    screen.begin(commands, pass)
    screen.text("A", x: 1, y: 1, color: 0xFF0000)
    var sprite = Sprite("dot")
    sprite.color = 0x00FF00
    screen.draw(sprite, x: 5, y: 1)
    screen.end()
    let pixels = try #require(device.makeBuffer(length: 8 * 7 * 4, options: .storageModeShared))
    let blit = try #require(commands.makeBlitCommandEncoder())
    blit.copy(from: screen.canvas, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(), sourceSize: MTLSize(width: 8, height: 7, depth: 1),
              to: pixels, destinationOffset: 0, destinationBytesPerRow: 8 * 4, destinationBytesPerImage: 8 * 7 * 4)
    blit.endEncoding()
    commands.commit()
    commands.waitUntilCompleted()
    let bgra = pixels.contents().bindMemory(to: UInt32.self, capacity: 8 * 7)
    let colors = (0..<7).map { y in String((0..<8).map { [0xFFFF_0000: "#", 0xFF00_FF00: "o"][bgra[y * 8 + $0]] ?? "." }) }
    #expect(colors == ["........", "..#..oo.", ".#.#.oo.", ".###....", ".#.#....", ".#.#....", "........"])
}
