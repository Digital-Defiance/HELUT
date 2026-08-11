# Specification: Enigma 256 (E256) — Polymorphic Stream Cipher

## Abstract

**E256** is a software-defined, SoftBus-accelerated stream cipher that keeps the reciprocal rotor *contract* of historical Enigma while deleting every leak the U-534 / P1030680 campaign proved fatal: 26-letter menus, the self-stecker ban, thin plugboards, odometer stepping, and paper day keys. Control-plane crypto (hybrid KEM, HKDF-SHA512, AEAD, Ed25519) never enters the datapath BRAMs. The live field is **Apple Silicon SoftBus** — no FPGA board on the critical path. Red Team pressure (TensorLUT, SoftBus KPA, `ent`) and Blue generation rolls share one Mac.

## Architecture overview

```mermaid
flowchart TB
  subgraph CP["Control plane (Swift / CryptoKit)"]
    HS["Handshake<br/>X25519 ‖ ML-KEM-768 / X-Wing<br/>Ed25519 HELLO/ACK"]
    KDF["HKDF-SHA512<br/>day-v2 · msg-v2 · mac-v1"]
    AEAD["AEAD<br/>HMAC-SHA512 tag<br/>monotonic nonce"]
    WIRE["E2W1 wire · TCP · PSK"]
    HS --> KDF --> AEAD --> WIRE
  end

  subgraph DP["Data plane (SoftBus ↔ enigma_256_core)"]
    BURST["AXIS / SoftBus burst<br/>10×256 BRAM tables"]
    CORE["enigma_256_core<br/>scramble-then-step"]
    STREAM["DATA_IN → scramble → DATA_OUT<br/>NLFF step enables"]
    BURST --> CORE --> STREAM
  end

  subgraph RED["Red / Blue field (this Mac)"]
    ENT["ent gate<br/>PRNG plaintext"]
    KPA["SoftBus KPA<br/>stochastic + structured + joint"]
    TL["TensorLUT cones<br/>NLFF → +lfsr_hi → +offsets"]
    GEN["Enigma256Generation<br/>Fixtures/enigma256_generation.json"]
    ENT --- KPA --- TL
    TL -->|"blue_hold / red_pressure"| GEN
    GEN -->|"mutate NLFF Verilog"| CORE
  end

  KDF -->|"day + message key"| BURST
  AEAD -->|"verify tag before fabric"| STREAM
  WIRE --> AEAD
```

### Byte path (reciprocal)

```mermaid
flowchart LR
  PT["PT byte"] --> PB1["plugboard"]
  PB1 --> R1F["R1 fwd ±off"]
  R1F --> R2F["R2 fwd ±off"]
  R2F --> R3F["R3 fwd ±off"]
  R3F --> R4F["R4 fwd ±off"]
  R4F --> REF["un-reflector<br/>fixed points OK"]
  REF --> R4R["R4 rev ±off"]
  R4R --> R3R["R3 rev ±off"]
  R3R --> R2R["R2 rev ±off"]
  R2R --> R1R["R1 rev ±off"]
  R1R --> PB2["plugboard"]
  PB2 --> CT["CT byte"]
```

Encrypt ≡ decrypt under the same machine state. After each byte: NLFF step enables advance offsets; Galois LFSR clocks.

## The machine (how E256 is put together)

Day key material is a **16-rotor virtual pool** plus plugboard and un-reflector. Each message’s nonce picks **four active rotors** (Walzenlage), **four Grundstellung bytes** (initial offsets), and a **64-bit LFSR seed**. Only the active slot is burst into SoftBus BRAMs (10 × 256 entries).

