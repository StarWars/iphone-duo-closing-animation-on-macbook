import Foundation

struct GestureTracker: Sendable {
    enum Output: Equatable, Sendable {
        case idle
        case bending(reference: Double, angle: Double)
        case closed
        case invalid
    }

    private(set) var trigger: LidTrigger
    private(set) var reference: Double?
    private(set) var active = false
    private var awaitingOpen = false
    var closedAngle = 8.0

    init(trigger: LidTrigger = LidTrigger()) {
        self.trigger = trigger
        reference = trigger.angle
    }

    mutating func configure(trigger: LidTrigger) {
        self.trigger = trigger
        reset()
        awaitingOpen = true
    }

    mutating func reset(at angle: Double? = nil) {
        reference = trigger.angle
        active = false
        awaitingOpen = false
    }

    mutating func update(_ angle: Double) -> Output {
        guard angle.isFinite, (0...180).contains(angle) else { return .invalid }
        guard angle > closedAngle else {
            reset()
            reference = nil
            awaitingOpen = true
            return .closed
        }
        if trigger.isOpen(angle) {
            active = false
            awaitingOpen = false
            reference = trigger.angle
            return .idle
        }
        guard !awaitingOpen else { return .idle }
        reference = trigger.angle
        active = true
        return .bending(reference: trigger.angle, angle: angle)
    }
}

struct AngleFilter: Sendable {
    private(set) var value: Double?
    private var target: Double?
    private var velocity = 0.0
    private var lastTime: Double?
    private var lastReportTime: Double?
    private var lastChangeTime: Double?
    // Sparse one-degree reports need a longer transition than rapid motion.
    // Cadence comes from distinct sensor reports, never from display frames.
    private(set) var responseTime = 0.065
    var isSettled: Bool { value == target && velocity == 0 }

    mutating func reset() {
        value = nil; target = nil; velocity = 0; lastTime = nil
        lastReportTime = nil; lastChangeTime = nil; responseTime = 0.065
    }

    @discardableResult
    mutating func ingest(_ raw: Double, time: Double) -> Bool {
        guard raw.isFinite, time.isFinite, (0...180).contains(raw),
              time >= (lastReportTime ?? time) else { return false }
        lastReportTime = time
        guard let oldTarget = target else {
            value = raw
            target = raw
            lastTime = time
            return true
        }
        guard raw != oldTarget else { return true }
        let previous = value ?? raw
        // Complete time spent on the OLD target before adopting the new one.
        // A paused view must not apply its entire idle gap to the new reading.
        // On reversal, freeze the last presented value immediately instead of
        // spending another partial frame travelling away from the new target.
        if velocity * (raw - previous) < 0 {
            velocity = 0
            lastTime = max(lastTime ?? time, time)
        } else {
            _ = sample(at: time)
        }
        // A delayed report can put its target between the last visible value
        // and the old target. Do not integrate past that newly measured bound.
        value = max(min(previous, raw), min(max(previous, raw), value ?? raw))
        if value == raw { velocity = 0 }
        let step = abs(raw - oldTarget)
        if step <= 1.01 {
            let interval = lastChangeTime.map { max(0, time - $0) / step }
            responseTime = interval.map { min(0.55, max(0.065, $0 * 0.3)) } ?? 0.4
        } else {
            responseTime = 0.065
        }
        lastChangeTime = time
        target = raw
        // Discard momentum pointing away from a new target. Clamp to the measured
        // interval so reversals and holds never predict past a sensor reading.
        if velocity * (raw - (value ?? raw)) < 0 { velocity = 0 }
        return true
    }

    mutating func sample(at time: Double) -> Double? {
        guard time.isFinite, let raw = target, let previous = value,
              let previousTime = lastTime else { return nil }
        guard time > previousTime else { return previous }
        let omega = 2 / max(0.001, responseTime)
        let elapsed = time - previousTime
        let offset = previous - raw
        let coefficient = velocity + omega * offset
        let decay = exp(-omega * elapsed)
        let filtered = raw + (offset + coefficient * elapsed) * decay
        velocity = (velocity - omega * coefficient * elapsed) * decay
        value = max(min(previous, raw), min(max(previous, raw), filtered))
        if abs((value ?? raw) - raw) < 0.002 && abs(velocity) < 0.1 {
            value = raw
            velocity = 0
        }
        lastTime = time
        return value
    }

    // Convenience for generated traces and tests that supply a report per frame.
    mutating func update(_ raw: Double, time: Double) -> Double? {
        guard ingest(raw, time: time) else { return nil }
        return sample(at: time)
    }
}

enum LidReport {
    static func angle(bytes: [UInt8], length: Int) -> Double? {
        guard length >= 3, length <= bytes.count else { return nil }
        let degrees = UInt16(bytes[1]) | (UInt16(bytes[2]) << 8)
        guard degrees <= 180 else { return nil }
        return Double(degrees)
    }
}
