import Metal

public extension Screen {
    /// Draws `text` with its top-left corner at (x, y), snapped to whole pixels; `\n` starts a new line.
    /// `font` is an image cut into glyphs, `Assets/<font>.png`, whose `.json` lists the `characters` they show (draw
    /// one in the pixel editor); without it, a built-in 3x5 font draws. `color` (0xRRGGBB) tints the glyphs, and white
    /// leaves them as they are.
    func text(_ text: String, x: Double, y: Double, font: String? = nil, color: UInt32 = 0xFFFFFF) {
        let (texture, font) = self.font(font)
        let tint = SIMD4<Float>(Float(color >> 16 & 0xFF), Float(color >> 8 & 0xFF), Float(color & 0xFF), 255) / 255
        for glyph in font.layout(text) {
            quad(texture, x: x + Double(glyph.x), y: y + Double(glyph.y), source: region(glyph.index, font.glyph, in: texture), color: tint)
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
        let glyphs = texture.width / sheet.frameWidth * (texture.height / sheet.frameHeight) // more characters would draw past the image
        return (texture, Font(glyph: Size(sheet.frameWidth, sheet.frameHeight), characters: String(characters.prefix(glyphs))))
    }
}

/// How a font's image is cut up: into glyphs of one size, which show `characters` in order. A glyph's frame includes
/// the space after it, so text advances one frame per character.
struct Font {
    let glyph: Size
    let characters: [String: Int]

    init(glyph: Size, characters: String) {
        self.glyph = glyph
        self.characters = Dictionary(characters.enumerated().map { (String($1), $0) }) { first, _ in first }
    }

    /// The glyph that draws `character`: its own, else the same letter in the other case, else "?". Spaces, and
    /// characters with no glyph in a font without "?", draw nothing but still take up their place.
    func index(of character: Character) -> Int? {
        if let index = characters[String(character)] ?? characters[character.uppercased()] ?? characters[character.lowercased()] {
            return index
        }
        return character.isWhitespace ? nil : characters["?"]
    }

    /// Each glyph of `text` and where it goes, relative to the text's top-left corner.
    func layout(_ text: String) -> [(index: Int, x: Int, y: Int)] {
        lines(text).enumerated().flatMap { row, line in
            line.enumerated().compactMap { column, character in
                index(of: character).map { ($0, column * glyph.width, row * glyph.height) }
            }
        }
    }

    func size(of text: String) -> Size {
        let lines = lines(text)
        return Size((lines.map(\.count).max() ?? 0) * glyph.width, lines.count * glyph.height)
    }

    private func lines(_ text: String) -> [Substring] { text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) }
}

extension Font {
    /// ASCII from space to "_": digits, capitals and punctuation. Lowercase letters draw as capitals.
    static let builtIn = Font(glyph: Size(4, 6), characters: String((32..<96).map { Character(UnicodeScalar(UInt8($0))) }))

    /// The built-in font's glyphs, white on clear, from `builtInArt`.
    static func builtInTexture(_ device: MTLDevice) -> MTLTexture {
        let (width, height) = (64, 24)
        let rows = builtInArt.split(separator: "\n", omittingEmptySubsequences: false).map(Array.init)
        let pixels: [UInt32] = (0..<height).flatMap { y in
            (0..<width).map { x in y < rows.count && x < rows[y].count && rows[y][x] == "#" ? 0xFFFF_FFFF : 0 }
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        let texture = device.makeTexture(descriptor: descriptor)!
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: pixels, bytesPerRow: width * 4)
        return texture
    }

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
