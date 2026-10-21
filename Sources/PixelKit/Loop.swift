import MetalKit
import PixelKitProtocol

/// The game loop: fixed 60 Hz updates, then the scene draws into the small canvas.
@MainActor final class Loop {
    nonisolated static let step = 1.0 / 60
    let screen: Screen
    let queue: MTLCommandQueue
    var last = CACurrentMediaTime()
    var pace = Pace()
    var frames = 0
    var paused = false {
        didSet { Music.paused = paused }
    }
    var steps = 0 // updates to run while paused

    init(resolution: Size, device: MTLDevice) {
        queue = device.makeCommandQueue()!
        screen = Screen(size: resolution, device: device, format: .bgra8Unorm)
        Input.canvas = resolution
        Sound.mixer.prepare() // so the first sounds don't wait for the audio engine
        Sound.readAhead() // in an app, the files of its sounds and objects, in the background, so none is waited for
        Scene.readAhead()
    }

    /// Runs the updates that are due at `now`, when the frame will be on the screen, then draws the scene into the canvas
    /// on a new command buffer.
    func tick(at now: Double = CACurrentMediaTime()) -> MTLCommandBuffer? {
        let elapsed = now - last
        last = now
        if paused {
            for _ in 0..<steps { update() }
            (steps, pace) = (0, Pace())
        } else {
            for _ in 0..<pace.updates(after: elapsed) { update() }
        }
        frames += 1
        if assetsCanChange, frames % 15 == 0 { // 4 times a second, but not in an app, whose files can't change
            screen.reloadChangedAssets()
            Scene.current.tilemap?.reloadIfChanged()
            Music.restartIfChanged()
            Sound.forgetChanged()
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

/// How many of the game's 60 Hz updates a frame runs, from the time since the last frame. On a 60 Hz display, one for
/// each refresh since then, give or take 2 ms, so a frame drawn a little late, or a display a hair off 60 Hz, still runs
/// one; at other rates, as many as the time adds up to.
struct Pace {
    /// Time not simulated yet, kept half an update from where a frame would run one more or one less, so a frame a little
    /// early or late can't tip it either way. At 0, as a stall used to leave it, a frame 3 ms late ran two updates and the
    /// next one none: the picture stood still, then jumped.
    var lag = Loop.step / 2
    static let most = 15 // in a frame: after a stall, the game slows down for a moment rather than run a burst of updates

    mutating func updates(after elapsed: Double) -> Int {
        let refreshes = (elapsed / Loop.step).rounded()
        if refreshes >= 1, abs(elapsed - refreshes * Loop.step) < 0.002 {
            lag = Loop.step / 2
            return min(Int(refreshes), Self.most)
        }
        lag = min(lag + elapsed, (Double(Self.most) + 0.5) * Loop.step)
        var due = 0
        while lag >= Loop.step {
            lag -= Loop.step
            due += 1
        }
        return due
    }
}

/// Shows the game in its own window, the canvas scaled up by whole numbers, or on iOS, the app's screen, edge to edge.
/// A display link draws it 60 times a second, rather than the view's own timer, and says when each frame will be on the
/// screen: the loop counts the time between frames from that, not from when `draw` gets to run, which other work on the
/// main thread, like a touch handled first, can make a few milliseconds late. On an iPhone or iPad it's a Metal display
/// link, which brings each frame's drawable: one taken after the frame could leave a launch a frame behind the screen,
/// every frame waiting about 12 ms for a drawable and showing 17 ms later. The simulator keeps a `CADisplayLink`: the
/// Metal one drew about 42 frames a second there, unevenly.
final class GameView: MTKView {
    let loop: Loop
    private var link: CADisplayLink? // on the Mac and in the simulator
    #if os(iOS)
    private var metalLink: CAMetalDisplayLink? // on an iPhone or iPad
    #endif
    private var shows: Double? // when the frame being drawn will be on the screen, from `link` or `metalLink`

    init(resolution: Size) {
        let device = MTLCreateSystemDefaultDevice()!
        loop = Loop(resolution: resolution, device: device)
        super.init(frame: .zero, device: device)
        colorPixelFormat = .bgra8Unorm
        (isPaused, enableSetNeedsDisplay) = (true, false) // drawn by `link`
        #if os(macOS)
        colorspace = CGColorSpace(name: CGColorSpace.sRGB) // show asset colors exactly as they are in the PNG
        // Moves come as the window's first responder (`acceptsMouseMovedEvents`); this says when the mouse leaves.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
        #elseif targetEnvironment(simulator)
        run(CADisplayLink(target: self, selector: #selector(refresh)))
        #else
        let link = CAMetalDisplayLink(metalLayer: layer as! CAMetalLayer)
        link.delegate = self
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        metalLink = link
        #endif
        #if os(iOS)
        // Stopped in the background, where iOS doesn't let an app use the GPU.
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(background), name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.addObserver(self, selector: #selector(foreground), name: UIApplication.willEnterForegroundNotification, object: nil)
        #endif
    }

    required init(coder: NSCoder) { fatalError("GameView is created in code") }

    private func run(_ link: CADisplayLink) {
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func refresh(_ link: CADisplayLink) {
        shows = link.targetTimestamp
        draw()
    }

    #if os(iOS)
    @objc private func background() { link?.isPaused = true; metalLink?.isPaused = true }
    @objc private func foreground() { link?.isPaused = false; metalLink?.isPaused = false }

    /// The view gives its layer a new drawable size only as it hands out drawables itself, and `metalLink` takes them from
    /// the layer: turned sideways, the game was drawn upright and squeezed onto the screen.
    override func layoutSubviews() {
        super.layoutSubviews()
        (layer as! CAMetalLayer).drawableSize = drawableSize
    }
    #else
    /// The display link of the screen the window is on, which follows it to another.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, link == nil { run(displayLink(target: self, selector: #selector(refresh))) }
    }
    #endif

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

    override func draw(_ dirtyRect: CGRect) { frame { currentDrawable } }

    /// The frame first, then a drawable to show it in: `link`'s taken now, held no longer than it takes to draw into it,
    /// or the one `metalLink` brought.
    private func frame(_ drawable: () -> CAMetalDrawable?) {
        guard let commands = loop.tick(at: shows ?? CACurrentMediaTime()) else { return }
        defer { commands.commit() } // with or without a drawable, for the canvas a dissolve copies
        guard let drawable = drawable() else { return }
        #if os(iOS)
        if Input.hardware { for case let controls as TouchControls in subviews { controls.shown = false } }
        #endif
        let window = MTLRenderPassDescriptor()
        window.colorAttachments[0].texture = drawable.texture
        (window.colorAttachments[0].loadAction, window.colorAttachments[0].storeAction) = (.clear, .store)
        window.colorAttachments[0].clearColor = clearColor
        // The drawable's own size: `metalLink`'s may be from before the screen turned.
        let size = CGSize(width: drawable.texture.width, height: drawable.texture.height)
        let screen = loop.screen
        screen.begin(commands, window)
        #if os(iOS)
        screen.encoder.setViewport(fit(screen.size, in: size))
        #else
        screen.encoder.setViewport(letterbox(screen.size, in: size))
        #endif
        screen.quad(screen.canvas, x: 0, y: 0, source: Rect(x: 0, y: 0, width: screen.size.width, height: screen.size.height))
        screen.end()
        commands.present(drawable)
    }
}

#if os(iOS)
extension GameView: @preconcurrency CAMetalDisplayLinkDelegate {
    /// A frame for the screen, with the drawable it will show in and when (`metalLink` is on the main run loop).
    func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        shows = update.targetPresentationTimestamp
        frame { update.drawable }
    }
}
#endif

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
