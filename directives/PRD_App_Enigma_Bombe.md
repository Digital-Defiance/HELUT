# HELUT Application: The Enigma Bombe (Massively Parallel Stateful Tensor Cryptanalysis)

## Objective
Build and execute a stateful, batched Enigma machine cryptanalysis engine ("HELUT-Bombe") using our validated `HELUTCore` library. We will synthesize a sequential Enigma core in Verilog, compile it to a JSON netlist via Yosys, and execute thousands of parallel rotor-stepping hypotheses across the batch dimension (`B = 10,000`) over multiple clock ticks.

## Step 1: Write the Verilog Core (`enigma_core.v`)
Create `enigma_core.v` in the repository root. It must implement:
- 3 rotors (fast, medium, slow) with mechanical turnover notch stepping logic.
- Synchronous reset (`resetn`) and clock enable semantics compatible with our `$_SDFF*` and `$_DFFE*` parser.
- Plugboard/scrambler wiring mapped to LUT lookup tables.
- Inputs: `clk`, `resetn`, `ciphertext_char[7:0]`.
- Outputs: `plaintext_char[7:0]`.

## Step 2: Synthesize via Yosys
Run the synthesis command in the terminal to generate the flat netlist:
yosys -p "read_verilog enigma_core.v; synth -top enigma_core -flatten; abc -lut 2; write_json enigma_netlist.json"

## Step 3: Implement the Execution Harness in `main.swift`
Update `main.swift` (or create a dedicated app target) to load `enigma_netlist.json`:
- Set batch dimension `B = 10,000` to simulate 10,000 parallel Enigma machine instances in unified memory.
- Initialize the state placeholders (`stateInputs`) across the batch lanes with different candidate initial rotor starting configurations (the *Grundstellung* hypotheses).
- Script the host clock loop for 10 ticks:
  - Feed the intercepted ciphertext stream into all batch lanes simultaneously.
  - Call `runClockCycles` using `retainHistory: false` with our double-buffered ping-pong memory discipline.
- Output or evaluate the resulting plaintext character tensors to isolate matching candidate keys.

## Constraints
- Do not modify `HELUTCore`. Utilize the existing flat-memory and DFFE/SDFF hold semantics.
- Keep all tensor arithmetic strictly as `MPSDataType.uInt32`.
