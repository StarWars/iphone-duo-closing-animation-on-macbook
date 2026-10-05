import AppKit
import XCTest
@testable import DuoLid

final class PreviewDrawingTests: XCTestCase {
    @MainActor
    func testManualRefreshDrawsImmediatelyAfterContinuousRenderingStops() throws {
        let renderer = try GlassRenderer()
        let view = GlassView(renderer: renderer)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.close() }

        var presentedAngles: [Float] = []
        view.onFrame = {
            presentedAngles.append(view.effect.angle)
            return view.effect
        }
        view.setAnimating(true)
        view.setAnimating(false)
        XCTAssertTrue(view.isPaused)

        for angle: Float in [90, 60, 30, 90] {
            view.effect.angle = angle
            let previousCount = presentedAngles.count
            view.refreshPausedFrame()
            XCTAssertGreaterThan(presentedAngles.count, previousCount)
            XCTAssertEqual(presentedAngles.last, angle)
            XCTAssertTrue(view.isPaused, "Manual changes must not start continuous rendering")
        }
    }
}
