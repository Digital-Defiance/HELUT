Here is the strategic contract for Phase 2:

### 1. The Genome & Mutation Protocol

- **The Chromosome:** The genome is the flattened `packedINITBuffer()`: a continuous `Float32` array of size `num_luts * 64`. For a 925-LUT Enigma core, that is 59,200 floats.
- **Mutation Strategy:** Mutating all 59k floats randomly is too chaotic. We apply a **Sparse Gaussian Drift**: we target a percentage of the floats (e.g., 5%), inject Gaussian noise $\mathcal{N}(0, \sigma)$, and clamp the result strictly between `0.0` and `1.0`. As the $\lambda$ penalty increases, $\sigma$ shrinks, naturally "cooling" the mutations into fine-tuning.

### 2. $F_{crypto}$ (Soft-Scoring the Wire States)

Because the TensorLUT emits fractional wire states (e.g., a pin sitting at `0.72`), passing those directly to a discrete Enigma IC/trigram scorer will crash or threshold early, destroying the gradient.

- **The $ct \times pt$ Metric:** We score the continuous network outputs directly against the binary bits of a known target template. If the target plaintext expects output wire 42 to be `1`, and the TensorLUT outputs `0.72`, the error is `0.28`.
- **The Soft Score:** $F_{crypto}$ is the negative Mean Squared Error (MSE) or Cross-Entropy of the output wires against the target bits. Maximum cryptographic fitness is `0.0` (a perfect binary match to the target).

### 3. The $\lambda$ Cooling Schedule

- **Generational Ramp:** $\lambda$ starts at `0.0` (pure mathematical exploration) and scales exponentially or parabolically over $G$ generations: $\lambda_g = \lambda_{max} \times (g / G_{total})^2$.
- **The Squeeze:** Early generations prioritize breaking the cipher ($F_{crypto}$). Late generations prioritize physical viability ($Penalty$).

Here is the Phase 2 slice, connecting the host GA contract, the Metal penalty kernel, and the `vDSP` reduction.

### 1. The Metal Friction Kernel (`TensorLUTFriction.metal`)

A microscopic, lightning-fast kernel to compute the parabolic distance from absolute binary.

Code snippet

```
#include <metal_stdlib>
using namespace metal;

kernel void tensor_lut_discreteness_penalty(
    device float const *inits       [[buffer(0)]], 
    device float *outPenalties      [[buffer(1)]], // Same dimension as inits
    constant uint32_t &totalFloats  [[buffer(2)]],
    uint id                         [[thread_position_in_grid]]
) {
    if (id >= totalFloats) return;
    
    float w = inits[id];
    // Parabolic penalty: max at 0.5, zero at 0.0 and 1.0
    outPenalties[id] = w * (1.0f - w); 
}
```

### 2. The Host-Side GA Contract (`AdversarialSynthesizer.swift`)

This module defines the continuous chromosome, applies the sparse Gaussian drift, and computes the total penalized fitness. We utilize Apple's Accelerate framework (`vDSP`) for zero-overhead array reduction on the host.

Swift

```
import Foundation
import Metal
import Accelerate // For vDSP_sve (Sum of Vector Elements)

package struct TensorChromosome {
    package var inits: [Float]
    package var fitness: Float = -Float.greatestFiniteMagnitude
}

package final class AdversarialSynthesizer {
    
    // GA Hyperparameters
    private let mutationRate: Float = 0.05 // Mutate 5% of floats per child
    private let maxNoise: Float = 0.3      // Gaussian spread
    private let lambdaMax: Float = 10.0    // Terminal penalty weight
    
    /// Sparse continuous mutation with clamping
    package func mutate(chromosome: inout TensorChromosome, currentGen: Int, totalGens: Int) {
        // Shrink noise variance as generations progress (simulated cooling)
        let progress = Float(currentGen) / Float(totalGens)
        let currentNoise = maxNoise * (1.0 - progress * 0.8) // Cool down to 20% of max noise
        
        for i in 0..<chromosome.inits.count {
            if Float.random(in: 0..<1) < mutationRate {
                // Approximate Gaussian noise via Box-Muller or simplified uniform accumulation
                let u1 = Float.random(in: 0..<1)
                let u2 = Float.random(in: 0..<1)
                let z0 = sqrt(-2.0 * log(u1)) * cos(2.0 * .pi * u2) // Standard Normal
                
                let drift = z0 * currentNoise
                var w = chromosome.inits[i] + drift
                
                // Clamp strictly to [0.0, 1.0] physical bounds
                w = max(0.0, min(1.0, w))
                chromosome.inits[i] = w
            }
        }
    }
    
    /// Soft $ct \times pt$ scoring: Mean Squared Error against expected output bits
    package func computeCryptoFitness(tensorOutputWires: [Float], targetBits: [Float]) -> Float {
        precondition(tensorOutputWires.count == targetBits.count)
        var errorSum: Float = 0.0
        
        // vDSP could also do this, but loop is fine for narrow output bit vectors (e.g., 5-bit Baudot)
        for i in 0..<tensorOutputWires.count {
            let diff = tensorOutputWires[i] - targetBits[i]
            errorSum += diff * diff
        }
        
        // F_crypto: 0.0 is perfect match, increasingly negative for errors
        return -errorSum
    }
    
    /// Evaluates the physical penalty via Metal, reduced via vDSP, and applies the Lambda schedule.
    package func computeTotalFitness(
        chromosome: inout TensorChromosome,
        cryptoFitness: Float,
        currentGen: Int,
        totalGens: Int,
        penaltyEncoder: MTLComputeCommandEncoder,
        penaltyPipelineState: MTLComputePipelineState,
        initsBuffer: MTLBuffer,
        outPenaltiesBuffer: MTLBuffer
    ) {
        let totalFloats = chromosome.inits.count
        var tFloats = UInt32(totalFloats)
        
        // 1. Dispatch Metal Penalty Kernel
        penaltyEncoder.setComputePipelineState(penaltyPipelineState)
        penaltyEncoder.setBuffer(initsBuffer, offset: 0, index: 0)
        penaltyEncoder.setBuffer(outPenaltiesBuffer, offset: 0, index: 1)
        penaltyEncoder.setBytes(&tFloats, length: MemoryLayout<UInt32>.size, index: 2)
        
        let gridSize = MTLSize(width: totalFloats, height: 1, depth: 1)
        let threadgroupSize = MTLSize(width: min(penaltyPipelineState.maxTotalThreadsPerThreadgroup, totalFloats), height: 1, depth: 1)
        penaltyEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadgroupSize)
        
        // (Assume commandBuffer.commit() & waitUntilCompleted() happens here in the runner)
        
        // 2. Fast Host Reduction using Accelerate
        let penaltiesPtr = outPenaltiesBuffer.contents().bindMemory(to: Float.self, capacity: totalFloats)
        var sumPenalty: Float = 0.0
        vDSP_sve(penaltiesPtr, 1, &sumPenalty, vDSP_Length(totalFloats))
        
        // 3. Apply Lambda Parabolic Schedule
        let progress = Float(currentGen) / Float(totalGens)
        let lambda = lambdaMax * (progress * progress)
        
        // Total Fitness Objective
        chromosome.fitness = cryptoFitness - (lambda * sumPenalty)
    }
}
```