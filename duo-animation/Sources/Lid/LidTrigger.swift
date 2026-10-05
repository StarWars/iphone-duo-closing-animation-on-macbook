import Foundation

struct LidTrigger: Sendable, Equatable {
    static let defaultAngle = 90.0
    static let range = 30.0...140.0
    static let fadeAngle = 10.0
    let angle: Double

    init(angle: Double = defaultAngle) {
        self.angle = angle.isFinite ? min(Self.range.upperBound, max(Self.range.lowerBound, angle.rounded())) : Self.defaultAngle
    }

    var approachUpperAngle: Double { angle + 10 }
    var degrees: Int { Int(angle) }

    func isOpen(_ reading: Double) -> Bool {
        reading.isFinite && (angle...180).contains(reading)
    }
}
