import AppKit
import MetalKit

final class GlassView: MTKView, @MainActor MTKViewDelegate {
    let renderer: GlassRenderer
    var onOverlayClick: (@MainActor () -> Void)?
    var onFrame: (@MainActor () -> EffectState)?
    var effect = EffectState() {
        didSet { if oldValue != effect && isPaused { needsDisplay = true } }
    }

    init(renderer: GlassRenderer) {
        self.renderer = renderer
        super.init(frame: .zero, device: renderer.device)
        delegate = self
        colorPixelFormat = .bgra8Unorm
        colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        framebufferOnly = true
        isPaused = true
        enableSetNeedsDisplay = true
        clearColor = MTLClearColorMake(0.035, 0.044, 0.060, 1)
        preferredFramesPerSecond = 60
        autoResizeDrawable = false
        autoresizingMask = [.width, .height]
    }

    required init(coder: NSCoder) { fatalError("GlassView uses its programmatic initializer") }
    func setAnimating(_ value: Bool) {
        guard value == isPaused else { return }
        isPaused = !value
        enableSetNeedsDisplay = !value
    }

    func refreshPausedFrame() {
        needsDisplay = true
        // Manual controls must render during slider tracking even after sensor
        // presentation has stopped. MTKView.draw() supports explicit drawing
        // while paused; a deferred AppKit repaint alone can leave a stale frame.
        if isPaused, window != nil { draw() }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateDrawableSize()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateDrawableSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
    }

    private func updateDrawableSize() {
        // Screenshots are at most 1600 px wide. Rendering them at 3K/6K adds
        // fragment cost without recovering any detail, especially on M1 GPUs.
        let backing = convertToBacking(bounds.size)
        guard backing.width > 0, backing.height > 0 else { return }
        let scale = min(1, 1600 / backing.width)
        drawableSize = CGSize(width: (backing.width * scale).rounded(),
                              height: (backing.height * scale).rounded())
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        onOverlayClick != nil || super.acceptsFirstMouse(for: event)
    }
    override func mouseDown(with event: NSEvent) {
        if let onOverlayClick { onOverlayClick() } else { super.mouseDown(with: event) }
    }
    override func rightMouseDown(with event: NSEvent) {
        if let onOverlayClick { onOverlayClick() } else { super.rightMouseDown(with: event) }
    }
    override func otherMouseDown(with event: NSEvent) {
        if let onOverlayClick { onOverlayClick() } else { super.otherMouseDown(with: event) }
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        if let onFrame { effect = onFrame() }
        guard let drawable = view.currentDrawable else { return }
        _ = renderer.encode(target: drawable.texture, state: effect, drawable: drawable)
    }
}
