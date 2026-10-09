import MetalKit
import PixelKitProtocol

/// The pixel canvas your game draws on. (0, 0) is the top-left pixel.
@MainActor public final class Screen {
    let size: Size
    let device: MTLDevice
    let pipeline: MTLRenderPipelineState
    let canvas: MTLTexture
    let loader: MTKTextureLoader
    var textures: [String: MTLTexture] = [:]
    var sheets: [String: SheetFile?] = [:] // nil: the image has no .json, so it's a single frame
    var modified: [String: Date?] = [:] // each loaded file's modification date, to spot edits
    var warned: Set<String> = []
    var encoder: MTLRenderCommandEncoder!
    var vertices: [SIMD4<Float>] = [] // queued quads, all using `batchTexture`
    var batchTexture: MTLTexture?
    /// Subtracted from every position; the scene sets it to its camera.
    var offset = Vector.zero

    init(size: Size, device: MTLDevice, format: MTLPixelFormat) {
        self.size = size
        self.device = device
        loader = MTKTextureLoader(device: device)

        let library = try! device.makeLibrary(source: shaders, options: nil)
        let pipeline = MTLRenderPipelineDescriptor()
        pipeline.vertexFunction = library.makeFunction(name: "spriteVertex")
        pipeline.fragmentFunction = library.makeFunction(name: "spriteFragment")
        let color = pipeline.colorAttachments[0]!
        color.pixelFormat = format
        color.isBlendingEnabled = true
        color.sourceRGBBlendFactor = .sourceAlpha
        color.destinationRGBBlendFactor = .oneMinusSourceAlpha
        color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        self.pipeline = try! device.makeRenderPipelineState(descriptor: pipeline)

        let texture = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format, width: size.width, height: size.height, mipmapped: false)
        texture.usage = [.renderTarget, .shaderRead]
        texture.storageMode = .private
        canvas = device.makeTexture(descriptor: texture)!
    }

    /// Draws all of `Assets/<image>.png` with its top-left corner at (x, y), snapped to whole pixels.
    public func draw(_ image: String, x: Double, y: Double) {
        let texture = texture(image)
        quad(texture, x: x, y: y, source: Rect(x: 0, y: 0, width: texture.width, height: texture.height))
    }

    /// Draws the sprite's current frame with its top-left corner at (x, y), snapped to whole pixels.
    public func draw(_ sprite: Sprite, x: Double, y: Double) {
        let texture = texture(sprite.image)
        let sheet = sheet(sprite.image)
        let size = Size(sheet?.frameWidth ?? texture.width, sheet?.frameHeight ?? texture.height)
        var frame = 0
        if let name = sprite.animation {
            if let animation = sheet?.animations?[name], !animation.frames.isEmpty {
                frame = animation.frames[Int(sprite.time * animation.fps) % animation.frames.count]
            } else if warned.insert("\(sprite.image) \(name)").inserted {
                print("PixelKit: \(sprite.image).json has no animation \"\(name)\"")
            }
        }
        quad(texture, x: x, y: y, source: region(frame, size, in: texture), flip: sprite.flipped)
    }

    // ponytail: draws every tile; cull to the camera when maps get big
    public func draw(_ map: Tilemap) {
        let texture = texture(map.tileset)
        let tile = Size(map.tileSize, map.tileSize)
        for layer in map.layers {
            for (i, cell) in layer.enumerated() {
                guard let cell else { continue }
                let (x, y) = (Double(i % map.width * map.tileSize), Double(i / map.width * map.tileSize))
                quad(texture, x: x, y: y, source: region(cell, tile, in: texture))
            }
        }
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
                sheets[name] = nil // read again on next use
            } else if let texture = try? loader.newTexture(URL: url, options: [.SRGB: false]) {
                textures[name] = texture
            }
        }
    }


    func modificationDate(_ url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    /// Queues a textured quad. Consecutive quads with the same texture reach the GPU as one draw call.
    func quad(_ texture: MTLTexture, x: Double, y: Double, source s: Rect, flip: Bool = false) {
        if texture !== batchTexture {
            flush()
            batchTexture = texture
        }
        let x0 = Float((x - offset.x).rounded(.down)), y0 = Float((y - offset.y).rounded(.down))
        let (x1, y1) = (x0 + Float(s.width), y0 + Float(s.height))
        let (w, h) = (Float(texture.width), Float(texture.height))
        var (u0, u1) = (Float(s.x) / w, Float(s.x + s.width) / w)
        let (v0, v1) = (Float(s.y) / h, Float(s.y + s.height) / h)
        if flip { swap(&u0, &u1) }
        vertices += [[x0, y0, u0, v0], [x1, y0, u1, v0], [x0, y1, u0, v1], [x1, y0, u1, v0], [x1, y1, u1, v1], [x0, y1, u0, v1]]
    }

    func flush() {
        if let batchTexture, !vertices.isEmpty {
            let buffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<SIMD4<Float>>.stride)
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.setFragmentTexture(batchTexture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
        }
        vertices.removeAll(keepingCapacity: true)
        batchTexture = nil
    }

    func begin(_ commands: MTLCommandBuffer, _ pass: MTLRenderPassDescriptor) {
        encoder = commands.makeRenderCommandEncoder(descriptor: pass)
        encoder.setRenderPipelineState(pipeline)
        let canvasSize = [SIMD2<Float>(Float(size.width), Float(size.height))]
        encoder.setVertexBytes(canvasSize, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
    }

    func end() {
        flush()
        encoder.endEncoding()
        encoder = nil
    }
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

struct Vertex { float4 position [[position]]; float2 uv; };

// v: x, y in canvas pixels (y down) + u, v texture coords.
vertex Vertex spriteVertex(uint i [[vertex_id]], constant float4 *v [[buffer(0)]], constant float2 &size [[buffer(1)]]) {
    float2 p = v[i].xy / size * 2 - 1;
    return { float4(p.x, -p.y, 0, 1), v[i].zw };
}

fragment float4 spriteFragment(Vertex in [[stage_in]], texture2d<float> t [[texture(0)]]) {
    constexpr sampler nearest(filter::nearest);
    return t.sample(nearest, in.uv);
}
"""

/// Where a game file is: inside the app once the game has been exported, otherwise in `Assets/` of the folder the
/// game runs in (the editor runs games in their project folder).
func assetURL(_ file: String) -> URL {
    if let bundledAssets { return bundledAssets.appending(path: file) }
    return URL(fileURLWithPath: "Assets/\(file)")
}

private let bundledAssets = Bundle.main.url(forResource: "Assets", withExtension: nil)
