# Bootstrap: HELUT × GNU Radio

**Start here** if you want a Mac flowgraph that ticks a **Yosys gate-level netlist**
(from Verilog) inside GNU Radio — on Apple Silicon.

HELUT is Swift / Metal. GNU Radio is C++ / Python. This app bridges them with a
C ABI dylib (`libHELUTRadio.dylib`) and a small Python OOT.

> **One sentence:** GNU Radio owns the sample clock; HELUT owns the circuit clock.

---

## What you get

| Piece | Role |
|-------|------|
| `libHELUTRadio.dylib` | C ABI over HELUT netlist tick (`Sources/HELUTRadio/include/helut.h`) |
| `helut-radio` | CLI smoke test (no GNU Radio needed) |
| `python/helut_radio/` | ctypes loader + optional `gr.sync_block` |
| `examples/helut_edge_matcher.py` | Closed-loop mindblower (no antenna) |

**Episode 13 story:** locally generated baseband IQ → simulated AWGN → recovered
bytes → the 48-input `ab0cde_matcher.v` Yosys netlist → ★ exact callsign
matches on ASCII `"AB0CDE"`. The transmitted payload is
`CQ CQ CQ DE AB0CDE AB0CDE K`, so match completion indices are `[17, 24]`.
Acts I–II use the clear oracle; the optional encrypted freeze evaluates one
six-byte window at demonstration parameter *N*=8.

---

## Requirements

- **Apple Silicon** Mac (Metal). Intel Mac / Linux: this OOT will not build the
  encrypted path; see repo root [`README.md`](../../README.md) / [`INTRO.md`](../../INTRO.md).
