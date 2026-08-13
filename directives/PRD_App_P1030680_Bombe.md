# HELUT-Bombe Adaptation: Message P1030680 (M-Thetis / M4)

## Objective
Turn the HELUT tensor pipeline into a dedicated cryptanalytic engine for unbroken Kriegsmarine message [P1030680](https://enigma.hoerenberg.com/index.php?cat=Unbroken&page=P1030680) (U-534, 1 May 1945, suspected **M-Thetis**).

Ciphertext (72 letters, no indicators):

`JCRSAJTGSJEYEXYKKZZSHVUOCTRFRCRPFVYPLKPPLGRHVVBBTBRSXSWXGGTYTVKQNGSCHVGF`

## 1. M4 Circuit Specialization
- Verilog: `enigma_m4_core.v`
- Static Greek Zusatzwalze (β/γ), thin Umkehrwalze B/C, three stepping naval rotors (I–VIII)
- Parameters: `GREEK_SEL`, `UKW_SEL`, `ROTOR_L/M/R`, `GREEK_POS` (outer Thetis partition)
- Default partition: γ / IV-III-VIII / thin B / Greek window A (re-synth for other WOs)
- Yosys → `enigma_m4_netlist.json`

```bash
yosys -p "read_verilog -sv enigma_m4_core.v; synth -top enigma_m4_core -flatten; abc -lut 2; write_json enigma_m4_netlist.json"
```

## 2. Batch-Space Hypothesis Partitioning (B = 17,576)
- `B = 26³ = 17,576` — every three-letter L/M/R Grundstellung / message-key window
- Lane `i` ↔ `(R, M, L) = (i % 26, ⌊i/26⌋ % 26, ⌊i/676⌋)`
- Greek window / UKW / Walzenlage / stecker fixed per netlist (outer host loop or recompile)
- Girard indicator notes (`VROL NMKA`, mistaken Potsdam MNNS/DGUG) stay host-side constraints

## 3. Automated Linguistic Scoring Circuit
- Output port `linguistic_score[15:0]` in the netlist (end of MPSGraph outputs)
- Accumulates German/naval trigram hits (`EIN`, `CHT`, `NDE`, `DER`, `UND`, `VON`, `UUU`, …) plus light monogram priors
- Harness ranks all batch lanes by this score after the ciphertext stream

## Run

```bash
# Graph compile only (default B=17576, M4 netlist)
swift run -c release helut -- --p1030680-bombe --compile-only

# Wider batch on 64 GB (probe compile, then 1 tick before full stream)
swift run -c release helut -- --p1030680-bombe --batch 30000 --compile-only
swift run -c release helut -- --p1030680-bombe --batch 30000 --ticks 1

# Short Metal smoke (10 ticks of P1030680)
swift run -c release helut -- --p1030680-bombe --ticks 10

# Full 72-letter stream (long-running)
swift run -c release helut -- --p1030680-bombe

# Host oracle CO attack (boolean-faithful; preferred for actual cryptanalysis)
swift run -c release helut -- --break-p1030680
```

## Constraint
Mock-PBS does not preserve boolean plaintext. Tensor score spikes demonstrate the batched graph + scoring wiring; cryptanalytic claims use the host M4 oracle (`--break-p1030680`).
