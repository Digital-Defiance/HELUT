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

The mathematical soundness of this reduction was verified in a blind control run. Given a 27-letter crib from a known message (P1030684) and no other parameters, the GPU pipeline evaluated 16 billion settings and extracted the true key, exact shell, and all ten historical plugboard cables in just 361 seconds (claim C2). The archived log (`logs/control-p1030684-rings.log`) reads 427 s: 361 s was the first run, and the log was overwritten by a re-run after head scoring was added. Both figures are recorded in `BREAK_P1030680.md`; the re-run is the reproducible one.

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
  ------------------------------------------------------------ ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  Welchman blind control (P1030684)                            Break in 361 s first run / 427 s archived re-run; all 10 plugs
  Stochastic KPA datapath                                      Control oracle + near-miss PASS; blind stecker $\sim$`<!-- -->`{=html}22/72
  Training / collapse / weather / RIGA priors                  0 survivors under 80% rigor (ceiling $\sim$`<!-- -->`{=html}60--69% = coincidence)
  Exact $\ge$`<!-- -->`{=html}16 catalog $\times$ rings AAAA   Clean negative
  Curated exact / fuzzed top-40 $\times$ right rings           Clean negative
  UEBUNG / Thetis-register arms                                Clean negative (register rings parked at 13/73)
  Soft-tail UEBUNG quarantine escalate                         55 seeds; Hybrid 0 survivors
  Regenbogen / Hannibal (anchor, scuttle, Hela)                Not BREAK; soft escalate 0 survivors
  Own-orders / filler $\times$ AAAA                            Own: 0 physical; filler below soft --- no rings
  Catalog exact $\times$ right rings                           Parked originalIndex 417/2513; `--bombe-from 418`
  Middle ring $\ne$ A                                          Untested vs P1030680; arm graded end-to-end (control breaks at full middle $\times$ right coverage, 26$\times$ space for 12.2$\times$ time)
  Long menus (len 28--40)                                      Prior negatives *incomplete*: old kernel cap silently eliminated up to 5.56% of lanes. Phase 16 arm 2 contaminated 40/40, Phase 8 top-30 20/30, catalog 300/2513; $\le$`<!-- -->`{=html}25 letters unaffected. Re-runs under way
  Ciphertext garble risk                                       Sister P1030681 needed degarbling; exact bars may drop true shells. **17 of 48** published U-534 keys fail to reproduce their own recorded plaintext, but from at least three causes --- multi-part per-part keys, indels, and only **4 controls / 8 events** of isolated substitution. An earlier "16 controls prove archive garble" reading is **withdrawn**
  Crib-free (Ostwald/Weierud)                                  Threshold measured at ${\sim}$`<!-- -->`{=html}200 letters; $+$`<!-- -->`{=html}141-plug exhaustion removes 68 % of the 72-letter deficit, margin still negative. Not a viable arm yet
  Tolerant board sensitivity                                   **Proven on a known key**: at 1--3 corrupted crib letters the exact board *loses* the true setting and a tolerance-$\ge g$ board *keeps* it, forcing 25/25 plugs correctly. Metal port cross-checks at **0/192** lane mismatches
  Tolerant board specificity                                   **Placement**-dependent, not crib-length dependent. An early "$\ge$`<!-- -->`{=html}17 edges buys tolerance 1" rule held only at offset 0 and is **withdrawn**: 18-edge menus admit 4,301 and 16,019 survivors elsewhere. Tolerance amplifies an under-determined menu rather than rescuing it, so it is a per-menu decision
  Tolerance against P1030680                                   **Not run.** No target verdict; pre-qualification pending. Indels (Girard's missing `HMHY` group) are a frame shift and are *not* modelled

  : Campaign grades (cleartext Metal). Fitness is not HELUT encrypted tick rate (N6). {#tab:campaign}

Soft-band Welchman stops can quarantine into Stochastic seeds (`--hybrid-quarantine`). Synthetic P1030684 block-wipe and historical P1030681 first-draft controls grade that path (escalate recovers edit ceilings, not a new key). On P1030680 itself, UEBUNG and Regenbogen soft bands produced German-looking IC without survivors under the 80% bar --- coincidence, not plaintext.

## A clean negative the board had not earned

The Metal bombe tabulates one upper-involution table per distinct slow-wheel $(l,m)$ state across a menu span, and capped that at four. On overflow it wrote a zero survivor mask --- the code for *eliminated* --- for a lane it had never tested. Pure stepping arithmetic over every span, all 56 naval (middle, right) rotor pairs and all 676 windows (`Scripts/max_upper_audit.py`) bounds how often that fired: never at or below 25 letters, then 0.29 % of lanes at 28, 1.14 % at 30 and 5.56 % at 40. The damage is concentrated in the curated long-menu arms rather than spread thinly. Phase 16 arm 2 --- forty mid-message anchors whose zero raw stops closed the Übung-push hypothesis --- is 40 letters throughout, so *all forty* placements were contaminated and that negative was unearned as recorded. It has since been re-run on the corrected kernel: 40/40 dead at the board, zero raw stops over $6.387\times10^{11}$ settings, so the cap was not concealing a key and the hypothesis stays closed on evidence. Phase 8's curated top-30, contaminated on 20 of 30 placements, likewise re-runs to 73 raw stops over $4.79\times10^{11}$ settings --- identical to the archived figures --- with best board IC 0.041 / tail $-4.819$ and no break. In both arms the previously untested lanes yielded *zero* additional survivors. Two archival notes belong with that: the scored-completion count on the top-30 moved $0\to35$ purely because the head-reading gate and quarantine's soft IC floor both postdate Phase 8, the raw-stop count being the coverage-sensitive figure; and the archived top-30 log is truncated at menu 6 of 30 with no summary, so its quoted figures had never been on disk until this re-run supplied them. Phase 8's curated top-30 is contaminated on 20 of 30 placements, and the main catalog on 300 of 2513. The Regenbogen queue is clean, and everything at 16--25 letters, including all of the Thetis-register work, is untouched and stands. The cap is now 8 and overflow reports *undecided*, which the host --- which has no such cap --- re-tests in full: a table size can no longer discard a key. Re-runs are ordered by contaminated share per GPU-hour, Phase 16 arm 2 first.

## Unpinning the middle ring for 6.5--11.4$\times$, not 26$\times$

Every campaign to date pinned the middle Ringstellung at A, which is exact only while the middle wheel stays off its own notch in span. The gap is real ($\sim$`<!-- -->`{=html}8--15 % of keys) and was priced at a flat 26$\times$. It is cheaper, because notch tests depend on *window* position and are ring-free: if neither a lane's middle wheel nor that of its ring-A partner at window $m-\rho$ reaches a notch across the span, the middle wheel steps only on right-wheel notches --- the same times in both trails --- the left wheel never moves, and $\mathrm{offset}_M = m-\rho$ *is* the partner's window. Same scramblers, same verdict. Ring A therefore runs in full and rings B--Z run only their notch-hitting lanes, and the union is complete coverage rather than a sample. Graded on the validated host board over 2.4$\times 10^{6}$ claimed-covered pairs and then through the kernel: zero verdict mismatches, and with $\sim$`<!-- -->`{=html}5 600--6 900 survivors per ring actually discarded, every discarded verdict is carried identically by its ring-A partner. Predicted cost is 6.5$\times$ a right-ring pass with a one-notch middle wheel and 11.4$\times$ with two. End-to-end on the blind control at full middle $\times$ right coverage --- 908 544 shells, $4.152\times10^{11}$ settings, the first run in this campaign with no residual ring gap --- the break is recovered with all ten plugs in $4\,307\,\mathrm{s}$ at $96.4\,\mathrm{M/s}$: 26$\times$ the search space for 12.2$\times$ the time of the right-ring pass, because roughly 70 % of lanes exit after the trail test. Raw stops rise from 2 to 4, which is the mechanism working rather than a regression: with the middle ring unpinned the true machine has several ring-equivalent representations in the swept space. Measured basis is $\sim$`<!-- -->`{=html}72 minutes per placement. Implemented and graded is not run: as of this revision the arm has produced no P1030680 verdict.

Two sieves were graded and rejected. The historical ten-lead board bounds the plugs a menu has not yet forced ($26 - \mathrm{determined} \ge 2(10-\mathrm{pairs})$); it is sound --- the blind control still breaks --- and useless, taking 847 434 raw stops to 847 414 ($0.002\,\%$) for a 4 % throughput loss, because it only bites on long strong menus that already die at the board. Separately, three quarantine flags this report and the ledger both document were never parsed, so the soft-tail arm recorded at $-4.3$ ran at the default $-4.0$.

## The crib-free path, measured

Every arm above needs a probable word, and every crib in the catalog is imported register from other nets. The Ostwald--Weierud ciphertext-only attack needs none: for each candidate rotor setting it hill-climbs the plugboard and ranks the setting by the score the climb reaches. Its published reach is messages down to roughly 100 letters, with 78 the shortest broken, on three-rotor Heer traffic; P1030680 is 72 letters on four-rotor naval M4, i.e. shorter than the record on a harder machine.

The limit is not throughput, which changes how hardware should be spent. Seventy-two letters of naval German carry ${\sim}223$ bits of redundancy, a ten-plug board is ${\sim}47$ bits of nuisance parameter *fitted per candidate*, and the shell${\times}$position space is ${\sim}10^{11}$: taking a maximum over that many overfitted candidates is a multiple-comparisons problem, and adding candidates raises the maximum of the noise. The decisive quantity is therefore the *margin* --- climbed score at the true setting minus the best climbed score over wrong settings --- and `--ostwald-curve` measures it at a ladder of truncation lengths over the published 1 May 1945 U-534 keys, with exhaustion applied symmetrically to true and decoy settings so the margin cannot be manufactured.

The harness refuses to report a curve unless its controls decrypt their own published plaintext under their own published key, and that preflight found something: **32 of 48 controls round-trip exactly**, the rest do not. An earlier revision read that as transcription garble corroborating the garble hypothesis; **that reading is withdrawn**. Classified by error shape, the 17 discrepant controls have at least three causes. Most are *multi-part* messages --- several exceed the ${\sim}320$-letter Kriegsmarine limit and were sent in parts with a fresh Grundstellung each, so end-to-end decryption under one message key correctly yields a good head and a garbage tail, which is precisely the observed shape. A few are indels or divergent transcripts. Only four controls, eight events in total, are isolated substitutions --- far too thin to fit a confusion model, so any degarbler must take its prior from Girard's direct reading of the originals (he names U$\leftrightarrow$N, Q$\leftrightarrow$G, H$\leftrightarrow$F) rather than from this corpus.

Validation is unambiguous --- at 372 letters the staged climb recovers all ten plugs and 100 % of the plaintext (margin $+1.64$, $z=35.6$) --- which is what licenses believing the negatives. Staged scoring (IC, then bigrams, then trigrams, matching the reference implementation's default) decisively beats the bigram-only climb previously in the repo: at 252 letters, 8/10 plugs against 0/10. The measured threshold is **${\sim}200$ letters**, where the median margin crosses zero; control counts above 180 are thin ($n=3$--6), so those medians are noisy while the monotone trend is not. Ostwald's partial exhaustion --- fixing one plug and climbing the rest over all 141 candidates --- removes **68 %** of the deficit at 72 letters ($-0.2389 \to -0.0754$ on identical controls) and doubles the win rate, the largest single lever found and the one the literature names.

Unseeded, the margin at 72 letters remains *negative*: the crib-free path is not yet a viable standalone arm against P1030680, our threshold is 2.8$\times$ worse than the published record, and that gap is unclosed.

The lever available only here changes that picture at the target length. A Welchman stop arrives with the stecker its menu forced --- 15--24 of 26 letters, i.e. 7--12 plugs --- and the reference implementation documents exactly that interface (`-s`, \"known plugboard connections, e.g. from running a bombe\") while requiring it to be fed by hand, because the bombe is someone else's program. Modelled fairly, with the true setting seeded from $k$ correct plugs and every decoy seeded from $k$ *random* plugs, at 72 letters on ten controls the margin crosses zero at $k=4$ ($+0.130$) and at $k=8$ the attack recovers the complete key and 100 % of the plaintext on every control ($+1.049$, 10/10 plugs). That is below the published 78-letter record, on the harder machine --- but it is *oracle-seeded*, so it assumes the seeded stop is the true key. What it establishes is narrower and still useful: a *true* bombe stop is finishable at 72 letters, so a stop the strict linguistic bar rejected for garble or short-message noise can be recovered.

That makes the climber a much better escalator than the genetic path of §Quarantine, which returned zero survivors at a ${\sim}60\,\%$ coincidence ceiling without saying why. Escalating every soft-band stop the campaign has ever quarantined --- 55 UEBUNG, 22 Regenbogen scuttle, 7 Hela, 2 from the Phase-49 re-run, 86 in total --- yields no break, and in every arm the best stop scores *below* the best of twelve random settings ($\Delta$ from $-0.19$ to $-0.80$). The soft band is not a near miss; it is worse than noise under a scorer that would finish a true stop. The quarantine escalation path is therefore closed with a reason rather than a ceiling.

## A diagonal board that counts contradictions

On the physical bombe a contradiction *is* current finding a second path through the diagonal board: the hypothesis short-circuits and the drum advances. Copper cannot answer "how many contradictions?", and every faithful reimplementation inherits that, including ours, which returns `nil` on the first doubled row. Under garble this is fatal --- one mis-transcribed ciphertext letter contradicts a *true* menu --- so every exact-crib clean negative above is a negative about the *recorded* ciphertext rather than the transmitted one.

In silicon the question can be posed differently: how few menu edges must be deleted before a setting closes consistently? Accepting a setting when $\le t$ deletions suffice gives a *deletion-tolerant* diagonal board, occupying the structural slot Welchman's diagonal board did --- a new board on the bombe, not a new bombe. Tolerance $0$ is the historical board bit for bit.

Tolerance must *remove* edges before propagating rather than abandon them mid-flight. A first implementation did the latter and measured as an exact no-op, for two compounding reasons worth recording: by the time a conflict surfaces the bad value is already committed and has propagated through the diagonal board, and the edge visited when it surfaces is typically a *correct* edge rather than the garbled one, so blaming it leaves the real culprit in place.

Sensitivity, graded on the published P1030684 key with letters corrupted inside a 27-letter crib span: at $1$, $2$ and $3$ garbles the exact board **loses** the true setting and a tolerance-$\ge g$ board **keeps** it, while still forcing $25/25$ plug deductions correctly. Since a true stop needs only four correct plugs to flip the crib-free margin at 72 letters, the two mechanisms compose: a garbled true key survives the board *and* is finishable. The Metal port is graded against the host board rather than trusted, at **0/192** lane mismatches across 45 crib $\times$ offset $\times$ tolerance cells, with wall time per shell rising $0.03\,\mathrm{s} \to 7\,\mathrm{s}$ from tolerance $0$ to $2$ --- confirming the extra closures are performed and not elided.

The cost is survivor inflation, and here an early reading was wrong and is withdrawn. At crib offset $0$ inflation looked like a clean function of menu size: 16 edges admitted 130,787 of 456,976 lanes at tolerance $1$, while $\ge17$ edges admitted exactly one, and $\ge22$ admitted one even at tolerance $2$. Varying the *placement* destroys that rule: 16 edges costs nothing at offset 15, while 18-edge menus admit $4{,}301$ and $16{,}019$ survivors at offsets 40 and 65. Crib length does not predict inflation; the menu's loop structure does, because tolerance spends redundancy and only a loop-rich menu has enough to spend. The placements that detonate are those already weak at tolerance $0$ --- tolerance *amplifies* an under-determined menu rather than rescuing it. Tolerance is therefore a per-menu decision, pre-qualified by measuring inflation against the escalator's budget, and not a global switch.

We claim no P1030680 verdict from this: tolerance has not been pointed at the target, pre-qualification of its placements is pending, and nothing here asserts that P1030680 *is* garbled --- only that a tolerant board would recover a garbled true key. Tolerance is applied to menu edges, not to the diagonal board itself, so it is an algebraic relaxation of the deduction rather than a hypothesis about which letters are wrong. Indels are not modelled: Girard records an entire four-letter group (`HMHY`) present on one transcript and absent from the other, which is a frame shift rather than a substitution.

# Parallel Track: TensorLUT

Independently of the Boolean catalog, HELUT ships a continuous--to--discrete compiler: Yosys LUT6 cells become 64-wide floating INIT tensors, Metal evaluates a multilinear stream, $\lambda$ squeezes toward binary, and an emitter writes gate-level Verilog. Unmutated `enigma_m4` locks $F_{\mathrm{crypto}}=0$ (925 LUT6 + 49 DFFs baseline). Full INIT cold-start and stecker-cone melts *shatter* under $\lambda$; the live arm freezes known-good silicon and evolves a $\le 10$-pair stecker involution by construction (blind three-pair rediscovery PASS; claims C8--C9). Six formal lemmas of the continuous--discrete loop hold in-repo (claim C19; `directives/tensorlut-theorem.md`). Melt--freeze--snap on a separable Boolean interpolant is claim C44; a 2-LUT cascade melt that emits Verilog and matches 8 Boolean corners is claim C48 (dual interpolants allowed). This grades generative hardware synthesis and reciprocal genotype search. It does **not** invent P1030680's missing plaintext (N7, H6).

# Scope Relative to the HELUT Stack

HELUT also graduates a torus FHE path (LWE/GLWE, GGSW blind-rotate, certificates) documented in `paper/helut.tex` and `directives/claim-sheet.md`. That path is out of scope for campaign fitness: P1030680 search remains cleartext Metal batch. Encrypted SING envelopes and hardness calibration are stack claims (C4--C7, H1--H3), not evidence that this message is broken.

# Conclusion

P1030680 remains unbroken. The contribution of this campaign is a graded, reproducible Boolean and stochastic laboratory on Apple Silicon; archival elimination of wrong nets and many wrong wedges; scoring and ghost-control fixes that make short-M4 search honest; and a parallel TensorLUT arm that learns reciprocal structure without claiming a decrypt. The next archival or combinatorial lever---not more GPU on a wrong template---is what would change the ledger.
