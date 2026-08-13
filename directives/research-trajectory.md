# Research trajectory (beyond disclosure)

Disclosure shares **what already reproduces**. This file is the **discovery path** after that — near-term science, mid-term pillars, and speculative avenues. None of the speculative items are claims until they have receipts in `REPRODUCE.md` / logs.

Living results inventory: [`claim-sheet.md`](claim-sheet.md).
Living textbook (course surface on this trajectory): [`../textbook/`](../textbook/).

---

## Near term (close the lab gaps)

| Track | Why it matters | Next experiment |
|-------|----------------|-----------------|
| **H2** full_adder @ *N*≥256 | ~~Multi-LUT encrypted correctness~~ **Closed** | Z_{2N} pack / `rotationPower` fix; SING PASS @ 256/512/1024 |
| **H1** Sage lattice-estimator | Honest classical bits | **C23** filled. Production Δ=4.5. Divergences = core-SVP vs Cost `rop`, not silent bugs. Optional retune / quote estimator-only on Δ>16 rows |
| **H3** Metal BR @ large *N* | Real wall-clock / memory envelope | **C20**/**C21** SING. NTT inside crypto ℓ=2 at *N*=1024 (incomplete public-MS gadget) |
| **H4** Noisy BK | Production depth story | **C28** Track B Metal SING @ *N*=128 + noisy BK PASS. Track A *N*=1024 stays *e*=0 (**C26**/**C27**). Next: new (*q*,*N*) for Track A, or tighten Gaussian ε at *N*=128 |
| Campaign catalog | Exhaust Boolean coverage | Resume `--bombe-from 418`; middle ring ≠ A |
| Garble / quarantine | Ciphertext may be wrong letters | Soft-band escalate grades; sister-message lessons |

## Mid term (pillar science)

From [`../roadmap-overall.md`](../roadmap-overall.md) Phase 0–II and the project registry:

1. **Phase 0 corpus** — abstract↔C-id; estimator honesty table (**C23** in paper); application gallery; artifact tag  
2. **Pillar I** — netlist-clocked FHE: shallower nets, NTT/persist graphs, estimator-backed params ([`metal-compiler-phases.md`](metal-compiler-phases.md)); **H4** product noisy BK  
3. **Pillar II** — formalize continuous→discrete: **Theorem 1** (**C19**); **corollary** emitter–discrete / freeze (**C25**); stream-cipher melts  
4. **Pillar III** — SoftBus reciprocity **Theorem 2** (**C24**); polymorphic Red/Blue standard beyond E256 SoftBus  
5. **Application gallery** — nine slots outlined (`directives/application-gallery.md`); figures + artifact tag remaining  
6. **FHE gate / ZK depth** — TensorLUT aimed at multiplicative depth (queued projects)  
7. **Side-channel (parked)** — bgpucap-style power on live Metal graphs only with controlled fixtures
## Speculative (not claims)

[`potential-avenues.md`](potential-avenues.md) — encrypted LLM guardrails, self-modifying dark PicoRV32, honey-token ledgers, online netlist evolution, Metal-tick–synced bgpucap DPA on controlled live graphs. Keep them here so the public story stays honest: **reproducible core now; weird frontier labeled as frontier.**

## Disclosure vs discovery

| | Disclosure package | Trajectory |
|--|--------------------|------------|
| Goal | Someone else can re-run what we assert | We know what to invent next |
| Artifact | `REPRODUCE.md`, logs, PDFs, claim inventory | this file + roadmap + avenues + [`../textbook/`](../textbook/) |
| Failure mode | Unreproducible hype | Silence / no next experiment |

When a trajectory item graduates, add a **C** row (or tighten an **H**) and a reproduce command — then it may enter public prose.
