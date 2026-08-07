# HELUT Application #2: Batched Encrypted Search (HELUT-Search)

## Objective
Evaluate a 3-character pattern matcher across 10,000 encrypted document streams simultaneously in a single tensor pass to stress-test unified memory bandwidth.

## Memory Mechanics
- Batch Size: 10,000
- Input Placeholder Shape: `[10000, 1024]`
- Reshape in `LUTNode`: `[10000, 1, 1024]`
- Broadcast Matrix Multiply Shape: `[10000, 1024, 1024]` (`uInt32` ≈ 41.9 GB)
- `reductionSum(axis: 2)` back to `[10000, 1024]`

## Implementation Plan
1. Parse `regex_netlist.json` using the Phase 3 netlist compiler.
2. Instantiate placeholders for 24 input wires (3 chars × 8 bits).
3. Feed 10,000 mock encrypted character triples into the compiled `MPSGraph`.
4. Measure total wall-clock execution time and verify `match` output tensor shape is `[10000, 1024]`.

## Constraints
- All tensors must remain `MPSDataType.uInt32`.
