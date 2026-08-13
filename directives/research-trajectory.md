# Research trajectory (beyond disclosure)

Disclosure shares **what already reproduces**. This file is the **discovery path** after that — near-term science, mid-term pillars, and speculative avenues. None of the speculative items are claims until they have receipts in `REPRODUCE.md` / logs.

Living results inventory: [`claim-sheet.md`](claim-sheet.md).

---

## Near term (close the lab gaps)

| Track | Why it matters | Next experiment |
|-------|----------------|-----------------|
| **H2** full_adder @ *N*≥256 | ~~Multi-LUT encrypted correctness~~ **Closed** | Z_{2N} pack / `rotationPower` fix; SING PASS @ 256/512/1024 |
| **H1** Sage lattice-estimator | Honest classical bits for production-shaped params | Needs SageMath (`sage` / `sage.all`) — not installed here; pending JSON ready |
| **H3** Metal BR @ large *N* | Real wall-clock / memory envelope | **C17** persist-tile 0.519 s/BR · boolean SING 12.2 s. Next: NTT poly-mul (schoolbook still in tile kernel) |
| **H4** Noisy BK | Production depth story | Measured *σ*<sub>BK</sub> into `TFHENoisyBKCertificate` (still modeled / *B*<sub>bk</sub>=0) |
| Campaign catalog | Exhaust Boolean coverage | Resume `--bombe-from 265`; middle ring ≠ A |
| Garble / quarantine | Ciphertext may be wrong letters | Soft-band escalate grades; sister-message lessons |

## Mid term (pillar science)

From [`../roadmap-overall.md`](../roadmap-overall.md) and the project registry:

1. **Pillar I** — netlist-clocked FHE: shallower nets, NTT/persist graphs, estimator-backed params ([`metal-compiler-phases.md`](metal-compiler-phases.md))  
2. **Pillar II** — formalize continuous→discrete (TensorLUT lemmas → paper theorem); stream-cipher melts  
3. **Pillar III** — polymorphic Red/Blue standard beyond E256 SoftBus  
4. **FHE gate / ZK depth** — TensorLUT aimed at multiplicative depth (queued projects)  
5. **Side-channel (parked)** — bgpucap-style power on live Metal graphs only with controlled fixtures  

## Speculative (not claims)

[`potential-avenues.md`](potential-avenues.md) — encrypted LLM guardrails, self-modifying dark PicoRV32, honey-token ledgers, online netlist evolution, Metal-tick–synced bgpucap DPA on controlled live graphs. Keep them here so the public story stays honest: **reproducible core now; weird frontier labeled as frontier.**

## Disclosure vs discovery

| | Disclosure package | Trajectory |
|--|--------------------|------------|
| Goal | Someone else can re-run what we assert | We know what to invent next |
| Artifact | `REPRODUCE.md`, logs, PDFs, claim inventory | this file + roadmap + avenues |
| Failure mode | Unreproducible hype | Silence / no next experiment |

When a trajectory item graduates, add a **C** row (or tighten an **H**) and a reproduce command — then it may enter public prose.
