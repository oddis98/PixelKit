import ImageIO
import Metal

public extension Screen {
    /// Draws `text` with its top-left corner at (x, y), snapped to whole pixels; `\n` starts a new line.
    /// `font` is an image cut into glyphs, `Assets/<font>.png`, whose `.json` lists the `characters` they show (draw
    /// one in the pixel editor); without it, a built-in 3x5 font draws. Each glyph takes up the columns it has pixels
    /// in, then 1 pixel of space, and digits all take up the widest one's, so numbers don't shift as they count.
    /// `color` (0xRRGGBB) tints the glyphs, and white leaves them as they are.
    func text(_ text: String, x: Double, y: Double, font: String? = nil, color: UInt32 = 0xFFFFFF) {
        let (texture, font) = self.font(font)
        for glyph in font.layout(text) {
            quad(texture, x: x + Double(glyph.x), y: y + Double(glyph.y), source: region(glyph.index, font.glyph, in: texture), color: color)
        }
    }

    /// The size of `text` in pixels, for example to center it: `x: Double(160 - screen.textSize(title).width / 2)`.
    func textSize(_ text: String, font: String? = nil) -> Size { self.font(font).1.size(of: text) }
}

extension Screen {
    /// A font's image and how it's cut into glyphs.
    func font(_ name: String?) -> (MTLTexture, Font) {
        guard let name else { return (builtInFont, .builtIn) }
        let texture = texture(name)
        guard let sheet = sheet(name), let characters = sheet.characters else {
            if warned.insert("\(name) font").inserted { print("PixelKit: \(name).json has no characters, so the built-in font draws instead") }
            return (builtInFont, .builtIn)
        }
        if let font = fonts[name] { return (texture, font) }
        // Measured in the file, since a texture may not be readable from the CPU (Intel Macs can't share textures).
        guard let image = opaquePixels(assetURL("\(name).png")) else { return (builtInFont, .builtIn) } // half-written: next frame
        let glyph = Size(sheet.frameWidth, sheet.frameHeight)
        let font = Font(glyph: glyph, characters: characters, columns: Font.measure(image.pixels, width: image.width, glyph: glyph))
        fonts[name] = font
        return (texture, font)
    }
}

/// Which pixels of a PNG show (alpha above 0), row by row, and how wide it is; nil if it can't be read.
func opaquePixels(_ url: URL) -> (width: Int, pixels: [Bool])? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue),
          let data = context.data else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return (image.width, UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: image.width * image.height).map { $0 > 0 })
}

/// How a font's image is cut up: into frames of one size, which show `characters` in order. A glyph takes up the
/// columns it has pixels in, then 1 pixel of space; one without pixels, like the space, takes up half a frame.
struct Font {
    let glyph: Size
    let characters: [String: Int]
    let columns: [ClosedRange<Int>?] // each frame's columns with pixels in them, from `measure`; nil for none
    let digits: Int // the widest digit's width, which every digit takes up so numbers don't shift as they change

    /// Characters past the last frame are left out.
    init(glyph: Size, characters: String, columns: [ClosedRange<Int>?]) {
        let characters = Dictionary(characters.prefix(columns.count).enumerated().map { (String($1), $0) }) { first, _ in first }
        (self.glyph, self.characters, self.columns) = (glyph, characters, columns)
        digits = (0...9).compactMap { characters[String($0)].flatMap { columns[$0]?.count } }.max() ?? 0
    }

    /// Each frame's columns with a pixel in `opaque`: an image `width` pixels wide, row by row.
    static func measure(_ opaque: [Bool], width: Int, glyph: Size) -> [ClosedRange<Int>?] {
        let (across, down) = (width / glyph.width, opaque.count / width / glyph.height)
        return (0..<across * down).map { frame in
            let (left, top) = (frame % across * glyph.width, frame / across * glyph.height)
            let filled = (0..<glyph.width).filter { x in (top..<top + glyph.height).contains { opaque[$0 * width + left + x] } }
            return filled.first.map { $0...filled.last! }
        }
    }

    /// The glyph that draws `character`: its own, else the same letter in the other case, else "?". Spaces, and
    /// characters with no glyph in a font without "?", draw nothing but still take up space.
    func index(of character: Character) -> Int? {
        if let index = characters[String(character)] ?? characters[character.uppercased()] ?? characters[character.lowercased()] {
            return index
        }
        return character.isWhitespace ? nil : characters["?"]
    }

    /// Each glyph of `text` and where its frame goes, relative to the text's top-left corner.
    func layout(_ text: String) -> [(index: Int, x: Int, y: Int)] {
        lines(text).enumerated().flatMap { row, line in
            var x = 0
            return line.compactMap { character -> (index: Int, x: Int, y: Int)? in
                let (drawn, advance) = place(character)
                defer { x += advance }
                return drawn.map { ($0.index, x + $0.x, row * glyph.height) }
            }
        }
    }

