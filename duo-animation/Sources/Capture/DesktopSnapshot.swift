import AppKit
import ScreenCaptureKit

@MainActor
enum DesktopSnapshot {
    enum Failure: LocalizedError {
        case permission
        case display
        var errorDescription: String? {
            switch self {
            case .permission: "Screen Recording is off. Allow Duo Lid in System Settings, then try again."
            case .display: "The built-in display is unavailable or mirrored. The sample preview still works."
            }
        }
    }

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }
    static var sessionIsActive: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session[kCGSessionOnConsoleKey as String] as? Bool == true &&
            session[kCGSessionLoginDoneKey as String] as? Bool == true
    }
    private static var requestedThisSession = false

    // Called only in response to an explicit desktop-preview/enable action.
    static func requestPermissionIfNeeded() -> Bool {
        if hasPermission { return true }
        guard !requestedThisSession else { return false }
        requestedThisSession = true
        return CGRequestScreenCaptureAccess()
    }

    static func builtInScreen() -> NSScreen? {
        NSScreen.screens.first {
            guard let id = displayID($0) else { return false }
            return CGDisplayIsBuiltin(id) != 0 && CGDisplayIsActive(id) != 0 &&
                CGDisplayIsAsleep(id) == 0 && CGDisplayIsInMirrorSet(id) == 0
        }
    }

    static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static func capture(screen: NSScreen) async throws -> CGImage {
        // Never let an incidental capture attempt produce a permission prompt.
        guard hasPermission else { throw Failure.permission }
        guard sessionIsActive else { throw Failure.display }
        guard let id = displayID(screen) else { throw Failure.display }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        guard let display = content.displays.first(where: { $0.displayID == id }) else { throw Failure.display }
        // Keep normal Duo Lid windows in the desktop image. Exclude only the
        // effect panels so capturing cannot feed a previous overlay back into it.
        let overlayIDs = Set(NSApp.windows.compactMap { window -> CGWindowID? in
            guard window is OverlayWindow, window.windowNumber > 0 else { return nil }
            return CGWindowID(window.windowNumber)
        })
        let excluded = content.windows.filter { overlayIDs.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)
        let configuration = SCStreamConfiguration()
        configuration.width = min(1600, display.width)
        configuration.height = max(1, Int(Double(configuration.width) * Double(display.height) / Double(display.width)))
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        try Task.checkCancellation()
        return image
    }
}
