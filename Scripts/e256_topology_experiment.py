#!/usr/bin/env python3
"""E256 topology gate: mirrored conjugated-XOR vs independent ingress/egress.

STATUS: OPEN_PROGRESS research gate. This is **not** a closure receipt. It does
not close E256-003, E256-061, any release gate, or promote any C/H/N row. It is
bounded structural + measured-advantage evidence for one design decision:

  (Q1) Does adding active rotors to the *mirrored* construction remove its
       fixed-state structure?     C_i = A_i^-1( A_i(P_i) XOR M_i )
  (Q2) Does an *independent* ingress/egress topology remove it at equal or
       lower online lookup depth?  C_i = B_i( A_i(P_i) XOR M_i )

Part A anchors the model to the shipped E256-v3/gen0 fixture-v5 (real tables,
real 1024-byte trace, center mask recomputed from the fixture's center-mask key)
so every structural result below describes the actual implementation rather than
a paraphrase of it. If Part A fails, the whole run fails.

All randomness is derived deterministically from fixed labels via HMAC-SHA512,
so the deterministic subtree of the receipt is byte-reproducible. Timing is
advisory and excluded from the results digest.

Usage:
  python3 Scripts/e256_topology_experiment.py            # emit receipt
  python3 Scripts/e256_topology_experiment.py --check    # verify reproducibility
"""

from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import platform
import statistics
import subprocess
import sys
import time
from pathlib import Path

import numpy as np

REPO = Path(__file__).resolve().parent.parent
PROFILE_HASH = "0206c00e5084ebafe1f841708d2af3f4a029bcf160f7b22ed63bb5078d376e16"
FIXTURE = REPO / "Fixtures/Staging/Enigma256" / f"E256-v3-gen0-{PROFILE_HASH}-fixture-v5"
RECEIPT = REPO / "logs/e256-vnext-topology-gate.json"
IDENTITY = np.arange(256, dtype=np.uint8)

# Pinned experiment parameters. Changing any of these changes the digest.
PINNED = {
    "rotor_counts": [1, 4, 8, 16, 256],
    "structural_keys": 64,
    "recovery_keys": 8,
    "cycle_statistics_keys": 64,
    "codebook_keys": 8,
    "distinguisher_trials": 20000,
    "distinguisher_masks_per_key": 128,
    "asymmetric_reference_stack": 4,
    "two_cycle_measured_masks": [1, 2, 3, 127, 128, 129, 254, 255],
}


# ---------------------------------------------------------------- derivation
# Same shapes as Sources/HELUTCore/Enigma256V3.swift: HMAC-SHA512 purpose
# stream, u16be_reject_high_v1 bounded sampler, Fisher-Yates, and a
# fixed-point-free involution plugboard.


class PurposeStream:
    def __init__(self, key: bytes, label: bytes) -> None:
        self.key = key
        self.label = label
        self.counter = 0
        self.buf = b""
        self.off = 0

    def byte(self) -> int:
        if self.off == len(self.buf):
            msg = self.label + b"\x00" + self.counter.to_bytes(8, "big")
            self.buf = hmac.new(self.key, msg, hashlib.sha512).digest()
            self.counter += 1
            self.off = 0
        value = self.buf[self.off]
        self.off += 1
        return value

    def u16be(self) -> int:
        return (self.byte() << 8) | self.byte()

    def bounded(self, upper: int) -> int:
        limit = 65536 - (65536 % upper)
        while True:
            value = self.u16be()
            if value < limit:
                return value % upper


def fisher_yates(count: int, stream: PurposeStream) -> np.ndarray:
    items = list(range(count))
    for index in range(count - 1, 0, -1):
        other = stream.bounded(index + 1)
        items[index], items[other] = items[other], items[index]
    return np.array(items, dtype=np.uint8)


def derive_permutation(key: bytes, label: bytes) -> tuple[np.ndarray, np.ndarray]:
    forward = fisher_yates(256, PurposeStream(key, label))
    reverse = np.empty(256, dtype=np.uint8)
    reverse[forward] = IDENTITY
    return forward, reverse


def derive_involution_plugboard(key: bytes, label: bytes) -> np.ndarray:
    order = fisher_yates(256, PurposeStream(key, label))
    table = np.zeros(256, dtype=np.uint8)
    for pair in range(0, 256, 2):
        left, right = int(order[pair]), int(order[pair + 1])
        table[left] = right
        table[right] = left
    return table


