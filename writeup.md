<!-- Generated from writeup.tex — do not edit by hand. Run: make writeup   (or ./Scripts/build_writeup.sh writeup.tex) -->

# Hardware Determinism over Statistical Gradients: A GPU-Accelerated Boolean Attack on the Final U-534 Enigma M4 Ciphertext (P1030680)

*Digital Defiance HELUT Campaign Report · August 2026*

## Abstract

For decades, message P1030680 has remained the sole unbroken Enigma M4 transmission from the May 1, 1945 intercept of German submarine U-534. Modern attempts to decrypt this 72-letter ciphertext have historically relied on statistical hill-climbing and distributed computing. This report shows that purely statistical attacks fail against short M4 ciphertexts due to plugboard overfitting, documents a mid-message middle-rotor turnover flaw in whole-message trigram scoring, and describes a software Welchman diagonal board on Apple Silicon Metal ( 40 million machine settings per second) with a mandatory $\le 10$-plug completion kill chain. We record graded controls (known-message break), archival eliminations, clean negatives under catalog and operational cribs, a quarantine path for soft near-misses, and a parallel TensorLUT continuous--discrete compiler track. We do not claim a decrypt of P1030680. Campaign fitness is cleartext Metal batch, not HELUT's encrypted torus path (documented separately in `paper/helut.tex`).

# The Failure of Statistical Gradients on Short Ciphertexts

When attempting to break an Enigma ciphertext, modern cryptographic approaches default to statistical optimization, such as Index of Coincidence (IC), $n$-gram fitness, and genetic algorithms. However, empirical testing against P1030680 proves that statistics cannot *search* a 72-letter Enigma space; they can only *rank* a small list of survivors.

The Enigma plugboard (the *Steckerbrett*) offers roughly 47 bits of freedom. On a short message, this immense freedom causes statistical models to overfit. Algorithms will output high-scoring strings of letters that closely resemble German syntax, but these strings are mathematical hallucinations. Control tests on a known, solved message (P1030684) confirmed that purely statistical engines favor these false positives over the true key. Consequently, any successful attack on short M4 intercepts must abandon statistical guessing in favor of absolute Boolean logic.

# Emulating the Welchman Diagonal Board in GPU Shaders

To execute a deterministic attack, the hardware architecture of the 1945 Enigma must be perfectly mapped to modern hardware. Using Homomorphic Edge Look-Up Tensors (HELUT), we engineered a digital Bombe inside Apple Silicon Metal shaders.

This software-defined FPGA evaluates Gordon Welchman's diagonal board graph reductions at a rate of 40 million machine settings per second. The engine utilizes Turing-shaped reductions based on the physical reality of the short-message M4:

- Because the far-left Enigma rotor (the Greek wheel) never steps during a short message, its ring can be digitally pinned.

- Because the left rotor's notch drives nothing, its ring can also be pinned.

- Together, this physical constraint collapses the total search space by a massive factor of 676.

The mathematical soundness of this reduction was verified in a blind control run. Given a 27-letter crib from a known message (P1030684) and no other parameters, the GPU pipeline evaluated 16 billion settings and extracted the true key, exact shell, and all ten historical plugboard cables in just 361 seconds (claim C2).

# Physical Constraints vs. Mathematical Ghosts

Translating mathematical graph theory into physical 1945 hardware exposed a significant vulnerability in pure Boolean reductions. Certain crib wedges produce valid Welchman states that are mathematically flawless but physically impossible.

We classify these false positives as "ghosts". In a trial run, a crib of `UUUVIRSIBENNULEINS` at offset 0 produced 12 mathematical survivors out of the Welchman board. However, when mapping the remaining letters, none of these 12 settings could be completed within the physical limit of exactly 10 plugboard cables. Forensics revealed these were "split menus," where connected components within the graph admitted zero valid starting seeds.

To prevent these ghosts from overwhelming the CPU, we built a SAT-completion kill chain inline as the GPU drains. This ensures that only mathematically valid states that *also* fit physical hardware constraints survive the hardware pipeline (claim C3).

# The Mid-Message Turnover Scoring Flaw

Our research uncovered a systemic flaw in how distributed computing projects historically score Enigma decrypts, likely explaining the decades-long failure to crack P1030680.

Standard algorithmic sweeps utilize a linguistic scanner to score the full 72-letter plaintext. However, if the true key clicks the middle rotor over *after* the crib phrase but *before* the end of the message, the plaintext will be perfectly decrypted across the crib span, but turn to garbage for the remainder of the message.

Because traditional trigram discriminators score the *entire* message, the garbled tail drags the overall score down to the midpoint between German and random noise. This causes the engine to discard the true key, actively rejecting the correct answer.

