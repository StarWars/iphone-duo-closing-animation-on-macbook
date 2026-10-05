import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit-test hosts must not restore a user's background capture setting.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              NSClassFromString("XCTestCase") == nil else { return }
        do {
            NSApp.applicationIconImage = AppBrand.icon
            let controller = try AppController(renderer: GlassRenderer())
            self.controller = controller
            controller.start()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Duo Lid couldn't start"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.showWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) { controller?.shutdown() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
