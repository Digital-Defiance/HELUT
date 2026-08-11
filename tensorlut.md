## TensorLUT Engine Architecture (Phase 1 Greenfield)

To establish the Phase 1 module boundary without modifying `HELUTCore`'s existing mock-PBS Toeplitz path, we construct a parallel pipeline: the **TensorLUT Engine**.

Instead of converting LUT truth tables into polynomial seeds and Toeplitz matrices, this path treats every cell as a padded 64-wide contiguous `Float32` array and evaluates inputs via a **multilinear extension kernel** on the GPU.

```
┌─────────────────────────────────────────────────────────────┐
│                 Yosys JSON Netlist Ingestion                │
│ (Reusable: Codable structs & YosysCellParameters parsing)   │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│             TensorLUT Netlist Compiler (Host-Side)            │
│  - Pads $lut (WIDTH 1…6) to uniform 64-entry Float32 arrays │
│  - Maps wire topologies into flat index arrays              │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│             Metal TensorLUT Forward Pipeline                  │
│  - INIT Buffer: [num_luts, 64] Float32                      │
│  - Wire Buffer: [batch_size, num_wires] Float32             │
│  - Kernel: Multilinear polynomial interpolation             │
└─────────────────────────────────────────────────────────────┘
```

## 1. Swift Types & Module Boundaries

The host-side layer parses the Yosys AST, normalizes all cells to 6-input LUTs (`LUT6`), and packs the wire topology into flat arrays suitable for direct GPU binding.

Swift

```
import Metal
import Foundation

/// A 64-wide continuous LUT6 representation.
package struct TensorLUT6Cell: Codable {
    package let cellID: Int
    /// Wire indices feeding inputs A[0…5]. Unused inputs map to dummy zero-wires.
    package var inputWires: (Int32, Int32, Int32, Int32, Int32, Int32)
    package var outputWire: Int32
    /// 64 continuous floating-point activations. Binary 1/0 or float [0.0, 1.0].
    package var entries: [Float]

    package init(cellID: Int, inputWires: [Int32], outputWire: Int32, rawTruthTable: String) {
        self.cellID = cellID
        self.outputWire = outputWire
        
        // Pad input wire indices up to 6 with dummy index (-1)
        var paddedInputs: [Int32] = inputWires
        while paddedInputs.count < 6 {
            paddedInputs.append(-1) // Maps to dummy zero-wire
        }
        self.inputWires = (paddedInputs[0], paddedInputs[1], paddedInputs[2], 
                           paddedInputs[3], paddedInputs[4], paddedInputs[5])

        // Parse and pad truth table to exactly 64 entries
        let width = inputWires.count
        let rawCount = 1 << width
        var initFloats = [Float](repeating: 0.0, count: 64)
        
        // Decode MSB-first string into LSB-first index mapping
        for mask in 0..<rawCount {
            let charIndex = rawTruthTable.count - 1 - mask
            if charIndex >= 0 && charIndex < rawTruthTable.count {
                let idx = rawTruthTable.index(rawTruthTable.startIndex, offsetBy: charIndex)
                initFloats[mask] = (rawTruthTable[idx] == "1") ? 1.0 : 0.0
            }
        }
        
        // Broadcast lower-arity truth tables across unused upper input bits
        if width < 6 {
            for i in rawCount..<64 {
                initFloats[i] = initFloats[i % rawCount]
            }
        }
        self.entries = initFloats
    }
}

/// Flat, uniform netlist representation mapped to GPU-aligned buffers.
package final class TensorLUTNetlist {
    package let luts: [TensorLUT6Cell]
    package let totalWires: Int
    package let executionLevels: [[Int32]] // Topologically sorted LUT indices per level

    package init(luts: [TensorLUT6Cell], totalWires: Int, executionLevels: [[Int32]]) {
        self.luts = luts
        self.totalWires = totalWires
        self.executionLevels = executionLevels
    }

    /// Packs all 64-entry LUT INITs into a single contiguous [num_luts * 64] Float32 array.
    package func packedINITBuffer() -> [Float] {
        var buffer = [Float]()
        buffer.reserveCapacity(luts.count * 64)
        for lut in luts {
            buffer.append(contentsOf: lut.entries)
        }
        return buffer
    }
}
```

## 2. Continuous Soft-LUT Metal Shader

To allow continuous floating-point optimization across discrete logic, we replace binary bit-indexing ($k = \sum_{m=0}^5 i_m 2^m$) with a **multilinear polynomial extension**.

For input activations $x_0, x_1, x_2, x_3, x_4, x_5 \in [0.0, 1.0]$, the soft output $y$ is defined as:

$$y = \sum_{k=0}^{63} \text{INIT}[k] \prod_{m=0}^{5} \left( b_m(k) x_m + (1 - b_m(k))(1 - x_m) \right)$$

