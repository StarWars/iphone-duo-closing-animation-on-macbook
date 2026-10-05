import AppKit

@MainActor
enum AppBrand {
    static let headline = "iPhone motion, reimagined for Mac. Created with curiosity by Michał Stawarz."
    static let linkedInURL = URL(string: "https://pl.linkedin.com/in/michal-stawarz-86726830")!

    static var icon: NSImage {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) { return image }
        return NSImage(systemSymbolName: "macbook", accessibilityDescription: "Duo Lid") ?? NSImage()
    }

    static var linkedInIcon: NSImage {
        let image = NSImage(size: NSSize(width: 24, height: 24))
        image.lockFocus()
        NSColor(red: 0.039, green: 0.400, blue: 0.761, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 24, height: 24), xRadius: 3, yRadius: 3).fill()
        ("in" as NSString).draw(at: NSPoint(x: 4, y: 2), withAttributes: [
            .font: NSFont.systemFont(ofSize: 19, weight: .bold), .foregroundColor: NSColor.white
        ])
        image.unlockFocus()
        return image
    }

    static func openLinkedIn() { NSWorkspace.shared.open(linkedInURL) }

    static func showAbout() {
        let credits = NSMutableAttributedString(string: "Created by Michal Stawarz, 2026\n\nEnjoying the app?\nI'd love to hear from you on LinkedIn")
        let text = credits.string as NSString
        credits.addAttribute(.link, value: linkedInURL, range: text.range(of: "I'd love to hear from you on LinkedIn"))
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Duo Lid", .applicationIcon: icon,
            .credits: credits
        ])
    }
}
