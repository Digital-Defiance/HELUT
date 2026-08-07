
Let's build the ingestion bridge and the sequential state logic. To move off isolated XOR tests and ingest the actual `enigma_m4_core.json`, we need the **TensorLUTCompiler** to run a topological sort (Kahn’s Algorithm) over the Yosys AST, and we need to add **D-Flip-Flops (DFFs)** to handle the clock ticks.

Here is the exact next slice. It translates the Yosys wire topology into strict Metal execution barriers and adds a dedicated DFF update phase to loop sequential networks natively on the GPU.

### 1. Update `TensorLUTTypes.swift` for DFFs

We need a struct to represent the DFFs and to update the netlist definition to carry them.

Swift

```
package struct TensorDFFCell: Codable {
    package let dWire: Int32
    package let qWire: Int32
}

package final class TensorLUTNetlist {
    package let luts: [TensorLUT6Cell]
    package let dffs: [TensorDFFCell]
    package let totalWires: Int
    package let executionLevels: [[Int32]] 

    package init(luts: [TensorLUT6Cell], dffs: [TensorDFFCell], totalWires: Int, executionLevels: [[Int32]]) {
        self.luts = luts
        self.dffs = dffs
        self.totalWires = totalWires
        self.executionLevels = executionLevels
    }
    
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

### 2. The Greenfield Compiler (`TensorLUTCompiler.swift`)

This module digests `YosysModule`, extracts the LUTs and DFFs, and maps the dataflow graph. Because Metal requires static barriers to avoid race conditions, Kahn’s algorithm groups the LUTs into strict `executionLevels`.

Swift

```
import Foundation

