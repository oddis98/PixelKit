import MetalKit

/// The pixel canvas your game draws on. (0, 0) is the top-left pixel.
@MainActor public final class Screen {
    let size: Size
    let device: MTLDevice
    let pipeline: MTLRenderPipelineState
    let canvas: MTLTexture
    let loader: MTKTextureLoader
    var textures: [String: MTLTexture] = [:]
    var modified: [String: Date?] = [:] // each loaded PNG's modification date, to spot edits
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
        quad(texture, x: x, y: y, source: region(sprite.frame, sprite.frameSize, in: texture), flip: sprite.flipped)
    }

    // ponytail: draws every tile; cull to the camera when maps get big
    public func draw(_ map: Tilemap) {
        let texture = texture(map.image)
        let tile = Size(map.tileSize, map.tileSize)
        for (row, cells) in map.cells.enumerated() {
            for (column, cell) in cells.enumerated() {
                guard let cell else { continue }
                let (x, y) = (Double(column * map.tileSize), Double(row * map.tileSize))
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
        let url = assetURL(name)
        do {
            let texture = try loader.newTexture(URL: url, options: [.SRGB: false])
            textures[name] = texture
            modified[name] = modificationDate(url)
            return texture
        } catch {
            fatalError("PixelKit: can't load \(url.path): \(error.localizedDescription)")
        }
    }

    /// Reloads textures whose PNG changed on disk, e.g. saved by the pixel editor.
    /// If the new file can't be read (deleted, half-written), the old texture stays.
    func reloadChangedTextures() {
        for (name, date) in modified {
            let url = assetURL(name)
            guard modificationDate(url) != date else { continue }
            modified[name] = modificationDate(url)
            if let texture = try? loader.newTexture(URL: url, options: [.SRGB: false]) { textures[name] = texture }
        }
    }

    // ponytail: reads from the project folder (the editor runs games there); bundle assets on export (Phase 7)
    func assetURL(_ name: String) -> URL { URL(fileURLWithPath: "Assets/\(name).png") }

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

/// Runs the game: fixed 60 Hz updates, then the scene draws into the small canvas, which is scaled up into the window.
final class GameView: MTKView {
    static let step = 1.0 / 60
    let screen: Screen
    let queue: MTLCommandQueue
    var last = CACurrentMediaTime()
    var lag = 0.0 // time not simulated yet
    var frames = 0

    init(resolution: Size) {
        let device = MTLCreateSystemDefaultDevice()!
        queue = device.makeCommandQueue()!
        screen = Screen(size: resolution, device: device, format: .bgra8Unorm)
        super.init(frame: .zero, device: device)
        colorPixelFormat = .bgra8Unorm
        colorspace = CGColorSpace(name: CGColorSpace.sRGB) // show asset colors exactly as they are in the PNG
    }

    required init(coder: NSCoder) { fatalError("GameView is created in code") }

    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { Input.keys.insert(Int(event.keyCode)) }
    override func keyUp(with event: NSEvent) { Input.keys.remove(Int(event.keyCode)) }

    override func draw(_ dirtyRect: NSRect) {
        let now = CACurrentMediaTime()
        var elapsed = now - last
        last = now
        if abs(elapsed - Self.step) < 0.002 { elapsed = Self.step } // absorb vsync jitter: one update per 60 Hz frame
        lag = min(lag + elapsed, 0.25) // after a stall, slow down instead of running a burst of catch-up updates
        while lag >= Self.step {
            Input.poll()
            Scene.current.update(Self.step)
            lag -= Self.step
        }
        frames += 1
        if frames % 15 == 0 { screen.reloadChangedTextures() } // 4 times a second

        guard let drawable = currentDrawable, let window = currentRenderPassDescriptor,
              let commands = queue.makeCommandBuffer() else { return }
        let scene = Scene.current
        let rgb = scene.background
        let canvas = MTLRenderPassDescriptor()
        canvas.colorAttachments[0].texture = screen.canvas
        canvas.colorAttachments[0].loadAction = .clear
        canvas.colorAttachments[0].clearColor = MTLClearColor(
            red: Double(rgb >> 16 & 0xFF) / 255, green: Double(rgb >> 8 & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255, alpha: 1)
        screen.begin(commands, canvas)
        scene.draw(screen)
        screen.end()

        screen.begin(commands, window)
        screen.encoder.setViewport(letterbox(screen.size, in: drawableSize))
        screen.quad(screen.canvas, x: 0, y: 0, source: Rect(x: 0, y: 0, width: screen.size.width, height: screen.size.height))
        screen.end()

        commands.present(drawable)
        commands.commit()
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
