import ImageIO
import MetalKit
import PixelKitProtocol
import Synchronization

/// The pixel canvas your game draws on. (0, 0) is the top-left pixel.
@MainActor public final class Screen {
    /// The canvas's size in pixels, the game's `resolution`: for laying out a HUD.
    public let size: Size
    let device: MTLDevice
    let pipeline: MTLRenderPipelineState // sprites, blended by their alpha
    let glow: MTLRenderPipelineState // lights, added up in the light map
    let multiply: MTLRenderPipelineState // the light map over the world
    let canvas: MTLTexture
    let canvasDescriptor: MTLTextureDescriptor
    /// What lights add up in, the canvas's size, made the first time a scene is dark.
    lazy var lightMap = device.makeTexture(descriptor: canvasDescriptor)!
    /// The last frame before a dissolve, which it draws over the next scene.
    lazy var snapshot = device.makeTexture(descriptor: canvasDescriptor)!
    let loader: MTKTextureLoader
    var textures: [String: MTLTexture] = [:]
    var sheets: [String: SheetFile?] = [:] // nil: the image has no .json, so it's a single frame
    var fonts: [String: Font] = [:] // image fonts, measured on first use
    var modified: [String: Date?] = [:] // each loaded file's modification date, to spot edits
    var warned: Set<String> = []
    var encoder: MTLRenderCommandEncoder!
    var commands: MTLCommandBuffer!
    var pass: MTLRenderPassDescriptor! // the canvas's, which a dark scene's light map interrupts
    // Queued quads, all using `batchTexture`, three for each corner: x, y, u, v; the tint r, g, b, a; and the flash and
    // how much of a dissolve's pattern to keep.
    var vertices: [SIMD4<Float>] = []
    var batchTexture: MTLTexture?
    /// The built-in font's glyphs, made on first use.
    lazy var builtInFont = Font.builtInTexture(device)
    /// One white pixel, which `fill` stretches and tints.
    lazy var white: MTLTexture = {
        let texture = device.makeTexture(descriptor: .texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false))!
        texture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: [UInt32.max], bytesPerRow: 4)
        return texture
    }()
    /// Subtracted from every position; the scene sets it to its camera.
    var offset = Vector.zero

    init(size: Size, device: MTLDevice, format: MTLPixelFormat) {
        self.size = size
        self.device = device
        loader = MTKTextureLoader(device: device)

        let library = try! device.makeLibrary(source: shaders, options: nil)
        func state(_ fragment: String, rgb: (MTLBlendFactor, MTLBlendFactor), alpha: (MTLBlendFactor, MTLBlendFactor)) -> MTLRenderPipelineState {
            let pipeline = MTLRenderPipelineDescriptor()
            pipeline.vertexFunction = library.makeFunction(name: "spriteVertex")
            pipeline.fragmentFunction = library.makeFunction(name: fragment)
            let color = pipeline.colorAttachments[0]!
            color.pixelFormat = format
            color.isBlendingEnabled = true
            (color.sourceRGBBlendFactor, color.destinationRGBBlendFactor) = rgb
            (color.sourceAlphaBlendFactor, color.destinationAlphaBlendFactor) = alpha
            return try! device.makeRenderPipelineState(descriptor: pipeline)
        }
        pipeline = state("spriteFragment", rgb: (.sourceAlpha, .oneMinusSourceAlpha), alpha: (.one, .oneMinusSourceAlpha))
        glow = state("glowFragment", rgb: (.one, .one), alpha: (.one, .one))
        multiply = state("spriteFragment", rgb: (.destinationColor, .zero), alpha: (.zero, .one))

        let texture = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format, width: size.width, height: size.height, mipmapped: false)
        texture.usage = [.renderTarget, .shaderRead]
        texture.storageMode = .private
        (canvasDescriptor, canvas) = (texture, device.makeTexture(descriptor: texture)!)
    }

    /// Draws all of `Assets/<image>.png` with its top-left corner at (x, y), snapped to whole pixels.
    public func draw(_ image: ImageName, x: Double, y: Double) { draw(image.name, x: x, y: y) }

    /// Draws an image named in a string.
    @_disfavoredOverload public func draw(_ image: String, x: Double, y: Double) {
        let texture = texture(image)
        quad(texture, x: x, y: y, source: Rect(x: 0, y: 0, width: texture.width, height: texture.height))
    }

    /// Draws the sprite's current frame with its top-left corner at (x, y), snapped to whole pixels.
    public func draw(_ sprite: Sprite, x: Double, y: Double) {
        let texture = texture(sprite.image)
        var frame = 0
        if let name = sprite.animation {
            if let shown = sheet(sprite.image)?.animations?[name]?.frame(at: sprite.time) {
                frame = shown
            } else if warned.insert("\(sprite.image) \(name)").inserted {
                print("PixelKit: \(sprite.image).json has no animation \"\(name)\"")
            }
        }
        quad(texture, x: x, y: y, source: region(frame, self.frame(sprite.image), in: texture), flip: sprite.flipped, color: sprite.color,
             opacity: sprite.opacity, flash: sprite.flash)
    }

    /// Draws the tilemap's `layers` (all of them unless you say), first to last: only the tiles on the canvas, so
    /// levels can be many screens big. `Scene` draws its `tilemap` this way, the layers `above` after the entities.
    public func draw(_ map: Tilemap, layers: [Int]? = nil) {
        let texture = texture(map.tileset)
        let tile = Size(map.tileSize, map.tileSize)
        let frames = map.frames(sheet(map.tileset)?.animations)
        let (left, top) = (Int(offset.x.rounded(.up)), Int(offset.y.rounded(.up))) // the world pixel `quad` puts in the canvas's corner
        let columns = stride(from: max(map.cell(left), 0), through: min(map.cell(left + size.width - 1), map.width - 1), by: 1)
        let rows = stride(from: max(map.cell(top), 0), through: min(map.cell(top + size.height - 1), map.height - 1), by: 1)
        for layer in layers ?? Array(map.layers.indices) where map.layers.indices.contains(layer) {
            for row in rows {
                for column in columns {
                    guard let cell = map.layers[layer][row * map.width + column] else { continue }
                    quad(texture, x: Double(column * map.tileSize), y: Double(row * map.tileSize), source: region(frames[cell] ?? cell, tile, in: texture))
                }
            }
        }
    }

    /// Fills `box` with a color, 0xRRGGBB, at an `opacity` from 0 to 1: a health bar, a text box's back, or a night
    /// that darkens the world.
    public func fill(_ box: Rect, color: UInt32, opacity: Double = 1) {
        quad(white, x: Double(box.x), y: Double(box.y), source: Rect(x: 0, y: 0, width: 1, height: 1),
             size: Size(box.width, box.height), color: color, opacity: opacity)
    }

    /// Draws `Assets/<image>.png` (its first frame, if its `.json` cuts it up) as a box of any size: the image cut
    /// in thirds each way, its corners as they are, its edges stretched along their length and its middle both ways.
    /// One frame drawn in the pixel editor makes every text box and menu.
    public func panel(_ image: ImageName, in box: Rect) { panel(image.name, in: box) }

    /// Draws an image named in a string as a box.
    @_disfavoredOverload public func panel(_ image: String, in box: Rect) {
        let (texture, frame) = (texture(image), frame(image))
        // Each third's start and length, in the image and in the box. In a box smaller than two corners, they overlap.
        func thirds(_ image: Int, _ start: Int, _ length: Int) -> [(from: Int, length: Int, to: Int, size: Int)] {
            let corner = image / 3
            return [(0, corner, start, corner), (corner, image - corner * 2, start + corner, max(0, length - corner * 2)),
                    (image - corner, corner, start + length - corner, corner)]
        }
        for row in thirds(frame.height, box.y, box.height) {
            for column in thirds(frame.width, box.x, box.width) where row.size > 0 && column.size > 0 {
                quad(texture, x: Double(column.to), y: Double(row.to), source: Rect(x: column.from, y: row.from, width: column.length, height: row.length),
                     size: Size(column.size, row.size))
            }
        }
    }

    /// The size of an image's frames, as its `.json` cuts it up, or of the whole image.
    func frame(_ image: String) -> Size {
        sheet(image).map { Size($0.frameWidth, $0.frameHeight) } ?? Size(texture(image).width, texture(image).height)
    }

    /// The middle of an entity, in world pixels: of its sprite's frame, or of its hitbox without one. Its light shines
    /// from there, and an iris closes on it.
    func middle(of entity: Entity) -> Vector {
        let corner = entity.position.rounded(.down)
        guard let sprite = entity.sprite else {
            let box = entity.hitbox
            return corner + [Double(box.x), Double(box.y)] + [Double(box.width), Double(box.height)] / 2
        }
        let frame = frame(sprite.image)
        return corner + [Double(frame.width), Double(frame.height)] / 2
    }

    /// Multiplies what's drawn so far by a light map: white mixed toward `color` by `darkness` everywhere, and each
    /// light's color added around its middle (in world pixels, as the rest), brightest there and gone at its radius.
    /// What's drawn after it isn't darkened.
    func light(_ lights: [(middle: Vector, radius: Double, color: UInt32)], darkness: Double, color: UInt32) {
        end()
        let map = MTLRenderPassDescriptor()
        map.colorAttachments[0].texture = lightMap
        map.colorAttachments[0].loadAction = .clear
        let dark = clearColor(color), lit = 1 - min(max(darkness, 0), 1)
        map.colorAttachments[0].clearColor = MTLClearColor(red: dark.red + (1 - dark.red) * lit, green: dark.green + (1 - dark.green) * lit,
                                                           blue: dark.blue + (1 - dark.blue) * lit, alpha: 1)
        start(map, glow)
        for light in lights {
            let size = Int((light.radius * 2).rounded())
            quad(white, x: light.middle.x - Double(size) / 2, y: light.middle.y - Double(size) / 2, source: Rect(x: 0, y: 0, width: 1, height: 1),
                 size: Size(size, size), color: light.color)
        }
        end()
        let canvas = pass.copy() as! MTLRenderPassDescriptor
        canvas.colorAttachments[0].loadAction = .load
        start(canvas, multiply)
        let offset = self.offset
        self.offset = .zero
        quad(lightMap, x: 0, y: 0, source: Rect(x: 0, y: 0, width: size.width, height: size.height))
        flush()
        encoder.setRenderPipelineState(pipeline)
        self.offset = offset
    }

    /// Copies the canvas as it is, still the last frame, for a dissolve to draw over the next scene.
    func snap(_ commands: MTLCommandBuffer) {
        guard let blit = commands.makeBlitCommandEncoder() else { return }
        blit.copy(from: canvas, to: snapshot)
        blit.endEncoding()
    }

    /// The `index`th `size` region of a sheet, counting left to right, then top to bottom.
    func region(_ index: Int, _ size: Size, in texture: MTLTexture) -> Rect {
        let columns = max(1, texture.width / size.width)
        return Rect(x: index % columns * size.width, y: index / columns * size.height, width: size.width, height: size.height)
    }

    func texture(_ name: String) -> MTLTexture {
        if let texture = textures[name] { return texture }
        let url = assetURL("\(name).png")
        do {
            let texture = try loader.newTexture(URL: url, options: [.SRGB: false])
            textures[name] = texture
            modified["\(name).png"] = modificationDate(url)
            return texture
        } catch {
            fatalError("PixelKit: can't load \(url.path): \(error.localizedDescription)")
        }
    }

    /// How an image is cut into frames, from its `.json`; nil if it has none.
    func sheet(_ name: String) -> SheetFile? {
        if let sheet = sheets[name] { return sheet }
        let url = assetURL("\(name).json")
        var sheet: SheetFile?
        if FileManager.default.fileExists(atPath: url.path) {
            do { sheet = try SheetFile(contentsOf: url) } catch { print("PixelKit: can't read \(url.path): \(error.localizedDescription)") }
        }
        sheets[name] = .some(sheet)
        modified["\(name).json"] = modificationDate(url)
        return sheet
    }

    /// Reloads images and their `.json` files that changed on disk, e.g. saved by the editor.
    /// An image that can't be read (deleted, half-written) keeps its old texture.
    func reloadChangedAssets() {
        for (file, date) in modified {
            let url = assetURL(file)
            guard modificationDate(url) != date else { continue }
            modified[file] = modificationDate(url)
            let name = (file as NSString).deletingPathExtension
            if file.hasSuffix(".json") {
                (sheets[name], fonts[name]) = (nil, nil) // read again on next use
            } else if let texture = try? loader.newTexture(URL: url, options: [.SRGB: false]) {
                (textures[name], fonts[name]) = (texture, nil)
            }
        }
    }

    /// Queues a textured quad: `source`, from the texture, stretched over `size` (the same size unless you say), its
    /// pixels multiplied by `color` (0xRRGGBB, where white leaves them as they are) and `opacity`, then mixed toward
    /// white by `flash`; of a dissolve's 4x4 pattern, only the share `keep` of its pixels draw.
    /// Consecutive quads with the same texture reach the GPU as one draw call.
    func quad(_ texture: MTLTexture, x: Double, y: Double, source s: Rect, size: Size? = nil, flip: Bool = false, color: UInt32 = 0xFFFFFF,
              opacity: Double = 1, flash: Double = 0, keep: Double = 1) {
        if texture !== batchTexture {
            flush()
            batchTexture = texture
        }
        let x0 = Float((x - offset.x).rounded(.down)), y0 = Float((y - offset.y).rounded(.down))
        let (x1, y1) = (x0 + Float(size?.width ?? s.width), y0 + Float(size?.height ?? s.height))
        let (w, h) = (Float(texture.width), Float(texture.height))
        var (u0, u1) = (Float(s.x) / w, Float(s.x + s.width) / w)
        let (v0, v1) = (Float(s.y) / h, Float(s.y + s.height) / h)
        if flip { swap(&u0, &u1) }
        let corners: [SIMD4<Float>] = [[x0, y0, u0, v0], [x1, y0, u1, v0], [x0, y1, u0, v1], [x1, y0, u1, v0], [x1, y1, u1, v1], [x0, y1, u0, v1]]
        let tint = SIMD4<Float>(Float(color >> 16 & 0xFF) / 255, Float(color >> 8 & 0xFF) / 255, Float(color & 0xFF) / 255, Float(opacity))
        let effects = SIMD4<Float>(Float(flash), Float(keep), 0, 0)
        for corner in corners { vertices += [corner, tint, effects] }
    }

    func flush() {
        if let batchTexture, !vertices.isEmpty {
            let buffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<SIMD4<Float>>.stride)
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.setFragmentTexture(batchTexture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count / 3)
        }
        vertices.removeAll(keepingCapacity: true)
        batchTexture = nil
    }

    func begin(_ commands: MTLCommandBuffer, _ pass: MTLRenderPassDescriptor) {
        (self.commands, self.pass) = (commands, pass)
        start(pass, pipeline)
    }

    private func start(_ pass: MTLRenderPassDescriptor, _ state: MTLRenderPipelineState) {
        pass.colorAttachments[0].storeAction = .store // kept for what's drawn after, the light map's multiply among them
        encoder = commands.makeRenderCommandEncoder(descriptor: pass)
        encoder.setRenderPipelineState(state)
        let canvasSize = [SIMD2<Float>(Float(size.width), Float(size.height))]
        encoder.setVertexBytes(canvasSize, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
    }

    func end() {
        flush()
        encoder.endEncoding()
        encoder = nil
    }
}

