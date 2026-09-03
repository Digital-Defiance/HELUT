#!/usr/bin/env python3
"""Run immutable, profile-bound E256 TensorLUT controls and bounded test arms."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
PROFILE_PATH = ROOT / "Fixtures/enigma256_generation.json"
RUN_ID_RE = re.compile(r"^[A-Za-z0-9._-]+$")

CONTROL_MATRIX = (
    ("control-planted-a", "planted-easy", 16, 8, 8, 0.0, 0xE25621),
    ("control-planted-b", "planted-easy", 16, 8, 8, 0.0, 0xC0FFEE),
    ("control-null-a", "contradictory-null", 16, 8, 8, 0.0, 0xE25621),
    ("control-null-b", "contradictory-null", 16, 8, 8, 0.0, 0xC0FFEE),
)

# The wider scramble fragment is cheap per generation but needs more mutation
# opportunities for both fixed seeds to recover its planted width-2 output LUT.
SCRAMBLE_CONTROL_MATRIX = (
    ("control-planted-a", "planted-easy", 64, 16, 16, 0.0, 0xE25621),
    ("control-planted-b", "planted-easy", 64, 16, 16, 0.0, 0xC0FFEE),
    ("control-null-a", "contradictory-null", 64, 16, 16, 0.0, 0xE25621),
    ("control-null-b", "contradictory-null", 64, 16, 16, 0.0, 0xC0FFEE),
)

CURRENT_MATRIX = (
    ("hard0", "current", 240, 64, 160, 0.0, 0xE25621),
    ("seedA", "current", 200, 48, 120, 0.0, 0xC0FFEE),
    ("seedB", "current", 200, 48, 120, 0.0, 0xBADC0DE),
    ("lam1", "current", 160, 48, 120, 1.0, 0xE25631),
    ("lam3", "current", 160, 48, 120, 3.0, 0xE25633),
    ("longex", "current", 320, 48, 80, 0.0, 0xE25641),
    ("fatpop", "current", 120, 96, 100, 0.0, 0xE25651),
)

# A checkpoint-sized matrix for bounded local receipts. It preserves the same
# seed/lambda/population dimensions while keeping the 786,425-row NLFF run finite.
BOUNDED_CURRENT_MATRIX = (
    ("hard0", "current", 48, 24, 24, 0.0, 0xE25621),
    ("seedA", "current", 40, 16, 20, 0.0, 0xC0FFEE),
    ("seedB", "current", 40, 16, 20, 0.0, 0xBADC0DE),
    ("lam1", "current", 32, 16, 16, 1.0, 0xE25631),
    ("lam3", "current", 32, 16, 16, 3.0, 0xE25633),
    ("longex", "current", 64, 16, 16, 0.0, 0xE25641),
    ("fatpop", "current", 24, 32, 16, 0.0, 0xE25651),
)

CONE_CONFIG = {
    "nlff": {
        "scratch_netlist": ROOT / "build/enigma_256_nlff_combo_netlist.json",
        "artifact_stem": "enigma_256_tensorlut",
    },
    "scramble-frag": {
        "scratch_netlist": ROOT / "build/enigma_256_scramble_frag_combo_netlist.json",
        "artifact_stem": "enigma_256_scramble_frag_tensorlut",
    },
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def command_text(args: list[str]) -> str:
    return " ".join(subprocess.list2cmdline([part]) for part in args)


def capture(args: list[str], *, check: bool = True) -> str:
    process = subprocess.run(
        args,
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if check and process.returncode != 0:
        raise RuntimeError(
            f"command failed ({process.returncode}): {command_text(args)}\n{process.stdout}"
        )
    return process.stdout.strip()


def parse_report(path: Path) -> dict[str, str]:
    fields: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        if raw.startswith("#") or ":" not in raw:
            continue
        key, value = raw.split(":", 1)
        fields[key.strip()] = value.strip()
    return fields


def require_field(fields: dict[str, str], key: str, expected: str) -> None:
    actual = fields.get(key)
    if actual != expected:
        raise RuntimeError(f"report field {key!r}: expected {expected!r}, got {actual!r}")


def as_bool(value: str) -> bool:
    if value == "true":
        return True
    if value == "false":
        return False
    raise ValueError(f"not a report boolean: {value!r}")


def finite_float(fields: dict[str, str], key: str) -> float:
    try:
        value = float(fields[key])
    except (KeyError, ValueError) as exc:
        raise RuntimeError(f"report field {key!r} is not numeric") from exc
    if not math.isfinite(value):
        raise RuntimeError(f"report field {key!r} is not finite: {value!r}")
    return value


def nonnegative_int(fields: dict[str, str], key: str) -> int:
    try:
        value = int(fields[key])
    except (KeyError, ValueError) as exc:
        raise RuntimeError(f"report field {key!r} is not an integer") from exc
    if value < 0:
        raise RuntimeError(f"report field {key!r} is negative: {value}")
    return value


def append_jsonl(path: Path, row: dict[str, Any]) -> None:
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(row, sort_keys=True, separators=(",", ":")) + "\n")


def write_json_new(path: Path, value: Any) -> None:
    with path.open("x", encoding="utf-8") as handle:
        json.dump(value, handle, indent=2, sort_keys=True)
        handle.write("\n")


def profile_metadata() -> tuple[dict[str, Any], str, str]:
    profile = json.loads(PROFILE_PATH.read_text(encoding="utf-8"))
    suite = int(profile["suite_version"])
    generation = int(profile["generation"])
    schema = int(profile["fixture_schema_version"])
    profile_hash = str(profile["profile_sha256"])
    tag = f"v{suite}-gen{generation}-fixture{schema}-{profile_hash[:12]}"
    compatibility = f"E256/v{suite}/gen{generation}/{profile_hash}/fixture-v{schema}"
    return profile, tag, compatibility


def source_snapshot() -> tuple[list[dict[str, str]], str]:
    paths = [ROOT / "Package.swift"]
    resolved = ROOT / "Package.resolved"
    if resolved.is_file():
        paths.append(resolved)
    paths.extend(path for path in sorted((ROOT / "Sources").rglob("*")) if path.is_file())
    entries = [
        {"path": str(path.relative_to(ROOT)), "sha256": sha256(path)}
        for path in paths
    ]
    digest = hashlib.sha256()
    for entry in entries:
        digest.update(entry["path"].encode())
        digest.update(b"\0")
        digest.update(entry["sha256"].encode())
        digest.update(b"\n")
    return entries, digest.hexdigest()


def archive_receipt_inputs(run_dir: Path, source_entries: list[dict[str, str]]) -> dict[str, Any]:
    """Archive exact build and orchestration bytes, including untracked inputs."""
    extra_paths = (
        PROFILE_PATH,
        Path(__file__).resolve(),
        ROOT / "Scripts/enigma256_red_battery.sh",
        ROOT / "Scripts/enigma256_scramble_frag_battery.sh",
        ROOT / "Scripts/enigma256_tensorlut_synth.sh",
        ROOT / "Hardware/RTL/Enigma256/enigma_256_step_cone.v",
        ROOT / "Hardware/RTL/Enigma256/enigma_256_nlff_combo.v",
        ROOT / "Hardware/RTL/Enigma256/enigma_256_nlff_lfsr_combo.v",
        ROOT / "Hardware/RTL/Enigma256/enigma_256_nlff_offset_combo.v",
        ROOT / "Hardware/RTL/Enigma256/enigma_256_scramble_frag_combo.v",
        ROOT / "Generated/Profiles/Enigma256/enigma_256_nlff_v2.vh",
    )
    expected = {entry["path"]: entry["sha256"] for entry in source_entries}
    for path in extra_paths:
        if not path.is_file():
            raise RuntimeError(f"receipt input is missing: {path}")
        expected[str(path.relative_to(ROOT))] = sha256(path)

    archive_root = run_dir / "input-archive"
    archive_root.mkdir()
    archived: list[dict[str, Any]] = []
    aggregate = hashlib.sha256()
    for relative, expected_hash in sorted(expected.items()):
        source = ROOT / relative
        data = source.read_bytes()
        actual_hash = hashlib.sha256(data).hexdigest()
        if actual_hash != expected_hash:
            raise RuntimeError(f"receipt input changed while it was being archived: {relative}")
        destination = archive_root / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        with destination.open("xb") as output:
            output.write(data)
        mode = source.stat().st_mode & 0o777
        destination.chmod(mode)
        if sha256(destination) != expected_hash:
            raise RuntimeError(f"archived receipt input hash mismatch: {relative}")
        aggregate.update(relative.encode())
        aggregate.update(b"\0")
        aggregate.update(expected_hash.encode())
        aggregate.update(b"\n")
        archived.append(
            {
                "path": relative,
                "archived_path": str(destination.relative_to(ROOT)),
                "sha256": expected_hash,
                "mode": f"{mode:04o}",
            }
        )

    archive_manifest = run_dir / "input-archive.json"
    write_json_new(
        archive_manifest,
        {
            "schema": 1,
            "aggregate_sha256": aggregate.hexdigest(),
            "file_count": len(archived),
            "files": archived,
        },
    )
    return {
        "input_archive": str(archive_root.relative_to(ROOT)),
        "input_archive_manifest": str(archive_manifest.relative_to(ROOT)),
        "input_archive_manifest_sha256": sha256(archive_manifest),
        "input_archive_aggregate_sha256": aggregate.hexdigest(),
        "input_archive_file_count": len(archived),
    }


def build_and_pin_binary(run_dir: Path) -> tuple[Path, dict[str, Any]]:
    if "HELUT_BIN" in os.environ:
        raise RuntimeError("HELUT_BIN is not accepted for receipt runs; the runner builds and pins current sources")

    before_entries, before_digest = source_snapshot()
    archive_provenance = archive_receipt_inputs(run_dir, before_entries)
    build_log = run_dir / "build.console.txt"
    with build_log.open("x", encoding="utf-8") as output:
        process = subprocess.run(
            ["swift", "build", "-c", "release", "--product", "helut"],
            cwd=ROOT,
            text=True,
            stdout=output,
            stderr=subprocess.STDOUT,
            check=False,
        )
    if process.returncode != 0:
        raise RuntimeError(f"HELUT build failed; inspect {build_log}")
    after_entries, after_digest = source_snapshot()
    if before_digest != after_digest or before_entries != after_entries:
        raise RuntimeError("HELUT source inputs changed while the receipt binary was building")

    built = ROOT / ".build/release/helut"
    if not built.is_file() or not os.access(built, os.X_OK):
        raise RuntimeError(f"built HELUT binary is not executable: {built}")
    pinned = run_dir / "helut"
    shutil.copy2(built, pinned)
    if not os.access(pinned, os.X_OK):
        raise RuntimeError(f"pinned HELUT binary is not executable: {pinned}")

    snapshot_path = run_dir / "source-snapshot.json"
    write_json_new(
        snapshot_path,
        {"schema": 1, "aggregate_sha256": after_digest, "files": after_entries},
    )
    patch = subprocess.run(
        ["git", "diff", "--binary", "HEAD", "--", "Package.swift", "Package.resolved", "Sources"],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if patch.returncode != 0:
        raise RuntimeError(f"failed to capture source patch: {patch.stderr.decode(errors='replace')}")
    patch_path = run_dir / "source.patch"
    with patch_path.open("xb") as output:
        output.write(patch.stdout)

    return pinned, {
        "build_log": str(build_log.relative_to(ROOT)),
        "build_log_sha256": sha256(build_log),
        "source_snapshot": str(snapshot_path.relative_to(ROOT)),
        "source_snapshot_sha256": sha256(snapshot_path),
        "source_inputs_sha256": after_digest,
        "source_patch": str(patch_path.relative_to(ROOT)),
        "source_patch_sha256": sha256(patch_path),
        **archive_provenance,
    }


def make_manifest(
    *,
    args: argparse.Namespace,
    run_id: str,
    run_dir: Path,
    profile: dict[str, Any],
    profile_tag: str,
    compatibility: str,
    binary: Path,
    binary_provenance: dict[str, Any],
    netlist: Path,
    matrix: tuple[tuple[str, str, int, int, int, float, int], ...],
) -> dict[str, Any]:
    git_status = capture(["git", "status", "--porcelain"], check=False)
    return {
        "schema": 1,
        "run_id": run_id,
        "created_utc": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
        "cone": args.cone,
        "scope": "bounded TensorLUT optimizer run; in-sample only; not a security claim or work factor",
        "controls_only": args.controls_only,
        "budget_profile": args.budget_profile,
        "profile_tag": profile_tag,
        "compatibility_key": compatibility,
        "profile_sha256": profile["profile_sha256"],
        "fixture_schema_version": profile["fixture_schema_version"],
        "receipt_sha256": profile["receipt_sha256"],
        "profile_fixture": str(PROFILE_PATH.relative_to(ROOT)),
        "profile_fixture_sha256": sha256(PROFILE_PATH),
        "source_netlist": str(netlist.relative_to(ROOT)),
        "source_netlist_sha256": sha256(netlist),
        "helut_binary": str(binary.relative_to(ROOT)),
        "helut_binary_sha256": sha256(binary),
        "binary_provenance": binary_provenance,
        "runner": str(Path(__file__).resolve().relative_to(ROOT)),
        "runner_sha256": sha256(Path(__file__).resolve()),
        "nlff_wrapper_sha256": sha256(ROOT / "Scripts/enigma256_red_battery.sh"),
        "scramble_wrapper_sha256": sha256(ROOT / "Scripts/enigma256_scramble_frag_battery.sh"),
        "yosys_version": capture(["yosys", "-V"]),
        "swift_version": capture(["swift", "--version"]).splitlines()[0],
        "macos_version": capture(["sw_vers", "-productVersion"]),
        "git_head": capture(["git", "rev-parse", "HEAD"]),
        "git_dirty": bool(git_status),
        "git_status_sha256": hashlib.sha256(git_status.encode()).hexdigest(),
        "run_directory": str(run_dir.relative_to(ROOT)),
        "matrix": [
            {
                "name": name,
                "role": role,
                "explore_gens": gens,
                "population": pop,
                "polish_gens": polish,
                "polish_lambda": lam,
                "seed": seed,
            }
            for name, role, gens, pop, polish, lam, seed in matrix
        ],
    }


def run_arm(
    *,
    cone: str,
    run_dir: Path,
    binary: Path,
    binary_sha256: str,
    netlist: Path,
    profile: dict[str, Any],
    compatibility: str,
    ledger: Path,
    name: str,
    role: str,
    gens: int,
    pop: int,
    polish: int,
    lam: float,
    seed: int,
) -> dict[str, Any]:
    if sha256(binary) != binary_sha256:
        raise RuntimeError("pinned HELUT binary changed before an arm")
    report = run_dir / f"{name}.report.txt"
    console = run_dir / f"{name}.console.txt"
    emitted = run_dir / f"{name}.baseline.v"
    for output in (report, console, emitted):
        if output.exists():
            raise RuntimeError(f"refusing to overwrite run artifact: {output}")

    command = [
        str(binary),
        "--enigma256-tensorlut",
        "--enigma256-tensorlut-role",
        role,
        "--enigma256-netlist",
        str(netlist),
        "--enigma256-emit-out",
        str(emitted),
        "--enigma256-tensorlut-log",
        str(report),
        "--enigma256-tensorlut-gens",
        str(gens),
        "--enigma256-tensorlut-pop",
        str(pop),
        "--enigma256-tensorlut-polish",
        str(polish),
        "--enigma256-tensorlut-lambda",
        str(lam),
        "--enigma256-tensorlut-seed",
        str(seed),
    ]
    if role == "current":
        command.append("--enigma256-tensorlut-expect-hold")

    print(
        f"[{cone}] {name}: role={role} gens={gens} pop={pop} "
        f"polish={polish} lambda={lam:g} seed={seed}",
        flush=True,
    )
    started = time.monotonic()
    with console.open("x", encoding="utf-8") as output:
        process = subprocess.run(
            command,
            cwd=ROOT,
            text=True,
            stdout=output,
            stderr=subprocess.STDOUT,
            check=False,
        )
    elapsed = time.monotonic() - started

    if sha256(binary) != binary_sha256:
        row = {
            "name": name,
            "role": role,
            "rc": process.returncode,
            "elapsed_seconds": elapsed,
            "error": "pinned HELUT binary changed during the arm",
            "console": str(console.relative_to(ROOT)),
            "command": command,
        }
        append_jsonl(ledger, row)
        raise RuntimeError(f"{name}: pinned HELUT binary changed during execution")

    if not report.is_file() or not emitted.is_file():
        row = {
            "name": name,
            "role": role,
            "rc": process.returncode,
            "elapsed_seconds": elapsed,
            "error": "missing report or emitted baseline",
            "console": str(console.relative_to(ROOT)),
            "command": command,
        }
        append_jsonl(ledger, row)
        raise RuntimeError(f"{name}: tool did not produce its report and baseline")

    fields = parse_report(report)
    source_hash = sha256(netlist)
    require_field(fields, "family", "E256")
    require_field(fields, "suite_version", str(profile["suite_version"]))
    require_field(fields, "generation", str(profile["generation"]))
    require_field(fields, "fixture_schema_version", str(profile["fixture_schema_version"]))
    require_field(fields, "profile_sha256", str(profile["profile_sha256"]))
    require_field(fields, "receipt_sha256", str(profile["receipt_sha256"]))
    require_field(fields, "run_role", role)
    require_field(fields, "target_scope", "in_sample_only_no_holdout")
    require_field(fields, "source_netlist_sha256", source_hash)
    require_field(fields, "explore_gens", str(gens))
    require_field(fields, "polish_gens", str(polish))
    require_field(fields, "pop", str(pop))
    require_field(fields, "explore_seed", str(seed))
    require_field(
        fields,
        "objective",
        "negative_sum_squared_output_error; perfect=0; threshold final_crypto>-0.05 and melt_nonbinary=0",
    )
    reported_lambda = finite_float(fields, "polish_lambda")
    if abs(reported_lambda - lam) > 1e-9:
        raise RuntimeError(f"report polish_lambda: expected {lam}, got {reported_lambda}")

    baseline_crypto = finite_float(fields, "baseline_crypto")
    baseline_expected = finite_float(fields, "baseline_expected_crypto")
    expected_baseline = -1.0 if role == "contradictory-null" else 0.0
    if abs(baseline_expected - expected_baseline) > 1e-6:
        raise RuntimeError(
            f"report baseline_expected_crypto: expected {expected_baseline}, got {baseline_expected}"
        )
    baseline_sanity = abs(baseline_crypto - expected_baseline) <= 1e-6
    if as_bool(fields["baseline_sanity_pass"]) != baseline_sanity or not baseline_sanity:
        raise RuntimeError("baseline sanity is false or inconsistent with the reported score")

    contradictory_rows = nonnegative_int(fields, "contradictory_rows")
    expected_contradictions = 1 if role == "contradictory-null" else 0
    if contradictory_rows != expected_contradictions:
        raise RuntimeError(
            f"report contradictory_rows: expected {expected_contradictions}, got {contradictory_rows}"
        )

    final_crypto = finite_float(fields, "final_crypto")
    final_nonbinary = nonnegative_int(fields, "final_nonbinary")
    squeeze = final_crypto > -0.05 and final_nonbinary == 0
    reported_squeeze = as_bool(fields["squeeze_survived"])
    if reported_squeeze != squeeze:
        raise RuntimeError("squeeze_survived is inconsistent with final_crypto/final_nonbinary")
    verdict = fields["verdict"]
    expected_verdict = "red_pressure" if squeeze else "blue_hold"
    if verdict != expected_verdict:
        raise RuntimeError(f"verdict: expected {expected_verdict}, got {verdict}")

    control_pass: bool | None
    planted_seed_crypto_value: float | None = None
    planted_seed_nonbinary_value: int | None = None
    planted_canonical_entry_value: float | None = None
    planted_final_entry_value: float | None = None
    planted_recovery_abs_error: float | None = None
    planted_exact_recovery_value: bool | None = None
    expected_outcome: str
    outcome_ok: bool
    if role == "planted-easy":
        require_field(fields, "planted_mutable_lut_count", "1")
        planted_seed_crypto_value = finite_float(fields, "planted_seed_crypto")
        planted_seed_nonbinary_value = nonnegative_int(fields, "planted_seed_nonbinary")
        planted_seed_defect = (
            planted_seed_crypto_value <= -0.05 and planted_seed_nonbinary_value == 1
        )
        if as_bool(fields["planted_seed_defect_pass"]) != planted_seed_defect or not planted_seed_defect:
            raise RuntimeError("planted seed is not a live one-entry defect")
        planted_canonical_entry_value = finite_float(fields, "planted_canonical_entry")
        planted_final_entry_value = finite_float(fields, "planted_final_entry")
        planted_recovery_abs_error = abs(
            planted_final_entry_value - planted_canonical_entry_value
        )
        planted_exact_recovery_value = planted_recovery_abs_error <= 1e-6
        if as_bool(fields["planted_exact_recovery"]) != planted_exact_recovery_value:
            raise RuntimeError(
                "planted_exact_recovery is inconsistent with the raw canonical/final entry values"
            )
        derived_control_pass = (
            baseline_sanity
            and planted_seed_defect
            and squeeze
            and planted_exact_recovery_value
        )
        control_pass = as_bool(fields["control_pass"])
        if control_pass != derived_control_pass:
            raise RuntimeError("planted control_pass is inconsistent with independently parsed metrics")
        expected_outcome = "live planted defect, exact recovery, red_pressure, rc=0"
        outcome_ok = derived_control_pass and process.returncode == 0
    elif role == "contradictory-null":
        require_field(fields, "planted_mutable_lut_count", "0")
        require_field(fields, "planted_canonical_entry", "n/a")
        require_field(fields, "planted_final_entry", "n/a")
        derived_control_pass = baseline_sanity and not squeeze
        control_pass = as_bool(fields["control_pass"])
        if control_pass != derived_control_pass:
            raise RuntimeError("null control_pass is inconsistent with independently parsed metrics")
        expected_outcome = "no-false-positive plumbing control: blue_hold, rc=0"
        outcome_ok = derived_control_pass and process.returncode == 0
    else:
        require_field(fields, "planted_mutable_lut_count", "0")
        require_field(fields, "planted_canonical_entry", "n/a")
        require_field(fields, "planted_final_entry", "n/a")
        require_field(fields, "control_pass", "n/a")
        control_pass = None
        expected_outcome = "blue_hold with rc=0; red_pressure is preserved with rc=2 and stops the battery"
        outcome_ok = not squeeze and process.returncode == 0
        if squeeze and process.returncode == 2:
            outcome_ok = False

    row: dict[str, Any] = {
        "ts": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
        "compatibility_key": compatibility,
        "cone": cone,
        "name": name,
        "role": role,
        "gens": gens,
        "pop": pop,
        "polish": polish,
        "lambda": lam,
        "seed": seed,
        "baseline_crypto": baseline_crypto,
        "baseline_expected_crypto": expected_baseline,
        "baseline_sanity_pass": baseline_sanity,
        "contradictory_rows": contradictory_rows,
        "final_crypto": final_crypto,
        "final_nonbinary": final_nonbinary,
        "squeeze_survived": squeeze,
        "verdict": verdict,
        "control_pass": control_pass,
        "planted_seed_crypto": planted_seed_crypto_value,
        "planted_seed_nonbinary": planted_seed_nonbinary_value,
        "planted_canonical_entry": planted_canonical_entry_value,
        "planted_final_entry": planted_final_entry_value,
        "planted_recovery_abs_error": planted_recovery_abs_error,
        "planted_exact_recovery": planted_exact_recovery_value,
        "expected_outcome": expected_outcome,
        "outcome_ok": outcome_ok,
        "rc": process.returncode,
        "elapsed_seconds": elapsed,
        "source_netlist_sha256": source_hash,
        "helut_binary_sha256": binary_sha256,
        "report": str(report.relative_to(ROOT)),
        "report_sha256": sha256(report),
        "console": str(console.relative_to(ROOT)),
        "console_sha256": sha256(console),
        "emitted_baseline": str(emitted.relative_to(ROOT)),
        "emitted_baseline_sha256": sha256(emitted),
        "command": command,
    }
    append_jsonl(ledger, row)
    print(
        f"[{cone}] {name}: verdict={verdict} final_crypto={row['final_crypto']:.6f} "
        f"nonbinary={row['final_nonbinary']} rc={process.returncode} "
        f"outcome_ok={outcome_ok} ({elapsed:.1f}s)",
        flush=True,
    )
    if not outcome_ok:
        raise RuntimeError(f"{name}: preregistered outcome failed; inspect {report}")
    return row


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cone", choices=tuple(CONE_CONFIG), required=True)
    parser.add_argument("--run-id")
    parser.add_argument("--controls-only", action="store_true")
    parser.add_argument("--budget-profile", choices=("full", "bounded"), default="full")
    args = parser.parse_args()

    profile, profile_tag, compatibility = profile_metadata()
    default_run_id = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ") + f"-{os.getpid()}"
    run_id = args.run_id or os.environ.get("RUN_ID") or default_run_id
    if not RUN_ID_RE.fullmatch(run_id):
        raise RuntimeError("run ID may contain only letters, digits, dot, underscore, and dash")
    if run_id in {".", ".."}:
        raise RuntimeError("run ID must not be a dot path component")

    profile_root = (ROOT / "logs/e256-red-runs" / profile_tag).resolve()
    run_dir = profile_root / run_id / args.cone
    resolved_run_dir = run_dir.resolve()
    if profile_root not in resolved_run_dir.parents:
        raise RuntimeError("resolved run directory escapes the profile namespace")
    run_dir = resolved_run_dir
    if run_dir.exists():
        raise RuntimeError(f"refusing to reuse run directory: {run_dir}")
    run_dir.mkdir(parents=True)

    synthesis_log = run_dir / "synthesis.console.txt"
    with synthesis_log.open("x", encoding="utf-8") as output:
        synthesis = subprocess.run(
            [str(ROOT / "Scripts/enigma256_tensorlut_synth.sh")],
            cwd=ROOT,
            text=True,
            stdout=output,
            stderr=subprocess.STDOUT,
            check=False,
        )
    if synthesis.returncode != 0:
        raise RuntimeError(f"TensorLUT synthesis failed; inspect {synthesis_log}")

    config = CONE_CONFIG[args.cone]
    scratch_netlist: Path = config["scratch_netlist"]
    if not scratch_netlist.is_file():
        raise RuntimeError(f"synthesis did not produce {scratch_netlist}")
    netlist = run_dir / "source-netlist.json"
    shutil.copy2(scratch_netlist, netlist)

    binary, binary_provenance = build_and_pin_binary(run_dir)
    binary_hash = sha256(binary)
    controls = SCRAMBLE_CONTROL_MATRIX if args.cone == "scramble-frag" else CONTROL_MATRIX
    current = BOUNDED_CURRENT_MATRIX if args.budget_profile == "bounded" else CURRENT_MATRIX
    matrix = controls if args.controls_only else controls + current
    manifest = make_manifest(
        args=args,
        run_id=run_id,
        run_dir=run_dir,
        profile=profile,
        profile_tag=profile_tag,
        compatibility=compatibility,
        binary=binary,
        binary_provenance=binary_provenance,
        netlist=netlist,
        matrix=matrix,
    )
    manifest["synthesis_log"] = str(synthesis_log.relative_to(ROOT))
    manifest["synthesis_log_sha256"] = sha256(synthesis_log)
    write_json_new(run_dir / "manifest.json", manifest)

    ledger = run_dir / "results.jsonl"
    rows: list[dict[str, Any]] = []
    status = "running"
    error: str | None = None
    try:
        for name, role, gens, pop, polish, lam, seed in matrix:
            rows.append(
                run_arm(
                    cone=args.cone,
                    run_dir=run_dir,
                    binary=binary,
                    binary_sha256=binary_hash,
                    netlist=netlist,
                    profile=profile,
                    compatibility=compatibility,
                    ledger=ledger,
                    name=name,
                    role=role,
                    gens=gens,
                    pop=pop,
                    polish=polish,
                    lam=lam,
                    seed=seed,
                )
            )
    except BaseException as exc:
        status = "interrupted" if isinstance(exc, KeyboardInterrupt) else "failed"
        error = f"{type(exc).__name__}: {exc}"
        raise
    else:
        status = "pass"
    finally:
        receipt_rows = (
            [json.loads(line) for line in ledger.read_text(encoding="utf-8").splitlines()]
            if ledger.exists()
            else []
        )
        complete = len(receipt_rows) == len(matrix) and all(
            row.get("outcome_ok") is True for row in receipt_rows
        )
        if status == "pass" and not complete:
            status = "failed"
            error = "receipt row set is incomplete or contains a failed outcome"
        summary = {
            "schema": 1,
            "status": status,
            "error": error,
            "scope": "bounded TensorLUT optimizer outcomes; in-sample only; not security evidence",
            "run_id": run_id,
            "cone": args.cone,
            "budget_profile": args.budget_profile,
            "compatibility_key": compatibility,
            "completed_rows": len(receipt_rows),
            "expected_rows": len(matrix),
            "complete": complete,
            "controls_passed": sum(row.get("control_pass") is True for row in receipt_rows),
            "current_blue_holds": sum(
                row.get("role") == "current" and row.get("verdict") == "blue_hold"
                for row in receipt_rows
            ),
            "current_red_pressure": sum(
                row.get("role") == "current" and row.get("verdict") == "red_pressure"
                for row in receipt_rows
            ),
            "rows": receipt_rows,
        }
        write_json_new(run_dir / "summary.json", summary)

    print(f"[{args.cone}] battery complete: {run_dir.relative_to(ROOT)}", flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("E256 TensorLUT battery interrupted", file=sys.stderr)
        raise SystemExit(130)
    except Exception as exc:
        print(f"E256 TensorLUT battery failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
