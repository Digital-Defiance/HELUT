"""ctypes loader for libHELUTRadio.dylib."""

from __future__ import annotations

import ctypes
import os
import sys
from pathlib import Path
from typing import Optional

HELUT_OK = 0

_lib: Optional[ctypes.CDLL] = None


def _candidate_libs() -> list[Path]:
    env = os.environ.get("HELUT_RADIO_LIB")
    out: list[Path] = []
    if env:
        out.append(Path(env))
    here = Path(__file__).resolve()
    # Apps/gr-helut/python/helut_radio/bindings.py → repo root
    repo = here.parents[4]
    out.extend(
        [
            repo / ".build" / "release" / "libHELUTRadio.dylib",
            repo / ".build" / "arm64-apple-macosx" / "release" / "libHELUTRadio.dylib",
            repo / ".build" / "debug" / "libHELUTRadio.dylib",
        ]
    )
    return out


def load_library(path: Optional[str] = None) -> ctypes.CDLL:
    global _lib
    if _lib is not None and path is None:
        return _lib
    candidates = [Path(path)] if path else _candidate_libs()
    last_err: Exception | None = None
    for cand in candidates:
        if not cand.is_file():
            continue
        try:
            lib = ctypes.CDLL(str(cand))
            _bind(lib)
            _lib = lib
            return lib
        except OSError as exc:
            last_err = exc
    searched = ", ".join(str(c) for c in candidates)
    raise FileNotFoundError(
        f"libHELUTRadio.dylib not found (searched: {searched}). "
        f"Build with: swift build -c release --product HELUTRadio"
        + (f" last error: {last_err}" if last_err else "")
    )


def _bind(lib: ctypes.CDLL) -> None:
    lib.helut_version.restype = ctypes.c_char_p
    lib.helut_version.argtypes = []

    lib.helut_open.restype = ctypes.c_void_p
    lib.helut_open.argtypes = [
        ctypes.c_char_p,
        ctypes.c_char_p,
        ctypes.c_char_p,
        ctypes.c_size_t,
    ]

    lib.helut_close.restype = None
    lib.helut_close.argtypes = [ctypes.c_void_p]

    lib.helut_mode.restype = ctypes.c_char_p
    lib.helut_mode.argtypes = [ctypes.c_void_p]

    lib.helut_module_name.restype = ctypes.c_char_p
    lib.helut_module_name.argtypes = [ctypes.c_void_p]

    lib.helut_input_port_count.restype = ctypes.c_int
    lib.helut_input_port_count.argtypes = [ctypes.c_void_p]
    lib.helut_output_port_count.restype = ctypes.c_int
    lib.helut_output_port_count.argtypes = [ctypes.c_void_p]

    lib.helut_input_bit_count.restype = ctypes.c_int
    lib.helut_input_bit_count.argtypes = [ctypes.c_void_p]
    lib.helut_output_bit_count.restype = ctypes.c_int
    lib.helut_output_bit_count.argtypes = [ctypes.c_void_p]

    lib.helut_regex_feed.restype = ctypes.c_int
    lib.helut_regex_feed.argtypes = [
        ctypes.c_void_p,
        ctypes.c_uint8,
        ctypes.POINTER(ctypes.c_uint8),
    ]

    lib.helut_reset.restype = ctypes.c_int
    lib.helut_reset.argtypes = [ctypes.c_void_p]

    lib.helut_tick.restype = ctypes.c_int
    lib.helut_tick.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(ctypes.c_uint8),
        ctypes.c_size_t,
        ctypes.POINTER(ctypes.c_uint8),
        ctypes.c_size_t,
        ctypes.POINTER(ctypes.c_size_t),
    ]


class HelutEngine:
    """Thin Pythonic wrapper around helut_engine*."""

    def __init__(self, netlist: str | Path, mode: str = "clear"):
        self._lib = load_library()
        err = ctypes.create_string_buffer(512)
        handle = self._lib.helut_open(
            str(netlist).encode(),
            mode.encode(),
            err,
            len(err),
        )
        if not handle:
            raise RuntimeError(err.value.decode(errors="replace") or "helut_open failed")
        self._handle = handle

    def close(self) -> None:
        if getattr(self, "_handle", None):
            self._lib.helut_close(self._handle)
            self._handle = None

    def __del__(self) -> None:
        try:
            self.close()
        except Exception:
            pass

    def __enter__(self) -> "HelutEngine":
        return self

    def __exit__(self, *args) -> None:
        self.close()

    @property
    def module_name(self) -> str:
        return self._lib.helut_module_name(self._handle).decode()

    @property
    def mode(self) -> str:
        return self._lib.helut_mode(self._handle).decode()

    def regex_feed(self, byte: int) -> int:
        match = ctypes.c_uint8(0)
        rc = self._lib.helut_regex_feed(self._handle, byte & 0xFF, ctypes.byref(match))
        if rc != HELUT_OK:
            raise RuntimeError(f"helut_regex_feed failed rc={rc}")
        return int(match.value)

    def reset(self) -> None:
        rc = self._lib.helut_reset(self._handle)
        if rc != HELUT_OK:
            raise RuntimeError(f"helut_reset failed rc={rc}")


def default_regex_netlist() -> Path:
    here = Path(__file__).resolve()
    repo = here.parents[4]
    candidate = repo / "regex_netlist.json"
    if candidate.is_file():
        return candidate
    raise FileNotFoundError("regex_netlist.json not found at repo root")


def main_probe() -> int:
    netlist = default_regex_netlist()
    with HelutEngine(netlist, "clear") as eng:
        print(f"HELUT {load_library().helut_version().decode()} module={eng.module_name} mode={eng.mode}")
        text = b"XXDEFYYDEFZZ"
        hits = []
        for i, b in enumerate(text):
            if eng.regex_feed(b):
                hits.append(i)
        print(f"feed {text!r} → hits {hits}")
        if hits != [4, 9]:
            print("FAIL", file=sys.stderr)
            return 1
        print("PASS")
        return 0


if __name__ == "__main__":
    raise SystemExit(main_probe())
