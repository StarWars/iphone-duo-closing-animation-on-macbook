import Foundation
import simd

struct EffectState: Sendable, Equatable {
    var angle: Float = 120
    var referenceAngle: Float = Float(LidTrigger.defaultAngle)
    var perspective: Float = 1
    var softness: Float = 1
    var shade: Float = 0.55
    var preview = true

    // Preserve the default effect's 80-degree visual range at any trigger,
    // reaching its final fade at the same physical near-closure angle.
    var fold: Float { max(0, min(120, (referenceAngle - angle) * 80 / max(1, referenceAngle - Float(LidTrigger.fadeAngle)))) }
}

// All fields are float4s so Swift and Metal agree on alignment.
struct EffectUniforms {
    var angles: SIMD4<Float>
    var style: SIMD4<Float>
    var content: SIMD4<Float>
    var stage: SIMD4<Float>
    var presentation: SIMD4<Float>
}
