# HELUT Application #1: The Encrypted CPU (State Retention)

## Objective
Upgrade the HELUT netlist parser to handle sequential logic (memory) by parsing Yosys D-Flip-Flops (`$_DFF_P_`) and wiring them as stateful feedback loops across multiple `graph.run` executions.

## The Architectural Leap (The Clock Cycle)
Combinational LUTs evaluate instantly. D-Flip-Flops hold state across clock cycles. 
To emulate a clock cycle in `MPSGraph`:
1. Every `$_DFF_P_` cell in the JSON requires TWO things: 
   - A `StateInputNode` (a placeholder fed into the graph at the start of the tick).
   - A `StateOutputNode` (the output tensor we read at the end of the tick).
2. The DFF cell connects its internal input wire (`D`) to the `StateOutputNode`, and its internal output wire (`Q`) to the logic gates via the `StateInputNode`.
3. The Swift host acts as the Clock:
   - Tick 1: Initialize the state placeholders with `UInt32` zeros. Run the graph. Read the `StateOutputNode` tensors.
   - Tick 2: Feed those exact output tensors back into the `StateInputNode` placeholders. Run the graph again.

## Implementation Plan
1. **JSON Parser Update:** Add support for parsing `$_DFF_P_` cells from `core_netlist.json`.
2. **State Nodes:** Create arrays to track `stateInputs` (placeholders) and `stateOutputs` (tensors to evaluate).
3. **The Clock Loop:** Write a Swift `for` loop that executes `graph.run` 5 times (5 clock cycles).
4. **The Execution:** Set the `en` (enable) input to an encrypted `1`. Run the 5 ticks.
5. **The Verification:** The graph should compile successfully, and the loop should pass the 4-bit state tensors from one iteration to the next without dimension mismatches. 

## Constraints
- Drop the batch dimension back down to `1` (shape `[1, 1024]`) for this test so we can focus strictly on the temporal routing.
- Keep all operations as `MPSDataType.uInt32`.