```mermaid
flowchart TB
  subgraph DAY["Day key (HKDF day-v2 OKM)"]
    PB["Plugboard<br/>256-entry involution<br/>128 pairs · no fixed points"]
    POOL["Rotor pool<br/>16 × (fwd 256 + rev 256)"]
    UKW["Un-reflector<br/>256-entry involution<br/>fixed points allowed"]
  end

  subgraph MSG["Message key (HKDF msg-v2 ← nonce)"]
    WALZ["Walzenlage<br/>pick 4 of 16 indices"]
    GRUND["Grundstellung<br/>offset_r1…r4 ∈ 0…255"]
    SEED["LFSR seed<br/>64-bit · zero→1"]
  end

  subgraph SLOT["Active slot → SoftBus BRAMs"]
    T0["0 plugboard"]
    T1["1–2 R1 fwd/rev"]
    T2["3–4 R2 fwd/rev"]
    T3["5–6 R3 fwd/rev"]
    T4["7–8 R4 fwd/rev"]
    T5["9 reflector"]
  end

  PB --> T0
  POOL --> WALZ
  WALZ --> T1 & T2 & T3 & T4
  UKW --> T5
  GRUND --> CORE
  SEED --> LFSR
```

### One-byte scramble (combinational)

Each rotor stage is **add offset → table lookup → subtract offset** (mod 256). The same plugboard is entered on the way in and on the way out. The un-reflector sits in the middle; because it is an involution, the whole path is reciprocal (encrypt ≡ decrypt).

```mermaid
flowchart LR
  PT["PT"] --> PBin["plugboard[PT]"]
  PBin --> A1["⊕ offset_r1"]
  A1 --> F1["r1_fwd[·]"]
  F1 --> S1["⊖ offset_r1"]
  S1 --> A2["⊕ offset_r2"]
  A2 --> F2["r2_fwd[·]"]
  F2 --> S2["⊖ offset_r2"]
  S2 --> A3["⊕ offset_r3"]
  A3 --> F3["r3_fwd[·]"]
  F3 --> S3["⊖ offset_r3"]
  S3 --> A4["⊕ offset_r4"]
  A4 --> F4["r4_fwd[·]"]
  F4 --> S4["⊖ offset_r4"]
  S4 --> REF["reflector[·]"]
  REF --> A4r["⊕ offset_r4"]
  A4r --> R4["r4_rev[·]"]
  R4 --> S4r["⊖ offset_r4"]
  S4r --> A3r["⊕ offset_r3"]
  A3r --> R3["r3_rev[·]"]
  R3 --> S3r["⊖ offset_r3"]
  S3r --> A2r["⊕ offset_r2"]
  A2r --> R2["r2_rev[·]"]
  R2 --> S2r["⊖ offset_r2"]
  S2r --> A1r["⊕ offset_r1"]
  A1r --> R1["r1_rev[·]"]
  R1 --> S1r["⊖ offset_r1"]
  S1r --> PBout["plugboard[·]"]
  PBout --> CT["CT"]
```

### After the byte: step (sequential)

```mermaid
flowchart TB
  LFSR["lfsr[63:0]<br/>Galois next<br/>feedback 0xD800…"]
  NLFF["NLFF cubic6<br/>four independent folds"]
  LFSR --> NLFF
  NLFF --> S1["step_r1"] & S2["step_r2"] & S3["step_r3"] & S4["step_r4"]
  S1 -->|"if 1: +1"| O1["offset_r1"]
  S2 -->|"if 1: +1"| O2["offset_r2"]
  S3 -->|"if 1: +1"| O3["offset_r3"]
  S4 -->|"if 1: +1"| O4["offset_r4"]
  LFSR -->|"clock"| LFSR
```

Order matches SoftBus / Verilog: **emit CT under current offsets, then step**. Gen 5 bred taps keep each `P(step_ri) ≈ 0.5` with low pairwise φ.

### Planes and trust boundary