/// A color, 0xRRGGBB, to clear a render pass to.
func clearColor(_ rgb: UInt32) -> MTLClearColor {
    MTLClearColor(red: Double(rgb >> 16 & 0xFF) / 255, green: Double(rgb >> 8 & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255, alpha: 1)
}

/// The biggest scale of `canvas` that fits in `drawable`, so on a phone the game reaches the screen's edges: at the top
/// when the screen is taller than wide, leaving the rest to the touch controls, and centered otherwise. ponytail: not a
/// whole number, so some of the game's pixels are a screen pixel wider; on a 3x screen that doesn't show.
func fit(_ canvas: Size, in drawable: CGSize) -> MTLViewport {
    let scale = min(drawable.width / Double(canvas.width), drawable.height / Double(canvas.height))
    let (width, height) = (Double(canvas.width) * scale, Double(canvas.height) * scale)
    return MTLViewport(originX: (drawable.width - width) / 2, originY: drawable.height > drawable.width ? 0 : (drawable.height - height) / 2,
                       width: width, height: height, znear: 0, zfar: 1)
}

/// The canvas pixel at `point` when the canvas shows in `viewport` (`fit`'s or `letterbox`'s, in the same units, from
/// the top left), in whole pixels, and off the canvas when the point is.
func pixel(at point: CGPoint, in viewport: MTLViewport, canvas: Size) -> Vector {
    let scale = viewport.width / Double(canvas.width)
    return [((point.x - viewport.originX) / scale).rounded(.down), ((point.y - viewport.originY) / scale).rounded(.down)]
}

/// The biggest whole-number scale of `canvas` that fits in `drawable` (at least 1x), centered.
func letterbox(_ canvas: Size, in drawable: CGSize) -> MTLViewport {
    let (w, h) = (Int(drawable.width), Int(drawable.height))
    let scale = max(1, min(w / canvas.width, h / canvas.height))
    let (sw, sh) = (canvas.width * scale, canvas.height * scale)
    return MTLViewport(
        originX: Double((w - sw) / 2), originY: Double((h - sh) / 2),
        width: Double(sw), height: Double(sh), znear: 0, zfar: 1)
}

// Compiled at runtime, so building games doesn't need the offline Metal toolchain.
let shaders = """
#include <metal_stdlib>
using namespace metal;

struct Vertex { float4 position [[position]]; float2 uv; float4 color [[flat]]; float4 effects [[flat]]; };

// As Screen.quad writes them: x, y in canvas pixels (y down) and u, v texture coords; the color to multiply by; then
// how far to mix toward white (a flash) and how much of a dissolve's pattern to keep.
struct Corner { float4 xyuv; float4 color; float4 effects; };

// A 4x4 ordered dither: the order a dissolve's pixels go in.
constant float bayer[16] = {0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5};

vertex Vertex spriteVertex(uint i [[vertex_id]], constant Corner *v [[buffer(0)]], constant float2 &size [[buffer(1)]]) {
    float2 p = v[i].xyuv.xy / size * 2 - 1;
    return { float4(p.x, -p.y, 0, 1), v[i].xyuv.zw, v[i].color, v[i].effects };
}

fragment float4 spriteFragment(Vertex in [[stage_in]], texture2d<float> t [[texture(0)]]) {
    uint2 cell = uint2(in.position.xy) % 4;
    if (bayer[cell.y * 4 + cell.x] / 16 >= in.effects.y) discard_fragment();
    constexpr sampler nearest(filter::nearest);
    float4 c = t.sample(nearest, in.uv) * in.color;
    return float4(mix(c.rgb, float3(1), saturate(in.effects.x)), c.a);
}

// A light, added to the light map: its color, brightest in the middle of its square and gone at the edge of its circle.
fragment float4 glowFragment(Vertex in [[stage_in]]) {
    float2 d = in.uv * 2 - 1;
    float glow = saturate(1 - dot(d, d));
    return float4(in.color.rgb * glow * glow, 1);
}
"""

/// Where a game file, `<name>.<extension>`, is: anywhere in `Assets`, at the top first, then in its folders by path, so
/// games keep their sprites, maps and sounds in folders and find them by name. `Assets` is inside the app once the game
/// has been exported, otherwise in the folder the game runs in (the editor runs games in their project folder).
/// A file that isn't where it was, or wasn't there, is looked for again once a folder in `Assets` has changed, which is
/// looked at no more than once a second (the loop checks loaded files 4 times a second), so files added or moved while
/// the game runs are found. In an app, whose files can't change, it's never looked for again.
func assetURL(_ file: String) -> URL {
    let root = bundledAssets ?? URL(fileURLWithPath: "Assets")
    return assetIndex.withLock { index in
        func found() -> URL? { index.files[file].flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil } }
        if index.root == root, let url = found() { return url }
        if index.root != root || index.stale() { index.build(root) }
        return found() ?? root.appending(path: file)
    }
}

