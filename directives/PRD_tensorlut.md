We can bypass `LUTNode` entirely, keep the Metal kernel cleanly inlined, pre-allocate the level dispatch buffers to prevent execution stall, and correct the `cellInit` indexing logic so we don't alias the unbounded wire IDs.

By pre-allocating the `LUT6Inputs` parameters into static Metal buffers inside the `TensorLUTPipeline` initializer, we avoid the heavy `setBytes` overhead. With the M4 Max’s unified memory architecture, passing those pre-allocated parameter buffers to the GPU during the evolutionary loop executes with zero memory copy latency, ensuring the Metal shaders stay saturated across millions of generations.

Here is the complete Phase 1 Greenfield implementation, split exactly as you outlined, including the binary parity tests.

### 1. `Sources/HELUTCore/TensorLUTTypes.swift`

This flattens the Yosys AST parameters into a strictly `Codable` 6-input format, padding absent wires with `-1` and repeating truth table bits to fill the 64-element matrix.

```swift
import Foundation

package struct TensorLUT6Cell: Codable {
    package let cellID: Int
    // Flattened so Codable synthesizes cleanly without tuple issues
    package let in0, in1, in2, in3, in4, in5, outWire: Int32
    package var entries: [Float] // Strictly 64 wide

    package init(cellID: Int, inputWires: [Int32], outputWire: Int32, rawTruthTable: String) {
        self.cellID = cellID
        self.outWire = outputWire
        
        // Pad input wire indices up to 6 with dummy index (-1)
        var pads = inputWires
        while pads.count < 6 { pads.append(-1) }
        self.in0 = pads[0]; self.in1 = pads[1]; self.in2 = pads[2]
        self.in3 = pads[3]; self.in4 = pads[4]; self.in5 = pads[5]
        
        let width = inputWires.count
        let rawCount = 1 << width
        var initFloats = [Float](repeating: 0.0, count: 64)
        
        // Decode MSB-first string into LSB-first continuous mapping
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

### 2. `Sources/HELUTCore/TensorLUTPipeline.swift`

This handles the inline shader and topological execution. Primary inputs are expected to be injected into the `wireBuffer` by the caller prior to invoking `evaluateForward()`.

```swift
import Metal
import Foundation

package struct LUT6Inputs {
    package let in0, in1, in2, in3, in4, in5, outWire: Int32
}