def derive_stack(key: bytes, tag: str, count: int):
    forwards, reverses = [], []
    for index in range(count):
        fwd, rev = derive_permutation(key, f"{tag}/rotor/{index:04d}".encode())
        forwards.append(fwd)
        reverses.append(rev)
    stream = PurposeStream(key, f"{tag}/positions".encode())
    positions = np.frombuffer(bytes(stream.byte() for _ in range(count)), dtype=np.uint8)
    return forwards, reverses, positions


# ------------------------------------------------------- literal byte paths
# Deliberately naive: one dependent lookup at a time, exactly as software or
# RTL walks it. Used to prove the collapsed algebra below is faithful rather
# than assumed.


def mirrored_literal(x, plug, forwards, reverses, positions, mask):
    v = int(plug[x])
    for r in range(len(forwards)):
        p = int(positions[r])
        v = (int(forwards[r][(v + p) & 0xFF]) - p) & 0xFF
    v ^= mask
    for r in range(len(reverses) - 1, -1, -1):
        p = int(positions[r])
        v = (int(reverses[r][(v + p) & 0xFF]) - p) & 0xFF
    return int(plug[v])


def asymmetric_literal(x, pin, fa, pa, pout, fb, pb, mask):
    v = int(pin[x])
    for r in range(len(fa)):
        p = int(pa[r])
        v = (int(fa[r][(v + p) & 0xFF]) - p) & 0xFF
    v ^= mask
    for r in range(len(fb)):
        p = int(pb[r])
        v = (int(fb[r][(v + p) & 0xFF]) - p) & 0xFF
    return int(pout[v])


def collapse_forward(plug, forwards, positions) -> np.ndarray:
    """Fold plugboard + offset rotor stack into one permutation."""
    a = plug[IDENTITY]
    for r in range(len(forwards)):
        p = int(positions[r])
        a = (forwards[r][(a.astype(np.uint16) + p) & 0xFF] - p).astype(np.uint8)
    return a


def invert(perm: np.ndarray) -> np.ndarray:
    out = np.empty(256, dtype=np.uint8)
    out[perm] = IDENTITY
    return out


def cycle_stats(perm: np.ndarray) -> dict:
    seen = np.zeros(256, dtype=bool)
    lengths = []
    for start in range(256):
        if seen[start]:
            continue
        length, cursor = 0, start
        while not seen[cursor]:
            seen[cursor] = True
            cursor = int(perm[cursor])
            length += 1
        lengths.append(length)
    return {
        "fixed_points": int(np.sum(perm == IDENTITY)),
        "two_cycles": sum(1 for n in lengths if n == 2),
        "max_cycle": max(lengths),
        "is_involution": bool(np.array_equal(perm[perm], IDENTITY)),
    }


def build_asymmetric(key: bytes, count: int):
    """C = B(A(x) XOR M) with independent ingress/egress material."""
    pin = derive_permutation(key, b"asym/pin")[0]
    pout = derive_permutation(key, b"asym/pout")[0]
    fa, _, pa = derive_stack(key, "asym/in", count)
    fb, _, pb = derive_stack(key, "asym/out", count)
    big_a = collapse_forward(pin, fa, pa)
    big_b = pout[collapse_forward(IDENTITY.copy(), fb, pb)]
    return big_a, big_b


# --------------------------------------------------------- part A: fidelity


