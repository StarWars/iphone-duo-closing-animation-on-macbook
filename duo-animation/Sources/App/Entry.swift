import AppKit

@main
struct Entry {
    @MainActor static func main() {
        if let flag = CommandLine.arguments.firstIndex(of: "--verify"), flag + 1 < CommandLine.arguments.count {
            do {
                try Verification.run(directory: URL(fileURLWithPath: CommandLine.arguments[flag + 1], isDirectory: true))
                exit(0)
            } catch {
                print("Verification failed: \(error.localizedDescription)")
                exit(1)
            }
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