- macOS 14+, Xcode CLT / Swift 6.3+
- GNU Radio via **radioconda** (not Homebrew — that formula is **deprecated**):
  1. Install [Apple Silicon .pkg](https://glare-sable.vercel.app/radioconda/radioconda-installer/radioconda-.*-MacOSX-arm64.pkg) **to your home directory** ([radioconda-installer](https://github.com/radioconda/radioconda-installer))
  2. Activate conda (`conda activate base` or your `gnuradio` env)
  3. Follow [CondaInstall](https://wiki.gnuradio.org/index.php/CondaInstall)

---

## 0. GNU Radio env (radioconda)

Homebrew’s `gnuradio` formula is **deprecated**. Proven Apple Silicon path:

### Step A — Install radioconda to your home directory

1. Installer repo: [radioconda/radioconda-installer](https://github.com/radioconda/radioconda-installer)
2. Download the **Apple Silicon graphical installer** (latest matching release):

   **https://glare-sable.vercel.app/radioconda/radioconda-installer/radioconda-.\*-MacOSX-arm64.pkg**

   CLI alternative on the same host: `radioconda-.*-MacOSX-arm64.sh`.  
   All assets: [releases](https://github.com/radioconda/radioconda-installer/releases)

3. Run the `.pkg`. Install **to your home directory** (default is typically
   `~/radioconda` — “Just Me” / user install, not system-wide).

### Step B — Make sure conda is activated

```bash
# New terminal, or load the hook once in zsh:
source ~/radioconda/etc/profile.d/conda.sh

conda activate base          # radioconda default after the .pkg
# or, if you created/use a named env:
# conda activate gnuradio

# Sanity:
which conda
conda info --envs
```

If `conda activate` says “run conda init”: `conda init zsh`, open a **new**
terminal, then activate again. Bare `conda init` only patches bash.

### Step C — Follow the GNU Radio conda wiki

With conda working, do the rest of the project’s conda instructions:

**https://wiki.gnuradio.org/index.php/CondaInstall**

That page covers env layout, packages, and Companion. When it and radioconda
disagree on download URLs, prefer the **radioconda-installer** links above for
getting the Mac arm64 `.pkg` onto disk.

### Step D — Verify GNU Radio, then come back here

```bash
python -c "import gnuradio; print('ok', gnuradio.__file__)"
which gnuradio-companion
```

Then continue with §1 (build `libHELUTRadio.dylib`).

---

## 1. Build the HELUT dylib

From the HELUT repo root:

```bash
cd /path/to/HELUT
swift build -c release --product HELUTRadio
swift build -c release --product helut-radio
.build/release/helut-radio --selftest
```

Or: `make radio` (dylib + CLI selftest + ctypes byte demo; GR optional).

You want:

```text
.build/release/libHELUTRadio.dylib
.build/release/helut-radio
```

---

## 2. Point Python at the bridge

```bash
cd /path/to/HELUT
export HELUT_RADIO_LIB="$PWD/.build/release/libHELUTRadio.dylib"
export PYTHONPATH="$PWD/Apps/gr-helut/python${PYTHONPATH:+:$PYTHONPATH}"
export GRC_BLOCKS_PATH="$PWD/Apps/gr-helut/grc${GRC_BLOCKS_PATH:+:$GRC_BLOCKS_PATH}"
```

Put those three exports in a small `env.sh` if you like; they must be set in every
shell that runs the demos or GRC.

---

## 3. Run the ladder

Stay in an activated radioconda env (`base` or `gnuradio`) for steps that import `gnuradio`.

### A — No GNU Radio (ctypes only)

```bash
python Apps/gr-helut/examples/helut_regex_demo.py --text 'XXDEFYYDEFZZ'
# expect: ★ MATCH on the two "DEF" endings
```

### B — Minimal GR flowgraph

```bash
python Apps/gr-helut/examples/helut_regex_flowgraph.py
# expect: PASS  hits@ […]
```

### C — Callsign edge demo (closed-loop, no OTA) ← **the one to show people**

```bash
python Apps/gr-helut/examples/helut_edge_matcher.py \
  --batch 10000 --noise 0.0 --encrypted-freeze
```

What you should see:

1. **Act I / GNU Radio** — local BPSK-like IQ → simulated AWGN → exact recovery of
   `CQ CQ CQ DE AB0CDE AB0CDE K`
2. **Act I / HELUT clear oracle** — the 48-input Yosys netlist reports callsign
   completion indices `[17, 24]`, agreeing with both recovered and transmitted bytes
3. **Act II** — 10,000 scalar host-loop windows produce `908/908` expected hits;
   this is explicitly not a native tensor batch or encrypted throughput
4. **Act III** — one recovered `AB0CDE` window evaluates on the fixed-seed *N*=8
   encrypted-demo path; this is not a production security parameter
5. Exit `OK — callsign envelope demo complete (local loopback; no antenna used)`

The older `DEF` CLI and minimal flowgraph remain as compatibility regressions.
To explore channel failures, increase `--noise` separately; noisy runs are not a
byte-for-byte reproducibility claim and now fail closed if the transmitted
callsign windows do not survive.

Or: `make radio-edge` (expects radioconda already activated and uses the
deterministic command above).

### D — Companion (optional)

```bash
gnuradio-companion
# Block category: [HELUT] → HELUT Regex Matcher
```

---

## Modes (honest labels)

| Mode | Engine | Use in demos |
|------|--------|----------------|
| `clear` | Boolean netlist oracle | Real-time / Act I–II |
| `encrypted-demo` | Blind-rotate @ *N*=8 | Act III freeze only — **slow is the point** |

**Not sayable here:** production *N*=1024 real-time FHE, “176-bit secure,” or any
P1030680 decrypt. Science of record stays in [`directives/claim-sheet.md`](../../directives/claim-sheet.md).

---

## Why this is interesting (pitch)

GNU Radio already does DSP on many platforms. What was empty on Mac:

> **Verilog → Yosys `$lut` netlist → Apple Silicon tick → inside a GR block.**

Cousins exist on Linux/CUDA FHE stacks. This hinge is **Metal + Yosys netlist + GR**
on Apple Silicon. The edge-matcher demo proves it **without an antenna**.

Discuss.gnuradio one-liner:

> HELUT OOT: tick a Yosys gate-level circuit from a GR flowgraph on Apple Silicon.
> Closed-loop baseband demo ships; see `Apps/gr-helut/README.md`.

---

## Layout

```text
Apps/gr-helut/
  README.md                 ← you are here (bootstrap)
  python/helut_radio/       ctypes + RegexMatcher sync_block
  grc/                      GRC YAML
  examples/
    helut_regex_demo.py           bytes → HELUT (no GR)
    helut_regex_flowgraph.py      minimal GR top_block
    helut_edge_matcher.py         IQ loopback + batch + encrypted freeze
Sources/HELUTRadio/         Swift → libHELUTRadio.dylib
Sources/HELUTRadio/include/helut.h
```

Repo root pointers: [`README.md`](../../README.md) (project), [`Apps/README.md`](../README.md)
(apps policy), [`make radio`](../../Makefile) / `make radio-edge`.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `conda activate` → “run conda init” | `source ~/radioconda/etc/profile.d/conda.sh`, or `conda init zsh` + new terminal |
| `libHELUTRadio.dylib not found` | `swift build -c release --product HELUTRadio` and set `HELUT_RADIO_LIB` |
| `import gnuradio` fails | .pkg → home dir → activate conda → [CondaInstall](https://wiki.gnuradio.org/index.php/CondaInstall). Apple Silicon: [arm64 .pkg](https://glare-sable.vercel.app/radioconda/radioconda-installer/radioconda-.*-MacOSX-arm64.pkg). Not Homebrew. |
| Still on Homebrew gnuradio | Switch to radioconda — brew formula is deprecated |
| preamble / Act I FAIL under noise | lower `--noise` (try `0.0` … `0.05`) |
| `vmcircbuf` / `shmat` warnings | noisy but often harmless on macOS; check for `PASS` / `OK` |
| encrypted freeze feels slow | expected at demo *N*; do not label it production SING |

---

## Say / don’t say

**Say:** closed-loop baseband; Yosys netlist tick; Apple Silicon; clear oracle real-time;
encrypted demo *N*=8 optional.

**Don’t say:** over-the-air intercept; production-*N* live FHE; Enigma break; “176-bit secure.”
