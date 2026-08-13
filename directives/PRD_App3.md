# HELUT Application #3: Zero-Noise Encrypted AI (Decision Trees)

## Objective
Prove that HELUT can evaluate exact non-linear logic across a massive batch of encrypted records simultaneously by utilizing a tensor batch dimension.

## The Circuit
We synthesized `decision_tree.v` into `tree_netlist.json`. It takes two 4-bit features and outputs a 1-bit binary classification (High Risk).

## The Tensor Batching Flex (The Core Mechanic)
Instead of evaluating 1 record, we will evaluate 1,000 records in parallel in a single tensor pass.
1. The `InputNode` placeholders must be created with shape `[1000, 1024]`.
2. The `LUTNode` must be upgraded to handle the batch dimension smoothly:
   - Input Tensor Shape: `[1000, 1024]`
   - Reshape to: `[1000, 1, 1024]`
   - Broadcast Multiply against the static `[1024, 1024]` Negacyclic Toeplitz Matrix.
   - The intermediate mathematical tensor will explode to `[1000, 1024, 1024]` in unified memory.
   - Run `reductionSum(axis: 2)` to collapse it back.
   - Output Tensor Shape must be `[1000, 1024]`.

## Implementation Plan
1. Parse `tree_netlist.json` using the existing Phase 3 parser.
2. Compile the updated batch-aware `MPSGraph`.
3. Feed the graph 1,000 mock encrypted patient records.
4. Measure and print the wall-clock time required for the NPU/GPU to evaluate the graph.
5. Print the output tensor shape to confirm it evaluated exactly 1,000 records simultaneously.

## Constraints
- Everything must remain `MPSDataType.uInt32`. Do not use floating-point types.
