import MetalKit

/// The pixel canvas your game draws on. (0, 0) is the top-left pixel.
@MainActor public final class Screen {
    let size: Size
    let pipeline: MTLRenderPipelineState
    let canvas: MTLTexture
    let loader: MTKTextureLoader
    var textures: [String: MTLTexture] = [:]
    var encoder: MTLRenderCommandEncoder!

    init(size: Size, device: MTLDevice, format: MTLPixelFormat) {
        self.size = size
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

    /// Draws `Assets/<name>.png` with its top-left corner at (x, y), snapped to whole pixels.
    public func draw(_ name: String, x: Double, y: Double) {
        quad(textures[name] ?? load(name), x: x.rounded(.down), y: y.rounded(.down))
    }

    func load(_ name: String) -> MTLTexture {
        // ponytail: reads from the project folder (the editor runs games there); bundle assets on export (Phase 7)
        let url = URL(fileURLWithPath: "Assets/\(name).png")
        do {
            let texture = try loader.newTexture(URL: url, options: [.SRGB: false])
            textures[name] = texture
            return texture
        } catch {
            fatalError("PixelKit: can't load \(url.path): \(error.localizedDescription)")
        }
    }

    // ponytail: one draw call per sprite; batch them in Phase 1
    func quad(_ texture: MTLTexture, x: Double, y: Double) {
        let (x, y, w, h) = (Float(x), Float(y), Float(texture.width), Float(texture.height))
        let corners: [SIMD4<Float>] = [[x, y, 0, 0], [x + w, y, 1, 0], [x, y + h, 0, 1], [x + w, y + h, 1, 1]]
        let canvasSize = [SIMD2<Float>(Float(size.width), Float(size.height))]
        encoder.setVertexBytes(corners, length: corners.count * MemoryLayout<SIMD4<Float>>.stride, index: 0)
        encoder.setVertexBytes(canvasSize, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
}

/// Runs the frame loop: the game draws into the small canvas, then the canvas is scaled up into the window.
final class GameView: MTKView {
    let game: any Game
    let screen: Screen
    let queue: MTLCommandQueue

    init(game: any Game) {
        let device = MTLCreateSystemDefaultDevice()!
        self.game = game
        queue = device.makeCommandQueue()!
        screen = Screen(size: game.resolution, device: device, format: .bgra8Unorm)
        super.init(frame: .zero, device: device)
        colorPixelFormat = .bgra8Unorm
        colorspace = CGColorSpace(name: CGColorSpace.sRGB) // show asset colors exactly as they are in the PNG
    }

    required init(coder: NSCoder) { fatalError("GameView is created in code") }

    override func draw(_ dirtyRect: NSRect) {
        guard let drawable = currentDrawable, let window = currentRenderPassDescriptor,
              let commands = queue.makeCommandBuffer() else { return }

        let canvas = MTLRenderPassDescriptor()
        canvas.colorAttachments[0].texture = screen.canvas
        canvas.colorAttachments[0].loadAction = .clear
        canvas.colorAttachments[0].clearColor = MTLClearColor(red: 0.114, green: 0.169, blue: 0.325, alpha: 1)
        screen.encoder = commands.makeRenderCommandEncoder(descriptor: canvas)
        screen.encoder.setRenderPipelineState(screen.pipeline)
        game.draw(screen)
        screen.encoder.endEncoding()

        screen.encoder = commands.makeRenderCommandEncoder(descriptor: window)
        screen.encoder.setRenderPipelineState(screen.pipeline)
        screen.encoder.setViewport(letterbox(screen.size, in: drawableSize))
        screen.quad(screen.canvas, x: 0, y: 0)
        screen.encoder.endEncoding()
        screen.encoder = nil

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
