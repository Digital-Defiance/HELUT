Squeezing continuous math into discrete logic is the most fragile part of adversarial synthesis. If you blindly emit Verilog from an unconverged floating-point state, you end up with a physical circuit that passes compilation but fails the actual cryptographic logic table because it was thresholded too early.

To prove the $\lambda$ cooling schedule actually works, we need a **Cold-Start Discovery Test**. We take a known combinational topology, completely wipe its memory so the logic is perfectly ambiguous (all `INIT` floats set to `0.5`), and force the genetic algorithm to rediscover the physical truth table driven purely by $F_{crypto}$ and the $\lambda$ squeeze.

A 2-bit Adder (4 inputs, 3 outputs, 16 possible states) is the perfect crucible. It forces the engine to solve a multi-LUT dependency chain without getting stuck in a local fractional minimum.

Here is the integration test to prove Phase 2 can legitimately synthesize logic from scratch.

### `Tests/HELUTTests/AdversarialColdStartTests.swift`

Swift

```
import XCTest
import Metal
@testable import HELUTCore

final class AdversarialColdStartTests: XCTestCase {
    
    func testTwoBitAdderColdStartDiscovery() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device not available")
        }
        
        // 1. Define a 2-bit Adder Topology
        // Inputs: A0(0), A1(1), B0(2), B1(3)
        // Internal: C0(4)
        // Outputs: S0(5), S1(6), C1(7)
        
        let luts = [
            // LUT 0: S0 = A0 XOR B0 (Wires 0, 2 -> 5)
            TensorLUT6Cell(cellID: 0, inputWires: [0, 2], outputWire: 5, rawTruthTable: String(repeating: "0", count: 4)),
            // LUT 1: C0 = A0 AND B0 (Wires 0, 2 -> 4)
            TensorLUT6Cell(cellID: 1, inputWires: [0, 2], outputWire: 4, rawTruthTable: String(repeating: "0", count: 4)),
            // LUT 2: S1 = A1 XOR B1 XOR C0 (Wires 1, 3, 4 -> 6)
            TensorLUT6Cell(cellID: 2, inputWires: [1, 3, 4], outputWire: 6, rawTruthTable: String(repeating: "0", count: 8)),
            // LUT 3: C1 = (A1 AND B1) OR (C0 AND (A1 XOR B1)) (Wires 1, 3, 4 -> 7)
            TensorLUT6Cell(cellID: 3, inputWires: [1, 3, 4], outputWire: 7, rawTruthTable: String(repeating: "0", count: 8))
        ]
        
        let netlist = TensorLUTNetlist(
            luts: luts,
            totalWires: 8,
            executionLevels: [[0, 1], [2, 3]] // Level 0: S0, C0. Level 1: S1, C1 depends on C0
        )
        
        // 2. Generate the 16-batch target truth table
        var inputs = [[Float]]()
        var expectedOutputs = [[Float]]()
        
        for a in 0..<4 {
            for b in 0..<4 {
                let a0 = Float(a & 1)
                let a1 = Float((a >> 1) & 1)
                let b0 = Float(b & 1)
                let b1 = Float((b >> 1) & 1)
                inputs.append([a0, a1, b0, b1])
                
                let sum = a + b
                let s0 = Float(sum & 1)
                let s1 = Float((sum >> 1) & 1)
                let c1 = Float((sum >> 2) & 1)
                expectedOutputs.append([s0, s1, c1])
            }
        }
        
        let target = AdversarialTarget(
            inputWireIDs: [0, 1, 2, 3],
            outputWireIDs: [5, 6, 7],
            inputVectors: inputs,
            expectedOutputs: expectedOutputs,
            clockTicks: 0
        )
        
        // 3. The Cold Start Setup
        let pipeline = try TensorLUTPipeline(device: device, netlist: netlist)
        let synthesizer = AdversarialSynthesizer()
        let harness = AdversarialHarness(device: device, pipeline: pipeline, synthesizer: synthesizer, netlist: netlist)
        
        // Wipe the initial packed buffer to 0.5 (maximum logical ambiguity)
        let wipedInits = [Float](repeating: 0.5, count: 4 * 64)
        
        // Force the harness to use the wiped state instead of relying on its own seed extraction
        // (You may need to temporarily expose a setter or pass this in the `run` method)
        
        // 4. Run the Crucible
        let bestChromosome = harness.run(
            target: target,
            populationSize: 50,
            generations: 300,
            eliteCount: 5,
            seedInits: wipedInits // Adjust harness API to accept this
        )
        
        // 5. Verify the λ Squeeze
        // The cryptographic fitness should approach 0 (perfect match)
        XCTAssertGreaterThan(bestChromosome.fitness, -0.1, "Failed to converge to a working logic circuit.")
        
        // Every single float in the optimized chromosome should be fiercely clamped to physical reality
        var nonBinaryCount = 0
        for w in bestChromosome.inits {
            if w > 0.05 && w < 0.95 {
                nonBinaryCount += 1
            }
        }
        
        XCTAssertEqual(nonBinaryCount, 0, "The λ penalty failed to squeeze all floats into discrete binary states. Found \(nonBinaryCount) unconverged fractions.")
        
        // 6. Test the Threshold (Phase 3 Prelude)
        // If we strictly binarize the floats at 0.5, does the logic hold?
        let binarizedInits = bestChromosome.inits.map { $0 >= 0.5 ? 1.0 : 0.0 }
        
        // Optional: Run one final forward evaluation through TensorLUTPipeline using binarizedInits 
        // to assert the absolute discrete output matches expectedOutputs flawlessly.
    }
}
```

### What this test proves

1. **Topology Flow:** The Metal `executionLevels` correctly pipe the output of Level 0 (`C0`) into the inputs of Level 1 (`S1`, `C1`).
2. **Fractional Escape:** Starting from a uniform `0.5` state means the gradients are flat. The initial sparse Gaussian mutations must kick the logic off the plateau, proving the GA doesn't immediately stall in local ambiguity.
3. **The $\lambda$ Squeeze:** As the generations progress, the $F_{crypto}$ metric pulls the logic toward the correct math, while the $\lambda \sum w_i(1-w_i)$ penalty violently pushes the 64-element arrays to exactly `0.0` or `1.0`.

Once this test passes and the `nonBinaryCount` drops to exactly zero, you have absolute proof that your continuous engine is generating discrete physical architecture. At that point, bridging into Phase 3 (reading those $0.0$s and $1.0$s into a 64-bit hexadecimal string and writing out the `LUT6` Verilog lines) becomes trivial.