where $b_m(k) = (k \gg m) \mathbin{\&} 1$. When inputs are strictly binary $\{0, 1\}$, this collapses exactly to the physical LUT6 truth-table lookup. When inputs are continuous floats in $[0, 1]$, the kernel executes a smooth, branchless $D$-dimensional multilinear interpolation across all 64 INIT weights.

### `TensorLUTForward.metal`

Code snippet

```
#include <metal_stdlib>
using namespace metal;

struct LUT6Inputs {
    int32_t in0;
    int32_t in1;
    int32_t in2;
    int32_t in3;
    int32_t in4;
    int32_t in5;
    int32_t outWire;
};

/// Evaluates a single level of topological LUT6 nodes across a batch of candidates.
kernel void tensor_lut6_eval_level(
    device float const *inits           [[buffer(0)]], // [num_luts, 64]
    device LUT6Inputs const *lutNodes   [[buffer(1)]], // [num_luts_in_level]
    device float *wireStates            [[buffer(2)]], // [batch_size, num_wires]
    constant uint32_t &numLutsInLevel   [[buffer(3)]],
    constant uint32_t &totalWires       [[buffer(4)]],
    uint2 position                      [[thread_position_in_grid]] // x: batch_lane, y: lut_index
) {
    uint batchIdx = position.x;
    uint lutLocalIdx = position.y;

    if (lutLocalIdx >= numLutsInLevel) return;

    LUT6Inputs node = lutNodes[lutLocalIdx];
    device float *laneWires = wireStates + (batchIdx * totalWires);

    // Read input wire activations (or 0.0 if unassigned/dummy)
    float x0 = (node.in0 >= 0) ? laneWires[node.in0] : 0.0f;
    float x1 = (node.in1 >= 0) ? laneWires[node.in1] : 0.0f;
    float x2 = (node.in2 >= 0) ? laneWires[node.in2] : 0.0f;
    float x3 = (node.in3 >= 0) ? laneWires[node.in3] : 0.0f;
    float x4 = (node.in4 >= 0) ? laneWires[node.in4] : 0.0f;
    float x5 = (node.in5 >= 0) ? laneWires[node.in5] : 0.0f;

    // Pointer to this cell's 64-entry Float INIT table
    device float const *cellInit = inits + (node.outWire * 64); // Mapped by LUT index

    float accumulatedOutput = 0.0f;

    // Branchless multilinear extension over all 64 hypercube corners
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

    // Write output activation to the wire array for this batch lane
    laneWires[node.outWire] = accumulatedOutput;
}
```

## 3. Host Dispatcher Contract

The host runner manages unified memory allocation, updates continuous LUT INIT weights during continuous mutations, and dispatches evaluation passes level-by-level.

Swift

```
package final class TensorLUTPipeline {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLComputePipelineState

    package init(device: MTLDevice) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            fatalError("Failed to create Metal command queue")
        }
        self.commandQueue = queue

        let library = try device.makeDefaultLibrary(bundle: Bundle.module)
        guard let function = library.makeFunction(name: "tensor_lut6_eval_level") else {
            fatalError("Failed to locate tensor_lut6_eval_level kernel")
        }
        self.pipelineState = try device.makeComputePipelineState(function: function)
    }

    package func evaluateForward(
        netlist: TensorLUTNetlist,
        initsBuffer: MTLBuffer,
        wireBuffer: MTLBuffer,
        batchSize: Int
    ) {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }

        encoder.setComputePipelineState(pipelineState)
        encoder.setBuffer(initsBuffer, offset: 0, index: 0)
        encoder.setBuffer(wireBuffer, offset: 0, index: 2)

        var totalWiresCount = UInt32(netlist.totalWires)
        encoder.setBytes(&totalWiresCount, length: MemoryLayout<UInt32>.size, index: 4)

        // Topological level-by-level evaluation pass
        for levelLUTs in netlist.executionLevels {
            var numLuts = UInt32(levelLUTs.count)
            
            // Build temporary buffer of LUT6Inputs for current level
            let levelInputs = levelLUTs.map { lutIdx -> (Int32, Int32, Int32, Int32, Int32, Int32, Int32) in
                let lut = netlist.luts[Int(lutIdx)]
                return (lut.inputWires.0, lut.inputWires.1, lut.inputWires.2,
                        lut.inputWires.3, lut.inputWires.4, lut.inputWires.5, lut.outputWire)
            }
            
            encoder.setBytes(levelInputs, length: MemoryLayout<(Int32, Int32, Int32, Int32, Int32, Int32, Int32)>.stride * levelInputs.count, index: 1)
            encoder.setBytes(&numLuts, length: MemoryLayout<UInt32>.size, index: 3)

            let gridSize = MTLSize(width: batchSize, height: levelLUTs.count, depth: 1)
            let threadgroupSize = MTLSize(width: min(pipelineState.maxTotalThreadsPerThreadgroup, batchSize), height: 1, depth: 1)

            encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadgroupSize)
        }

        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
}
```