To rectify this, we designed a **windowed discriminator score**. This metric evaluates the readable head of a decrypt (requiring at least 16 non-crib letters) independently from the whole message, passing the key if either the full message or the head meets the $-3.600$ threshold. Applying this fix revealed 2,219 physically valid ten-plug boards that had been previously rejected by the flawed whole-message scoring (claim C12).

# The M-Thetis / Potsdam Register Mismatch

Cryptanalysis is limited by the quality of the plaintext hypotheses (cribs) used as wedges. Archival auditing of the May 1, 1945 U-534 corpus highlighted a severe historical blindspot regarding the target message.

The scraped corpus contains 48 broken M4 messages. Crucially, 31 originate from the Potsdam net, 16 from a second net, and 1 from a third. P1030680 is the *only* message originating from the M-Thetis network.

Because Bletchley Park never bothered to work the M-Thetis training net, and no other Thetis messages survive in the corpus, all 100 historical cribs used to attack P1030680 were register language borrowed from other operational networks. If Thetis operators opened their 72-letter messages with callsigns or key groups before the body---unlike Potsdam operators---the exact crib placements used in modern attacks are fundamentally the wrong shape. The resilience of P1030680 is therefore likely a result of mismatched operational doctrine rather than the cryptographic strength of the cipher itself.

Potsdam and Plaice daily keys for 1 May were eliminated by exhaustion against P1030680 (claim C11): all $26^4$ message keys land at the noise floor.

# Graded Campaign Status (August 2026)

The operational ledger is `BREAK_P1030680.md`; the public claim freeze is `directives/claim-sheet.md`. Table [1](#tab:campaign){reference-type="ref" reference="tab:campaign"} summarizes what is *proven*, what is *eliminated*, and what remains open. **None of these rows is a decrypt of P1030680** (non-claim N5).

  **Result**                                                   **Status**
  ------------------------------------------------------------ -----------------------------------------------------------------------------
  Welchman blind control (P1030684)                            Break in 361 s; all 10 plugs
  Stochastic KPA datapath                                      Control oracle + near-miss PASS; blind stecker $\sim$`<!-- -->`{=html}22/72
  Exact $\ge$`<!-- -->`{=html}16 catalog $\times$ rings AAAA   Clean negative
  Curated exact / fuzzed top-40 $\times$ right rings           Clean negative
  UEBUNG / Thetis-register arms                                Clean negative (register rings parked)
  Regenbogen / Hannibal operational cribs                      Not BREAK under graded rings
  Catalog exact $\times$ right rings                           Parked at menu 264/868; resume `--bombe-from 265`
  Middle ring $\ne$ A                                          Untested ($\sim$`<!-- -->`{=html}8--15% of keys)
  Ciphertext garble risk                                       Sister P1030681 needed degarbling; exact bars may drop true shells

  : Campaign grades (cleartext Metal). Fitness is not HELUT encrypted tick rate (N6). {#tab:campaign}

Soft-band Welchman stops can quarantine into Stochastic seeds (`--hybrid-quarantine`). Synthetic and historical garble controls grade that path; it has not produced a P1030680 BREAK.

# Parallel Track: TensorLUT

Independently of the Boolean catalog, HELUT ships a continuous--to--discrete compiler: Yosys LUT6 cells become 64-wide floating INIT tensors, Metal evaluates a multilinear stream, $\lambda$ squeezes toward binary, and an emitter writes gate-level Verilog. Unmutated `enigma_m4` locks $F_{\mathrm{crypto}}=0$ (925 LUT6 + 49 DFFs baseline). Full INIT cold-start and stecker-cone melts *shatter* under $\lambda$; the live arm freezes known-good silicon and evolves a $\le 10$-pair stecker involution by construction (blind three-pair rediscovery PASS; claims C8--C9). This grades generative hardware synthesis and reciprocal genotype search. It does **not** invent P1030680's missing plaintext (N7, H6).

# Scope Relative to the HELUT Stack

HELUT also graduates a torus FHE path (LWE/GLWE, GGSW blind-rotate, certificates) documented in `paper/helut.tex` and `directives/claim-sheet.md`. That path is out of scope for campaign fitness: P1030680 search remains cleartext Metal batch. Encrypted SING envelopes and hardness calibration are stack claims (C4--C7, H1--H3), not evidence that this message is broken.

# Conclusion

P1030680 remains unbroken. The contribution of this campaign is a graded, reproducible Boolean and stochastic laboratory on Apple Silicon; archival elimination of wrong nets and many wrong wedges; scoring and ghost-control fixes that make short-M4 search honest; and a parallel TensorLUT arm that learns reciprocal structure without claiming a decrypt. The next archival or combinatorial lever---not more GPU on a wrong template---is what would change the ledger.
