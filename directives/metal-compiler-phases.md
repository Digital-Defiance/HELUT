# Metal torus compiler — Phase 1 / Phase 2

**Status:** Phase 1 control plane **in tree**; Phase 2.2 fused EP **in tree**; Phase 2.3 GPU-resident BR tile **in tree**; Phase 2 NTT persist BR **in tree** (2026-08-13). Not a security claim.  
**Why now:** fused schoolbook-in-MPSGraph at *N*=1024 spent **11.6 h** on host encode, never reached GPU, killed SIGTERM 143 (`logs/helut-encrypted-micro-n1024.log`).  
**Doctrine:** SoftBus/ANE remains a graph machine; we stop mistaking “unroll all ring math into MLIR” for “use the GPU.”

Living hedges: [`claim-sheet.md`](claim-sheet.md) **H3**. Reproduce: [`../REPRODUCE.md`](../REPRODUCE.md). Broader path: [`research-trajectory.md`](research-trajectory.md).

## Lab status (2026-08-13)

| Item | Result |
|------|--------|
| Fused `--bench-encrypted-micro --degree 1024` | **DNF** — 11.6 h, RSS ~4 GiB, still `BR start bit=0` / `negacyclicPolyMul` MLIR, SIGTERM 143 |
| CPU SING *N*=1024 full_adder | **PASS** ~52 s (`logs/helut-encrypted-n1024-cpu-sing.log`) |
| Tiled-kernel micro *N*=64 | **PASS** NTT-tile **0.010 s/BR** (`logs/helut-encrypted-micro-n64-ntt.log`) vs persist-schoolbook 0.001 s vs fused-EP 0.043 s vs fused MPSGraph ~50 s |
| Tiled-kernel micro *N*=1024 | **PASS** NTT-tile **0.433 s/BR** (gpu 0.43 s, RSS 148 MiB, `logs/helut-encrypted-micro-n1024-ntt.log`) vs persist-schoolbook 0.519 s vs fused-EP 1.043 s vs poly-mul 3.645 s |
| Metal full_adder SING *N*=1024 | **PASS** boolean wavefront-NTT **10.6 s / 8 vec (1.33 s/row)** vs persist-schoolbook 12.2 s vs serial NTT 15.6 s vs fused-EP 25.1 s; crypto 175.6 s not re-timed |
| Metal netlist-scheduled SING *N*=1024 | **PASS** 91.9 s / 8 vec pre-fusion; same tiled-kernel path now hits NTT persist BR (**C18**) |
| Default Metal BR | `fused` if *N*≤64; `tiled-kernel` otherwise (GPU-resident ACC+BK, **NTT EP** inside tiles) |
| CLI | `--metal-br-fused` · `--metal-br-tile W` |
| In tree | CMUX tiles (1.1) · `GraphConstBank` CSE (1.2) · cached PSO (1.3) · telemetry (1.4) · poly-mul kernel (2.1) · fused EP (2.2) · GPU-resident BR tile (2.3) · **3-prime NTT persist BR (C18)** |

Whole-netlist `evaluateTopoNetlistSingleGraph` defaults to **host-scheduled tiled-kernel** at *N*>64 (same GPU-resident NTT BR as **C18**). Legacy fused MPSGraph is `--metal-br-fused` only.

**Validate:** `make test-metal-p1` (MetalCompilerPhase1Tests + NegacyclicNTTTests). *N*=1024 wall-clock: `--bench-encrypted-micro --degree 1024 --trials 2 --warmup 1`.

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

- New lattice assumption. Sage estimator JSON filled (**C23**); noisy BK measured at covering gadget (**C22**); *N*=1024 Metal SING still *e*=0.
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

**Bar:** Bit-identical vs CPU schoolbook on full_adder / micro at *N*∈{64,256,1024}; encode time dominated by tile glue, not Σⱼ loops. **Met 2026-08-13 (C18):** 3-prime twisted NTT ≡ schoolbook (CPU + Metal poly-mul + inlined persist BR).

### 2.2 External product / CMUX as GPU stages

