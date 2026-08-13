# HELUT-Bombe Architecture: Evolutionary Plugboard & Parallel Tensor Rotor Hybridization

## Objective
Implement a nested hybrid cryptanalytic engine for message P1030680 in Swift. We are pairing an outer genetic algorithm (for the combinatorial plugboard space) with our inner massively parallel tensor batch engine (for the discrete rotor starting positions). 

## Context & Constants
- **Target Ciphertext:** `JCRSAJTGSJEYEXYKKZZSHVUOCTRFRCRPFVYPLKPPLGRHVVBBTBRSXSWXGGTYTVKQNGSCHVGF` (72 letters)
- **Batch Space:** `B = 17,576` (Representing the full 26^3 rotor-start space).
- **Graph:** We are using our compiled M4 netlist. All tensor arithmetic is strictly `MPSDataType.uInt32`.

## Step-by-Step Implementation Plan

### 1. File Structure & Boundaries
- **DO NOT** modify anything inside `HELUTCore`. 
- Create a new file/struct named `HybridBombeHarness.swift` to house the evolutionary and scoring logic.

### 2. The Outer Loop: Genetic Algorithm (Host-Side)
Create a `PlugboardChromosome` struct to represent a candidate plugboard wiring.
- **Population:** Maintain a population of these chromosomes.
- **Mutation & Crossover:** Implement basic functions to randomly swap wire pairs (ensuring valid Enigma reciprocal plug constraints, max 10 pairs).
- **Fitness Score:** This will be updated by the inner tensor loop.

### 3. The Inner Loop: Tensor Batch Execution (Device-Side)
For each generation in the genetic algorithm, evaluate the population:
- Initialize the tensor batch `[17576, 1]` state placeholders. 
- **Partitioning:** Slice the batch initialization so Lane Block A tests the 3-rotor hypothesis (Greek wheel locked to 'A') and Lane Block B tests the full 4-rotor hypothesis.
- Feed the ciphertext and the current `PlugboardChromosome` mapping into the `graph.run` execution loop over 72 ticks.
- Ensure we use double-buffered ping-pong memory (`retainHistory: false`).

### 4. The Fitness Function & Scoring Sieve
After the tensor batch completes its run for a chromosome:
- Extract the 72-character output tensors across all 17,576 lanes.
- Write a lightweight host-side Swift function `calculateLinguisticScore(text: [UInt32]) -> Float`.
- **Scoring:** The function must calculate the Index of Coincidence (IC) and check for common German naval n-grams (e.g., `VON`, `UUU`, `EINS`).
- **Feedback:** Find the max score among the 17,576 lanes. Assign this max score as the fitness of the current `PlugboardChromosome`. 
- When the IC breaches `0.055` and naval cribs hit, halt the evolution and print the winning lane's rotor settings and plugboard.

## Strict Rules
- Write clean, compile-ready Swift 6 code.
- Do not hallucinate proprietary ML frameworks; rely only on `Metal` and `MetalPerformanceShadersGraph`.

# Addendum: Plugboard Pre/Post Processing (Keep it out of the LUTs)

To keep the tensor graph lean and avoid recompiling `MPSGraph` during evolution, the plugboard logic MUST NOT be compiled into the Verilog netlist. 

Instead, leverage the Enigma's reciprocal plugboard mathematics on the host:
1. Before feeding the `ciphertext` into the tensor graph, apply the current `PlugboardChromosome` character swaps to the input array in Swift.
2. The `HELUTCore` graph executes ONLY the rotor stepping and reflection mechanics.
3. After the graph outputs the batched plaintext arrays, apply the `PlugboardChromosome` character swaps again to the output arrays in Swift.
4. Run the linguistic scoring function on the final swapped output.

## Status
Shipped as the **veritable ASIC-esque cracker** (see `ASIC_CRACKER.md`):

- Outer GA: **shell + stecker** (WO / Greek / UKW / rings / plugs) via `--hybrid`
- Rings mutate freely by default — starting on AACU can walk to AAAA
- Inner datapath: cleartext Metal/CPU batch `B=17576` (`CleartextBatchHybrid.swift`)
- `--hybrid-lock-shell` for stecker-only; `--subspace potsdam|two-notch|full|…`

```bash
.build/release/helut --hybrid --quick
.build/release/helut --hybrid --rings AACU --hybrid-pop 32 --hybrid-gens 80
```