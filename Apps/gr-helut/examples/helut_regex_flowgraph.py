#!/usr/bin/env python3
"""Minimal GNU Radio flowgraph: vector source → HELUT regex → time sink / print.

Requires:
  conda activate base       # radioconda default; or: conda activate gnuradio
                            # https://github.com/radioconda/radioconda-installer
                            # Apple Silicon: …/radioconda-.*-MacOSX-arm64.pkg
  swift build -c release --product HELUTRadio
"""

from __future__ import annotations

import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(_ROOT / "python"))

try:
    from gnuradio import blocks, gr
    import numpy as np
except ImportError:
    sys.stderr.write(
        "gnuradio not installed.\n"
        "  Install: https://github.com/radioconda/radioconda-installer\n"
        "  Apple Silicon pkg:\n"
        "    https://glare-sable.vercel.app/radioconda/radioconda-installer/radioconda-.*-MacOSX-arm64.pkg\n"
        "  then: conda activate base   # or: conda activate gnuradio\n"
        "  (Homebrew's gnuradio formula is deprecated.)\n"
        "Until then, run: python3 Apps/gr-helut/examples/helut_regex_demo.py\n"
    )
    raise SystemExit(2)

from helut_radio import RegexMatcher, default_regex_netlist  # noqa: E402


class HelutRegexTop(gr.top_block):
    def __init__(self, mode: str = "clear"):
        gr.top_block.__init__(self, "HELUT Regex Demo")
        payload = np.frombuffer(
            b"........DEF........xyzDEF!!........",
            dtype=np.uint8,
        )
        self.src = blocks.vector_source_b(payload.tolist(), False)
        self.helut = RegexMatcher(str(default_regex_netlist()), mode)
        self.sink = blocks.vector_sink_f()
        self.connect(self.src, self.helut, self.sink)


def main() -> int:
    mode = "clear"
    if "--encrypted-demo" in sys.argv:
        mode = "encrypted-demo"
    tb = HelutRegexTop(mode=mode)
    tb.run()
    data = tb.sink.data()
    hits = [i for i, v in enumerate(data) if v >= 0.5]
    print(f"mode={mode} samples={len(data)} hits@ {hits}")
    # "DEF" ends at indices of the final 'F' in each occurrence.
    text = b"........DEF........xyzDEF!!........"
    expected = [i for i in range(2, len(text)) if text[i - 2 : i + 1] == b"DEF"]
    if hits != expected:
        print(f"FAIL expected {expected}", file=sys.stderr)
        return 1
    print("PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
