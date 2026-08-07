# HELUT PRD: Phase 2 (The Tensor Netlist Compiler)

## Objective
Build a graph compiler that takes a topological representation of a digital circuit (a netlist) and compiles it into a single, executable `MPSGraph`. 

## The Circuit: Encrypted Half-Adder
A Half-Adder takes two bits (A, B) and outputs a Sum and a Carry.
- Sum = A XOR B (In TFHE, this is a free vector addition)
- Carry = A AND B (In TFHE, this requires a LUT / Negacyclic MatVec)

## Implementation Plan
1. **The Netlist Structure:** Define a Swift representation of a circuit graph.
   - `InputNode` (Accepts dynamic input tensors).
   - `AddNode` (Uses `MPSGraph.addition` for XOR).
   - `LUTNode` (The Bootstrapping step).
2. **The MatVec Workaround:** `MPSGraph.matrixMultiplication` does not support `UInt32`. The `LUTNode` MUST be implemented using the Phase 1 workaround: a broadcast multiplication followed by a `reductionSum` on axis 1, yielding a shape of `[N, 1]`.
3. **The Graph Builder:** Write a compiler class that traverses the circuit structure and constructs a persistent `MPSGraph`.
   - Wires between nodes must be implemented as `MPSGraphTensor` outputs feeding directly into subsequent node inputs.
4. **The Execution:** Hardcode the Half-Adder netlist. Pass in two mock ciphertexts (vectors of $N=1024$). Assert that the `MPSGraph` successfully evaluates the topology and outputs the Sum and Carry tensors.

## Constraints
- Maintain the exact `UInt32` execution from Phase 1. 
- Keep all operations within a single, unified `MPSGraph` instance to ensure zero-copy routing between gates.