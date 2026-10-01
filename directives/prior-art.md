# Prior art (checked 2026-09-30)

This is a literature pass, not a claim row. Nothing here is a C, H, or N.
"To our knowledge" means these searches did not find a counterexample. It is
not a proof that none exists.

## Cite, do not imply novelty

**Verilog under TFHE.** HELM turns synthesizable Verilog into CGGI circuits
with a gate mode and lookup-table modes, including sequential circuits
(Gouert, Mouris, and Tsoutsos, ePrint 2023/1382; IEEE TIFS 2025). Romeo, the
earlier HDL-to-encrypted-evaluation paper from the same group, is DAC 2020,
not 2022. Google's HEIR lowers Verilog through Yosys into a CGGI pipeline.
Scytale (Shokri and Tsoutsos, ePrint 2026/361, DATE 2026) evaluates LUT
circuits up to 12 bits by circuit bootstrapping and vertical packing, on top
of HEIR. That is a different route from packing weighted wires into one
programmable bootstrap.

**Weights before a bootstrap.** Zama's Concrete optimizer states that noise
growth depends on the 2-norm of any dot product of ciphertexts with integer
weights, and sizes the preceding bootstrap from that norm (Concrete optimizer
docs; Bergerat et al., ePrint 2022/704). HELUT's port-weighted gate is the
same kind of fact for public-MS LUT packing: a refreshed native error is
multiplied by the port weight 2^i. The certificate bounds the sum of those
weights. It is not Concrete's variance formula, and it is not a new noise law.

**GPU RTL simulation.** RTLFlow (NVIDIA, ICPP 2022) compiles RTL to CUDA and
runs a batch of stimuli. GEM (Guo, Zhang, Wang, Lin, and Ren, DAC 2025) maps
a gate-level netlist onto a virtual VLIW processor and runs it in CUDA, up to
64× over CPU simulators in the paper. HELUT's cleartext path is the Metal
laboratory, and the same Yosys artifact feeds the encrypted path and the
relaxation.

**Multilinear LUT relaxation.** Differentiable logic gate networks (Petersen,
Borgelt, Kuehne, and Deussen, NeurIPS 2022) relax discrete gates so they can
be trained. DiffLUT-Net (Ye et al., arXiv:2609.09254, 8 September 2026)
parameterises each 6-LUT truth table as a multilinear relaxation that is exact
on binary inputs, trains the network from scratch, and emits synthesizable
Verilog. That is TensorLUT's formula. Those papers learn new networks. They
do not melt the tables of an existing third-party sequential core against a
cipher-stream fitness.

## To our knowledge, after this pass

These searches (HELM, HEIR, Scytale, Concrete, GEM, RTLFlow, DiffLUT-Net,
cuFHE, cuFHEpp, VeloFHE) did not find:

- a TFHE blind rotation on Apple Metal (the GPU TFHE implementations found
  are CUDA or ROCm; Apple's published Swift HomomorphicEncryption library is
  BFV)
- one Yosys netlist held to bit-level agreement across a cleartext GPU
  engine, an encrypted engine, and a relaxation that emits Verilog again
- a deletion-tolerant diagonal board whose pruning is proved complete and
  checked against the host

The deletion-tolerant board and the Enigma GPU literature (enigma-cuda,
Krah, Ostwald–Weierud) were not re-read in this pass. Do not upgrade that
row from the earlier note without opening those sources.

Parendi on Graphcore was named from memory in the first note and was not
verified here. Leave it off the site.

## Not yet earned

A certified encrypted tick of unmodified PicoRV32 on Apple silicon is still
open. The LUT3 netlist at k=127 has two receipts (one all-zero tick, and four ticks
with reset released on tick 4; log₂ε=−747.6, outputs and DFF Q matched).
Neither is a claim row, and neither is a fetch.
The sampled mixed-strategy melt is not a result. The tolerant
board is not a published method.
