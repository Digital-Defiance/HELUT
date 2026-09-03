import Accelerate
import Foundation
import Metal

/// Metal + vDSP path for \(\sum_i w_i(1-w_i)\) over TensorLUT INIT floats.
package final class TensorLUTFrictionEngine {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLComputePipelineState
    private var penaltiesBuffer: MTLBuffer?
    private var penaltiesCapacity: Int = 0
    private var freezeBuffer: MTLBuffer?
    private var freezeCapacity: Int = 0

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    // freezeLUT[lutIdx] != 0 ⇒ INIT floats for that LUT contribute 0 penalty (targeted melt).
    kernel void tensor_lut_discreteness_penalty(
        device float const *inits      [[buffer(0)]],
        device float *outPenalties     [[buffer(1)]],
        constant uint32_t &totalFloats [[buffer(2)]],
        device uchar const *freezeLUT  [[buffer(3)]],
        constant uint32_t &hasFreeze   [[buffer(4)]],
        uint id                        [[thread_position_in_grid]]
    ) {
        if (id >= totalFloats) return;
        if (hasFreeze != 0) {
            uint lutIdx = id / 64u;
            if (freezeLUT[lutIdx] != 0) {
                outPenalties[id] = 0.0f;
                return;
            }
        }
        float w = inits[id];
        outPenalties[id] = w * (1.0f - w);
    }
    """

    package init(device: MTLDevice) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            fatalError("Failed to create Metal command queue for TensorLUTFrictionEngine")
        }
        self.commandQueue = queue

        let library = try device.makeLibrary(source: TensorLUTFrictionEngine.shaderSource, options: nil)
        guard let function = library.makeFunction(name: "tensor_lut_discreteness_penalty") else {
            fatalError("Failed to locate tensor_lut_discreteness_penalty kernel")
        }
        self.pipelineState = try device.makeComputePipelineState(function: function)
    }

    /// Ensures a shared penalties buffer large enough for `count` floats.
    package func prepare(capacity: Int) {
        guard capacity > penaltiesCapacity else { return }
        let bytes = capacity * MemoryLayout<Float>.stride
        guard let buffer = device.makeBuffer(length: bytes, options: .storageModeShared) else {
            fatalError("Failed to allocate TensorLUT penalties buffer (\(bytes) bytes)")
        }
        penaltiesBuffer = buffer
        penaltiesCapacity = capacity
    }

    private func prepareFreeze(lutCount: Int) -> MTLBuffer {
        if lutCount <= freezeCapacity, let freezeBuffer {
            return freezeBuffer
        }
        let bytes = max(lutCount, 1) * MemoryLayout<UInt8>.stride
        guard let buffer = device.makeBuffer(length: bytes, options: .storageModeShared) else {
            fatalError("Failed to allocate TensorLUT freeze mask buffer")
        }
        freezeBuffer = buffer
        freezeCapacity = lutCount
        return buffer
    }

    /// Dispatches the friction kernel and returns \(\sum w(1-w)\) via `vDSP_sve`.
    /// When `freezeMask` is set (per-LUT), frozen LUTs contribute `0`.
    package func sumDiscretenessPenalty(
        initsBuffer: MTLBuffer,
        count: Int,
        freezeMask: [Bool]? = nil
    ) -> Float {
        precondition(count > 0)
        if let freezeMask {
            precondition(count % 64 == 0, "INIT float count must be num_luts×64 when freezing")
            precondition(freezeMask.count == count / 64, "freezeMask length must equal lutCount")
        }
        prepare(capacity: count)
        let lutCount = max(count / 64, 1)
        guard let penaltiesBuffer,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            return 0
        }

        var hasFreeze: UInt32 = 0
        let freezeBuf: MTLBuffer
        if let freezeMask {
            precondition(freezeMask.count == lutCount, "freezeMask length must equal lutCount")
            freezeBuf = prepareFreeze(lutCount: lutCount)
            let ptr = freezeBuf.contents().bindMemory(to: UInt8.self, capacity: lutCount)
            for i in 0..<lutCount {
                ptr[i] = freezeMask[i] ? 1 : 0
            }
            hasFreeze = 1
        } else {
            freezeBuf = prepareFreeze(lutCount: 1)
            hasFreeze = 0
        }

        encoder.setComputePipelineState(pipelineState)
        encoder.setBuffer(initsBuffer, offset: 0, index: 0)
        encoder.setBuffer(penaltiesBuffer, offset: 0, index: 1)
        var totalFloats = UInt32(count)
        encoder.setBytes(&totalFloats, length: MemoryLayout<UInt32>.size, index: 2)
        encoder.setBuffer(freezeBuf, offset: 0, index: 3)
        encoder.setBytes(&hasFreeze, length: MemoryLayout<UInt32>.size, index: 4)

        let w = min(pipelineState.maxTotalThreadsPerThreadgroup, count)
        encoder.dispatchThreads(
            MTLSize(width: count, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: w, height: 1, depth: 1)
        )
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let ptr = penaltiesBuffer.contents().bindMemory(to: Float.self, capacity: count)
        var sum: Float = 0
        vDSP_sve(ptr, 1, &sum, vDSP_Length(count))
        return sum
    }

    /// Host reference: \(\sum w(1-w)\) (for tests / CPU-only paths).
    package static func hostSumDiscretenessPenalty(
        _ inits: [Float],
        freezeMask: [Bool]? = nil
    ) -> Float {
        var sum: Float = 0
        if let freezeMask {
            precondition(inits.count % 64 == 0, "INIT float count must be num_luts×64 when freezing")
            let lutCount = inits.count / 64
            precondition(freezeMask.count == lutCount)
            for lut in 0..<lutCount {
                if freezeMask[lut] { continue }
                let base = lut * 64
                for j in 0..<64 {
                    let w = inits[base + j]
                    sum += w * (1 - w)
                }
            }
        } else {
            for w in inits {
                sum += w * (1 - w)
            }
        }
        return sum
    }
}