| Plane | Runs where | Owns |
|-------|------------|------|
| **Control** | Host Swift | Handshake, IKM, HKDF, AEAD tag verify, nonce counter, `E2W1` |
| **Data** | SoftBus / `enigma_256_core` | BRAM tables, LFSR+NLFF, scramble stream |
| **Red** | Yosys + TensorLUT + SoftBus oracles | Cone melt, KPA, `ent`, campaign ledger |
| **Blue genes** | `Fixtures/enigma256_generation.json` | NLFF formula/taps, HKDF generation labels |

## 1. Architectural corrections (the core machine)

- **Base-256:** alphabet is `0x00…0xFF`; classical 26-letter menus do not transfer.
- **Un-reflector:** involution **with** fixed points — blinds crib self-stecker placement. (Encrypting zeros is *not* a keystream test; ~30% `scramble(0)==0` is expected.)
- **Full-spectrum plugboard:** 128-pair base-256 involution from day-key OKM.
- **Galois LFSR + NLFF stepping:** all four active rotors can move every byte; step enables are non-linear folds, not raw LFSR taps.

## 2. Ephemeral key distribution (handshake)

Control plane only — never in BRAM fabric.

- Ephemeral **X25519**; hybrid **ML-KEM-768** (macOS 26+) → `IKM = X25519_SS ‖ ML-KEM_SS`; optional **X-Wing**.
- Long-term **Ed25519** identities sign hybrid HELLO/ACK (`Enigma256Auth`).
- `burn()` for PFS when the session ends.

## 3. State initialization & key derivation

**HKDF-SHA512** (RFC 5869). Labels: `enigma256-day-v2`, `enigma256-msg-v2`, `enigma256-ecdh-v2`, `enigma256-mac-v1` (plus generation-scoped day/msg info from live genes).

- IKM: ECDH / hybrid / **PBKDF2-HMAC-SHA512** passphrase (default width 64 B).
- Day OKM: plugboard + 16-rotor pool + un-reflector.
- MAC key: separate expand — never reused as stream material.

## 4. Message transmission, AEAD & nonce discipline

- Nonce → Walzenlage (4 of 16), Grundstellung, LFSR seed (micro-HKDF).
- **E256** containers ver=2: HMAC-SHA512 (32-byte tag) over `nonce ‖ ciphertext`. Wire **verifies before** SoftBus/AXI.
- `Enigma256ProtectedSession`: `random[8] ‖ counter_be[8]`; reject nonce reuse under one IKM.

## 5. Non-linear LFSR stepping (NLFF)

Primitive Galois taps 64, 63, 61, 60 → feedback `0xD800_0000_0000_0000`.

| Gen | Formula | Outcome |
|-----|---------|---------|
| 0–2 | `quadratic3` `(a∧b)⊕c` | TensorLUT repeatedly squeezed |
| 3 | `cubic6` fixed taps | TensorLUT hard; **dead middle rotors** |
| 4 | `coupledCubic6` | **Rejected** — correlates steps |
| **5 live** | `cubic6` **bred taps** | ~0.5 rates, low φ; SoftBus field |

Gen 5 folds (`Fixtures/enigma256_generation.json`):

```
step_r1 = (lfsr[4]  & lfsr[15] & lfsr[17]) ^ (lfsr[23] & lfsr[26]) ^ lfsr[61]
step_r2 = (lfsr[7]  & lfsr[9]  & lfsr[31]) ^ (lfsr[38] & lfsr[50]) ^ lfsr[59]
step_r3 = (lfsr[30] & lfsr[43] & lfsr[46]) ^ (lfsr[49] & lfsr[51]) ^ lfsr[60]
step_r4 = (lfsr[12] & lfsr[29] & lfsr[54]) ^ (lfsr[55] & lfsr[57]) ^ lfsr[62]
```

Swift (`Enigma256LFSR.stepMask`) and `enigma_256_core.v` agree. Grade balance with `--enigma256-nlff-stats` / breed with `--enigma256-nlff-breed` **before** celebrating TensorLUT holds. Blue evolves **stronger stepping crypto**; TensorLUT hardness is a constraint, not a trade for correlated rotors.

