# Metal torus compiler — Phase 1 / Phase 2

**Status:** trajectory story (not a claim).  
**Why now:** encrypted Metal micro at *N*=1024 spends hours on **host MPSGraph encoding** of schoolbook poly-mul inside fused blind-rotate — GPU never starts.  
**Doctrine:** SoftBus/ANE remains a graph machine; we stop mistaking “unroll all ring math into MLIR” for “use the GPU.”

Living hedges: [`claim-sheet.md`](claim-sheet.md) **H3**. Reproduce: [`../REPRODUCE.md`](../REPRODUCE.md). Broader path: [`research-trajectory.md`](research-trajectory.md).

---

## The problem in one picture

```
Yosys $lut  →  pack LWE  →  blind rotate (N CMUXes)
                              │
                              ├─ today: each external product expands
                              │         Σ_j bⱼ · Xʲ a  as O(N) MPSGraph ops
                              │         → millions of host MLIR nodes
                              │         → encode wall ≫ run wall
                              │
                              └─ goal: small graph that *calls* ring kernels
                                        encode cheap · run on Metal · cache forever
```

CMUX dependence across the *N* bootstrap bits is real and sequential.  
The pain is not “CMUX can’t run on GPU.” It is **encoding a schoolbook expansion that should never have been a graph.**

---

## Phase 1 — CPU-side compiler (survive *N*=1024)

**Story:** Make the *current* Metal BR path finish, report, and amortize — without changing the cryptographic math. Treat MPSGraph as a **staged IR**, not one fused megagraph.

### 1.1 Tiled blind rotate

- Lower CMUX windows of size *W* (e.g. 32 / 64 / 128).
- Build → run → re-ingest accumulator as host constants → next tile.
- Semantics unchanged; encode cost scales with *W*, not full fused *N* × schoolbook.

**Bar:** `--bench-encrypted-micro --degree 1024` prints `TRIAL` / `PASS|FAIL` with a wall-clock; RSS bounded vs today’s multi‑GiB climb with no GPU progress.

### 1.2 Constant CSE / shared banks

- One shared bank of splats (`0`, `1`, fixed `X^j` helpers) per tile graph.
- Stop minting fresh `constantWithScalar` / `ones` per schoolbook term (dominant stack in `sample` today).
- Extend the INIT test-poly sharing already used in `evaluateTopoNetlistSingleGraph`.

**Bar:** Encode time and peak RSS drop measurably at *N*=256/512 on the same micro harness; op-count or host-side timer logged.

### 1.3 Executable / tile cache

- Cold path: encode + compile once per `(N, baseLog, levels, W, BK layout)`.
- Hot path: feed ACC / LWE → run cached `MPSGraphExecutable` (or equivalent).
- Microbench trial 1 = cold; trials ≥2 (and netlist ticks) hit cache.

**Bar:** Second BR at fixed params is ≪ first (document ratio in log / claim-sheet **H3** note).

### 1.4 Compiler telemetry

- Split wall into `encode`, `mps_compile` (if separable), `gpu_run`, `host_repack`.
- Progress: `BR tile=k/K bit=j…` so silence never looks like a hang.

**Bar:** One log line schema used by `helut-encrypted-micro-n*.log` and SING Metal paths.

### Phase 1 non-goals

- New lattice assumption, noisy-BK product path (**H4**), Sage estimator (**H1**).
- Claiming production Metal tick rate for campaign search (**N6**).
- Parallelizing *within* one CMUX accumulator chain.

### Phase 1 exit

*N*=64 still PASS; *N*=256/512/1024 Metal micro **completes** with receipts; claim-sheet **H3** updated from “in flight / graph-build bound” to timed envelope + asterisks (schoolbook still underneath).

---

## Phase 2 — GPU ring kernels (accelerate after Phase 1)

**Story:** Once tiles + CSE + cache prove the control plane, **replace schoolbook-in-MLIR** with Metal arithmetic. MPSGraph (or raw command buffers) becomes the **scheduler**; poly mul / external product become **first-class GPU ops**.

Phase 1 without Phase 2 still leaves O(*W*·*N*) encode inside each tile.  
Phase 2 without Phase 1 is a big kernel drop into an unmeasured fused path. **Do both; order is Phase 1 then Phase 2.**

### 2.1 Negacyclic poly-mul backend

- Metal compute (or NTT/FFT over `Z/2³²Z[X]/(X^N+1)`) implementing the same math as CPU / today’s graph expansion.
- `negacyclicPolyMul` / `scaleGLWE` call the kernel; graph holds buffers + control edges only.

**Bar:** Bit-identical (or SING-equivalent) vs CPU BR on full_adder / micro at *N*∈{64,256,1024}; encode time dominated by tile glue, not Σⱼ loops.

### 2.2 External product / CMUX as GPU stages

- Optional fusion: gadget decompose + EP in one or few kernels per CMUX.
- Still scheduled in Phase‑1 tiles so depth and memory stay bounded.

**Bar:** Metal micro *N*=1024 wall competitive with CPU SING order-of-magnitude story (exact target TBD after Phase‑1 baseline); memory envelope published.

### 2.3 Persistent param packs

- BK upload once; tile executables + kernels bound to param id.
- Netlist path: INIT CSE + kernel cache + topo schedule (step 10l lineage).

**Bar:** Multi-LUT encrypted Metal SING (adder / tree) with compile-once / run-many profile in `REPRODUCE.md`.

### Phase 2 non-goals

- Rewriting cleartext Welchman / campaign Metal (different stack).
- “We invented TFHE” or new hardness claims.
- Requiring ANE specifically — Metal GPU is enough for this phase.

### Phase 2 exit

Schoolbook expansion **gone** from the hot Metal BR path; Phase‑1 tiles still available as a debug / fallback lowering; **H3** closed with GPU-run-dominated timings; cookbook row for Metal production-shaped *N*=1024.

---

## How the phases compose

| Lever | Phase 1 | Phase 2 |
|-------|---------|---------|
| Tile CMUX windows | **Required** | Still used (control plane) |
| Constant CSE | **Required** | Keeps glue graphs tiny |
| Executable cache | **Required** | Caches glue + kernel binds |
| Schoolbook-in-MPSGraph | Tolerated (bounded) | **Removed** from hot path |
| Metal NTT / poly-mul | Not yet | **Required** |
| Parallel independent BRs | Optional (multi-LUT) | Natural once kernels exist |

**Punchline:** Phase 1 makes encoding *finish*; Phase 2 makes encoding *irrelevant*. Together they are the SoftBus-native torus compiler — staged IR + ring kernels + cached executables — instead of a single schoolbook megagraph hoping the GPU will eventually appear.

---

## Suggested implementation order (lab)

1. Telemetry + tile *W*=64 at *N*=256 (prove correctness vs fused).  
2. CSE constants; retune *W*; hit *N*=1024 micro PASS/FAIL.  
3. Executable cache; publish cold/hot ratio.  
4. Poly-mul Metal kernel behind a flag; equiv vs CPU.  
5. Flip default hot path; keep schoolbook tile as `--metal-br-schoolbook` fallback.

When a step graduates, add a **C** row (or close **H3**) and a reproduce command — then it may enter public prose.
