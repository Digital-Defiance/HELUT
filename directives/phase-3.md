# HELUT PRD: Phase 3 (The Yosys Netlist Parser)

## Objective
Upgrade the HELUT graph compiler to ingest a Yosys JSON netlist and dynamically construct the `MPSGraph` topology. We are turning Verilog into a compiled cryptographic tensor graph.

## The Yosys JSON Structure
Yosys `write_json` outputs a structure where:
- `modules` contains the top-level module (e.g., `full_adder`).
- `ports` defines the Inputs and Outputs.
- `cells` defines the actual logic gates. For our pipeline, `type` will be `$lut`.
- `connections` (or `netnames`) use integer IDs to represent wires connecting the cells and ports.

## Implementation Plan
1. **The JSON Parser:** Write a Swift `Codable` struct to parse `netlist.json`. We need to extract the ports, cells, and wire IDs.
2. **The Wire Dictionary:** The compiler needs to track `[Int: MPSGraphTensor]` (mapping Yosys wire IDs to live `MPSGraph` outputs). 
3. **Graph Construction:**
   - **Inputs:** Iterate through `ports` (direction: input). Create an `InputNode` placeholder for each, and store its tensor in the wire dictionary.
   - **LUTs:** Iterate through `cells`. Extract the `LUT` parameter (this defines the truth table). Create a `LUTNode` (using the Phase 1 `UInt32` MatVec). Feed it the input tensors from the wire dictionary. Store its output tensor back into the wire dictionary using the cell's output wire ID. Note: Ensure `LUTNode` reshapes its output to `[1, 1024]` after the `reductionSum` to maintain dimensionality.
   - **Outputs:** Iterate through `ports` (direction: output). Retrieve the final tensors from the wire dictionary.
4. **The Execution:** Run the parser on `netlist.json`. Assert that the dynamic graph compiles without errors and print the final output tensors to confirm the shapes are `[1, 1024]`.

## Constraints
- The JSON parsing must be generic enough to handle any 2-input LUT truth table Yosys throws at it.
- Keep the `UInt32` constraint intact.