# Apps/

Researcher-owned applications that **depend on** HELUT libraries and never edit Core dispatch.

Until SPM app templates land (`packaging-roadmap.md` P3), add demos here as packages or scripts that call:

| Binary | Use |
|--------|-----|
| `helut-bench` | SING, microbench, noisy-BK, hardness |
| `helut-compile` | `--validate` / compile helpers |
| `helut-e256` | SoftBus / red-battery / TensorLUT melt |
| `helut-bombe` | Welchman / hybrid / campaign |
| `helut` | Umbrella shim (same flags as before) |
| `helut-radio` | C ABI smoke for GNU Radio (`Apps/gr-helut/`) |

### `Apps/gr-helut/`

**Bootstrap:** [`gr-helut/README.md`](gr-helut/README.md) — radioconda
[.pkg → home dir](https://glare-sable.vercel.app/radioconda/radioconda-installer/radioconda-.*-MacOSX-arm64.pkg)
→ activate conda → [CondaInstall](https://wiki.gnuradio.org/index.php/CondaInstall),
then build `libHELUTRadio.dylib` and run the demo ladder.

GNU Radio / ctypes surface over `libHELUTRadio.dylib` (`Sources/HELUTRadio/`).
Build: `make radio`. Edge demo: `make radio-edge` (needs radioconda activated;
Homebrew `gnuradio` is deprecated).

Claim sheet stays in `directives/claim-sheet.md`. Do not invent lecture-voice results in an app README.
