import AppKit

final class OverlayWindow: NSPanel {
    let glass: GlassView
    init(screen: NSScreen, renderer: GlassRenderer) {
        glass = GlassView(renderer: renderer)
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        contentView = glass
        level = .screenSaver
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        // A frozen, warped desktop has no matching click targets. Consume clicks
        // instead of letting a misleading visual trigger actions in underlying apps.
        ignoresMouseEvents = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
        // Feedback protection comes from the ScreenCaptureKit filter, not sharingType.
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
