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

Claim sheet stays in `directives/claim-sheet.md`. Do not invent lecture-voice results in an app README.