private let bundledAssets = Bundle.main.url(forResource: "Assets", withExtension: nil)
/// Whether the game's files can change while it runs, saved by the editor: not once they're inside an app, where
/// they're signed, as on an iPhone or iPad. Only then does the loop look for files that changed.
let assetsCanChange = bundledAssets == nil
let assetIndex = Mutex(AssetIndex())

/// The names of the files in an app's `Assets` with one of `extensions`, without it; none outside an app.
func bundledNames(_ extensions: Set<String>) -> [String] {
    guard let root = bundledAssets else { return [] }
    let names = (FileManager.default.subpaths(atPath: root.path) ?? []).compactMap { path -> String? in
        let file = (path as NSString).lastPathComponent as NSString
        return extensions.contains(file.pathExtension) ? file.deletingPathExtension : nil
    }
    return Set(names).sorted()
}

/// What `read` makes of the file `key`, kept in `kept` the first time in an app, whose files can't change, so it's
/// read once; read each time where they can (`keeping` false), as in the editor, which may have saved it since.
func once<Value: Sendable>(_ key: String, in kept: borrowing Mutex<[String: Value]>, keeping: Bool = !assetsCanChange,
                           _ read: () throws -> Value) rethrows -> Value {
    if keeping, let value = kept.withLock({ $0[key] }) { return value }
    let value = try read()
    if keeping { kept.withLock { $0[key] = value } }
    return value
}

