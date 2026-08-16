"""GNU Radio sync block: byte stream → HELUT regex_matcher match bit."""

from __future__ import annotations

from pathlib import Path

from .bindings import HelutEngine, default_regex_netlist

try:
    from gnuradio import gr
    import numpy as np
    import pmt
except ImportError as exc:  # pragma: no cover
    gr = None
    np = None
    pmt = None
    _import_error = exc
else:
    _import_error = None


def _require_gr():
    if gr is None:
        raise ImportError(
            "gnuradio is not installed. Install radioconda: "
            "https://github.com/radioconda/radioconda-installer "
            "(Apple Silicon: https://glare-sable.vercel.app/radioconda/radioconda-installer/radioconda-.*-MacOSX-arm64.pkg) "
            "then: conda activate base  # or: conda activate gnuradio. "
            "(Homebrew's gnuradio formula is deprecated). "
            f"(import error: {_import_error})"
        )


if gr is not None:

    class RegexMatcher(gr.sync_block):
        """Slide bytes through HELUT regex_netlist.json; output float match ∈ {0,1}."""

        def __init__(self, netlist_path: str = "", mode: str = "clear"):
            gr.sync_block.__init__(
                self,
                name="helut_regex_matcher",
                in_sig=[np.uint8],
                out_sig=[np.float32],
            )
            path = netlist_path or str(default_regex_netlist())
            if not Path(path).is_file():
                raise FileNotFoundError(path)
            self._engine = HelutEngine(path, mode=mode)
            self.message_port_register_out(pmt.intern("match"))

        def __del__(self):
            try:
                self._engine.close()
            except Exception:
                pass

        def work(self, input_items, output_items):
            inn = input_items[0]
            out = output_items[0]
            n = min(len(inn), len(out))
            for i in range(n):
                match = self._engine.regex_feed(int(inn[i]))
                out[i] = float(match)
                if match:
                    self.message_port_pub(
                        pmt.intern("match"),
                        pmt.cons(pmt.intern("match"), pmt.from_long(1)),
                    )
            return n

else:

    class RegexMatcher:  # type: ignore[no-redef]
        def __init__(self, *args, **kwargs):
            _require_gr()
