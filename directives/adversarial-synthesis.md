# HELUT Adversarial Synthesis: The Continuous-Discrete Compiler Loop

Traditional hardware compilation maps static logic to silicon. The HELUT Adversarial Synthesizer acts as a generative cryptographic compiler, pitting continuous mathematical optimization against the strict, discrete realities of physical hardware.

By running a forward tensor-extraction pipeline against a reverse logic-instantiation pipeline, the engine evolves cryptographic logic in floating-point space and forces it to reconcile with binary physical limits. The result is auto-generated, highly optimized physical Verilog tailored specifically for the decryption target.

## Phase 1: Forward Extraction (Melting the Silicon)

The forward pass strips away physical routing and structural anomalies, converting rigid digital logic into uniform, continuous mathematical arrays.

- **Dimensional Uniformity Constraint:** The Yosys synthesis pass is strictly constrained to generate perfectly uniform $N$-input components, typically exclusively 6-input Look-Up Tables (LUT6).
- **Tensor Mapping:** Every LUT6 is translated into a uniform tensor representation. A LUT6 becomes a perfectly aligned 64-bit vector.
- **Branchless GPU Execution:** Because the generated tensors are structurally identical, they require zero memory padding. The logic translates into pure, branchless matrix operations executed across the Metal shaders.
- **Mathematical Emancipation:** Once loaded into unified memory, the hardware logic is no longer restricted to absolute binary states (`0` or `1`). It transitions into continuous floating-point space, allowing genetic or gradient-free algorithms to mutate the logic probabilistically.

## Phase 2: Adversarial Friction and Loss

The system optimizes the continuous tensor matrices to solve the cryptographic objective, but pure mathematics naturally drifts toward continuous fractions that physical hardware cannot execute. The adversarial loop computes a loss function between the ideal mathematical state and the discrete physical reality.

- **Native Parameter Processing:** To calculate fitness rapidly, the architecture bypasses heavy double-ciphertext multiplication. The Metal shaders remain lean and execute at maximum bandwidth by processing plaintext parameters directly against the ciphertexts ($ct \times pt$).
- **Cryptographic Fitness:** The primary objective function evaluates how effectively the mutated tensor logic decrypts the target ciphertext, climbing toward higher linguistic or structural scores.
- **Physical Penalty:** A secondary loss function applies a penalty based on how far the continuous tensor values have drifted from binary absolutes. Logic gates attempting to sit at 60% activation are increasingly penalized, forcing the algorithm to find optimizations that can actually survive discretization.

## Phase 3: Reverse Instantiation (The Physical Anchor)

Once the tensor engine discovers a highly optimized logical state, the reverse pipeline forces the continuous math back into physical silicon constraints.

- **Quantization / Cooling:** The optimized floating-point tensors are processed through a cooling schedule (such as simulated annealing) or a strict step-function threshold, violently snapping the probabilistic logic back into discrete `1`s and `0`s.
- **Truth Table Generation:** The quantized tensor states are grouped back into their native blocks. A 64-element binarized tensor array directly forms the 64-bit hexadecimal initialization string required for a physical logic gate.
- **Verilog Synthesis:** The engine generates raw, gate-level Verilog code, outputting explicit physical instantiations (e.g., `LUT6 #( .INIT(64'h...) )`). The result is a novel, highly optimized FPGA netlist ready for immediate deployment.

## Phase 4: Targeted Melting (Avoiding Dependency-Chain Shatter)

Full cold-start on a 925-LUT sequential cipher discovers continuous shortcuts that shatter under λ squeeze. Targeted melting freezes known-good LUT blocks and only evolves the unknown region.

- **`freezeMask`:** Per-LUT boolean on `TensorChromosome`. Frozen indices skip Gaussian mutation, crossover swaps, and the Metal \(\sum w(1-w)\) penalty.
- **Wipe scope:** Only melt-region INITs are set to `0.5`; rotors/stepping keep binary physical tables.
- **Cone tagger:** On abc-flattened `enigma_m4`, `TensorLUTConeTagger` recovers edge stecker indices (CT-closure + registered-PT unwrap) without re-synthesis. CLI: `--tag-stecker-cones` / `--melt-stecker`.
- **Early resignation:** If melt-region non-binary count is still above threshold when λ hits its midpoint, the lineage resigns and reboots from a fresh wipe (`--cold-resign-nonbinary`, `--cold-resign-restarts`). Doomed reciprocal shortcuts are not squeezed to the end.
- **CLI:** `--tensorlut-targeted-melt --melt-stecker` (or explicit `--melt-luts …`).
- **Stecker involution (not INIT melt):** The 16 cone LUTs are I/O codecs around an *identity* `plugboard()` in the abc netlist — melting their INITs cannot invent reciprocal letter swaps. Instead freeze the full TensorLUT core and evolve a `SteckerInvolution` (≤10 disjoint pairs). Sandwich: inject `S(CT)` → frozen core → score soft PT vs bits of `S(P)`. Reciprocity is structural. Short cribs leave unused pairs unconstrained and can admit false \(F=0\) steckers — grade **active-map** agreement on CT∪PT, use **parsimony**, **`--stecker-grow`** (raise pair budget on plateau), and **soft freeze + thaw** (sequential plugs with escape). Blind 3-pair rediscovery on a 14-letter crib recovers `AB CD EF` with full-map PASS (`logs/tensorlut-m4-stecker-involution-blind-3pair.log`). CLI: `--tensorlut-stecker-involution --stecker-blind --stecker-target …`.

## Hardware and Execution Environment

The sheer parallel throughput required to constantly evaluate, mutate, and quantize these matrices demands an environment without traditional architectural bottlenecks.

- **Compute Engine:** The full adversarial loop executes on an Apple M4 Max MacBook Pro, heavily leveraging its unified memory architecture to pass massive tensor grids between the CPU (managing the evolutionary loop) and the GPU (executing the branchless matrix math) with zero memory copy overhead.
- **State Logging and I/O:** Logging the fitness scores and physical Verilog checkpoints of millions of candidate circuits generates massive data throughput. To prevent the I/O write speeds from bottlenecking the Metal shaders, state data is streamed directly to an external NVMe drive connected via USB utilizing the USB Attached SCSI (UAS) protocol.