    func size(of text: String) -> Size {
        let lines = lines(text)
        return Size(lines.map { $0.reduce(0) { $0 + place($1).advance } }.max() ?? 0, lines.count * glyph.height)
    }

    /// The glyph that draws `character` and where its frame goes from the pen, and how far the pen moves on.
    /// The frame starts left of the pen by its empty columns; a digit's is centered in the widest digit's width.
    private func place(_ character: Character) -> (glyph: (index: Int, x: Int)?, advance: Int) {
        guard let index = index(of: character), let filled = columns[index] else { return (nil, (glyph.width + 1) / 2) }
        let width = ("0"..."9").contains(character) ? max(digits, filled.count) : filled.count
        return ((index, (width - filled.count) / 2 - filled.lowerBound), width + 1)
    }

    private func lines(_ text: String) -> [Substring] { text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) }
}

extension Font {
    /// ASCII from space to "_": digits, capitals and punctuation. Lowercase letters draw as capitals.
    static let builtIn = Font(glyph: Size(4, 6), characters: String((32..<96).map { Character(UnicodeScalar(UInt8($0))) }),
                              columns: measure(builtInPixels, width: 64, glyph: Size(4, 6)))

    /// The built-in font's glyphs, white on clear.
    static func builtInTexture(_ device: MTLDevice) -> MTLTexture {
        let (width, height) = (64, 24)
        let pixels: [UInt32] = builtInPixels.map { $0 ? 0xFFFF_FFFF : 0 }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        let texture = device.makeTexture(descriptor: descriptor)!
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: pixels, bytesPerRow: width * 4)
        return texture
    }

    /// `builtInArt` as 64x24 pixels, row by row: true where there's a "#".
    static let builtInPixels: [Bool] = {
        let rows = builtInArt.split(separator: "\n", omittingEmptySubsequences: false).map(Array.init)
        return (0..<24).flatMap { y in (0..<64).map { x in y < rows.count && x < rows[y].count && rows[y][x] == "#" } }
    }()

    /// One line per pixel row of a 64x24 image: 16 glyphs to a row in 4x6 frames, in `builtIn`'s order. "#" is a pixel.
    /// The blank lines are the space between lines of text.
    static let builtInArt = """
    ... .#. #.# #.# .## #.# .#. .#. ..# #.. ... ... ... ... ... ..#
    ... .#. #.# ### ##. ..# #.# .#. .#. .#. #.# .#. ... ... ... ..#
    ... .#. ... #.# .#. .#. .#. ... .#. .#. .#. ### ... ### ... .#.
    ... ... ... ### .## #.. #.# ... .#. .#. #.# .#. .#. ... ... #..
    ... .#. ... #.# ##. #.# .## ... ..# #.. ... ... #.. ... .#. #..

    ### .#. ##. ##. #.# ### .## ### ### ### ... ... ..# ... #.. ##.
    #.# ##. ..# ..# #.# #.. #.. ..# #.# #.# .#. .#. .#. ### .#. ..#
    #.# .#. .#. .#. ### ##. ### .#. ### ### ... ... #.. ... ..# .#.
    #.# .#. #.. ..# ..# ..# #.# .#. #.# ..# .#. .#. .#. ### .#. ...
    ### ### ### ##. ..# ##. ### .#. ### ##. ... #.. ..# ... #.. .#.

    .#. .#. ##. .## ##. ### ### .## #.# ### ..# #.# #.. #.# ##. .#.
    #.# #.# #.# #.. #.# #.. #.. #.. #.# .#. ..# #.# #.. ### #.# #.#
    ### ### ##. #.. #.# ##. ##. #.# ### .#. ..# ##. #.. ### #.# #.#
    #.. #.# #.# #.. #.# #.. #.. #.# #.# .#. #.# #.# #.. #.# #.# #.#
    .## #.# ##. .## ##. ### #.. .## #.# ### .#. #.# ### #.# #.# .#.

    ##. .#. ##. .## ### #.# #.# #.# #.# #.# ### ##. #.. .## .#. ...
    #.# #.# #.# #.. .#. #.# #.# #.# #.# #.# ..# #.. #.. ..# #.# ...
    ##. #.# ##. .#. .#. #.# #.# ### .#. .#. .#. #.. .#. ..# ... ...
    #.. ##. #.# ..# .#. #.# #.# ### #.# .#. #.. #.. ..# ..# ... ...
    #.. .## #.# ##. .#. ### .#. #.# #.# .#. ### ##. ..# .## ... ###
    """
}