/// The files in `Assets` and its folders, by name.
struct AssetIndex {
    var root: URL?
    var files: [String: URL] = [:]
    var folders: [(url: URL, modified: Date?)] = [] // `Assets` and its folders, which change as a file in one is added, moved or deleted
    var checked = Date.distantPast // when the folders were last looked at
    var warned: Set<String> = []

    /// Names must be unique among files of one type; of two, the first by path wins, and the console says so.
    mutating func build(_ root: URL) {
        let paths = (FileManager.default.subpaths(atPath: root.path) ?? [])
            .filter { !$0.split(separator: "/").contains { $0.hasPrefix(".") } } // the editor's, like an image's layers
            .sorted { ($0.contains("/") ? 1 : 0, $0) < ($1.contains("/") ? 1 : 0, $1) }
        (self.root, files, folders, checked) = (root, [:], [(root, modificationDate(root))], Date())
        for path in paths {
            let url = root.appending(path: path)
            var folder: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &folder), folder.boolValue { folders.append((url, modificationDate(url))) }
            let name = (path as NSString).lastPathComponent
            if let first = files[name] {
                if warned.insert(name).inserted { print("PixelKit: Assets has two files called \(name), so it uses \(first.path), not \(path)") }
            } else {
                files[name] = url
            }
        }
    }

    /// Whether a file may have been added, moved or deleted since it was built: once one of its folders has changed,
    /// looked at no more than once a second. Building it takes a couple of milliseconds; this, a microsecond or two a folder.
    mutating func stale() -> Bool {
        guard assetsCanChange, Date().timeIntervalSince(checked) >= 1 else { return false }
        checked = Date()
        return folders.contains { modificationDate($0.url) != $0.modified }
    }
}

