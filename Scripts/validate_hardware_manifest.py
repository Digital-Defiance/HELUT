#!/usr/bin/env python3
"""Validate HELUT's hardware source/generated relocation contract.

This tool is deliberately read-only. It verifies that the manifest names existing
current artifacts, uses unique stable IDs, and keeps authored, generated, and
compatibility paths inside their declared ownership boundaries.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path, PurePosixPath
from typing import Any


REPO_ROOT = Path(__file__).resolve().parent.parent
MANIFEST_PATH = REPO_ROOT / "Hardware" / "artifact-manifest.json"
EXPECTED_SCHEMA = "helut.hardware-artifacts/v1"
EXPECTED_POLICIES = {
    "authored_hardware_root": "Hardware",
    "checked_in_generated_root": "Generated",
    "scratch_generated_root": "build",
    "legacy_generators_must_not_write_through_aliases": True,
    "promotion_requires_explicit_validation": True,
}
EXPECTED_FIXED_PATHS = {
    PurePosixPath(value)
    for value in (
        "BREAK_P1030680.md",
        "writeup.tex",
        "directives/claim-sheet.md",
        "REPRODUCE.md",
        "Apps",
        "Fixtures",
        "Scripts",
        "Sources",
        "Tests",
        "logs",
        "site",
        "textbook",
    )
}


def fail(message: str) -> None:
    print(f"hardware-manifest: {message}", file=sys.stderr)


def relative_path(value: Any, field: str, artifact_id: str) -> PurePosixPath | None:
    if not isinstance(value, str) or not value:
        fail(f"{artifact_id}: {field} must be a non-empty string")
        return None
    path = PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts:
        fail(f"{artifact_id}: {field} must be repository-relative without '..': {value}")
        return None
    return path


def first_symlink_component(path: PurePosixPath) -> PurePosixPath | None:
    """Return the first repository-relative symlink component, if any."""
    candidate = REPO_ROOT
    traversed: list[str] = []
    for part in path.parts:
        candidate /= part
        traversed.append(part)
        if candidate.is_symlink():
            return PurePosixPath(*traversed)
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--allow-copy-drift",
        action="store_true",
        help="validate manifest structure before canonical-to-legacy synchronization",
    )
    args = parser.parse_args()

    try:
        document = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read {MANIFEST_PATH.relative_to(REPO_ROOT)}: {error}")
        return 1

    errors_before = 0
    if document.get("schema") != EXPECTED_SCHEMA:
        fail(f"schema must be {EXPECTED_SCHEMA!r}")
        errors_before += 1

    if document.get("policies") != EXPECTED_POLICIES:
        fail(
            "policies must exactly declare the canonical Hardware/, Generated/, "
            "and build/ ownership contract"
        )
        errors_before += 1

    parsed_fixed_paths: set[PurePosixPath] = set()
    fixed_paths = document.get("fixed_paths")
    if not isinstance(fixed_paths, list) or not fixed_paths:
        fail("fixed_paths must be a non-empty array")
        errors_before += 1
    else:
        for value in fixed_paths:
            path = relative_path(value, "fixed_paths entry", "manifest")
            if path is None:
                errors_before += 1
                continue
            if path in parsed_fixed_paths:
                fail(f"duplicate fixed path: {path}")
                errors_before += 1
                continue
            parsed_fixed_paths.add(path)
            if not (REPO_ROOT / Path(path)).exists():
                fail(f"fixed path does not exist: {path}")
                errors_before += 1

    missing_fixed_paths = sorted(EXPECTED_FIXED_PATHS - parsed_fixed_paths)
    unexpected_fixed_paths = sorted(parsed_fixed_paths - EXPECTED_FIXED_PATHS)
    if missing_fixed_paths or unexpected_fixed_paths:
        details: list[str] = []
        if missing_fixed_paths:
            details.append("missing " + ", ".join(map(str, missing_fixed_paths)))
        if unexpected_fixed_paths:
            details.append("unexpected " + ", ".join(map(str, unexpected_fixed_paths)))
        fail("fixed_paths must match the protected repository contract: " + "; ".join(details))
        errors_before += 1

    artifacts = document.get("artifacts")
    if not isinstance(artifacts, list) or not artifacts:
        fail("artifacts must be a non-empty array")
        return 1

    migration_state = document.get("migration_state")
    if migration_state not in {"phased", "canonical"}:
        fail(f"unsupported top-level migration_state {migration_state!r}")
        errors_before += 1
    elif migration_state == "canonical":
        planned_ids = [
            str(raw.get("id", f"artifact #{index}"))
            for index, raw in enumerate(artifacts)
            if isinstance(raw, dict)
            and raw.get("role") != "compatibility-alias"
            and raw.get("migration") == "planned"
        ]
        if planned_ids:
            fail(
                "canonical migration_state cannot contain planned artifacts: "
                + ", ".join(planned_ids)
            )
            errors_before += 1

    identifiers: set[str] = set()
    current_paths: set[PurePosixPath] = set()
    canonical_owners: dict[PurePosixPath, str] = {}
    compatibility_destinations: dict[PurePosixPath, str] = {}
    parsed: list[tuple[dict[str, Any], PurePosixPath, PurePosixPath]] = []
    errors = errors_before

    for index, raw in enumerate(artifacts):
        if not isinstance(raw, dict):
            fail(f"artifact #{index} must be an object")
            errors += 1
            continue
        artifact_id = raw.get("id")
        if not isinstance(artifact_id, str) or not artifact_id:
            fail(f"artifact #{index}: id must be a non-empty string")
            errors += 1
            continue
        if artifact_id in identifiers:
            fail(f"duplicate artifact id: {artifact_id}")
            errors += 1
        identifiers.add(artifact_id)

        role = raw.get("role")
        if not isinstance(role, str) or not role:
            fail(f"{artifact_id}: role must be a non-empty string")
            errors += 1

        current = relative_path(raw.get("current_path"), "current_path", artifact_id)
        canonical = relative_path(raw.get("canonical_path"), "canonical_path", artifact_id)
        if current is None or canonical is None:
            errors += 1
            continue
        if current in current_paths:
            fail(f"duplicate current_path: {current}")
            errors += 1
        current_paths.add(current)
        current_file = REPO_ROOT / Path(current)
        current_symlink = first_symlink_component(current)
        if current_symlink is not None:
            fail(f"{artifact_id}: current_path traverses symlink {current_symlink}")
            errors += 1
        canonical_file = REPO_ROOT / Path(canonical)
        if canonical != current:
            canonical_symlink = first_symlink_component(canonical)
            if canonical_symlink is not None:
                fail(f"{artifact_id}: canonical_path traverses symlink {canonical_symlink}")
                errors += 1
            if canonical_file.exists() and not canonical_file.is_file():
                fail(f"{artifact_id}: canonical_path exists but is not a file: {canonical}")
                errors += 1
        current_is_repairable_copy = (
            args.allow_copy_drift
            and role == "compatibility-alias"
            and not current_file.exists()
            and not current_file.is_symlink()
        )
        if not current_file.is_file() and not current_is_repairable_copy:
            fail(f"{artifact_id}: current artifact is missing or not a file: {current}")
            errors += 1

        if role != "compatibility-alias":
            previous = canonical_owners.get(canonical)
            if previous is not None:
                fail(f"canonical path {canonical} is owned by both {previous} and {artifact_id}")
                errors += 1
            canonical_owners[canonical] = artifact_id
        else:
            if len(current.parts) != 1:
                fail(f"{artifact_id}: compatibility alias must be a repository-root file: {current}")
                errors += 1
            previous = compatibility_destinations.get(current)
            if previous is not None:
                fail(
                    f"compatibility destination {current} is owned by both "
                    f"{previous} and {artifact_id}"
                )
                errors += 1
            else:
                compatibility_destinations[current] = artifact_id

        migration = raw.get("migration")
        if migration == "canonical" and current != canonical:
            fail(f"{artifact_id}: canonical migration requires current_path == canonical_path")
            errors += 1
        elif migration == "planned" and current == canonical:
            fail(f"{artifact_id}: planned migration already points at its canonical path")
            errors += 1
        elif migration not in {
            "canonical", "planned", "legacy-alias", "fixed-compatibility"
        }:
            fail(f"{artifact_id}: unsupported migration state {migration!r}")
            errors += 1

        legacy_policy = raw.get("legacy_policy")
        if legacy_policy not in {"none", "retain-wrapper", "retain-copy"}:
            fail(f"{artifact_id}: unsupported legacy policy {legacy_policy!r}")
            errors += 1

        legacy_values = raw.get("legacy_paths", [])
        legacy_paths: list[PurePosixPath] = []
        if not isinstance(legacy_values, list):
            fail(f"{artifact_id}: legacy_paths must be an array when present")
            errors += 1
        else:
            seen_legacy_paths: set[PurePosixPath] = set()
            for value in legacy_values:
                legacy = relative_path(value, "legacy_paths entry", artifact_id)
                if legacy is None:
                    errors += 1
                    continue
                if legacy in seen_legacy_paths:
                    fail(f"{artifact_id}: duplicate legacy path: {legacy}")
                    errors += 1
                    continue
                seen_legacy_paths.add(legacy)
                legacy_paths.append(legacy)
                if len(legacy.parts) != 1:
                    fail(
                        f"{artifact_id}: legacy compatibility path must be a "
                        f"repository-root file: {legacy}"
                    )
                    errors += 1
                previous = compatibility_destinations.get(legacy)
                if previous is not None:
                    fail(
                        f"compatibility destination {legacy} is owned by both "
                        f"{previous} and {artifact_id}"
                    )
                    errors += 1
                else:
                    compatibility_destinations[legacy] = artifact_id
                if legacy == current:
                    fail(f"{artifact_id}: legacy path must differ from current_path: {legacy}")
                    errors += 1
                legacy_file = REPO_ROOT / Path(legacy)
                legacy_symlink = first_symlink_component(legacy)
                if legacy_symlink is not None:
                    fail(f"{artifact_id}: legacy path traverses symlink {legacy_symlink}")
                    errors += 1
                legacy_is_repairable_copy = (
                    args.allow_copy_drift
                    and legacy_policy == "retain-copy"
                    and not legacy_file.exists()
                    and not legacy_file.is_symlink()
                )
                if not legacy_file.is_file() and not legacy_is_repairable_copy:
                    fail(
                        f"{artifact_id}: legacy artifact is missing or not a file: {legacy}"
                    )
                    errors += 1

        if migration == "canonical" and legacy_policy in {
            "retain-wrapper", "retain-copy"
        } and not legacy_paths:
            fail(f"{artifact_id}: canonical {legacy_policy} migration requires legacy_paths")
            errors += 1
        if legacy_policy == "none" and legacy_paths:
            fail(f"{artifact_id}: legacy_policy 'none' cannot declare legacy_paths")
            errors += 1

        if isinstance(role, str):
            if role in {"authored-rtl", "vendored-rtl", "app-authored-rtl"}:
                if migration not in {"canonical", "planned"}:
                    fail(f"{artifact_id}: {role} must use canonical or planned migration")
                    errors += 1
                if legacy_policy not in {"none", "retain-wrapper"}:
                    fail(f"{artifact_id}: {role} must use no legacy path or retain-wrapper")
                    errors += 1
            elif role == "authored-testbench":
                if migration not in {"canonical", "planned"} or legacy_policy != "none":
                    fail(
                        f"{artifact_id}: authored-testbench must use canonical/planned "
                        "migration with no legacy path"
                    )
                    errors += 1
            elif role.startswith("generated-"):
                if migration not in {"canonical", "planned"} or legacy_policy != "retain-copy":
                    fail(
                        f"{artifact_id}: generated artifacts must use canonical/planned "
                        "migration with retain-copy"
                    )
                    errors += 1
            elif role == "fixture-data":
                if migration not in {"canonical", "planned"} or legacy_policy != "none":
                    fail(
                        f"{artifact_id}: fixture-data must use canonical/planned "
                        "migration with no legacy path"
                    )
                    errors += 1
            elif role == "compatibility-alias":
                if migration != "legacy-alias" or legacy_policy != "retain-copy":
                    fail(
                        f"{artifact_id}: compatibility-alias must use legacy-alias "
                        "migration with retain-copy"
                    )
                    errors += 1
            else:
                fail(f"{artifact_id}: unsupported artifact role {role!r}")
                errors += 1

        if migration == "canonical" and legacy_policy == "retain-wrapper":
            expected_include = f'`include "{canonical.as_posix()}"'
            for legacy in legacy_paths:
                try:
                    wrapper = (REPO_ROOT / Path(legacy)).read_text(encoding="utf-8")
                except (OSError, UnicodeError) as error:
                    fail(f"{artifact_id}: cannot read legacy wrapper {legacy}: {error}")
                    errors += 1
                    continue
                nonempty_lines = [
                    line.strip() for line in wrapper.splitlines() if line.strip()
                ]
                if (
                    len(nonempty_lines) != 2
                    or not nonempty_lines[0].startswith("// Compatibility wrapper:")
                    or nonempty_lines[1] != expected_include
                ):
                    fail(
                        f"{artifact_id}: legacy wrapper {legacy} must contain only "
                        "one compatibility comment and the canonical include"
                    )
                    errors += 1

        if migration == "canonical" and legacy_policy == "retain-copy":
            try:
                canonical_bytes = canonical_file.read_bytes()
            except OSError as error:
                fail(f"{artifact_id}: cannot read canonical copy {canonical}: {error}")
                errors += 1
            else:
                for legacy in legacy_paths:
                    legacy_file = REPO_ROOT / Path(legacy)
                    if args.allow_copy_drift and not legacy_file.exists():
                        continue
                    try:
                        if canonical_file.samefile(legacy_file):
                            fail(
                                f"{artifact_id}: legacy copy aliases canonical inode: {legacy}"
                            )
                            errors += 1
                            continue
                        legacy_bytes = legacy_file.read_bytes()
                    except OSError as error:
                        fail(f"{artifact_id}: cannot read legacy copy {legacy}: {error}")
                        errors += 1
                        continue
                    if legacy_bytes != canonical_bytes and not args.allow_copy_drift:
                        fail(f"{artifact_id}: legacy copy differs from canonical: {legacy}")
                        errors += 1

        if isinstance(role, str):
            canonical_text = canonical.as_posix()
            if role == "authored-rtl" and not canonical_text.startswith("Hardware/RTL/"):
                fail(f"{artifact_id}: authored RTL must target Hardware/RTL/")
                errors += 1
            if role == "app-authored-rtl" and not canonical_text.startswith("Apps/"):
                fail(f"{artifact_id}: app-authored RTL must target Apps/")
                errors += 1
            if role == "authored-testbench" and not canonical_text.startswith(
                "Hardware/Testbenches/"
            ):
                fail(f"{artifact_id}: testbench must target Hardware/Testbenches/")
                errors += 1
            if role == "vendored-rtl" and not canonical_text.startswith(
                "Hardware/RTL/Vendor/"
            ):
                fail(f"{artifact_id}: vendored RTL must target Hardware/RTL/Vendor/")
                errors += 1
            if role.startswith("generated-") and not canonical_text.startswith("Generated/"):
                fail(f"{artifact_id}: checked-in generated artifact must target Generated/")
                errors += 1
            if role == "fixture-data" and not canonical_text.startswith("Fixtures/"):
                fail(f"{artifact_id}: fixture data must target Fixtures/")
                errors += 1

        parsed.append((raw, current, canonical))

    for destination, owner in compatibility_destinations.items():
        canonical_owner = canonical_owners.get(destination)
        if canonical_owner is not None:
            fail(
                f"{owner}: compatibility destination {destination} overlaps "
                f"canonical artifact {canonical_owner}"
            )
            errors += 1
        if destination in parsed_fixed_paths:
            fail(f"{owner}: compatibility destination overlaps fixed path {destination}")
            errors += 1

    parsed_by_id = {raw["id"]: (raw, current, canonical) for raw, current, canonical in parsed}
    for raw, current, canonical in parsed:
        artifact_id = raw["id"]
        source = raw.get("source_artifact")
        if source is None:
            continue
        if not isinstance(source, str) or not source:
            fail(f"{artifact_id}: source_artifact must be a non-empty string")
            errors += 1
            continue
        if isinstance(raw.get("role"), str) and raw["role"].startswith("generated-"):
            if source not in identifiers:
                fail(f"{artifact_id}: generated source_artifact must be an artifact id: {source}")
                errors += 1
                continue
        elif source not in identifiers and not (REPO_ROOT / source).is_file():
            fail(f"{artifact_id}: source_artifact is neither an artifact id nor a file: {source}")
            errors += 1
            continue

        if raw.get("role") == "compatibility-alias":
            source_record = parsed_by_id.get(source)
            if source_record is None:
                fail(f"{artifact_id}: compatibility alias source must be an artifact id: {source}")
                errors += 1
                continue
            _, source_current, source_canonical = source_record
            if canonical != source_canonical:
                fail(
                    f"{artifact_id}: alias canonical_path must equal source canonical_path "
                    f"{source_canonical}"
                )
                errors += 1
            try:
                source_bytes = (REPO_ROOT / Path(source_current)).read_bytes()
            except OSError as error:
                fail(f"{artifact_id}: cannot read compatibility alias source: {error}")
                errors += 1
                continue

            alias_file = REPO_ROOT / Path(current)
            if not alias_file.is_file():
                continue
            try:
                source_file = REPO_ROOT / Path(source_current)
                if source_file.samefile(alias_file):
                    fail(f"{artifact_id}: compatibility alias shares source inode: {current}")
                    errors += 1
                    continue
                alias_bytes = alias_file.read_bytes()
            except OSError as error:
                fail(f"{artifact_id}: cannot read compatibility alias: {error}")
                errors += 1
            else:
                if alias_bytes != source_bytes and not args.allow_copy_drift:
                    fail(f"{artifact_id}: compatibility alias differs from source: {current}")
                    errors += 1

    if errors:
        fail(f"FAIL ({errors} error{'s' if errors != 1 else ''})")
        return 1

    canonical_count = sum(1 for raw, _, _ in parsed if raw["migration"] == "canonical")
    planned_count = sum(1 for raw, _, _ in parsed if raw["migration"] == "planned")
    print(
        "hardware-manifest: PASS "
        f"({len(parsed)} artifacts; {canonical_count} canonical, {planned_count} planned)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
