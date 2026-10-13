import MetalKit
import PixelKitProtocol

/// The game loop: fixed 60 Hz updates, then the scene draws into the small canvas.
@MainActor final class Loop {
    static let step = 1.0 / 60
    let screen: Screen
    let queue: MTLCommandQueue
    var last = CACurrentMediaTime()
    var lag = 0.0 // time not simulated yet
    var frames = 0
    var paused = false {
        didSet { Music.paused = paused }
    }
    var steps = 0 // updates to run while paused

    init(resolution: Size, device: MTLDevice) {
        queue = device.makeCommandQueue()!
        screen = Screen(size: resolution, device: device, format: .bgra8Unorm)
        Input.canvas = resolution
    }

    /// Runs the updates that are due, then draws the scene into the canvas on a new command buffer.
    func tick() -> MTLCommandBuffer? {
        let now = CACurrentMediaTime()
        var elapsed = now - last
        last = now
        if abs(elapsed - Self.step) < 0.002 { elapsed = Self.step } // absorb vsync jitter: one update per 60 Hz frame
        if paused {
            for _ in 0..<steps { update() }
            (steps, lag) = (0, 0)
        } else {
            lag = min(lag + elapsed, 0.25) // after a stall, slow down instead of running a burst of catch-up updates
            while lag >= Self.step {
                update()
                lag -= Self.step
            }
        }
        frames += 1
        if frames % 15 == 0 { // 4 times a second
            screen.reloadChangedAssets()
            Scene.current.tilemap?.reloadIfChanged()
            Music.restartIfChanged()
        }

        guard let commands = queue.makeCommandBuffer() else { return nil }
        if Scene.changing?.style == .dissolve, Scene.changing?.snapped == false { // the canvas still has the last frame
            screen.snap(commands)
            Scene.changing?.snapped = true
        }
        let scene = Scene.current
        let canvas = MTLRenderPassDescriptor()
        canvas.colorAttachments[0].texture = screen.canvas
        canvas.colorAttachments[0].loadAction = .clear
        canvas.colorAttachments[0].clearColor = clearColor(scene.background)
        screen.begin(commands, canvas)
        scene.draw(screen)
        Scene.changing?.draw(screen, over: scene)
        screen.end()
        return commands
    }

    func update() {
        Input.poll()
        Scene.tick(Self.step)
    }
}

/// Shows the game in its own window, the canvas scaled up by whole numbers, or on iOS, the app's screen, edge to edge.
final class GameView: MTKView {
    let loop: Loop

    init(resolution: Size) {
        let device = MTLCreateSystemDefaultDevice()!
        loop = Loop(resolution: resolution, device: device)
        super.init(frame: .zero, device: device)
        colorPixelFormat = .bgra8Unorm
        #if os(macOS)
        colorspace = CGColorSpace(name: CGColorSpace.sRGB) // show asset colors exactly as they are in the PNG
        // Moves come as the window's first responder (`acceptsMouseMovedEvents`); this says when the mouse leaves.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
        #endif
    }

    required init(coder: NSCoder) { fatalError("GameView is created in code") }

    #if os(macOS)
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { Input.keys.insert(Int(event.keyCode)) }
    override func keyUp(with event: NSEvent) { Input.keys.remove(Int(event.keyCode)) }
    override func mouseDown(with event: NSEvent) { point(event, down: true) }
    override func mouseDragged(with event: NSEvent) { point(event, down: true) }
    override func mouseUp(with event: NSEvent) { point(event, down: false) }
    override func mouseMoved(with event: NSEvent) { point(event, down: false) }
    override func mouseExited(with event: NSEvent) { if NSEvent.pressedMouseButtons & 1 == 0 { Input.point(nil, down: false) } }

    /// The mouse, through the letterbox, in canvas pixels. The view's y goes up, the drawable's down.
    private func point(_ event: NSEvent, down: Bool) {
        let (point, scale, canvas) = (convert(event.locationInWindow, from: nil), drawableSize.width / bounds.width, loop.screen.size)
        let drawn = CGPoint(x: point.x * scale, y: (bounds.height - point.y) * scale)
        Input.point(pixel(at: drawn, in: letterbox(canvas, in: drawableSize), canvas: canvas), down: down)
    }
    #endif

    override func draw(_ dirtyRect: CGRect) {
        guard let drawable = currentDrawable, let window = currentRenderPassDescriptor, let commands = loop.tick() else { return }
        #if os(iOS)
        if Input.hardware { for case let controls as TouchControls in subviews { controls.shown = false } }
        #endif
        let screen = loop.screen
        screen.begin(commands, window)
        #if os(iOS)
        screen.encoder.setViewport(fit(screen.size, in: drawableSize))
        #else
        screen.encoder.setViewport(letterbox(screen.size, in: drawableSize))
        #endif
        screen.quad(screen.canvas, x: 0, y: 0, source: Rect(x: 0, y: 0, width: screen.size.width, height: screen.size.height))
        screen.end()
        commands.present(drawable)
        commands.commit()
    }
}

#if os(macOS)
/// Runs the game without a window and sends every frame to the editor that launched it, which shows it in its
/// preview. Keys pressed in the preview, and pause and step, come back the same way.
@MainActor final class EditorHost {
    let loop: Loop
    let channel: Channel
    let pixels: MTLBuffer // the canvas, copied out each frame

    init(resolution: Size, channel: Channel) {
        let device = MTLCreateSystemDefaultDevice()!
        loop = Loop(resolution: resolution, device: device)
        self.channel = channel
        pixels = device.makeBuffer(length: resolution.width * resolution.height * 4, options: .storageModeShared)!
    }

    // ponytail: copies the small canvas each frame (230 KB at 320x180); share an IOSurface if games outgrow it
    func frame() {
        guard let commands = loop.tick(), let blit = commands.makeBlitCommandEncoder() else { return }
        let (width, height) = (loop.screen.size.width, loop.screen.size.height)
        blit.copy(from: loop.screen.canvas, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1), to: pixels, destinationOffset: 0,
                  destinationBytesPerRow: width * 4, destinationBytesPerImage: width * height * 4)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        channel.send(.frame(width: width, height: height, pixels: Data(bytes: pixels.contents(), count: width * height * 4)))
    }

    func handle(_ message: Message) {
        switch message {
        case let .keys(keys): Input.keys = Set(keys)
        case let .pointer(x, y, down): Input.point([Double(x), Double(y)], down: down)
        case .pause: loop.paused = true
        case .resume: loop.paused = false
        case .step: loop.steps += 1
        case let .reload(path): print(Reloader.load(path)) // shows in the editor's console
        case .frame: break
        }
    }
}
#endif
