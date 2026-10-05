import AppKit

@MainActor
enum Verification {
    struct Failure: LocalizedError {
        let reason: String
        var errorDescription: String? { reason }
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure(reason: message) }
        print("PASS: \(message)")
    }

    static func run(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let renderer = try GlassRenderer()
        print("GPU: \(renderer.device.name)")
        try renderer.prepare(SampleDesktop.make())
        var screen = EffectState()
        screen.preview = false
        let reference = try renderer.offscreen(state: screen)
        print("Preparation CPU: \(renderer.preparationCPUMilliseconds) ms; GPU: \(renderer.preparationGPUMilliseconds) ms; retained textures: \(renderer.textureBytes) bytes")
        var preparationCPU: [Double] = [], preparationGPU: [Double] = []
        let sample = try SampleDesktop.make()
        for _ in 0..<7 {
            try renderer.prepare(sample)
            _ = try renderer.offscreen(state: screen)
            preparationCPU.append(renderer.preparationCPUMilliseconds)
            preparationGPU.append(renderer.preparationGPUMilliseconds)
        }
        print("Warm preparation median CPU: \(preparationCPU.sorted()[3]) ms; GPU: \(preparationGPU.sorted()[3]) ms")
        try reference.write(to: directory.appendingPathComponent("screen-open.png"))
        renderer.clear()
        let cleared = try renderer.offscreen(state: screen)
        let blankPixel = Array(cleared.bytes.prefix(4))
        try check(blankPixel[0] < 20 && blankPixel[1] < 20 && blankPixel[2] < 20 && blankPixel[3] == 255 &&
                  stride(from: 0, to: cleared.bytes.count, by: 4).allSatisfy {
                      Array(cleared.bytes[$0..<($0 + 4)]) == blankPixel
                  }, "Clearing captured textures replaces every pixel with the blank background")
        try renderer.prepare(sample)
        var times: [Double] = []
        for angle: Float in [120, 105, 90, 89, 75, 60, 44, 30, 20, 10] {
            var state = EffectState()
            state.angle = angle
            let image = try renderer.offscreen(state: state, width: 1600, height: 1120)
            try image.write(to: directory.appendingPathComponent("preview-\(Int(angle)).png"))
            times.append(image.gpuMilliseconds)
            state.preview = false
            let physical = try renderer.offscreen(state: state)
            try physical.write(to: directory.appendingPathComponent("screen-\(Int(angle)).png"))
        }
        screen.angle = 60
        let closing = try renderer.offscreen(state: screen)
        screen.angle = 30
        _ = try renderer.offscreen(state: screen)
        screen.angle = 60
        let opening = try renderer.offscreen(state: screen)
        try check(closing.bytes == opening.bytes, "Reopening to the same angle reproduces identical pixels")
        screen.angle = 120
        let reopened = try renderer.offscreen(state: screen)
        try check(reference.bytes == reopened.bytes, "Returning to the reference restores the original render")
        // Avoid the outermost texel, whose transparent boundary is intentionally antialiased.
        screen.angle = 75
        let moderate = try renderer.offscreen(state: screen)
        let bottomError = difference(reference, moderate, rows: 998..<999, columns: 400..<1200)
        try check(bottomError < 2.5, "The bottom edge stays anchored at the hinge (mean channel error \(String(format: "%.3f", bottomError)))")

        // Project stationary desktop landmarks onto the moving physical lid
        // independently of the shader, then inspect its compensating pixels.
        try renderer.prepare(planeCalibration())
        var registration = EffectState()
        registration.preview = false
        registration.softness = 0
        registration.shade = 0
        let grid = try renderer.offscreen(state: registration)
        try grid.write(to: directory.appendingPathComponent("plane-calibration-90.png"))
        var previewRegistration = registration
        previewRegistration.preview = true
        let stationary = try renderer.offscreen(state: previewRegistration)
        for angle: Float in [89, 75, 60, 44] {
            previewRegistration.angle = angle
            let movingLid = try renderer.offscreen(state: previewRegistration)
            // This interior strip remains covered by the physical panel at
            // each angle. Its asymmetric desktop landmarks must not move.
            let error = difference(stationary, movingLid, rows: 730..<780, columns: 560..<1040)
            try check(error < 0.01, "Preview content stays stationary as the lid folds at \(Int(angle)) degrees (mean channel error \(String(format: "%.5f", error)))")
            try check(movingLid.bytes != stationary.bytes, "Preview lid boundary moves at \(Int(angle)) degrees")
        }
        for angle: Float in [89, 75, 60, 44] {
            registration.angle = angle
            let fitted = try renderer.offscreen(state: registration)
            let radians = Double(90 - angle) * .pi / 180
            let c = cos(radians), s = sin(radians)
            var largestError = 0
            var visibleProbes = 0
            for y in [0.02, 0.25, 0.5, 0.75, 0.98] {
                for x in [0.02, 0.25, 0.5, 0.75, 0.98] {
                    // Eye-to-reference ray intersects the physical panel.
                    // Occluded landmarks must not be fitted back into view.
                    let fromHinge = 1 - y
                    let t = (1.8 * c - 1.35 * s) / (1.8 * c - (1.35 - fromHinge) * s)
                    let projectedX = 0.5 + (x - 0.5) * t
                    let projectedY = 1 - ((1.35 + (fromHinge - 1.35) * t) * c + 1.8 * (1 - t) * s)
                    guard t > 0, (0.01...0.99).contains(projectedX),
                          (0.01...0.99).contains(projectedY) else { continue }
                    visibleProbes += 1
                    largestError = max(largestError, pixelError(grid, x: x, y: y,
                        fitted, x: projectedX, y: projectedY))
                }
            }
            try check(visibleProbes >= 5 && largestError <= 1, "Physical lid preserves stationary desktop at \(Int(angle)) degrees (\(visibleProbes) visible GPU landmarks, maximum channel error \(largestError))")
            try fitted.write(to: directory.appendingPathComponent("plane-calibration-\(Int(angle)).png"))
        }
        registration.angle = 60
        registration.perspective = 0
        let flat = try renderer.offscreen(state: registration)
        try check(flat.bytes == grid.bytes, "Zero Depth disables the entire perspective transform")

        registration.perspective = 1
        registration.angle = 75
        let defaultFold = try renderer.offscreen(state: registration)
        for trigger: Float in [30, 75, 110, 140] {
            registration.referenceAngle = trigger
            registration.angle = trigger
            let atTrigger = try renderer.offscreen(state: registration)
            try check(atTrigger.bytes == grid.bytes, "Custom trigger \(Int(trigger)) restores the complete desktop at its boundary")
            registration.angle = trigger + 5
            let aboveTrigger = try renderer.offscreen(state: registration)
            try check(aboveTrigger.bytes == grid.bytes, "Custom trigger \(Int(trigger)) remains flat above its boundary")
            // Compensation uses measured angular travel, independently of
            // the trigger-normalized blur/fade interval.
            registration.angle = trigger - 15
            let customFold = try renderer.offscreen(state: registration)
            let error = difference(defaultFold, customFold, rows: 1..<999, columns: 1..<1599)
            try check(error < 0.02, "Custom trigger \(Int(trigger)) compensates actual 15-degree lid travel (mean channel error \(String(format: "%.5f", error)))")
            try customFold.write(to: directory.appendingPathComponent("trigger-\(Int(trigger))-plane.png"))
            registration.angle = 10
            let customClosed = try renderer.offscreen(state: registration)
            try check(customClosed.bytes.enumerated().allSatisfy { $0.offset % 4 == 3 || $0.element == 0 },
                      "Custom trigger \(Int(trigger)) fades to black by 10 degrees with blur/shade disabled")
        }

        try renderer.prepare(SampleDesktop.make(calibration: true))
        var calibration = EffectState()
        calibration.preview = false
        calibration.perspective = 0
        calibration.shade = 0
        calibration.angle = 60
        let blurred = try renderer.offscreen(state: calibration)
        let upper = contrast(blurred, row: 120)
        let lower = contrast(blurred, row: 900)
        try check(Double(upper) < Double(lower) * 0.35, "Blur is stronger far from the hinge (upper \(upper), lower \(lower))")
        try blurred.write(to: directory.appendingPathComponent("blur-calibration.png"))
        calibration.angle = 120
        let sharp = try renderer.offscreen(state: calibration)
        try check(contrast(sharp, row: 120) > 240, "The open screen remains sharp")
        calibration.angle = 20
        let disappearing = try renderer.offscreen(state: calibration)
        let bottomContrast = contrast(disappearing, row: 975)
        try check(bottomContrast < 20, "Late blur reaches the bottom edge, including with shade disabled (contrast \(bottomContrast))")
        try disappearing.write(to: directory.appendingPathComponent("blur-bottom-calibration.png"))
        calibration.angle = 10
        let closed = try renderer.offscreen(state: calibration)
        try check(closed.bytes.enumerated().allSatisfy { $0.offset % 4 == 3 || $0.element == 0 }, "Content has disappeared before the near-closure safety cutoff")

        var gesture = GestureTracker()
        gesture.reset(at: 120)
        try check(gesture.update(90) == .idle, "No overlay at or above 90 degrees")
        try check(gesture.update(89.999) == .bending(reference: 90, angle: 89.999), "Closing starts strictly below 90 degrees")
        try check(gesture.update(70) == .bending(reference: 90, angle: 70), "Closing follows current position")
        try check(gesture.update(70) == .bending(reference: 90, angle: 70), "Holding the lid holds the effect")
        try check(gesture.update(85) == .bending(reference: 90, angle: 85), "Partial reopening keeps the fixed 90-degree reference")
        try check(gesture.update(120) == .idle, "Reopening clears the overlay")
        try check(gesture.update(8) == .closed && !gesture.active, "Near closure fails closed")
        try check(gesture.update(.nan) == .invalid, "Invalid sensor values are rejected")
        print("Median preview GPU pass: \(String(format: "%.3f", times.sorted()[times.count / 2])) ms")
        print("Permission check (no prompt): \(DesktopSnapshot.hasPermission ? "already granted" : "not granted")")
        print("No desktop capture, sensor opening or system-permission requests occurred during verification.")
        try renderer.prepare(SampleDesktop.make())
        let sequence = directory.appendingPathComponent("sequence", isDirectory: true)
        try FileManager.default.createDirectory(at: sequence, withIntermediateDirectories: true)
        for frame in 0..<120 {
            let phase = Double(frame) / 119
            var state = EffectState()
            state.angle = Float(100 - 90 * (1 - cos(phase * 2 * .pi)) * 0.5)
            let image = try renderer.offscreen(state: state, width: 960, height: 600)
            try image.write(to: sequence.appendingPathComponent(String(format: "%04d.png", frame)))
        }
        print("Saved a reversible preview sequence for visual inspection.")
        let sensorSequence = directory.appendingPathComponent("sensor-sequence", isDirectory: true)
        try FileManager.default.createDirectory(at: sensorSequence, withIntermediateDirectories: true)
        var filter = AngleFilter()
        var trace = "frame,time,simulated_raw_degrees,presented_degrees\n"
        for frame in 0..<240 {
            let time = Double(frame) / 60
            // Deliberately coarse, repeated whole-degree reports at 12 Hz,
            // with a hold and partial reopening. This is not hardware telemetry.
            let sampleTime = floor(time * 12) / 12
            let raw: Double
            switch sampleTime {
            case ..<0.3: raw = 100
            case ..<1.5: raw = (100 - (sampleTime - 0.3) / 1.2 * 75).rounded()
            case ..<2.0: raw = 25
            case ..<3.5: raw = (25 + (sampleTime - 2) / 1.5 * 75).rounded()
            default: raw = 100
            }
            if raw >= 90 { filter.reset() }
            let presented = filter.update(min(90, raw), time: time) ?? 90
            var state = EffectState()
            state.angle = Float(raw >= 90 ? 90 : presented)
            let image = try renderer.offscreen(state: state, width: 960, height: 600)
            try image.write(to: sensorSequence.appendingPathComponent(String(format: "%04d.png", frame)))
            trace += "\(frame),\(time),\(raw),\(state.angle)\n"
        }
        try trace.write(to: directory.appendingPathComponent("simulated-sensor-angles.csv"), atomically: true, encoding: .utf8)
        print("Saved a 60 Hz preview driven by simulated 12 Hz whole-degree readings, including hold/reversal.")
        try slowSensorSequence(renderer: renderer, directory: directory)
    }

    private static func slowSensorSequence(renderer: GlassRenderer, directory: URL) throws {
        let sequence = directory.appendingPathComponent("slow-sensor-sequence", isDirectory: true)
        try FileManager.default.createDirectory(at: sequence, withIntermediateDirectories: true)
        var filter = AngleFilter()
        var previous = 70.0
        var largestStep = 0.0
        var movingFrames = 0
        var held: RenderedImage?
        var trace = "frame,time,simulated_raw_degrees,presented_degrees,response_seconds,drawing_active\n"
        for frame in 0..<1080 {
            let time = Double(frame) / 60
            // Healthy sensor polling continues through a held value, including
            // while drawing is paused. Distinct reports change only every 2 s.
            let sampleTime = floor(time * 12) / 12
            let raw: Double
            switch sampleTime {
            case ..<8: raw = 70 - min(3, floor(sampleTime / 2))
            case ..<10: raw = 67
            default: raw = 67 + min(3, floor((sampleTime - 8) / 2))
            }
            filter.ingest(raw, time: time)
            let drawing = !filter.isSettled
            let presented = drawing ? (filter.sample(at: time) ?? raw) : (filter.value ?? raw)
            try checkWithinMeasurement(presented, previous: previous, raw: raw)
            largestStep = max(largestStep, abs(presented - previous))
            if frame >= 240 && frame < 360 && abs(presented - previous) > 0.0001 { movingFrames += 1 }
            previous = presented
            var state = EffectState()
            state.angle = Float(presented)
            if drawing || held == nil {
                held = try renderer.offscreen(state: state, width: 960, height: 600)
            }
            try held?.write(to: sequence.appendingPathComponent(String(format: "%04d.png", frame)))
            trace += "\(frame),\(time),\(raw),\(presented),\(filter.responseTime),\(drawing)\n"
        }
        try check(largestStep < 0.035, "One degree per two seconds has no large frame jumps (maximum \(String(format: "%.5f", largestStep)) degrees)")
        try check(movingFrames > 100, "Slow two-second steps have sustained fractional motion (\(movingFrames)/120 moving frames)")
        try check(filter.isSettled && filter.value == 70, "Slow reopening settles exactly and pauses drawing")
        try trace.write(to: directory.appendingPathComponent("simulated-slow-sensor-angles.csv"), atomically: true, encoding: .utf8)
        print("Saved an 18-second 60 Hz slow-motion preview: one degree every two seconds, held-angle draw pauses and partial reopening.")
    }

    private static func checkWithinMeasurement(_ value: Double, previous: Double, raw: Double) throws {
        guard value >= min(previous, raw) && value <= max(previous, raw) else {
            throw Failure(reason: "Slow presentation overshot its measured interval")
        }
    }

    private static func difference(_ lhs: RenderedImage, _ rhs: RenderedImage,
                                   rows: Range<Int>, columns: Range<Int>) -> Double {
        var sum = 0.0
        for y in rows {
            for x in columns {
                let offset = (y * lhs.width + x) * 4
                for channel in 0..<3 { sum += abs(Double(lhs.bytes[offset + channel]) - Double(rhs.bytes[offset + channel])) }
            }
        }
        return sum / Double(rows.count * columns.count * 3)
    }

    private static func contrast(_ image: RenderedImage, row: Int) -> Int {
        let values = (400..<1200).map { Int(image.bytes[(row * image.width + $0) * 4]) }
        return (values.max() ?? 0) - (values.min() ?? 0)
    }

    private static func pixelError(_ lhs: RenderedImage, x lhsX: Double, y lhsY: Double,
                                   _ rhs: RenderedImage, x rhsX: Double, y rhsY: Double) -> Int {
        let lhsOffset = (Int(lhsY * Double(lhs.height)) * lhs.width + Int(lhsX * Double(lhs.width))) * 4
        let rhsOffset = (Int(rhsY * Double(rhs.height)) * rhs.width + Int(rhsX * Double(rhs.width))) * 4
        return (0..<3).map { abs(Int(lhs.bytes[lhsOffset + $0]) - Int(rhs.bytes[rhsOffset + $0])) }.max() ?? 0
    }

    private static func planeCalibration() throws -> CGImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: 1600, height: 1000,
                                      bitsPerComponent: 8, bytesPerRow: 1600 * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw GlassRenderer.Failure.image }
        let colors: [NSColor] = [.red, .green, .blue, .yellow, .magenta, .cyan,
                                NSColor(red: 1, green: 0.5, blue: 0, alpha: 1),
                                NSColor(red: 0.5, green: 0, blue: 1, alpha: 1), .lightGray]
        for row in 0..<3 {
            for column in 0..<3 {
                context.setFillColor(colors[row * 3 + column].cgColor)
                let tile = CGRect(x: Double(column) * 1600 / 3, y: Double(row) * 1000 / 3,
                                  width: 1600.0 / 3, height: 1000.0 / 3)
                context.fill(tile)
                context.setStrokeColor(NSColor.white.cgColor)
                context.setLineWidth(4)
                context.stroke(tile.insetBy(dx: 2, dy: 2))
            }
        }
        guard let image = context.makeImage() else { throw GlassRenderer.Failure.image }
        return image
    }
}
