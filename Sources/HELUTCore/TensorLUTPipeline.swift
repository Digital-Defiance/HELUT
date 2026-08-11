import Foundation
import Metal

/// GPU-side LUT6 wiring record (must match the Metal `LUT6Inputs` layout).
package struct LUT6Inputs {
    package let in0, in1, in2, in3, in4, in5, outWire: Int32

    package init(in0: Int32, in1: Int32, in2: Int32, in3: Int32, in4: Int32, in5: Int32, outWire: Int32) {
        self.in0 = in0
        self.in1 = in1
        self.in2 = in2
        self.in3 = in3
        self.in4 = in4
        self.in5 = in5
        self.outWire = outWire
    }
}

/// Metal TensorLUT forward pipeline: multilinear LUT6 eval + DFF clock edge.
///
/// Does not touch `LUTNode` / mock-PBS. Caller injects primary inputs (and Q state)
/// into `wireBuffer` before `evaluateForward`.
package final class TensorLUTPipeline {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLComputePipelineState
    private let dffPipelineState: MTLComputePipelineState

    private struct LevelBuffers {
        let nodesBuffer: MTLBuffer
        let indicesBuffer: MTLBuffer
        let numLuts: UInt32
    }

    private var levelDispatchData: [LevelBuffers] = []
    private var dffBuffer: MTLBuffer?
    private var numDFFs: UInt32 = 0

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct LUT6Inputs {
        int32_t in0; int32_t in1; int32_t in2;
        int32_t in3; int32_t in4; int32_t in5;
        int32_t outWire;
    };

    struct DFFInputs {
        int32_t dWire;
        int32_t qWire;
        int32_t enableWire;
        int32_t resetWire;
        int32_t enableActiveHigh;
        int32_t resetActiveHigh;
        int32_t resetValue;
    };

    kernel void tensor_lut6_eval_level(
        device float const *inits              [[buffer(0)]],
        device LUT6Inputs const *lutNodes      [[buffer(1)]],
        device float *wireStates               [[buffer(2)]],
        device uint32_t const *levelLUTIndices [[buffer(3)]],
        constant uint32_t &numLutsInLevel      [[buffer(4)]],
        constant uint32_t &totalWires          [[buffer(5)]],
        uint2 position                         [[thread_position_in_grid]]
    ) {
        uint batchIdx = position.x;
        uint lutLocalIdx = position.y;

        if (lutLocalIdx >= numLutsInLevel) return;

        LUT6Inputs node = lutNodes[lutLocalIdx];
        uint32_t globalLutIdx = levelLUTIndices[lutLocalIdx];
        device float *laneWires = wireStates + (batchIdx * totalWires);

        float x0 = (node.in0 >= 0) ? laneWires[node.in0] : 0.0f;
        float x1 = (node.in1 >= 0) ? laneWires[node.in1] : 0.0f;
        float x2 = (node.in2 >= 0) ? laneWires[node.in2] : 0.0f;
        float x3 = (node.in3 >= 0) ? laneWires[node.in3] : 0.0f;
        float x4 = (node.in4 >= 0) ? laneWires[node.in4] : 0.0f;
        float x5 = (node.in5 >= 0) ? laneWires[node.in5] : 0.0f;

        device float const *cellInit = inits + (globalLutIdx * 64);

        float accumulatedOutput = 0.0f;
        for (uint k = 0; k < 64; ++k) {
            float weight = cellInit[k];

            float p0 = (k & 1)  ? x0 : (1.0f - x0);
            float p1 = (k & 2)  ? x1 : (1.0f - x1);
            float p2 = (k & 4)  ? x2 : (1.0f - x2);
            float p3 = (k & 8)  ? x3 : (1.0f - x3);
            float p4 = (k & 16) ? x4 : (1.0f - x4);
            float p5 = (k & 32) ? x5 : (1.0f - x5);

            accumulatedOutput += weight * (p0 * p1 * p2 * p3 * p4 * p5);
        }

        laneWires[node.outWire] = accumulatedOutput;
    }

    kernel void soft_dff_update(
        device DFFInputs const *dffNodes [[buffer(0)]],
        device float *wireStates         [[buffer(1)]],
        constant uint32_t &numDFFs       [[buffer(2)]],
        constant uint32_t &totalWires    [[buffer(3)]],
        uint2 position                   [[thread_position_in_grid]]
    ) {
        uint batchIdx = position.x;
        uint dffIdx = position.y;

        if (dffIdx >= numDFFs) return;

        DFFInputs node = dffNodes[dffIdx];
        device float *laneWires = wireStates + (batchIdx * totalWires);

        float dVal = (node.dWire >= 0) ? laneWires[node.dWire] : 0.0f;
        float qCur = laneWires[node.qWire];
        float qNext = dVal;

        if (node.enableWire >= 0) {
            float eRaw = laneWires[node.enableWire];
            float enabled = (node.enableActiveHigh != 0) ? eRaw : (1.0f - eRaw);
            qNext = (enabled >= 0.5f) ? dVal : qCur;
        }

        if (node.resetWire >= 0) {
            float rRaw = laneWires[node.resetWire];
            float asserted = (node.resetActiveHigh != 0) ? rRaw : (1.0f - rRaw);
            if (asserted >= 0.5f) {
                qNext = float(node.resetValue);
            }
        }

        laneWires[node.qWire] = qNext;
    }
    """

    package init(device: MTLDevice, netlist: TensorLUTNetlist? = nil) throws {
        precondition(
            MemoryLayout<LUT6Inputs>.stride == 28,
            "LUT6Inputs stride must match Metal (7×int32)"
        )
        precondition(
            MemoryLayout<TensorDFFCell>.stride == 28,
            "TensorDFFCell stride must match Metal DFFInputs (7×int32)"
        )
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            fatalError("Failed to create Metal command queue")
        }
        self.commandQueue = queue

        let library = try device.makeLibrary(source: TensorLUTPipeline.shaderSource, options: nil)
        guard let lutFunc = library.makeFunction(name: "tensor_lut6_eval_level") else {
            fatalError("Failed to locate tensor_lut6_eval_level kernel")
        }
        guard let dffFunc = library.makeFunction(name: "soft_dff_update") else {
            fatalError("Failed to locate soft_dff_update kernel")
        }
        self.pipelineState = try device.makeComputePipelineState(function: lutFunc)
        self.dffPipelineState = try device.makeComputePipelineState(function: dffFunc)

        if let netlist {
            prepareLevelBuffers(netlist: netlist)
        }
    }

    /// Pre-allocates per-level node/index buffers and the DFF table (call once per netlist).
    package func prepareLevelBuffers(netlist: TensorLUTNetlist) {
        levelDispatchData = netlist.executionLevels.compactMap { levelIndices in
            guard !levelIndices.isEmpty else { return nil }

            var levelNodes: [LUT6Inputs] = []
            var globalIndices: [UInt32] = []
            levelNodes.reserveCapacity(levelIndices.count)
            globalIndices.reserveCapacity(levelIndices.count)

            for lutIdx in levelIndices {
                let lut = netlist.luts[Int(lutIdx)]
                levelNodes.append(
                    LUT6Inputs(
                        in0: lut.in0, in1: lut.in1, in2: lut.in2,
                        in3: lut.in3, in4: lut.in4, in5: lut.in5,
                        outWire: lut.outWire
                    )
                )
                globalIndices.append(UInt32(lutIdx))
            }

            guard
                let nodesBuffer = device.makeBuffer(
                    bytes: levelNodes,
                    length: levelNodes.count * MemoryLayout<LUT6Inputs>.stride,
                    options: .storageModeShared
                ),
                let indicesBuffer = device.makeBuffer(
                    bytes: globalIndices,
                    length: globalIndices.count * MemoryLayout<UInt32>.stride,
                    options: .storageModeShared
                )
            else {
                fatalError("Failed to allocate TensorLUT level buffers")
            }

            return LevelBuffers(
                nodesBuffer: nodesBuffer,
                indicesBuffer: indicesBuffer,
                numLuts: UInt32(levelIndices.count)
            )
        }

        if netlist.dffs.isEmpty {
            numDFFs = 0
            dffBuffer = nil
        } else {
            numDFFs = UInt32(netlist.dffs.count)
            guard let buffer = device.makeBuffer(
                bytes: netlist.dffs,
                length: netlist.dffs.count * MemoryLayout<TensorDFFCell>.stride,
                options: .storageModeShared
            ) else {
                fatalError("Failed to allocate TensorLUT DFF buffer")
            }
            dffBuffer = buffer
        }
    }

    /// Combinational TensorLUT levels. Primary inputs / Q state must already be in `wireBuffer`.
    package func evaluateForward(
        totalWires: Int,
        initsBuffer: MTLBuffer,
        wireBuffer: MTLBuffer,
        batchSize: Int
    ) {
        precondition(!levelDispatchData.isEmpty, "Call prepareLevelBuffers before evaluateForward")
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        encodeForward(
            on: commandBuffer,
            totalWires: totalWires,
            initsBuffer: initsBuffer,
            wireBuffer: wireBuffer,
            batchSize: batchSize
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    /// Posedge: copy D→Q (with enable / sync-reset) across the batch.
    package func clockTick(totalWires: Int, wireBuffer: MTLBuffer, batchSize: Int) {
        guard numDFFs > 0 else { return }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        encodeClockTick(on: commandBuffer, totalWires: totalWires, wireBuffer: wireBuffer, batchSize: batchSize)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    /// One sequential cycle: combinational TensorLUT levels, then DFF update.
    package func evaluateTick(
        totalWires: Int,
        initsBuffer: MTLBuffer,
        wireBuffer: MTLBuffer,
        batchSize: Int
    ) {
        precondition(!levelDispatchData.isEmpty, "Call prepareLevelBuffers before evaluateTick")
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        encodeForward(
            on: commandBuffer,
            totalWires: totalWires,
            initsBuffer: initsBuffer,
            wireBuffer: wireBuffer,
            batchSize: batchSize
        )
        encodeClockTick(on: commandBuffer, totalWires: totalWires, wireBuffer: wireBuffer, batchSize: batchSize)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func encodeForward(
        on commandBuffer: MTLCommandBuffer,
        totalWires: Int,
        initsBuffer: MTLBuffer,
        wireBuffer: MTLBuffer,
        batchSize: Int
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }

        encoder.setComputePipelineState(pipelineState)
        encoder.setBuffer(initsBuffer, offset: 0, index: 0)
        encoder.setBuffer(wireBuffer, offset: 0, index: 2)

        var tWires = UInt32(totalWires)
        encoder.setBytes(&tWires, length: MemoryLayout<UInt32>.size, index: 5)

        for level in levelDispatchData {
            encoder.setBuffer(level.nodesBuffer, offset: 0, index: 1)
            encoder.setBuffer(level.indicesBuffer, offset: 0, index: 3)

            var numLuts = level.numLuts
            encoder.setBytes(&numLuts, length: MemoryLayout<UInt32>.size, index: 4)

            let w = min(pipelineState.maxTotalThreadsPerThreadgroup, max(batchSize, 1))
            let gridSize = MTLSize(width: batchSize, height: Int(numLuts), depth: 1)
            let threadgroupSize = MTLSize(width: w, height: 1, depth: 1)
            encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadgroupSize)
        }

        encoder.endEncoding()
    }

    private func encodeClockTick(
        on commandBuffer: MTLCommandBuffer,
        totalWires: Int,
        wireBuffer: MTLBuffer,
        batchSize: Int
    ) {
        guard numDFFs > 0, let dffBuffer,
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }

        encoder.setComputePipelineState(dffPipelineState)
        encoder.setBuffer(dffBuffer, offset: 0, index: 0)
        encoder.setBuffer(wireBuffer, offset: 0, index: 1)

        var nDffs = numDFFs
        var tWires = UInt32(totalWires)
        encoder.setBytes(&nDffs, length: MemoryLayout<UInt32>.size, index: 2)
        encoder.setBytes(&tWires, length: MemoryLayout<UInt32>.size, index: 3)

        let w = min(dffPipelineState.maxTotalThreadsPerThreadgroup, max(batchSize, 1))
        let gridSize = MTLSize(width: batchSize, height: Int(numDFFs), depth: 1)
        let threadgroupSize = MTLSize(width: w, height: 1, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()
    }
}
