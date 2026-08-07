#!/usr/bin/env python3
"""Synchronize HELUT's manifest-declared hardware compatibility copies.

Canonical generated artifacts live under ``Generated/``. Legacy root files remain
checked-in compatibility copies because published commands and downstream tools
still consume those names. This tool is the only bulk copy mechanism between the
two layouts:

* ``--bootstrap`` copies planned generated artifacts from their current legacy
  locations to previously absent canonical paths. It refuses conflicting files.
* ``--sync`` copies canonical artifacts to their declared legacy paths and keeps
  compatibility aliases equal to their source artifacts.
* ``--check`` (the default) is read-only and fails on any drift.

There is deliberately no general legacy-to-canonical update mode after migration.
Generators write disposable outputs under ``build/``; reviewed outputs are promoted
explicitly into ``Generated/`` before compatibility copies flow outward.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any, Iterable


REPO_ROOT = Path(__file__).resolve().parent.parent
MANIFEST_PATH = REPO_ROOT / "Hardware" / "artifact-manifest.json"
VALIDATOR_PATH = REPO_ROOT / "Scripts" / "validate_hardware_manifest.py"
EXPECTED_SCHEMA = "helut.hardware-artifacts/v1"


class SyncError(RuntimeError):
    """A manifest or artifact synchronization contract was violated."""


@dataclass
class PreparedCopy:
    artifact_id: str
    source: Path
    destination: Path
    replacement: Path | None
    backup: Path | None
    destination_existed: bool


def validate_manifest_for_mutation() -> None:
    """Run the complete structural contract before any compatibility write."""
    result = subprocess.run(
        [sys.executable, str(VALIDATOR_PATH), "--allow-copy-drift"],
        cwd=REPO_ROOT,
        check=False,
    )
    if result.returncode != 0:
        raise SyncError("manifest structural validation failed before mutation")


def repository_path(value: Any, field: str, artifact_id: str) -> Path:
    if not isinstance(value, str) or not value:
        raise SyncError(f"{artifact_id}: {field} must be a non-empty string")
    relative = PurePosixPath(value)
    if relative.is_absolute() or ".." in relative.parts:
        raise SyncError(
            f"{artifact_id}: {field} must be repository-relative without '..': {value}"
        )
    return REPO_ROOT / Path(relative)


def load_manifest() -> tuple[list[dict[str, Any]], dict[str, dict[str, Any]]]:
    try:
        document = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SyncError(f"cannot read {MANIFEST_PATH.relative_to(REPO_ROOT)}: {error}")
    if document.get("schema") != EXPECTED_SCHEMA:
        raise SyncError(f"manifest schema must be {EXPECTED_SCHEMA!r}")
    artifacts = document.get("artifacts")
    if not isinstance(artifacts, list):
        raise SyncError("manifest artifacts must be an array")

    by_id: dict[str, dict[str, Any]] = {}
    parsed: list[dict[str, Any]] = []
    for index, raw in enumerate(artifacts):
        if not isinstance(raw, dict):
            raise SyncError(f"artifact #{index} must be an object")
        artifact_id = raw.get("id")
        if not isinstance(artifact_id, str) or not artifact_id:
            raise SyncError(f"artifact #{index}: id must be a non-empty string")
        if artifact_id in by_id:
            raise SyncError(f"duplicate artifact id: {artifact_id}")
        by_id[artifact_id] = raw
        parsed.append(raw)
    return parsed, by_id


def same_bytes(left: Path, right: Path) -> bool:
    if (
        left.is_symlink()
        or right.is_symlink()
        or not left.is_file()
        or not right.is_file()
    ):
        return False
    if left.stat().st_size != right.stat().st_size:
        return False
    with left.open("rb") as left_file, right.open("rb") as right_file:
        while True:
            left_chunk = left_file.read(1024 * 1024)
            right_chunk = right_file.read(1024 * 1024)
            if left_chunk != right_chunk:
                return False
            if not left_chunk:
                return True


def validate_path_topology(path: Path, label: str) -> None:
    """Reject links and non-directory ancestors below the repository root."""
    try:
        relative = path.relative_to(REPO_ROOT)
    except ValueError as error:
        raise SyncError(f"{label} escapes the repository: {path}") from error

    candidate = REPO_ROOT
    for part in relative.parts[:-1]:
        candidate /= part
        if candidate.is_symlink():
            raise SyncError(
                f"{label} traverses symlink {candidate.relative_to(REPO_ROOT)}"
            )
        if candidate.exists() and not candidate.is_dir():
            raise SyncError(
                f"{label} has non-directory ancestor {candidate.relative_to(REPO_ROOT)}"
            )
    if path.is_symlink():
        raise SyncError(f"{label} must not be a symlink: {relative}")


def preflight_copy_pairs(
    pairs: Iterable[tuple[str, Path, Path]], *, refuse_conflicting_destination: bool
) -> list[tuple[str, Path, Path]]:
    """Validate complete source/destination topology before staging any copy."""
    prepared = list(pairs)
    destinations: dict[Path, str] = {}
    source_paths = {source for _, source, _ in prepared}

    for artifact_id, source, destination in prepared:
        validate_path_topology(source, f"{artifact_id}: source")
        validate_path_topology(destination, f"{artifact_id}: destination")
        if not source.is_file():
            raise SyncError(
                f"{artifact_id}: source artifact is missing or not a file: "
                f"{source.relative_to(REPO_ROOT)}"
            )
        if source == destination:
            raise SyncError(f"{artifact_id}: source and destination are identical")
        if destination.exists() and not destination.is_file():
            raise SyncError(
                f"{artifact_id}: destination is not a file: "
                f"{destination.relative_to(REPO_ROOT)}"
            )
        if destination.is_file() and source.samefile(destination):
            raise SyncError(
                f"{artifact_id}: destination aliases the source inode: "
                f"{destination.relative_to(REPO_ROOT)}"
            )
        if (
            refuse_conflicting_destination
            and destination.is_file()
            and not same_bytes(source, destination)
        ):
            raise SyncError(
                f"{artifact_id}: refusing to overwrite conflicting bootstrap target "
                f"{destination.relative_to(REPO_ROOT)}"
            )
        previous = destinations.get(destination)
        if previous is not None:
            raise SyncError(
                f"destination {destination.relative_to(REPO_ROOT)} "
                f"is selected by both {previous} and {artifact_id}"
            )
        for prior_destination, prior_owner in destinations.items():
            if destination in prior_destination.parents or prior_destination in destination.parents:
                raise SyncError(
                    "copy destinations have an ancestor collision: "
                    f"{prior_owner}={prior_destination.relative_to(REPO_ROOT)} and "
                    f"{artifact_id}={destination.relative_to(REPO_ROOT)}"
                )
        if destination in source_paths:
            raise SyncError(
                f"{artifact_id}: destination is also a selected source: "
                f"{destination.relative_to(REPO_ROOT)}"
            )
        destinations[destination] = artifact_id
    return prepared


def temporary_copy(source: Path, destination: Path, kind: str, mode: int) -> Path:
    destination.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{destination.name}.{kind}.", suffix=".tmp", dir=destination.parent
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as output, source.open("rb") as input_file:
            shutil.copyfileobj(input_file, output, length=1024 * 1024)
            os.fchmod(output.fileno(), mode)
            output.flush()
            os.fsync(output.fileno())
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise
    return temporary


def prepare_copy_batch(
    pairs: Iterable[tuple[str, Path, Path]],
) -> list[PreparedCopy]:
    """Stage every changed output and rollback image before the first replace."""
    plans: list[PreparedCopy] = []
    try:
        for artifact_id, source, destination in pairs:
            if same_bytes(source, destination):
                plans.append(
                    PreparedCopy(artifact_id, source, destination, None, None, True)
                )
                continue

            destination_existed = destination.is_file()
            source_mode = source.stat().st_mode & 0o7777
            destination_mode = (
                destination.stat().st_mode & 0o7777
                if destination_existed
                else source_mode
            )
            backup = (
                temporary_copy(destination, destination, "backup", destination_mode)
                if destination_existed
                else None
            )
            try:
                replacement = temporary_copy(
                    source, destination, "replacement", destination_mode
                )
            except BaseException:
                if backup is not None:
                    backup.unlink(missing_ok=True)
                raise
            plans.append(
                PreparedCopy(
                    artifact_id,
                    source,
                    destination,
                    replacement,
                    backup,
                    destination_existed,
                )
            )
    except BaseException:
        for plan in plans:
            if plan.replacement is not None:
                plan.replacement.unlink(missing_ok=True)
            if plan.backup is not None:
                plan.backup.unlink(missing_ok=True)
        raise
    return plans


def commit_copy_batch(plans: list[PreparedCopy]) -> list[PreparedCopy]:
    """Commit a staged batch, restoring earlier destinations if a replace fails."""
    changed = [plan for plan in plans if plan.replacement is not None]
    applied: list[PreparedCopy] = []
    preserved_backups: set[int] = set()
    try:
        for plan in changed:
            assert plan.replacement is not None
            os.replace(plan.replacement, plan.destination)
            plan.replacement = None
            applied.append(plan)
    except BaseException as error:
        rollback_errors: list[str] = []
        for plan in reversed(applied):
            try:
                if plan.backup is not None:
                    os.replace(plan.backup, plan.destination)
                    plan.backup = None
                elif not plan.destination_existed:
                    plan.destination.unlink(missing_ok=True)
            except OSError as rollback_error:
                preserved_backups.add(id(plan))
                backup_note = f"; recovery copy {plan.backup}" if plan.backup else ""
                rollback_errors.append(
                    f"{plan.artifact_id}: {rollback_error}{backup_note}"
                )
        detail = ""
        if rollback_errors:
            detail = "; rollback errors: " + "; ".join(rollback_errors)
        raise SyncError(f"copy transaction failed: {error}{detail}") from error
    finally:
        for plan in plans:
            if plan.replacement is not None:
                plan.replacement.unlink(missing_ok=True)
            if plan.backup is not None and id(plan) not in preserved_backups:
                plan.backup.unlink(missing_ok=True)
    return changed


def selected_artifacts(
    artifacts: Iterable[dict[str, Any]], requested_ids: set[str]
) -> list[dict[str, Any]]:
    available = list(artifacts)
    known_ids = {raw["id"] for raw in available}
    missing = sorted(requested_ids - known_ids)
    if missing:
        raise SyncError("unknown artifact id(s): " + ", ".join(missing))
    if not requested_ids:
        return available

    selected_ids = set(requested_ids)
    while True:
        dependent_aliases = {
            raw["id"]
            for raw in available
            if raw.get("role") == "compatibility-alias"
            and raw.get("source_artifact") in selected_ids
        }
        expanded = selected_ids | dependent_aliases
        if expanded == selected_ids:
            break
        selected_ids = expanded
    return [raw for raw in available if raw["id"] in selected_ids]


def source_path(raw: dict[str, Any], by_id: dict[str, dict[str, Any]]) -> Path:
    artifact_id = raw["id"]
    source_id = raw.get("source_artifact")
    if not isinstance(source_id, str) or source_id not in by_id:
        raise SyncError(f"{artifact_id}: compatibility alias needs a source artifact id")
    source = by_id[source_id]
    if source.get("migration") == "canonical":
        return repository_path(source.get("canonical_path"), "canonical_path", source_id)
    return repository_path(source.get("current_path"), "current_path", source_id)


def bootstrap_pairs(
    artifacts: Iterable[dict[str, Any]],
) -> list[tuple[str, Path, Path]]:
    pairs: list[tuple[str, Path, Path]] = []
    for raw in artifacts:
        artifact_id = raw["id"]
        role = raw.get("role")
        if (
            raw.get("migration") != "planned"
            or raw.get("legacy_policy") != "retain-copy"
            or not isinstance(role, str)
            or not role.startswith("generated-")
        ):
            continue
        pairs.append(
            (
                artifact_id,
                repository_path(raw.get("current_path"), "current_path", artifact_id),
                repository_path(raw.get("canonical_path"), "canonical_path", artifact_id),
            )
        )
    if not pairs:
        raise SyncError("no planned generated retain-copy artifacts selected for bootstrap")
    return pairs


def preflight_bootstrap(
    pairs: Iterable[tuple[str, Path, Path]],
) -> list[tuple[str, Path, Path]]:
    """Validate the complete one-time bootstrap set before its first write."""
    return preflight_copy_pairs(pairs, refuse_conflicting_destination=True)


def bootstrap(artifacts: Iterable[dict[str, Any]]) -> tuple[int, int]:
    prepared = preflight_bootstrap(bootstrap_pairs(artifacts))
    plans = prepare_copy_batch(prepared)
    changed = commit_copy_batch(plans)
    for plan in changed:
        print(
            f"bootstrapped {plan.artifact_id}: {plan.source.relative_to(REPO_ROOT)} -> "
            f"{plan.destination.relative_to(REPO_ROOT)}"
        )
    return len(changed), len(plans) - len(changed)


def compatibility_pairs(
    artifacts: Iterable[dict[str, Any]], by_id: dict[str, dict[str, Any]]
) -> list[tuple[str, Path, Path]]:
    pairs: list[tuple[str, Path, Path]] = []
    for raw in artifacts:
        artifact_id = raw["id"]
        if raw.get("role") == "compatibility-alias":
            if raw.get("legacy_policy") != "retain-copy":
                continue
            pairs.append(
                (
                    artifact_id,
                    source_path(raw, by_id),
                    repository_path(raw.get("current_path"), "current_path", artifact_id),
                )
            )
            continue
        if raw.get("migration") != "canonical" or raw.get("legacy_policy") != "retain-copy":
            continue
        canonical = repository_path(raw.get("canonical_path"), "canonical_path", artifact_id)
        legacy_values = raw.get("legacy_paths")
        if not isinstance(legacy_values, list) or not legacy_values:
            raise SyncError(f"{artifact_id}: canonical retain-copy artifact needs legacy_paths")
        for value in legacy_values:
            pairs.append(
                (
                    artifact_id,
                    canonical,
                    repository_path(value, "legacy_paths entry", artifact_id),
                )
            )
    return pairs


def check(pairs: Iterable[tuple[str, Path, Path]]) -> tuple[int, int]:
    prepared = preflight_sync(pairs)
    checked = 0
    drifted = 0
    for artifact_id, canonical, legacy in prepared:
        checked += 1
        if not same_bytes(canonical, legacy):
            drifted += 1
            print(
                f"hardware-sync: DRIFT {artifact_id}: "
                f"{legacy.relative_to(REPO_ROOT)} != {canonical.relative_to(REPO_ROOT)}",
                file=sys.stderr,
            )
    if drifted:
        raise SyncError(f"{drifted} compatibility cop{'y' if drifted == 1 else 'ies'} drifted")
    return checked, drifted


def preflight_sync(
    pairs: Iterable[tuple[str, Path, Path]],
) -> list[tuple[str, Path, Path]]:
    """Validate every copy source/destination before staging the first write."""
    return preflight_copy_pairs(pairs, refuse_conflicting_destination=False)


def sync(pairs: Iterable[tuple[str, Path, Path]]) -> tuple[int, int]:
    prepared = preflight_sync(pairs)
    plans = prepare_copy_batch(prepared)
    changed = commit_copy_batch(plans)
    for plan in changed:
        print(
            f"synced {plan.artifact_id}: {plan.source.relative_to(REPO_ROOT)} -> "
            f"{plan.destination.relative_to(REPO_ROOT)}"
        )
    return len(changed), len(plans) - len(changed)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="fail if compatibility copies drift")
    mode.add_argument("--sync", action="store_true", help="copy canonical artifacts to legacy paths")
    mode.add_argument(
        "--bootstrap",
        action="store_true",
        help="one-time copy of planned generated artifacts into absent canonical paths",
    )
    parser.add_argument(
        "--artifact",
        action="append",
        default=[],
        metavar="ID",
        help="limit the operation to a stable manifest artifact id (repeatable)",
    )
    args = parser.parse_args()

    try:
        if args.sync or args.bootstrap:
            validate_manifest_for_mutation()
        artifacts, by_id = load_manifest()
        selected = selected_artifacts(artifacts, set(args.artifact))
        if args.bootstrap:
            copied, unchanged = bootstrap(selected)
            print(f"hardware-sync: BOOTSTRAP PASS ({copied} copied, {unchanged} unchanged)")
            return 0

        pairs = compatibility_pairs(selected, by_id)
        if args.sync:
            copied, unchanged = sync(pairs)
            print(f"hardware-sync: SYNC PASS ({copied} copied, {unchanged} unchanged)")
        else:
            checked, _ = check(pairs)
            print(f"hardware-sync: CHECK PASS ({checked} compatibility copies)")
        return 0
    except (OSError, SyncError) as error:
        print(f"hardware-sync: FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