package final class TensorLUTPipeline {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLComputePipelineState

    // Pre-allocated buffers for level dispatch to avoid loop allocation overhead
    private struct LevelBuffers {
        let nodesBuffer: MTLBuffer
        let indicesBuffer: MTLBuffer
        let numLuts: UInt32
    }
    private var levelDispatchData: [LevelBuffers] = []

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct LUT6Inputs {
        int32_t in0; int32_t in1; int32_t in2;
        int32_t in3; int32_t in4; int32_t in5;
        int32_t outWire;
    };

    kernel void tensor_lut6_eval_level(
        device float const *inits              [[buffer(0)]], // [num_luts * 64]
        device LUT6Inputs const *lutNodes      [[buffer(1)]], // [num_luts_in_level]
        device float *wireStates               [[buffer(2)]], // [batch_size * totalWires]
        device uint32_t const *levelLUTIndices [[buffer(3)]], // [num_luts_in_level]
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

        // Fetch inputs or map dummy (-1) to 0.0f
        float x0 = (node.in0 >= 0) ? laneWires[node.in0] : 0.0f;
        float x1 = (node.in1 >= 0) ? laneWires[node.in1] : 0.0f;
        float x2 = (node.in2 >= 0) ? laneWires[node.in2] : 0.0f;
        float x3 = (node.in3 >= 0) ? laneWires[node.in3] : 0.0f;
        float x4 = (node.in4 >= 0) ? laneWires[node.in4] : 0.0f;
        float x5 = (node.in5 >= 0) ? laneWires[node.in5] : 0.0f;

        // Map safely against the packed INIT buffer
        device float const *cellInit = inits + (globalLutIdx * 64);

        float accumulatedOutput = 0.0f;
        
        // Branchless multilinear extension
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
    """

    package init(device: MTLDevice, netlist: TensorLUTNetlist? = nil) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            fatalError("Failed to create Metal command queue")
        }
        self.commandQueue = queue

        let library = try device.makeLibrary(source: TensorLUTPipeline.shaderSource, options: nil)
        guard let function = library.makeFunction(name: "tensor_lut6_eval_level") else {
            fatalError("Failed to locate tensor_lut6_eval_level kernel")
        }
        self.pipelineState = try device.makeComputePipelineState(function: function)
        
        if let netlist = netlist {
            prepareLevelBuffers(netlist: netlist)
        }
    }

    /// Pre-allocates execution buffers to prevent dynamic allocation inside the evolutionary loop.
    package func prepareLevelBuffers(netlist: TensorLUTNetlist) {
        self.levelDispatchData = netlist.executionLevels.compactMap { levelIndices in
            guard !levelIndices.isEmpty else { return nil }
            
            var levelNodes = [LUT6Inputs]()
            var globalIndices = [UInt32]()
            
            for lutIdx in levelIndices {
                let lut = netlist.luts[Int(lutIdx)]
                levelNodes.append(LUT6Inputs(
                    in0: lut.in0, in1: lut.in1, in2: lut.in2,
                    in3: lut.in3, in4: lut.in4, in5: lut.in5,
                    outWire: lut.outWire
                ))
                globalIndices.append(UInt32(lutIdx))
            }
            
            let nodesBuffer = device.makeBuffer(bytes: levelNodes, length: levelNodes.count * MemoryLayout<LUT6Inputs>.stride, options: .storageModeShared)!
            let indicesBuffer = device.makeBuffer(bytes: globalIndices, length: globalIndices.count * MemoryLayout<UInt32>.stride, options: .storageModeShared)!
            
            return LevelBuffers(nodesBuffer: nodesBuffer, indicesBuffer: indicesBuffer, numLuts: UInt32(levelIndices.count))
        }
    }

    /// The wireBuffer must have primary input values injected by the caller prior to execution.
    package func evaluateForward(
        totalWires: Int,
        initsBuffer: MTLBuffer,
        wireBuffer: MTLBuffer,
        batchSize: Int
    ) {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }

        encoder.setComputePipelineState(pipelineState)
        encoder.setBuffer(initsBuffer, offset: 0, index: 0)
        encoder.setBuffer(wireBuffer, offset: 0, index: 2)

        var tWires = UInt32(totalWires)
        encoder.setBytes(&tWires, length: MemoryLayout<UInt32>.size, index: 5)

        // Dispatch level-synchronously 
        for level in levelDispatchData {
            encoder.setBuffer(level.nodesBuffer, offset: 0, index: 1)
            encoder.setBuffer(level.indicesBuffer, offset: 0, index: 3)
            
            var numLuts = level.numLuts
            encoder.setBytes(&numLuts, length: MemoryLayout<UInt32>.size, index: 4)

            let w = min(pipelineState.maxTotalThreadsPerThreadgroup, batchSize)
            let gridSize = MTLSize(width: batchSize, height: Int(numLuts), depth: 1)
            let threadgroupSize = MTLSize(width: w, height: 1, depth: 1)

            encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadgroupSize)
        }

        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
}

```

### 3. `Tests/HELUTTests/TensorLUTParityTests.swift`

This test explicitly checks that the multilinear extension mathematically collapses to the expected binary truth table when provided exact binary floats, verifying parity against standard discrete simulation.

```swift
import XCTest
import Metal
@testable import HELUTCore

final class TensorLUTParityTests: XCTestCase {
    
    func testBinaryParityWithXOR() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device not available")
        }
        
        // Truth table for a 2-input XOR: 0110 (binary)
        let xorLUT = TensorLUT6Cell(
            cellID: 0,
            inputWires: [0, 1], // Wires 0 and 1 are inputs
            outputWire: 2,      // Wire 2 is output
            rawTruthTable: "0110"
        )
        
        let netlist = TensorLUTNetlist(
            luts: [xorLUT],
            totalWires: 3,
            executionLevels: [[0]] // Topo map: One LUT at execution level 0
        )
        
        let pipeline = try TensorLUTPipeline(device: device, netlist: netlist)
        
        // Populate continuous INIT weights
        let initData = netlist.packedINITBuffer()
        let initsBuffer = device.makeBuffer(bytes: initData, length: initData.count * MemoryLayout<Float>.stride, options: .storageModeShared)!
        
        // Setup Batch of 4 inputs representing [0,0], [1,0], [0,1], [1,1]
        // Flattened Wires: [A, B, OUT]
        var wiresData: [Float] = [
            0.0, 0.0, 0.0, // Batch 0: wire0=0, wire1=0
            1.0, 0.0, 0.0, // Batch 1: wire0=1, wire1=0
            0.0, 1.0, 0.0, // Batch 2: wire0=0, wire1=1
            1.0, 1.0, 0.0  // Batch 3: wire0=1, wire1=1
        ]
        
        let wireBuffer = device.makeBuffer(bytes: wiresData, length: wiresData.count * MemoryLayout<Float>.stride, options: .storageModeShared)!
        
        // Execute Pipeline
        pipeline.evaluateForward(totalWires: netlist.totalWires, initsBuffer: initsBuffer, wireBuffer: wireBuffer, batchSize: 4)
        
        // Verify results
        let outputPtr = wireBuffer.contents().bindMemory(to: Float.self, capacity: 12)
        
        XCTAssertEqual(outputPtr[2],  0.0, "0 XOR 0 should be 0.0")
        XCTAssertEqual(outputPtr[5],  1.0, "1 XOR 0 should be 1.0")
        XCTAssertEqual(outputPtr[8],  1.0, "0 XOR 1 should be 1.0")
        XCTAssertEqual(outputPtr[11], 0.0, "1 XOR 1 should be 0.0")
    }
}
```