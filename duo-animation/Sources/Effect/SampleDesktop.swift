import AppKit

@MainActor
enum SampleDesktop {
    static func make(width: Int = 1600, height: Int = 1000, calibration: Bool = false) throws -> CGImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw GlassRenderer.Failure.image }
        if calibration {
            for x in stride(from: 0, to: width, by: 12) {
                context.setFillColor((x / 12).isMultiple(of: 2) ? NSColor.white.cgColor : NSColor.black.cgColor)
                context.fill(CGRect(x: x, y: 0, width: 12, height: height))
            }
        } else {
            context.scaleBy(x: CGFloat(width) / 1600, y: CGFloat(height) / 1000)
            let sky = [NSColor(red: 0.30, green: 0.46, blue: 0.55, alpha: 1).cgColor,
                       NSColor(red: 0.76, green: 0.72, blue: 0.57, alpha: 1).cgColor,
                       NSColor(red: 0.90, green: 0.78, blue: 0.56, alpha: 1).cgColor]
            if let gradient = CGGradient(colorsSpace: space, colors: sky as CFArray, locations: [0, 0.65, 1]) {
                context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 1000),
                                           end: CGPoint(x: 0, y: 330), options: [.drawsAfterEndLocation])
            }
            mountain(context, base: 395, amplitude: 78, phase: 0.8,
                     color: NSColor(red: 0.32, green: 0.31, blue: 0.25, alpha: 1))
            mountain(context, base: 345, amplitude: 63, phase: 2.1,
                     color: NSColor(red: 0.23, green: 0.23, blue: 0.21, alpha: 1))
            dune(context, points: [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 390),
                                  CGPoint(x: 450, y: 300), CGPoint(x: 960, y: 180),
                                  CGPoint(x: 1600, y: 140), CGPoint(x: 1600, y: 0)],
                 top: NSColor(red: 0.83, green: 0.73, blue: 0.56, alpha: 1),
                 bottom: NSColor(red: 0.48, green: 0.39, blue: 0.28, alpha: 1), space: space)
            dune(context, points: [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 65),
                                  CGPoint(x: 520, y: 145), CGPoint(x: 1160, y: 350),
                                  CGPoint(x: 1600, y: 450), CGPoint(x: 1600, y: 0)],
                 top: NSColor(red: 0.86, green: 0.77, blue: 0.61, alpha: 1),
                 bottom: NSColor(red: 0.61, green: 0.51, blue: 0.37, alpha: 1), space: space)
            let graphics = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            text("Friday, October 2", font: .systemFont(ofSize: 25, weight: .medium),
                 rect: CGRect(x: 0, y: 790, width: 1600, height: 42), alignment: .center)
            text("9:41", font: .systemFont(ofSize: 190, weight: .ultraLight),
                 rect: CGRect(x: 0, y: 580, width: 1600, height: 235), alignment: .center)
            text("Finder   File   Edit   View   Go   Window   Help", font: .systemFont(ofSize: 15, weight: .medium),
                 rect: CGRect(x: 28, y: 966, width: 650, height: 25), alignment: .left)
            text("100%    Fri 2 Oct  9:41", font: .systemFont(ofSize: 15, weight: .medium),
                 rect: CGRect(x: 1190, y: 966, width: 382, height: 25), alignment: .right)
            context.setFillColor(NSColor.white.withAlphaComponent(0.16).cgColor)
            context.addPath(CGPath(roundedRect: CGRect(x: 535, y: 22, width: 530, height: 74),
                                   cornerWidth: 23, cornerHeight: 23, transform: nil))
            context.fillPath()
            for (index, color) in [NSColor.systemBlue, .systemOrange, .systemPurple, .systemMint,
                                   .systemYellow, .systemPink, .systemGray, .systemTeal].enumerated() {
                context.setFillColor(color.withAlphaComponent(0.88).cgColor)
                context.addPath(CGPath(roundedRect: CGRect(x: 553 + index * 62, y: 35, width: 49, height: 49),
                                       cornerWidth: 12, cornerHeight: 12, transform: nil))
                context.fillPath()
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        guard let image = context.makeImage() else { throw GlassRenderer.Failure.image }
        return image
    }

    private static func mountain(_ context: CGContext, base: Double, amplitude: Double,
                                 phase: Double, color: NSColor) {
        context.beginPath()
        context.move(to: .zero)
        for x in stride(from: 0.0, through: 1600, by: 8) {
            let y = base + sin(x / 170 + phase) * amplitude + sin(x / 37 + phase) * 11 + sin(x / 19) * 7
            context.addLine(to: CGPoint(x: x, y: y))
        }
        context.addLine(to: CGPoint(x: 1600, y: 0))
        context.closePath()
        context.setFillColor(color.cgColor)
        context.fillPath()
    }

    private static func dune(_ context: CGContext, points: [CGPoint], top: NSColor,
                             bottom: NSColor, space: CGColorSpace) {
        context.saveGState()
        context.beginPath()
        context.move(to: points[0])
        context.addLine(to: points[1])
        context.addCurve(to: points[4], control1: points[2], control2: points[3])
        context.addLine(to: points[5])
        context.closePath()
        context.clip()
        if let gradient = CGGradient(colorsSpace: space, colors: [bottom.cgColor, top.cgColor] as CFArray,
                                     locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 600, y: 430),
                                       options: [.drawsAfterEndLocation, .drawsBeforeStartLocation])
        }
        context.restoreGState()
    }

    private static func text(_ value: String, font: NSFont, rect: CGRect, alignment: NSTextAlignment) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        (value as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: NSColor.white,
                                                           .paragraphStyle: paragraph])
    }
}
