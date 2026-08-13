# Homebrew

HELUT **CLI tools** install from the Digital Defiance tap
([`Digital-Defiance/homebrew-tap`](https://github.com/Digital-Defiance/homebrew-tap)).
Swift libraries (`HELUTCore`, …) are consumed with **Swift Package Manager**, not as a
Homebrew keg of headers.

## Install

```bash
brew tap digital-defiance/homebrew-tap
brew install helut                 # needs tag 0.1.0 + real sha256 in the formula
# until the first stable tag is published:
brew install --HEAD helut
```

Requires **macOS 14+**, **Apple Silicon**, and Xcode / CLT with Swift 6.3+.
Builds from source (Metal + MPSGraph — no generic bottle yet).

## What you get

| Binary | Role |
|--------|------|
| `helut` | Umbrella shim (legacy flags) |
| `helut-bench` | SING / micro / noisy-BK / hardness |
| `helut-e256` | Enigma256 SoftBus / melt |
| `helut-bombe` | Welchman / hybrid / campaign |
| `helut-compile` | Netlist validate |

```bash
helut
helut-bench --hardness-table
```

## Library (SPM — not Homebrew)

```swift
dependencies: [
  .package(url: "https://github.com/Digital-Defiance/HELUT.git", from: "0.1.0")
]
```

Tag `0.1.0` is the API / CLI semver (optional alias `helut-lib-0.1.0`). Corpus tags
`helut-corpus-C*` are disclosure freezes, not API versions.

## Maintainers

Formula path: `/Volumes/Code/homebrew-tap/Formula/helut.rb` (not this repo).

```bash
# In HELUT, after tagging and pushing 0.1.0:
./Scripts/homebrew-bump.sh 0.1.0
# Paste sha256 into homebrew-tap/Formula/helut.rb, commit + push the tap.
```
