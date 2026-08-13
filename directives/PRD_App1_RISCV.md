# HELUT Capstone: Encrypted RISC-V Core Execution

## Objective
Load the synthesized `picorv32_netlist.json` into the HELUT engine and successfully boot the encrypted CPU by simulating 10 clock cycles.

## The Architecture
The PicoRV32 core is massive (thousands of LUTs and DFFs). Our Phase 2 patches ensure that `MPSGraph` will evaluate it perfectly without memory leaks or missing enable semantics.
- We will run `batchSize = 1`.
- The CPU has a `resetn` (active-low reset) pin. To boot the CPU, we must hold `resetn = 0` for the first few ticks, then raise it to `1`.

## Implementation Plan
1. Update `main.swift` to load `picorv32_netlist.json`.
2. Locate the input placeholder for the `resetn` port. 
3. Modify the host clock loop:
   - Ticks 1-3: Feed an encrypted `0` into the `resetn` port to clear the CPU registers.
   - Ticks 4-10: Feed an encrypted `1` into the `resetn` port to let the CPU start executing.
   - All other input ports (like memory read data) can be fed encrypted `0`s for this idle boot test.
4. Execute `runClockCycles` for 10 ticks with `retainHistory = false`.
5. Measure the setup time (graph compilation) and the average wall-clock time per tick.

## Constraints
- Do not modify `HELUTCore`. The library is validated and locked. All changes must happen in the executable `main.swift`.
