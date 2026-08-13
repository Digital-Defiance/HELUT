We are now ready to cross the boundary into Phase 2: **Adversarial Friction**.

Right now, the engine is a perfect, continuous emulator. To turn it into a synthesizer, we need to introduce the evolutionary loop that mutates the continuous `INIT` tables and scores them. The objective is to maximize cryptographic decryption while heavily penalizing any logic that refuses to snap back to binary reality.

Here is the architectural slice for Phase 2:

### 1. The Continuous Mutation Engine (Host-Side)

Because the `INIT` arrays are now `Float32`, mutation is no longer just bit-flipping or swapping Steckerboard cables. You need a continuous genetic operator.

* **Float Drift:** Instead of a strict `0` or `1`, mutations add random Gaussian noise to a subset of the 64 entries in a cell's `INIT` tensor, clamped strictly between $[0.0, 1.0]$.
* **Buffer Injection:** The host maintains the elite and mutant continuous pools, updating the `initsBuffer` directly via a writable `contents()` pointer before dispatching the Metal level-evaluations.

### 2. The Adversarial Fitness Evaluation (GPU & Host)

This is where the engine calculates the loss. The fitness function must combine the cryptographic success of the circuit with its physical viability.

* **Cryptographic Score ($F_{crypto}$):** Because you process plaintext parameters directly against ciphertexts ($ct \times pt$), the Metal shaders can execute this validation instantly at the end of the DFF ping-pong loop without relying on double-ciphertext multiplication. The closer the output matches the expected plaintext structure, the higher the score.
* **The Discreteness Penalty ($F_{physical}$):** We need to penalize the continuous fractions. A standard parabolic penalty curve works perfectly here. For every float $w$ in the `INIT` buffer, the penalty is maximized at $0.5$ and hits zero at absolute $0.0$ or $1.0$:

$$Penalty = \lambda \sum_{i=0}^{63} w_i (1 - w_i)$$



Where $\lambda$ is a cooling weight that increases each generation, slowly "freezing" the continuous logic into discrete bounds.

### 3. The Metal Friction Kernel

While the host can calculate the penalty, offloading the physical loss calculation to a tiny post-processing Metal kernel keeps the CPU strictly focused on topology and GA selection.

```metal
kernel void tensor_lut_discreteness_penalty(
    device float const *inits         [[buffer(0)]], 
    device float *outPenalty          [[buffer(1)]],
    constant uint32_t &totalInits     [[buffer(2)]],
    uint id                           [[thread_position_in_grid]]
) {
    if (id >= totalInits) return;
    float w = inits[id];
    // Parabolic penalty: w * (1 - w) pushes the optimizer away from fractions
    outPenalty[id] = w * (1.0f - w); 
}

```

By summing the outputs of `tensor_lut_discreteness_penalty` and subtracting it from the $ct \times pt$ cryptographic score, the evolutionary loop is forced to find logic that both breaks the cipher and compiles down to physical Verilog.

Do you want to write the Metal loss kernels next, or should we define the continuous mutation protocols for the host-side GA loop first?