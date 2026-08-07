#!/usr/bin/env python3
"""HELUT regex demo without GNU Radio — ctypes → libHELUTRadio.dylib."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

# Allow running from repo root without installing the package.
_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(_ROOT / "python"))

from helut_radio import HelutEngine, default_regex_netlist, load_library  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description="HELUT regex_matcher byte-stream demo")
    parser.add_argument("--netlist", type=Path, default=None)
    parser.add_argument("--mode", choices=("clear", "encrypted-demo"), default="clear")
    parser.add_argument(
        "--text",
        default="noise...DEF...more noise...DEF...end",
        help="ASCII probe string",
    )
    args = parser.parse_args()

    netlist = args.netlist or default_regex_netlist()
    lib = load_library()
    print(f"lib: {lib.helut_version().decode()}")
    print(f"netlist: {netlist}")
    print(f"mode: {args.mode}")
    print(f"text: {args.text!r}")
    print("-" * 40)

    with HelutEngine(netlist, args.mode) as eng:
        print(f"module: {eng.module_name}")
        hits = 0
        for i, ch in enumerate(args.text.encode("latin-1", errors="replace")):
            match = eng.regex_feed(ch)
            glyph = chr(ch) if 32 <= ch < 127 else f"\\x{ch:02x}"
            star = "  ★ MATCH \"DEF\"" if match else ""
            print(f"{i:4d}  '{glyph}'{star}")
            hits += match
        print("-" * 40)
        print(f"hits: {hits}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
