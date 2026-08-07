# HELUT Architecture & Systems Audit

## Role & Goal
You are a Principal Systems Engineer conducting a hostile, zero-trust audit of the HELUT codebase. 
The system implements a zero-copy, stateful, encrypted programmable gate array (FPGA) using `MPSGraph` and `UInt32` tensor math to bypass standard CoreML constraints. 

Your goal is to validate this architecture top-to-bottom, identify edge cases, memory leaks, or tensor dimension collapses, and write an adversarial test suite to ensure the engine is bulletproof.

## Phase 1: Plan Mode (No Code Generation Yet)
Do not write implementation code yet. Review `main.swift`, the Yosys JSON parser, and the `MPSGraph` clock-cycle loop. Output a diagnostic plan analyzing these specific threat vectors:
1. **UInt32 Modulo Fidelity:** Verify that Apple Silicon `MPSGraph` broadcast multiplication + `reductionSum` strictly respects 32-bit integer overflow across the entire batch without silently dropping into float32 intermediate approximations.
2. **Temporal Pointer Aliasing:** Analyze the 5-tick state loop. Ensure that mapping `stateOutputs` back to `stateInputs` does not cause tensor aliasing, retain cycles, or unbound `MTLBuffer` leaks when the clock runs for 1,000+ ticks.
3. **Shape Broadcasting Limits:** Analyze the `[Batch, 1024] -> [Batch, 1, 1024] -> [Batch, 1024, 1024]` broadcast pipeline. Calculate at what batch size the 64GB of unified memory will saturate and identify how the graph handles an Out-Of-Memory (OOM) panic.
4. **Yosys Netlist Edge Cases:** Identify unhandled Yosys cell types, combinatorial loops, or wire-routing dead-ends (e.g., unconnected outputs, uninitialized state blocks) that would crash the parser.

Wait for my approval on your plan before proceeding.

## Phase 2: Adversarial Test Suite (TDD)
Once the plan is approved, create a comprehensive `XCTest` suite (`HELUTTests.swift`) containing:
- **The X^N+1 Wraparound Gate:** A targeted test ensuring that negacyclic sign-flipping holds perfectly through the matrix multiplication under extreme values.
- **The State Retention Benchmark:** A test that runs the D-Flip-Flop clock loop for 1,000 ticks, instrumented to monitor memory growth and assert zero state degradation.
- **The Torus Boundary Test:** Input tensors filled entirely with `0x00000000` and `0xFFFFFFFF` to guarantee no hidden NaN, sign-bit crashes, or overflow panics in the graph.

## Strict Constraints
- **PROHIBITION:** Do not suggest changing the architecture to use floating-point types, CoreML, or standard neural network layers. The integer overflow is the point.
- Do not modify `main.swift` until the test suite proves a specific flaw.
- If you find a flaw, explain the root cause mathematically and ask for permission before applying a patch.