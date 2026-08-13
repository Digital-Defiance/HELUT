# Packaging roadmap — HELUT as a research library + apps

**Status:** planning (not a claim). Goal: HELUT becomes a **general-purpose
reconfigurable-homomorphic research stack** that outsiders are happy to depend on,
not a single Enigma/campaign megabin.

Living inventory stays [`claim-sheet.md`](claim-sheet.md). Science north star stays
[`../roadmap-overall.md`](../roadmap-overall.md). This file is the **product / API
shape** track.

---

## Diagnosis (today)

| Fact | Implication |
|------|-------------|
| One product: `HELUTCore` library + one `helut` executable | Every new app is another `--flag` in `main.swift` (~1.4k LOC of dispatch) |
| Almost everything is `package`, not `public` | Outsiders cannot import a stable API; Core is an internal bag |
| Core mixes Pillar I FHE, Pillar II TensorLUT, Pillar III E256, Welchman/bombe | Consumers of “just FHE” pull campaign + SoftBus |
| Apps grow in the gallery (I.1–III.3) + avenues | Without packaging, the next app is another spaghetti branch |

**North star:** researchers add an **application package** that depends on thin
library layers, ships its own binary, and never edits Core dispatch.

---

## Target shape

```
Products (SPM)
├── HELUTCore          # torus math, GGSW/BR, certificates, Metal kernels (Pillar I kernel)
├── HELUTNetlist       # Yosys JSON → clear/encrypted netlist sim, compile pipeline
├── HELUTTensorLUT     # continuous INIT, melt/squeeze/friction, emitter (Pillar II)
├── HELUTSoftBus       # Enigma256 SoftBus + reciprocity (Pillar III) — optional dep
│
├── helut              # thin CLI umbrella: `helut <subcommand>` → delegates
├── helut-compile      # Yosys/netlist → Metal / certificates
├── helut-bench        # SING / micro / noisy-BK / hardness
├── helut-tensorlut    # melt / squeeze / emit / involution protocols
├── helut-e256         # SoftBus listen/connect/red-battery
├── helut-bombe        # Welchman / hybrid / campaign (P1030680)
└── Apps/…             # researcher-owned: riscv, regex, gallery demos, third-party
```

**Rules**

1. **Libraries are the product.** Binaries are thin `ArgumentParser` (or equivalent) fronts.
2. **Campaign is an app**, not the center. `helut-bombe` may depend on Core + Netlist;
   Core must not depend on campaign types.
3. **Public API surface is small and versioned.** Prefer `public` structs/protocols with
   documented invariants; keep Metal/GPU guts `package`/`internal` until stable.
4. **One claim sheet, many binaries.** Reproduce commands name the binary
   (`helut-bench --measure-bk-noise …`), not a 40-flag soup.
5. **Extension point:** `Apps/<name>/` with its own executable target + README that
   points at claims it consumes — never invents lecture-voice results.

---

## Layer contracts

### `HELUTCore` (Pillar I kernel)

- LWE/GLWE/GGSW, blind-rotate, publicMS/secret refresh, certificates (noise, ε, hardness, noisy-BK)
- Metal BR / NTT / persist tiles
- **No** Yosys JSON parsing, **no** Enigma M4, **no** Welchman menus, **no** TensorLUT melt loop

### `HELUTNetlist`

- Cleartext + encrypted netlist sim, ingest, wavefront schedule
- Depends on: Core
- Binary: `helut-compile`, pieces of `helut-bench`

### `HELUTTensorLUT`

- Continuous tensors, λ friction, shatter/hold, Verilog emit, formal certs (C19/C25)
- Depends on: Core (minimal) — **not** on SoftBus or bombe
- Binary: `helut-tensorlut`

### `HELUTSoftBus` (Pillar III)

- Enigma256 SoftBus, reciprocity, fail-closed NLFF
- Depends on: Core (crypto primitives only as needed)
- Binary: `helut-e256`
- Optional dep of TensorLUT *apps*, not of Core

### Campaign / Welchman

- Move `Bombe*`, `Hybrid*`, `Welchman*`, P1030680 harness out of Core into
  `Sources/HELUTBombe/` + executable `helut-bombe`
- Ledger / journal sync rules unchanged

---

## Migration phases (ordered)

### P0 — Freeze the map (1–2 days)

- [x] Inventory every `helut` flag → binary (see `HelutEntries.swift` CLIs)
- [x] Shared `HELUTCLI` + `HELUTToolKit` landed
- [ ] Add `directives/public-api.md` stub: what becomes `public` in Core v0.1
- [x] Do **not** break `REPRODUCE.md` in this phase — umbrella `helut` still accepts old flags

### P1 — Split libraries without new binaries ( mechanize )

- [ ] SPM targets: `HELUTNetlist`, `HELUTTensorLUT`, `HELUTSoftBus`, `HELUTBombe` (library)
- [x] Interim: `HELUTToolKit` holds former `Sources/helut` command code
- [ ] Start marking stable Core entry points `public` (params, certs, encrypt/BR)

### P2 — Carve binaries (UX)

- [x] Ship `helut-bench`, `helut-compile`, `helut-e256`, `helut-bombe`
- [x] `helut` becomes a dispatcher (in-process; same flags)
- [ ] Update `REPRODUCE.md` preferred binary names; keep shim ≥1 epoch
- [ ] `helut-tensorlut` binary (still under `helut-e256 --enigma256-tensorlut` for now)

### P3 — Apps directory (growth)

```
Apps/
  FullAdderSING/
  RegexNet/
  PicoRV/
  GalleryDemo/
  <third-party>/
```

- [ ] Template: `Package.swift` snippet or SPM plugin doc — “depend on HELUTCore ≥ C34”
- [ ] Each app: README with claim IDs consumed + reproduce one-liner
- [ ] Gallery site points at Apps/, not at megabin flags

### P4 — Researcher happiness

- [ ] DocC for Core public API (`make docs-api`)
- [x] Semver tags for library (`0.1.0` / `helut-lib-0.1.0`) separate from corpus tags (`helut-corpus-C*`)
- [x] Homebrew formula in [`Digital-Defiance/homebrew-tap`](https://github.com/Digital-Defiance/homebrew-tap) (`Formula/helut.rb`) + HELUT `HOMEBREW.md`
- [ ] Example out-of-tree package in MuleinLabs or `examples/hello-br/`
- [ ] CI matrix: Core-only tests vs app tests (Metal optional jobs)

---

## What stays unified

| Keep one of | Why |
|-------------|-----|
| `directives/claim-sheet.md` | Science of record |
| Living textbook TeX in HELUT | Same-turn as claims |
| Corpus tags `helut-corpus-C*` | Disclosure freeze |
| MuleinLabs as publish umbrella | Videos + site; HELUT submodule pin |

Library semver ≠ corpus epoch. A researcher can depend on `HELUTCore 0.2` while
your disclosure tag is `C40`.

---

## Explicit non-goals (near term)

- Rewriting Metal kernels during the split
- Moving textbook TeX to MuleinLabs
- Merging campaign fitness into Core APIs (**N6**)
- Claiming “general TFHE library competitive with Concrete/tfhe-rs” until public API + docs exist

---

## Success metric

A new researcher can:

1. `dependencies: [.package(url: "…HELUT", from: "0.1.0")]`
2. `import HELUTCore` and run a certified blind-rotate on a 1-LUT netlist in <30 lines
3. Add `Apps/MyCipher/` with its own binary without touching `main.swift`
4. Never link `HELUTBombe` unless they opted in

Until then, HELUT remains a powerful lab — not yet a tool others are happy to grow.
