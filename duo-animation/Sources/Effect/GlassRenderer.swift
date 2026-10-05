import AppKit
import MetalKit
import MetalPerformanceShaders

@MainActor
final class GlassRenderer {
    enum Failure: LocalizedError {
        case unavailable
        case allocation
        case image
        var errorDescription: String? {
            switch self {
            case .unavailable: "Metal is unavailable on this Mac."
            case .allocation: "The image could not be prepared. Try again with other apps closed."
            case .image: "The image could not be loaded."
            }
        }
    }

    let device: any MTLDevice
    private let queue: any MTLCommandQueue
    private let pipeline: any MTLRenderPipelineState
    private var levels: [any MTLTexture] = []
    private var imageWidth = 1600
    private var imageHeight = 1000
    private var padding = 150
    private var maxSigma: Float = 50
    private var preparation: (any MTLCommandBuffer)?
    private(set) var preparationCPUMilliseconds = 0.0
    var preparationGPUMilliseconds: Double {
        guard let preparation, preparation.status == .completed else { return 0 }
        return max(0, (preparation.gpuEndTime - preparation.gpuStartTime) * 1000)
    }
    var textureBytes: Int { levels.reduce(0) { $0 + $1.width * $1.height * 4 } }

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let shaderURL = Bundle.main.url(forResource: "Glass.metal", withExtension: "txt") else { throw Failure.unavailable }
        let source = try String(contentsOf: shaderURL, encoding: .utf8)
        // Compiled once by the system's Metal driver; no optional Xcode Metal toolchain is needed.
        let library = try device.makeLibrary(source: source, options: nil)
        self.device = device
        self.queue = queue
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "glassVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "glassFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    }

    func prepare(_ image: CGImage) throws {
        let started = CACurrentMediaTime()
        let loader = MTKTextureLoader(device: device)
        let input = try loader.newTexture(cgImage: image, options: [.SRGB: false])
        imageWidth = image.width
        imageHeight = image.height
        maxSigma = Float(imageHeight) * 0.05
        padding = Int(ceil(maxSigma * 3)) + 2
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: input.pixelFormat, width: imageWidth + 2 * padding,
            height: imageHeight + 2 * padding, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.usage.insert(.renderTarget)
        descriptor.storageMode = .private
        guard let original = device.makeTexture(descriptor: descriptor),
              let command = queue.makeCommandBuffer()
        else { throw Failure.allocation }
        // Clear padding on the GPU instead of allocating/copying a large CPU zero buffer.
        let clear = MTLRenderPassDescriptor()
        clear.colorAttachments[0].texture = original
        clear.colorAttachments[0].loadAction = .clear
        clear.colorAttachments[0].storeAction = .store
        clear.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        guard let clearing = command.makeRenderCommandEncoder(descriptor: clear) else { throw Failure.allocation }
        clearing.endEncoding()
        guard let blit = command.makeBlitCommandEncoder() else { throw Failure.allocation }
        blit.copy(from: input, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: imageWidth, height: imageHeight, depth: 1),
                  to: original, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: MTLOrigin(x: padding, y: padding, z: 0))
        blit.endEncoding()
        var prepared: [any MTLTexture] = [original]
        let fullWidth = descriptor.width, fullHeight = descriptor.height
        for (index, factor) in [Float(0.03125), 0.0625, 0.125, 0.25, 0.5, 1].enumerated() {
            // Increasing sigma needs progressively less spatial resolution.
            // Keep every level in the same normalized padded coordinate system.
            let divisor = 1 << (index + 1)
            descriptor.width = max(1, (fullWidth + divisor - 1) / divisor)
            descriptor.height = max(1, (fullHeight + divisor - 1) / divisor)
            guard let scaled = device.makeTexture(descriptor: descriptor),
                  let texture = device.makeTexture(descriptor: descriptor) else { throw Failure.allocation }
            // Successive half-scales of the previous filtered image prevent
            // aliased text/moire at the very small, heavily blurred levels.
            MPSImageBilinearScale(device: device).encode(commandBuffer: command,
                sourceTexture: prepared[index], destinationTexture: scaled)
            let incrementalSigma: Float = index == 0 ? 1 : sqrt(0.75)
            let blur = MPSImageGaussianBlur(device: device,
                sigma: maxSigma * factor * Float(descriptor.height) / Float(fullHeight) * incrementalSigma)
            blur.edgeMode = .zero
            blur.encode(commandBuffer: command, sourceTexture: scaled, destinationTexture: texture)
            prepared.append(texture)
        }
        command.label = "Prepare temporary blur textures"
        command.commit()
        // The same command queue orders preparation before any draw. No main-thread GPU wait.
        levels = prepared
        preparation = command
        preparationCPUMilliseconds = (CACurrentMediaTime() - started) * 1000
    }

    func clear() { levels.removeAll(); preparation = nil }

    func encode(target: any MTLTexture, state: EffectState,
                drawable: (any CAMetalDrawable)? = nil) -> (any MTLCommandBuffer)? {
        guard let command = queue.makeCommandBuffer() else { return nil }
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.035, 0.044, 0.060, 1)
        guard let encoder = command.makeRenderCommandEncoder(descriptor: descriptor) else { return nil }
        guard levels.count == 7 else {
            // Cleared desktop textures must produce a fresh blank drawable,
            // never leave the previous captured image displayed after a reset.
            encoder.endEncoding()
            if let drawable { command.present(drawable) }
            command.label = "Clear preview"
            command.commit()
            return command
        }
        let aspect = Float(imageWidth) / Float(imageHeight)
        let outputAspect = Float(target.width) / Float(target.height)
        var stageWidth: Float = 0.68
        var stageHeight = stageWidth * outputAspect / aspect
        if stageHeight > 0.84 {
            stageHeight = 0.84
            stageWidth = stageHeight * aspect / outputAspect
        }
        var uniforms = EffectUniforms(
            angles: SIMD4(state.angle, state.referenceAngle, state.perspective, state.softness),
            style: SIMD4(state.shade, 1.35, 1.8, aspect),
            content: SIMD4(Float(imageWidth), Float(imageHeight), Float(padding), maxSigma),
            stage: SIMD4((1 - stageWidth) * 0.5, (1 - stageHeight) * 0.5, stageWidth, stageHeight),
            presentation: SIMD4(state.preview ? 1 : 0, Float(target.width), Float(target.height), 0))
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<EffectUniforms>.stride, index: 0)
        for (index, texture) in levels.enumerated() { encoder.setFragmentTexture(texture, index: index) }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        if let drawable { command.present(drawable) }
        command.label = "Lid glass"
        command.commit()
        return command
    }

    // Only the explicit developer verification mode reads GPU output back or writes PNGs.
    func offscreen(state: EffectState, width: Int = 1600, height: Int = 1000) throws -> RenderedImage {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor),
              let command = encode(target: texture, state: state) else { throw Failure.allocation }
        command.waitUntilCompleted()
        if let error = command.error { throw error }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4,
                         from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return RenderedImage(width: width, height: height, bytes: bytes,
                             gpuMilliseconds: max(0, (command.gpuEndTime - command.gpuStartTime) * 1000))
    }
}

struct RenderedImage {
    let width: Int
    let height: Int
    let bytes: [UInt8]
    let gpuMilliseconds: Double

    func write(to url: URL) throws {
        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8,
                                  bitsPerPixel: 32, bytesPerRow: width * 4, space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
                                    .union(.byteOrder32Little),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw GlassRenderer.Failure.image }
        try png.write(to: url, options: .atomic)
    }
}
