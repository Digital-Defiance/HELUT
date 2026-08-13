# HELUT Enhancement: Simultaneous 3-Rotor and 4-Rotor Batch Partitioning for P1030680

## Objective
Modify our batch initialization logic for the HELUT-Bombe tensor harness to simultaneously test both 3-rotor (M3-compatible mode with the Greek wheel locked to 'A') and full 4-rotor M4 hypotheses in a single batch run, leveraging our tensor batch dimension.

## Implementation Requirements
1. **Batch Slicing & Partitioning:**
   - **Lane Block A (The 3-Rotor Shortcut / Operator Error Mode):** Initialize a dedicated subset of batch lanes with the fourth "Greek" wheel explicitly locked to position 'A' with a matching ring setting (emulating a 3-rotor Enigma M3 configuration).
   - **Lane Block B (The Full M4 Space):** Initialize the remaining batch lanes to actively sweep across full 4-rotor permutations (varying Greek wheels like Beta/Gamma and thin reflectors).
2. **State Seeding:** Update the population of `stateInputs` so that each lane's initial rotor position and Greek wheel configuration match its assigned partition layout.
3. **Logging & Attribution:** Ensure that when the in-graph scoring or host-side sieve evaluates output tensors, it logs whether any high-scoring candidate originated from the 3-rotor block or the 4-rotor block.

## Constraints
- Do not modify `HELUTCore`. Keep all modifications isolated to the execution harness (`main.swift` / bombe target).
- Maintain strict `MPSDataType.uInt32` typing across all tensor buffers.

## Status
Shipped in the ASIC-esque cracker (`--hybrid`, see `ASIC_CRACKER.md`):
Block A = Greek=`A` via cleartext Metal/CPU batch `B=17576`; Block B = sampled or `--hybrid-full-greek`.
Fitness is boolean-faithful M4 (not mock-PBS). Plugboard stays host-side.
See also `evolution-hybridization.md`.