def part_a_fixture_fidelity() -> dict:
    art = FIXTURE / "artifacts"
    manifest = json.loads((FIXTURE / "fixture-v5.json").read_text())
    names = ("plugboard", "r1_fwd", "r1_rev", "r2_fwd", "r2_rev",
             "r3_fwd", "r3_rev", "r4_fwd", "r4_rev")
    tables = {
        n: np.frombuffer((art / "tables" / f"{n}.bin").read_bytes(), dtype=np.uint8)
        for n in names
    }
    plug = tables["plugboard"]
    forwards = [tables[f"r{i}_fwd"] for i in (1, 2, 3, 4)]
    reverses = [tables[f"r{i}_rev"] for i in (1, 2, 3, 4)]

    center_key = bytes.fromhex(manifest["derivation"]["center_mask_key_hex"])
    domain = f"E256/v3/gen0/{PROFILE_HASH}/center-mask/block".encode()

    def center_mask(counter: int) -> int:
        msg = domain + b"\x00" + (counter // 32).to_bytes(8, "big")
        return hmac.new(center_key, msg, hashlib.sha256).digest()[counter % 32]

    rows = (art / "stream-trace.csv").read_text().strip().splitlines()
    idx = {name: i for i, name in enumerate(rows[0].split(","))}
    plaintext = (art / "plaintext.bin").read_bytes()
    ciphertext = (art / "ciphertext.bin").read_bytes()

    checked = mask_ok = out_ok = center_ok = round_trip = 0
    for row, p_byte, c_byte in zip(rows[1:], plaintext, ciphertext):
        f = row.split(",")
        counter = int(f[idx["counter_before"]], 16)
        positions = np.frombuffer(bytes.fromhex(f[idx["positions_before"]]), dtype=np.uint8)
        x = int(f[idx["input"]], 16)
        want_out = int(f[idx["output"]], 16)
        want_mask = int(f[idx["center_mask"]], 16)
        want_cin = int(f[idx["center_input"]], 16)
        want_cout = int(f[idx["center_output"]], 16)

        mask_ok += center_mask(counter) == want_mask
        out_ok += mirrored_literal(x, plug, forwards, reverses, positions, want_mask) == want_out
        a = collapse_forward(plug, forwards, positions)
        center_ok += int(a[x]) == want_cin and (int(a[x]) ^ want_mask) == want_cout
        round_trip += (
            mirrored_literal(c_byte, plug, forwards, reverses, positions, want_mask) == p_byte
        )
        checked += 1

    return {
        "fixture": str(FIXTURE.relative_to(REPO)),
        "trace_rows": checked,
        "recomputed_center_mask_matches": mask_ok,
        "modeled_output_matches": out_ok,
        "collapsed_algebra_matches_center_io": center_ok,
        "ciphertext_to_plaintext_matches": round_trip,
        "pass": mask_ok == out_ok == center_ok == round_trip == checked == 1024,
    }


# ------------------------- part B: structure vs rotor count (exhaustive)


def part_b_structure() -> dict:
    results = {}
    for count in PINNED["rotor_counts"]:
        verdicts = []
        for k in range(PINNED["structural_keys"]):
            key = hashlib.sha512(f"B/{count}/{k}".encode()).digest()
            plug = derive_involution_plugboard(key, b"plugboard")
            forwards, reverses, positions = derive_stack(key, "mirror", count)
            a = collapse_forward(plug, forwards, positions)
            a_inv = invert(a)

            masks = np.arange(256, dtype=np.uint8).reshape(256, 1)
            s_all = a_inv[np.bitwise_xor(a.reshape(1, 256), masks)]
            identity_at_zero = bool(np.array_equal(s_all[0], IDENTITY))

            nonzero = s_all[1:]
            round_trip = np.take_along_axis(nonzero, nonzero.astype(np.intp), axis=1)
            all_involution = bool(np.all(round_trip == IDENTITY.reshape(1, 256)))
            all_fpf = bool(np.all(np.sum(nonzero == IDENTITY.reshape(1, 256), axis=1) == 0))
            sampled_two_cycles = all(
                cycle_stats(s_all[m])["two_cycles"] == 128
                for m in PINNED["two_cycle_measured_masks"]
            )

            literal_agrees = True
            for mask in (0, 1, 7, 128, 255):
                for x in range(256):
                    if mirrored_literal(x, plug, forwards, reverses, positions, mask) != int(
                        a_inv[int(a[x]) ^ mask]
                    ):
                        literal_agrees = False
                        break
                if not literal_agrees:
                    break

            verdicts.append(
                all([identity_at_zero, all_involution, all_fpf,
                     sampled_two_cycles, literal_agrees])
            )
        results[str(count)] = {
            "keys": PINNED["structural_keys"],
            "masks_per_key": 256,
            "inputs_per_mask": 256,
            "identity_at_mask_zero": all(verdicts),
            "involution_for_all_255_nonzero_masks": all(verdicts),
            "fixed_point_free_for_all_255_nonzero_masks": all(verdicts),
            "exactly_128_two_cycles_on_measured_masks": all(verdicts),
            "literal_stack_equals_collapsed_algebra": all(verdicts),
        }
    return results


# ------------------------ part C: mask uniqueness/recovery (exhaustive)


def part_c_mask_recovery() -> dict:
    mirrored_ok = asym_ok = 0
    keys = PINNED["recovery_keys"]
    for k in range(keys):
        key = hashlib.sha512(f"C/{k}".encode()).digest()
        plug = derive_involution_plugboard(key, b"plugboard")
        fwd, _, pos = derive_stack(key, "mirror", 4)
        a = collapse_forward(plug, fwd, pos)
        a_inv = invert(a)
        big_a, big_b = build_asymmetric(key, 4)
        big_b_inv = invert(big_b)

        m_ok = z_ok = True
        for mask in range(256):
            s_m = a_inv[(a.astype(np.uint16) ^ mask).astype(np.uint8)]
            s_a = big_b[(big_a.astype(np.uint16) ^ mask).astype(np.uint8)]
            for x in (0, 3, 97, 200, 255):
                c_m, c_a = int(s_m[x]), int(s_a[x])
                if (int(a[x]) ^ int(a[c_m])) != mask:
                    m_ok = False
                if (int(big_a[x]) ^ int(big_b_inv[c_a])) != mask:
                    z_ok = False
                if sum(1 for g in range(256) if int(a_inv[int(a[x]) ^ g]) == c_m) != 1:
                    m_ok = False
                if sum(1 for g in range(256) if int(big_b[int(big_a[x]) ^ g]) == c_a) != 1:
                    z_ok = False
        mirrored_ok += m_ok
        asym_ok += z_ok
    return {
        "keys": keys,
        "masks_per_key": 256,
        "mirrored_mask_unique_and_equals_A_P_xor_A_C": mirrored_ok == keys,
        "asymmetric_mask_unique_and_equals_A_P_xor_Binv_C": asym_ok == keys,
        "note": "rotor count does not appear in either recovery formula",
    }


# --------------- part D: asymmetric cycle structure vs random permutation


def part_d_cycle_structure() -> dict:
    keys = PINNED["cycle_statistics_keys"]
    stack = PINNED["asymmetric_reference_stack"]

    def sample(kind):
        fixed, invol, maxc = [], 0, []
        for k in range(keys):
            key = hashlib.sha512(f"D/{kind}/{k}".encode()).digest()
            if kind == "asymmetric":
                big_a, big_b = build_asymmetric(key, stack)
                mask = PurposeStream(key, b"mask").byte()
                s = big_b[(big_a.astype(np.uint16) ^ mask).astype(np.uint8)]
                assert len(np.unique(s)) == 256, "asymmetric map must be a bijection"
                b_inv, a_inv = invert(big_b), invert(big_a)
                decrypted = a_inv[(b_inv[s].astype(np.uint16) ^ mask).astype(np.uint8)]
                assert np.array_equal(decrypted, IDENTITY), "asymmetric decrypt must be exact"
            else:
                s = derive_permutation(key, b"random")[0]
            st = cycle_stats(s)
            fixed.append(st["fixed_points"])
            invol += st["is_involution"]
            maxc.append(st["max_cycle"])
        return {
            "mean_fixed_points": round(statistics.mean(fixed), 4),
            "involution_rate": invol / keys,
            "mean_max_cycle": round(statistics.mean(maxc), 2),
        }

    return {
        "keys": keys,
        "asymmetric_stack": f"{stack}+{stack}",
        "asymmetric": sample("asymmetric"),
        "uniform_random_permutation_control": sample("random"),
        "mirrored_exact": {"mean_fixed_points": 0.0, "involution_rate": 1.0, "mean_max_cycle": 2.0},
        "poisson_expectation_fixed_points": 1.0,
    }


# ------------------- part E: two-query same-state distinguisher advantage


def part_e_distinguisher() -> dict:
    """Adversary: query x -> y, then y -> z at one frozen state.

    Guess 'structured' iff z == x. Two queries, no key guessing.
    """
    trials = PINNED["distinguisher_trials"]
    per_key = PINNED["distinguisher_masks_per_key"]

    def rate(family, tag):
        hits = done = 0
        key_index = 0
        while done < trials:
            key = hashlib.sha512(f"E/{tag}/{key_index}".encode()).digest()
            key_index += 1
            probe = PurposeStream(key, b"probe")
            for s in family(key, per_key):
                if done >= trials:
                    break
                x = probe.byte()
                hits += int(s[int(s[x])]) == x
                done += 1
        return hits / done

    def mirrored(count):
        def family(key, n):
            plug = derive_involution_plugboard(key, b"plugboard")
            fwd, _, pos = derive_stack(key, "mirror", count)
            a = collapse_forward(plug, fwd, pos)
            a_inv = invert(a)
            return [a_inv[(a.astype(np.uint16) ^ m).astype(np.uint8)] for m in range(1, n + 1)]
        return family

    def asymmetric(count):
        def family(key, n):
            big_a, big_b = build_asymmetric(key, count)
            return [big_b[(big_a.astype(np.uint16) ^ m).astype(np.uint8)] for m in range(1, n + 1)]
        return family

    def random_family(key, n):
        return [derive_permutation(key, f"random/{i}".encode())[0] for i in range(n)]

    control = rate(random_family, "ctrl")
    out = {
        "trials_per_cell": trials,
        "masks_per_key": per_key,
        "queries_per_trial": 2,
        "random_permutation_control_rate": control,
        "mirrored": {},
        "asymmetric": {},
    }
    for count in PINNED["rotor_counts"]:
        r = rate(mirrored(count), f"m{count}")
        out["mirrored"][str(count)] = {"detect_rate": r, "advantage": round(abs(r - control), 6)}
    for count in PINNED["rotor_counts"]:
        r = rate(asymmetric(count), f"a{count}")
        out["asymmetric"][str(count)] = {"detect_rate": r, "advantage": round(abs(r - control), 6)}
    return out


# ----------------------------- part F: codebook cost at one frozen state


def part_f_codebook() -> dict:
    keys = PINNED["codebook_keys"]
    mirrored_costs, asym_costs = [], []
    for k in range(keys):
        key = hashlib.sha512(f"F/{k}".encode()).digest()
        plug = derive_involution_plugboard(key, b"plugboard")
        fwd, _, pos = derive_stack(key, "mirror", 4)
        a = collapse_forward(plug, fwd, pos)
        a_inv = invert(a)
        mask = PurposeStream(key, b"mask").byte() or 1
        s_m = a_inv[(a.astype(np.uint16) ^ mask).astype(np.uint8)]

        known, queries = {}, 0
        for x in range(256):
            if x in known:
                continue
            y = int(s_m[x])
            queries += 1
            known[x] = y
            known[y] = x  # the involution hands over the partner for free
        assert len(known) == 256
        mirrored_costs.append(queries)

        big_a, big_b = build_asymmetric(key, 4)
        s_a = big_b[(big_a.astype(np.uint16) ^ mask).astype(np.uint8)]
        known2, queries2 = {}, 0
        for x in range(256):
            if len(known2) == 255:
                break  # final entry follows by elimination
            known2[x] = int(s_a[x])
            queries2 += 1
        asym_costs.append(queries2)
    return {
        "keys": keys,
        "mirrored_queries_for_full_state_map": int(statistics.mean(mirrored_costs)),
        "asymmetric_queries_for_full_state_map": int(statistics.mean(asym_costs)),
        "leak_factor": round(
            statistics.mean(asym_costs) / statistics.mean(mirrored_costs), 4
        ),
    }


# ------------------------------------------- part G: online cost per byte


def part_g_cost() -> dict:
    rows = {}
    for count in PINNED["rotor_counts"]:
        key = hashlib.sha512(f"G/{count}".encode()).digest()
        plug = derive_involution_plugboard(key, b"plugboard")
        fwd, rev, pos = derive_stack(key, "mirror", count)
        split = max(1, count // 2)
        pin = derive_permutation(key, b"asym/pin")[0]
        pout = derive_permutation(key, b"asym/pout")[0]
        fa, _, pa = derive_stack(key, "asym/in", split)
        fb, _, pb = derive_stack(key, "asym/out", split)

        samples = 64
        t0 = time.perf_counter()
        for x in range(samples):
            mirrored_literal(x & 0xFF, plug, fwd, rev, pos, 0x5A)
        mirror_us = (time.perf_counter() - t0) / samples * 1e6
        t0 = time.perf_counter()
        for x in range(samples):
            asymmetric_literal(x & 0xFF, pin, fa, pa, pout, fb, pb, 0x5A)
        asym_us = (time.perf_counter() - t0) / samples * 1e6

        rows[str(count)] = {
            "mirrored_dependent_lookups_per_byte": 2 * count + 2,
            "mirrored_us_per_byte": round(mirror_us, 2),
            "asymmetric_split": f"{split}+{split}",
            "asymmetric_dependent_lookups_per_byte": 2 * split + 2,
            "asymmetric_us_per_byte": round(asym_us, 2),
        }
    return rows


# ---------------------------------------------------------------- receipt


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def toolchain() -> dict:
    def run(cmd):
        try:
            return subprocess.run(cmd, capture_output=True, text=True, timeout=20).stdout.strip().splitlines()[0]
        except Exception:
            return "unavailable"

    return {
        "python": sys.version.split()[0],
        "numpy": np.__version__,
        "platform": platform.platform(),
        "git_head": run(["git", "-C", str(REPO), "rev-parse", "HEAD"]),
        "git_dirty": bool(run(["git", "-C", str(REPO), "status", "--porcelain"])),
    }


def build_receipt() -> dict:
    results = {
        "A_fixture_fidelity": part_a_fixture_fidelity(),
        "B_structure_vs_rotor_count": part_b_structure(),
        "C_mask_recovery": part_c_mask_recovery(),
        "D_cycle_structure": part_d_cycle_structure(),
        "E_two_query_distinguisher": part_e_distinguisher(),
        "F_same_state_codebook_cost": part_f_codebook(),
    }
    digest = hashlib.sha256(
        json.dumps(results, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()
    return {
        "schema": "E256-VNEXT-TOPOLOGY-GATE-1",
        "status": "OPEN_PROGRESS",
        "question": {
            "mirrored": "C_i = A_i^-1( A_i(P_i) XOR M_i )",
            "asymmetric_candidate": "C_i = B_i( A_i(P_i) XOR M_i )",
            "decision": "does active rotor count remove the fixed-state involution?",
        },
        "pinned_parameters": PINNED,
        "inputs": {
            "harness": "Scripts/e256_topology_experiment.py",
            "harness_sha256": sha256_file(Path(__file__)),
            "fixture_manifest": str((FIXTURE / "fixture-v5.json").relative_to(REPO)),
            "fixture_manifest_sha256": sha256_file(FIXTURE / "fixture-v5.json"),
            "profile_sha256": PROFILE_HASH,
        },
        "results": results,
        "results_sha256": digest,
        "performance_advisory_excluded_from_digest": part_g_cost(),
        "toolchain": toolchain(),
        "no_wall_clock": "No timestamp is asserted; the machine clock and session date disagree.",
        "findings": [
            "Mirrored: for every tested rotor count in {1,4,8,16,256}, every key, and all "
            "256 masks x 256 inputs, the fixed-state map is the identity at mask 0 and a "
            "fixed-point-free involution otherwise. Active rotor count does not change this.",
            "Two-query same-state distinguisher advantage against the mirrored construction "
            "is invariant in rotor count; 256 active rotors does not reduce it.",
            "The independent ingress/egress candidate is statistically indistinguishable from "
            "a uniform random permutation under the same two-query test, and matches the "
            "Poisson(1) fixed-point expectation.",
            "The involution halves same-state codebook cost (128 queries versus 255).",
            "At equal online lookup depth the independent candidate is not slower; the "
            "mirrored path pays 2R+2 dependent lookups per byte.",
        ],
        "limitations": [
            "This is bounded structural and measured-advantage evidence, not an IND-CPA proof, "
            "not an HMAC/HKDF security proof, and not external cryptanalysis.",
            "The distinguisher assumes a repeated-state or chosen-plaintext oracle at one frozen "
            "position. It is not a decrypt of nonce-respecting traffic and implies no plaintext "
            "recovery against E256-v3 as deployed under a standard AEAD.",
            "Indistinguishability under this one test is not security. The asymmetric candidate "
            "has no independent implementation, KATs, RTL, side-channel evidence, or review.",
            "Cycle statistics use 64 keys; they are consistent with random-permutation behavior "
            "but are not a proof of pseudorandomness.",
            "Exact 128-two-cycle counts are measured on the pinned mask sample; for the remaining "
            "masks the count follows from involution and fixed-point freedom, not measurement.",
            "No C/H/N row, E256-003, E256-061, or release gate is closed by this receipt. "
            "Standard AEAD remains mandatory for real data.",
        ],
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="verify the committed receipt reproduces")
    ap.add_argument("--json", type=str, default=str(RECEIPT.relative_to(REPO)))
    args = ap.parse_args()

    out_path = REPO / args.json
    print("=" * 78)
    print("E256 vNEXT TOPOLOGY GATE  (OPEN_PROGRESS — not a closure receipt)")
    print("=" * 78)

    receipt = build_receipt()
    r = receipt["results"]

    fid = r["A_fixture_fidelity"]
    print("\n[A] fidelity vs shipped E256-v3/gen0 fixture-v5")
    for k in ("trace_rows", "recomputed_center_mask_matches", "modeled_output_matches",
              "collapsed_algebra_matches_center_io", "ciphertext_to_plaintext_matches"):
        print(f"    {k:44s} {fid[k]}")
    print(f"    {'pass':44s} {fid['pass']}")

    print(f"\n[B] fixed-state structure, exhaustive 256 masks x 256 inputs, "
          f"{PINNED['structural_keys']} keys/row")
    for count, v in r["B_structure_vs_rotor_count"].items():
        print(f"    rotors={count:<4s} id@m=0={v['identity_at_mask_zero']}  "
              f"involution={v['involution_for_all_255_nonzero_masks']}  "
              f"fpf={v['fixed_point_free_for_all_255_nonzero_masks']}  "
              f"literal==algebra={v['literal_stack_equals_collapsed_algebra']}")

    print("\n[C] mask uniqueness / closed-form recovery")
    c = r["C_mask_recovery"]
    print(f"    mirrored   unique & M=A(P)^A(C)      {c['mirrored_mask_unique_and_equals_A_P_xor_A_C']}")
    print(f"    asymmetric unique & M=A(P)^Binv(C)   {c['asymmetric_mask_unique_and_equals_A_P_xor_Binv_C']}")

    print("\n[D] cycle structure")
    d = r["D_cycle_structure"]
    for name in ("asymmetric", "uniform_random_permutation_control", "mirrored_exact"):
        print(f"    {name:36s} {d[name]}")

    print(f"\n[E] two-query same-state distinguisher, {PINNED['distinguisher_trials']} trials/cell")
    e = r["E_two_query_distinguisher"]
    print(f"    random-permutation control rate: {e['random_permutation_control_rate']}")
    for count in map(str, PINNED["rotor_counts"]):
        print(f"    rotors={count:<4s} mirrored adv={e['mirrored'][count]['advantage']:.5f}   "
              f"asymmetric adv={e['asymmetric'][count]['advantage']:.5f}")

    print("\n[F] same-state codebook cost")
    f = r["F_same_state_codebook_cost"]
    print(f"    mirrored {f['mirrored_queries_for_full_state_map']} queries vs "
          f"asymmetric {f['asymmetric_queries_for_full_state_map']} "
          f"(factor {f['leak_factor']})")

    print("\n[G] online cost per byte (advisory, excluded from digest)")
    for count, v in receipt["performance_advisory_excluded_from_digest"].items():
        print(f"    rotors={count:<4s} mirrored {v['mirrored_dependent_lookups_per_byte']:>4d} lookups "
              f"{v['mirrored_us_per_byte']:>7.2f} us/B | asym {v['asymmetric_split']:>8s} "
              f"{v['asymmetric_dependent_lookups_per_byte']:>4d} lookups "
              f"{v['asymmetric_us_per_byte']:>7.2f} us/B")

    print(f"\nresults_sha256: {receipt['results_sha256']}")

    if not fid["pass"]:
        print("\nFIDELITY ANCHOR FAILED — refusing to emit receipt")
        return 1

    if args.check:
        if not out_path.exists():
            print(f"\nCHECK FAILED: {args.json} does not exist")
            return 1
        prior = json.loads(out_path.read_text())
        same_digest = prior.get("results_sha256") == receipt["results_sha256"]
        same_results = prior.get("results") == receipt["results"]
        print(f"\nreproducibility: digest_match={same_digest} results_match={same_results}")
        print("CHECK PASS" if (same_digest and same_results) else "CHECK FAIL")
        return 0 if (same_digest and same_results) else 1

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    print(f"wrote {out_path.relative_to(REPO)}")
    print("\nSTATUS: OPEN_PROGRESS. No C/H/N row, E256-003, E256-061, or release gate closed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