/// When the file at `url` last changed; nil without one. From `stat`, in a microsecond or two, where FileManager's
/// attributes took 10 to 20 for each file the loop checks.
func modificationDate(_ url: URL) -> Date? {
    var status = stat()
    guard url.withUnsafeFileSystemRepresentation({ $0.map { stat($0, &status) } }) == 0 else { return nil }
    return Date(timeIntervalSince1970: Double(status.st_mtimespec.tv_sec) + Double(status.st_mtimespec.tv_nsec) / 1_000_000_000)
}

/// The size of `Assets/<name>.png`'s frames, as its `.json` cuts it up, or of the whole image; nil without one. Read
/// `once`.
func frameSize(_ name: String) -> Size? {
    once(name, in: framesRead) {
        guard let source = CGImageSourceCreateWithURL(assetURL("\(name).png") as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let sheet = try? SheetFile(contentsOf: assetURL("\(name).json"))
        return Size(sheet?.frameWidth ?? width, sheet?.frameHeight ?? height)
    }
}

let framesRead = Mutex<[String: Size?]>([:])

extension SheetFile.Animation {
    /// The frame showing `time` seconds in, looping; nil without frames.
    func frame(at time: Double) -> Int? { frames.isEmpty ? nil : frames[Int(time * fps) % frames.count] }
}
