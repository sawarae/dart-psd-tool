import Foundation
import Metal

/// Native Metal compositor for PSD blending (iOS).
///
/// Uses a Metal compute shader to perform PSDTool-compatible 3-component
/// alpha compositing on the GPU. All 26 PSD blend modes are supported.
public class PsdMetalCompositor {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLComputePipelineState

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw MetalError.noDevice
        }
        self.device = device

        guard let commandQueue = device.makeCommandQueue() else {
            throw MetalError.noCommandQueue
        }
        self.commandQueue = commandQueue

        // Load the Metal shader library from the plugin bundle
        let bundle = Bundle(for: PsdMetalCompositor.self)
        guard let libraryURL = bundle.url(forResource: "default", withExtension: "metallib")
              ?? bundle.url(forResource: "psd_composite", withExtension: "metallib") else {
            // Fallback: compile from source at runtime
            guard let metalURL = bundle.url(forResource: "psd_composite", withExtension: "metal") else {
                throw MetalError.noShaderSource
            }
            let source = try String(contentsOf: metalURL)
            let library = try device.makeLibrary(source: source, options: nil)
            guard let function = library.makeFunction(name: "psdComposite") else {
                throw MetalError.noFunction
            }
            self.pipelineState = try device.makeComputePipelineState(function: function)
            return
        }
        let library = try device.makeLibrary(URL: libraryURL)
        guard let function = library.makeFunction(name: "psdComposite") else {
            throw MetalError.noFunction
        }
        self.pipelineState = try device.makeComputePipelineState(function: function)
    }

    /// Composite src onto dst using the specified blend mode.
    func composite(
        srcBytes: Data,
        dstBytes: Data,
        width: Int,
        height: Int,
        blendMode: Int,
        opacity: Float
    ) throws -> Data {
        let pixelCount = width * height
        let bufferSize = pixelCount * 4

        guard srcBytes.count >= bufferSize, dstBytes.count >= bufferSize else {
            throw MetalError.invalidBufferSize
        }

        guard let srcBuffer = device.makeBuffer(bytes: (srcBytes as NSData).bytes,
                                                 length: bufferSize,
                                                 options: .storageModeShared),
              let dstBuffer = device.makeBuffer(bytes: (dstBytes as NSData).bytes,
                                                 length: bufferSize,
                                                 options: .storageModeShared),
              let outBuffer = device.makeBuffer(length: bufferSize,
                                                options: .storageModeShared) else {
            throw MetalError.bufferCreationFailed
        }

        var params = CompositeParams(
            width: UInt32(width),
            height: UInt32(height),
            opacity: opacity,
            blendMode: Int32(blendMode)
        )

        guard let paramsBuffer = device.makeBuffer(bytes: &params,
                                                    length: MemoryLayout<CompositeParams>.size,
                                                    options: .storageModeShared) else {
            throw MetalError.bufferCreationFailed
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw MetalError.encodingFailed
        }

        encoder.setComputePipelineState(pipelineState)
        encoder.setBuffer(srcBuffer, offset: 0, index: 0)
        encoder.setBuffer(dstBuffer, offset: 0, index: 1)
        encoder.setBuffer(outBuffer, offset: 0, index: 2)
        encoder.setBuffer(paramsBuffer, offset: 0, index: 3)

        // Use non-uniform dispatch for iOS devices that support it
        let threadgroupSize = MTLSize(
            width: min(16, pipelineState.maxTotalThreadsPerThreadgroup),
            height: min(16, pipelineState.maxTotalThreadsPerThreadgroup / 16),
            depth: 1
        )
        let gridSize = MTLSize(width: width, height: height, depth: 1)

        if device.supportsFamily(.apple4) {
            encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadgroupSize)
        } else {
            // Fallback for older devices
            let threadgroupCount = MTLSize(
                width: (width + threadgroupSize.width - 1) / threadgroupSize.width,
                height: (height + threadgroupSize.height - 1) / threadgroupSize.height,
                depth: 1
            )
            encoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
        }

        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if let error = commandBuffer.error {
            throw MetalError.executionFailed(error.localizedDescription)
        }

        let outputPointer = outBuffer.contents().bindMemory(to: UInt8.self, capacity: bufferSize)
        return Data(bytes: outputPointer, count: bufferSize)
    }

    static var isAvailable: Bool {
        return MTLCreateSystemDefaultDevice() != nil
    }
}

struct CompositeParams {
    var width: UInt32
    var height: UInt32
    var opacity: Float
    var blendMode: Int32
}

enum MetalError: Error, LocalizedError {
    case noDevice
    case noCommandQueue
    case noShaderSource
    case noFunction
    case invalidBufferSize
    case bufferCreationFailed
    case encodingFailed
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noDevice: return "No Metal device available"
        case .noCommandQueue: return "Failed to create command queue"
        case .noShaderSource: return "Metal shader source not found"
        case .noFunction: return "Metal function 'psdComposite' not found"
        case .invalidBufferSize: return "Buffer size does not match dimensions"
        case .bufferCreationFailed: return "Failed to create Metal buffer"
        case .encodingFailed: return "Failed to create command encoder"
        case .executionFailed(let msg): return "Metal execution failed: \(msg)"
        }
    }
}