package final class TensorLUTCompiler {
    
    /// Compiles a Yosys AST module into a topographically sorted TensorLUTNetlist.
    package static func compile(module: YosysModule) -> TensorLUTNetlist {
        var luts = [TensorLUT6Cell]()
        var dffs = [TensorDFFCell]()
        var maxWire: Int32 = 0
        
        // 1. Extract physical cells and track max wire ID for buffer sizing
        for (cellName, cell) in module.cells {
            if cell.type == "$lut" {
                guard let aBits = cell.connections["A"],
                      let yBits = cell.connections["Y"], yBits.count == 1,
                      let rawTruth = cell.parameters.LUT else { continue }
                
                let inWires = aBits.compactMap { bit -> Int32? in
                    if case .bit(let w) = bit { return Int32(w) }
                    return nil
                }
                
                guard case .bit(let outW) = yBits[0] else { continue }
                let outWire = Int32(outW)
                
                inWires.forEach { maxWire = max(maxWire, $0) }
                maxWire = max(maxWire, outWire)
                
                let lut = TensorLUT6Cell(cellID: luts.count, inputWires: inWires, outputWire: outWire, rawTruthTable: rawTruth)
                luts.append(lut)
                
            } else if cell.type == "$dff" {
                guard let dBits = cell.connections["D"], dBits.count == 1,
                      let qBits = cell.connections["Q"], qBits.count == 1,
                      case .bit(let dW) = dBits[0],
                      case .bit(let qW) = qBits[0] else { continue }
                
                let dWire = Int32(dW)
                let qWire = Int32(qW)
                
                maxWire = max(maxWire, max(dWire, qWire))
                dffs.append(TensorDFFCell(dWire: dWire, qWire: qWire))
            }
        }
        
        let totalWires = Int(maxWire + 1)
        
        // 2. Kahn's Algorithm for Topological Sorting
        var producerLUT = [Int32: Int]() // wireID -> LUT index
        for (idx, lut) in luts.enumerated() {
            producerLUT[lut.outWire] = idx
        }
        
        var inDegree = [Int](repeating: 0, count: luts.count)
        var dependents = [Int: [Int]](minimumCapacity: luts.count)
        
        for (idx, lut) in luts.enumerated() {
            let inputs = [lut.in0, lut.in1, lut.in2, lut.in3, lut.in4, lut.in5].filter { $0 >= 0 }
            for inWire in inputs {
                // If the input wire is produced by another LUT (not a DFF/Primary Input), build the edge
                if let prodIdx = producerLUT[inWire] {
                    dependents[prodIdx, default: []].append(idx)
                    inDegree[idx] += 1
                }
            }
        }
        
        var executionLevels = [[Int32]]()
        var currentQueue = [Int]()
        
        // Base level: LUTs driven entirely by DFFs or Primary Inputs
        for i in 0..<luts.count {
            if inDegree[i] == 0 {
                currentQueue.append(i)
            }
        }
        
        while !currentQueue.isEmpty {
            executionLevels.append(currentQueue.map { Int32($0) })
            var nextQueue = [Int]()
            
            for lutIdx in currentQueue {
                for depIdx in dependents[lutIdx] ?? [] {
                    inDegree[depIdx] -= 1
                    if inDegree[depIdx] == 0 {
                        nextQueue.append(depIdx)
                    }
                }
            }
            currentQueue = nextQueue
        }
        
        // Safety check for cyclic combinational logic
        let sortedCount = executionLevels.reduce(0) { $0 + $1.count }
        precondition(sortedCount == luts.count, "Combinational loop detected in Yosys AST. Sorted \(sortedCount)/\(luts.count) LUTs.")
        
        return TensorLUTNetlist(luts: luts, dffs: dffs, totalWires: totalWires, executionLevels: executionLevels)
    }
}
```

### 3. Add Sequential DFF Updates to `TensorLUTPipeline.swift`

Add a small, lightning-fast kernel to the inline shader string to copy `D` to `Q` across the entire batch simultaneously at the end of the combinational clock tick.

**Add to the inline Metal shader source:**

Code snippet

```
struct DFFInputs {
    int32_t dWire;
    int32_t qWire;
};

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

    // Ping-pong state update
    laneWires[node.qWire] = laneWires[node.dWire];
}
```

**Add the pipeline compilation and dispatch to `TensorLUTPipeline.swift`:**

Swift

```
    // Add to class properties:
    private let dffPipelineState: MTLComputePipelineState
    private var dffBuffer: MTLBuffer?
    private var numDFFs: UInt32 = 0

    // Add to init():
    guard let dffFunc = library.makeFunction(name: "soft_dff_update") else {
        fatalError("Failed to locate soft_dff_update kernel")
    }
    self.dffPipelineState = try device.makeComputePipelineState(function: dffFunc)

    // Add to prepareLevelBuffers(netlist:):
    if !netlist.dffs.isEmpty {
        self.numDFFs = UInt32(netlist.dffs.count)
        self.dffBuffer = device.makeBuffer(
            bytes: netlist.dffs, 
            length: netlist.dffs.count * MemoryLayout<TensorDFFCell>.stride, 
            options: .storageModeShared
        )
    }

    // Add as a new function:
    package func clockTick(totalWires: Int, wireBuffer: MTLBuffer, batchSize: Int, commandBuffer: MTLCommandBuffer) {
        guard numDFFs > 0, let dffBuffer = dffBuffer,
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        
        encoder.setComputePipelineState(dffPipelineState)
        encoder.setBuffer(dffBuffer, offset: 0, index: 0)
        encoder.setBuffer(wireBuffer, offset: 0, index: 1)
        
        var nDffs = numDFFs
        var tWires = UInt32(totalWires)
        encoder.setBytes(&nDffs, length: MemoryLayout<UInt32>.size, index: 2)
        encoder.setBytes(&tWires, length: MemoryLayout<UInt32>.size, index: 3)
        
        let w = min(dffPipelineState.maxTotalThreadsPerThreadgroup, batchSize)
        let gridSize = MTLSize(width: batchSize, height: Int(numDFFs), depth: 1)
        let threadgroupSize = MTLSize(width: w, height: 1, depth: 1)
        
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()
    }
```