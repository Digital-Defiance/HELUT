#!/usr/bin/env python3
"""Cross-process determinism gate for the encrypted path.

Why this exists as a separate process driver rather than a test.

On 2026-08-15 `EncryptedNetlistSimulator.tick` encrypted primary inputs while
iterating `inputs` as a Dictionary, drawing from the shared serial RNG inside the
loop. Swift reseeds Dictionary hashing *per process*, so two runs of the same
binary at the same seed visited the ports in different orders and handed a
different mask to a different wire. Wherever the decode margin was thin this
turned into a coin toss, and it cost a real claim: the n=512 covering-b2 adder
was recorded as a noise-limit FAIL (C69) when it was actually this.

An in-process test can permute keys to *simulate* the effect, and
`EncryptedDeterminismTests` does. But one process has one hash seed, so no
in-process test can observe the property that actually broke. This driver runs
the emitting test as N separate processes and requires byte-identical
fingerprints.

Critical: `SWIFT_DETERMINISTIC_HASHING` must stay unset. Setting it suppresses
the per-process reseeding, which would make this check pass unconditionally --
it would test nothing. The script refuses to run if it is set.

Usage:
    python3 Scripts/determinism_cross_process.py [--runs N] [--verbose]

Exit status:
    0  all runs agreed
    1  fingerprints diverged (a real determinism defect)
    2  harness problem (build failure, marker missing, env misconfigured)
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys

MARKER = "CROSS_PROCESS_FINGERPRINT"
TEST_FILTER = "EncryptedCrossProcessDeterminismTests"
DEFAULT_RUNS = 5


def warmup() -> None:
    """Compile the test bundle once so the compared runs are pure execution.

    `swift build --build-tests` does not enable testability under `-c release`
    (the bundle fails with "module 'HELUTCore' was not compiled for testing"),
    so the warmup goes through `swift test` like the real runs do.
    """
    proc = subprocess.run(
        ["swift", "test", "-c", "release", "--filter", TEST_FILTER],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0 or MARKER not in (proc.stdout + proc.stderr):
        sys.stderr.write("harness: warmup run failed to produce a fingerprint\n")
        sys.stderr.write((proc.stdout + proc.stderr)[-4000:])
        sys.exit(2)


def one_run(index: int, verbose: bool) -> str:
    env = dict(os.environ)
    # Belt and braces: the check is meaningless with hashing pinned.
    env.pop("SWIFT_DETERMINISTIC_HASHING", None)
    # Vary something innocuous so the processes are not identical images.
    env["HELUT_DETERMINISM_PROBE"] = str(index)

    proc = subprocess.run(
        ["swift", "test", "-c", "release", "--filter", TEST_FILTER],
        capture_output=True,
        text=True,
        env=env,
    )
    haystack = proc.stdout + proc.stderr
    found = re.findall(rf"{MARKER}\s+([0-9a-f]+)", haystack)

    if not found:
        sys.stderr.write(
            f"harness: run {index} produced no {MARKER} line.\n"
            "The test may have failed to build or the marker was renamed.\n"
        )
        sys.stderr.write(haystack[-3000:])
        sys.exit(2)

    # The test asserts before printing, so a nonzero status with a marker still
    # means something went wrong.
    if proc.returncode != 0:
        sys.stderr.write(f"harness: run {index} exited {proc.returncode}\n")
        sys.stderr.write(haystack[-3000:])
        sys.exit(2)

    if verbose:
        print(f"  run {index}: {found[0]}")
    return found[0]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--runs", type=int, default=DEFAULT_RUNS)
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    if os.environ.get("SWIFT_DETERMINISTIC_HASHING"):
        sys.stderr.write(
            "refusing to run: SWIFT_DETERMINISTIC_HASHING is set, which pins the\n"
            "Dictionary hash seed and makes this check vacuous. Unset it.\n"
        )
        return 2

    if args.runs < 2:
        sys.stderr.write("refusing to run: need at least 2 processes to compare\n")
        return 2

    print(f"cross-process determinism: {args.runs} separate processes")
    warmup()

    fingerprints = [one_run(i, args.verbose) for i in range(args.runs)]
    unique = sorted(set(fingerprints))

    if len(unique) == 1:
        print(f"PASS all {args.runs} processes agreed: {unique[0]}")
        return 0

    print(f"FAIL {len(unique)} distinct fingerprints across {args.runs} processes")
    for fp in unique:
        count = fingerprints.count(fp)
        print(f"  {fp}  x{count}")
    print(
        "\nThe encrypted path depends on per-process state. The 2026-08-15 cause\n"
        "was Dictionary iteration order feeding a shared RNG; check for any\n"
        "unordered collection traversed while drawing randomness or assigning\n"
        "ciphertexts. See AUDIT.md and EncryptedDeterminismTests."
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