- **Landed 2026-08-13:** CPU gadget decompose + one `helut_ggsw_external_product` launch per CMUX (all ℓ levels, k=1). Cache key `(device, N, ℓ)`.
- Still scheduled in Phase‑1 tiles so depth and memory stay bounded.

**Bar (met):** Metal micro *N*=1024 **1.043 s/BR** (gpu-dominated); boolean SING **25.1 s / 8** vs CPU SING ~52 s. Schoolbook arithmetic still inside the kernel.

### 2.3 Persistent param packs

- **Landed 2026-08-13:** `helut_blind_rotate_tile` — ACC + BK on GPU; one threadgroup of *N* runs a CMUX tile (rotate, gadget, EP, add). BK fingerprint skips re-upload on later BRs. Fallback: per-CMUX host EP if `maxTotalThreadsPerThreadgroup < N`.
- One-tile (*W*=1024) ≡ 16-tile (*W*=64) wall at *N*=1024: remaining time is schoolbook ALU/mem, not launch.

**Bar (met):** Metal micro *N*=1024 **0.519 s/BR**; boolean SING **12.2 s / 8**. Compile-once / run-many: second BR encode=0. NTT inlined in **C18**.

### 2.4 NTT external product inside the persist tile

- **Landed 2026-08-13:** `helut_blind_rotate_ntt_tile` — gadget digits in-tile; BK uploaded in 3-prime NTT domain; pointwise EP + iNTT + CRT; bit-identical to schoolbook.
- Fallback: schoolbook persist tile if `maxTotalThreadsPerThreadgroup < N`.

**Bar (met for micro):** *N*=1024 **0.433 s/BR** vs **C17** 0.519. Serial NTT SING was 15.6 s (**C18**). Wavefront-parallel (**C20**) boolean **10.6 s / 8**; crypto ℓ=2 (**C21**) **11.38 s / 8**.

### Phase 2 non-goals

- Rewriting cleartext Welchman / campaign Metal (different stack).
- “We invented TFHE” or new hardness claims.
- Requiring ANE specifically — Metal GPU is enough for this phase.

### Phase 2 exit

Schoolbook expansion **gone** from the tiled hot path (**C18** `ring=ntt`); Phase‑1 tiles still available as a debug / fallback lowering; **H3** SING bars met (**C20** boolean 10.6 s, **C21** crypto 11.38 s). Cookbook row for Metal production-shaped *N*=1024 NTT micro.

---

## How the phases compose

| Lever | Phase 1 | Phase 2 |
|-------|---------|---------|
| Tile CMUX windows | **Required** | Still used (control plane) |
| Constant CSE | **Required** | Keeps glue graphs tiny |
| Executable cache | **Required** | Caches glue + kernel binds |
| Schoolbook-in-MPSGraph | Tolerated (bounded) | **Removed** from hot path |
| Metal NTT / poly-mul | Not yet (schoolbook in 2.1/2.2 kernels) | **In tree (C18)** — schoolbook fallback if TG < *N* |
| Parallel independent BRs | Optional (multi-LUT) | Natural once kernels exist |

**Punchline:** Phase 1 makes encoding *finish*; Phase 2 makes encoding *irrelevant*. Together they are the SoftBus-native torus compiler — staged IR + ring kernels + cached executables — instead of a single schoolbook megagraph hoping the GPU will eventually appear.

---

## Suggested implementation order (lab)

1. Telemetry + tile *W*=64 at *N*=256 (prove correctness vs fused).  
2. CSE constants; retune *W*; hit *N*=1024 micro PASS/FAIL.  
3. Executable cache; publish cold/hot ratio.  
4. Poly-mul Metal kernel behind a flag; equiv vs CPU.  
5. Flip default hot path; keep schoolbook tile as `--metal-br-schoolbook` fallback.  
6. **Fused EP kernel (2.2) — done.**  
7. **GPU-resident BR tile (2.3) — done.**  
8. **NTT persist BR (C18) — done** for micro (0.433 s/BR; fused 3-prime 0.420 s/BR). SING 15.2 s with pack cache; wavefront-parallel independent `$lut` BRs in tree. Sage **H1** filled (**C23**).

When a step graduates, add a **C** row (or close **H3**) and a reproduce command — then it may enter public prose.
