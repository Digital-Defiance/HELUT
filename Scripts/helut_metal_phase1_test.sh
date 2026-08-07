#!/usr/bin/env bash
# Metal torus compiler battery (release): Phase 1 tiles + 2.1/2.2/2.3 + NTT ≡ schoolbook.
# N=1024 wall-clock is logs/helut-encrypted-micro-n1024-persist.log, not this suite.
set -euo pipefail
cd "$(dirname "$0")/.."
swift test -c release --filter 'MetalCompilerPhase1Tests|NegacyclicNTTTests'