## 6. Red / Blue evolutionary loop

```mermaid
flowchart LR
  G5["Live gen 5<br/>cubic6 bred"] --> GATES["Fail-closed gates<br/>ent + structured KPA"]
  GATES --> TL["TensorLUT<br/>expect blue_hold"]
  TL -->|hold| HOLD["Keep gen 5"]
  TL -->|"squeeze_survived"| MUT["--enigma256-campaign-mutate<br/>retap / rollback"]
  MUT --> V["Rewrite<br/>core · combo · offset cone"]
  V --> G5
```

- **Red:** SoftBus stochastic KPA, structured hill-climb (partial leak + **day-only joint**), `ent` (PRNG PT), TensorLUT on expanding cones.
- **Blue:** Under pressure, mutate genes + rewrite NLFF lines in `enigma_256_core.v`, `enigma_256_nlff_combo.v`, `enigma_256_nlff_lfsr_combo.v`, `enigma_256_nlff_offset_combo.v`, step cone.

### TensorLUT adversarial cones (growing surface)

| Cone | Module | ~LUT6 | Meaning |
|------|--------|------:|---------|
| NLFF | `enigma_256_nlff_combo` | 4 | Step enables only |
| + LFSR hi | `enigma_256_nlff_lfsr_combo` | 8 | + `lfsr_next[63:56]` |
| **Past NLFF** | `enigma_256_nlff_offset_combo` | ~47 | + `next_ri = offset_ri + step_ri` |
| Full core | `enigma_256_core` | — | **Deferred** (BRAM melt) |

## 7. Deployment field (Apple Silicon)

- SoftBus = AXI/AXIS stand-in; iverilog co-sim + Yosys/TensorLUT = Red harness.
- COTS PL board optional — **not** on the critical path.
- Optional `SCA_CTRL` stream jitter; dual-rail / masked LUTs remain HA synthesis.

## 8. Implementation status

- **Oracle / core:** `Enigma256.swift` ↔ `enigma_256_core.v`. Golden: `Scripts/enigma256_sim.sh`.
- **Session / AEAD:** `Enigma256Context`, `Enigma256AEAD`, `Enigma256ProtectedSession`; `E256` ver=2.
- **AXI / SoftBus:** Lite + AXIS table burst (`enigma_256_axis_tables.v`); SoftBus burst + jitter. Co-sim: `Scripts/enigma256_axi_sim.sh`.
- **Handshake / wire / TCP / PSK:** hybrid default on macOS 26+; `--enigma256-classical` / `--enigma256-passphrase`.
- **Live genes:** gen **5** balanced cubic6.
- **Campaign:** `Scripts/enigma256_rb_campaign.sh` — fail-closes on SoftBus `ent` + structured KPA (`--no-gates` to skip). `--hard-red` NLFF; `--wide` **offset cone** (past NLFF); `--wide-lfsr` NLFF+`lfsr_next_hi`. Battery: `Scripts/enigma256_red_battery.sh`.
- **Ent:** PRNG plaintext (`Scripts/enigma256_ent.sh`). Zero-PT is diagnostic only (un-reflector FP bias).

## 9. Protocol gap closure

| Area | Vulnerability | Severity | Fix shipped |
|------|----------------|----------|-------------|
| LFSR stepping | Raw taps → Berlekamp–Massey | High | NLFF fold (gen 5 live) |
| Data integrity | Bit-flip malleability | High | HMAC-SHA512 AEAD; verify before fabric |
| Key state | Nonce-reuse keystream collision | Critical | Monotonic counter + reject reuse |
| Hardware bus | 2,560 AXI-Lite table writes | Medium | AXIS / SoftBus burst load |
| Side-channel | BRAM address DPA | Medium | Stream jitter; dual-rail noted for HA |
| Red surface | NLFF-only diminishing returns | — | Offset cone (`--wide`); full-core melt still deferred |
