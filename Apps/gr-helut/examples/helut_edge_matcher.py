#!/usr/bin/env python3
"""HELUT Callsign Edge Matcher — closed-loop demo (no over-the-air).

Act I  — Local baseband: bits → complex IQ → AWGN → slice → bytes → HELUT matcher
Act II — Clear-oracle repetition: B overlapping windows through the netlist, timed
Act III — Optional encrypted-demo freeze on one callsign (N=8 demonstration only)

Requires:
  radioconda activated
  swift build -c release --product HELUTRadio
  make generate-ab0cde-netlist && make promote-ab0cde-netlist

Honest scope: Acts I–II use the clear Boolean netlist oracle. Act III evaluates
one window at N=8, not production-N FHE. No antenna, interception, or OTA signal.
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

import numpy as np

_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(_ROOT / "python"))

from helut_radio import HelutEngine, default_ab0cde_netlist, load_library  # noqa: E402


PREAMBLE = b"\xaa\x55"
DEFAULT_PATTERN = b"AB0CDE"
DEFAULT_PAYLOAD = b"CQ CQ CQ DE AB0CDE AB0CDE K"


def _require_gr():
    try:
        from gnuradio import blocks, channels, gr  # noqa: F401
    except ImportError as exc:
        sys.stderr.write(
            "gnuradio required.\n"
            "  Install: https://github.com/radioconda/radioconda-installer\n"
            "  Apple Silicon pkg:\n"
            "    https://glare-sable.vercel.app/radioconda/radioconda-installer/radioconda-.*-MacOSX-arm64.pkg\n"
            "  then: conda activate base   # or: conda activate gnuradio\n"
            "(Homebrew's gnuradio formula is deprecated.)\n"
            f"  ({exc})\n"
        )
        raise SystemExit(2)


def baseband_loopback(payload: bytes, noise: float, sps: int = 4) -> tuple[bytes, np.ndarray]:
    """Bits → ±1 BPSK-like IQ → AWGN → hard slice → recovered bytes and raw IQ."""
    from gnuradio import blocks, channels, gr

    frame = PREAMBLE + payload
    # channel_model drops roughly 1–2 leading bits; pad both ends so the framed
    # payload survives while the AA55 preamble still proves byte alignment.
    bits = np.concatenate(
        [
            np.zeros(16, dtype=np.uint8),
            np.unpackbits(np.frombuffer(frame, dtype=np.uint8)),
            np.zeros(32, dtype=np.uint8),
        ]
    )

    class Top(gr.top_block):
        def __init__(self):
            gr.top_block.__init__(self, "helut_callsign_loopback")
            self.src = blocks.vector_source_b(bits.tolist(), False)
            self.b2f = blocks.char_to_float(1, 1)
            self.sub = blocks.add_const_ff(-0.5)
            self.mul = blocks.multiply_const_ff(2.0)
            self.rep = blocks.repeat(gr.sizeof_float, sps)
            self.f2c = blocks.float_to_complex(1)
            self.chan = channels.channel_model(
                noise_voltage=noise,
                frequency_offset=0.0,
                epsilon=1.0,
            )
            self.creal = blocks.complex_to_real(1)
            self.keep = blocks.keep_one_in_n(gr.sizeof_float, sps)
            self.thr = blocks.threshold_ff(0.0, 0.0)
            self.f2b = blocks.float_to_uchar()
            self.bits_out = blocks.vector_sink_b()
            self.iq_out = blocks.vector_sink_c()
            self.connect(self.src, self.b2f, self.sub, self.mul, self.rep, self.f2c)
            self.connect(self.f2c, self.chan)
            self.connect(self.chan, self.creal, self.keep, self.thr, self.f2b, self.bits_out)
            self.connect(self.chan, self.iq_out)

    tb = Top()
    t0 = time.perf_counter()
    tb.run()
    dsp_s = time.perf_counter() - t0

    out_bits = np.array(tb.bits_out.data(), dtype=np.uint8)
    iq = np.array(tb.iq_out.data(), dtype=np.complex64)
    recovered = _align_and_pack(out_bits, expected_len=len(frame))
    print(
        f"[Act I] GNU Radio local IQ  noise={noise}  sps={sps}  "
        f"iq_samps={len(iq)}  dsp={dsp_s * 1e3:.2f} ms"
    )
    return recovered, iq


def _align_and_pack(bits: np.ndarray, expected_len: int) -> bytes:
    """Lock PREAMBLE bits in the sliced stream (channel_model may drop edges)."""
    pre_bits = np.unpackbits(np.frombuffer(PREAMBLE, dtype=np.uint8)).astype(np.uint8)
    payload_len = expected_len - len(PREAMBLE)
    payload_bits_n = payload_len * 8
    pre_n = len(pre_bits)

    def try_stream(stream: np.ndarray) -> bytes | None:
        limit = len(stream) - pre_n - payload_bits_n + 1
        for start in range(max(0, limit)):
            if np.array_equal(stream[start : start + pre_n], pre_bits):
                body = stream[start + pre_n : start + pre_n + payload_bits_n]
                if len(body) == payload_bits_n:
                    return bytes(np.packbits(body).tolist())
        return None

    for invert in (False, True):
        stream = (1 - bits) if invert else bits
        for off in range(8):
            got = try_stream(stream[off:])
            if got is not None:
                return got

    usable = (len(bits) // 8) * 8
    packed = bytes(np.packbits(bits[:usable]).tolist())
    raise RuntimeError(
        f"failed to lock preamble {PREAMBLE!r} after AWGN slice "
        f"(got prefix {packed[:12]!r}). Try --noise 0.0 … 0.05"
    )


def act1_helut_match(payload_rx: bytes, pattern: bytes, netlist: Path) -> list[int]:
    """Slide recovered bytes through the clear HELUT literal-matcher oracle."""
    with HelutEngine(netlist, "clear") as eng:
        expected_input_bits = len(pattern) * 8
        if eng.input_bit_count != expected_input_bits:
            raise RuntimeError(
                f"netlist/pattern width mismatch: netlist={eng.input_bit_count} bits "
                f"pattern={expected_input_bits} bits"
            )
        print(
            f"[Act I] HELUT Yosys netlist  module={eng.module_name}  mode={eng.mode}  "
            f"input_bits={eng.input_bit_count}"
        )
        print(f"        recovered={payload_rx!r}")
        hits: list[int] = []
        t0 = time.perf_counter()
        for i, byte in enumerate(payload_rx):
            if eng.regex_feed(byte):
                hits.append(i)
                print(f"        ★ CALLSIGN MATCH completes at payload byte {i}")
        dt = time.perf_counter() - t0
        rate = len(payload_rx) / dt if dt > 0 else float("inf")
        print(f"[Act I] clear feed  {dt * 1e3:.2f} ms  ({rate:.0f} bytes/s)  hits={hits}")
        return hits


def act2_batch(payload: bytes, pattern: bytes, batch: int, netlist: Path) -> bool:
    """Repeat overlapping recovered-byte windows through the clear netlist oracle."""
    width = len(pattern)
    if len(payload) < width:
        print(f"[Act II] FAIL  recovered payload is shorter than the {width}-byte pattern")
        return False

    source_windows = len(payload) - width + 1
    b = max(1, batch)
    windows = [payload[(i % source_windows) : (i % source_windows) + width] for i in range(b)]
    expected = sum(window == pattern for window in windows)

    with HelutEngine(netlist, "clear") as eng:
        hits = 0
        t0 = time.perf_counter()
        for window in windows:
            eng.reset()
            match = 0
            for byte in window:
                match = eng.regex_feed(byte)
            hits += int(match)
        dt = time.perf_counter() - t0

    ok = hits == expected
    print(
        f"[Act II] clear scalar host-loop  B={b}  source_windows={source_windows}  "
        f"hits={hits}/{expected}  verdict={'PASS' if ok else 'FAIL'}"
    )
    print(
        f"         wall={dt * 1e3:.2f} ms  ({b / dt:.0f} win/s)  "
        f"~{dt / b * 1e6:.1f} µs/window  (not native tensor batch)"
    )
    return ok


def act3_encrypted_freeze(payload: bytes, pattern: bytes, netlist: Path) -> bool:
    """Freeze one recovered callsign window and run the N=8 encrypted demo path."""
    index = payload.find(pattern)
    if index < 0:
        print(f"[Act III] FAIL  recovered payload has no {pattern!r} window to freeze")
        return False

    window = payload[index : index + len(pattern)]
    print(f"[Act III] encrypted-demo freeze  window[{index}:{index + len(pattern)}]={window!r}")
    print("          N=8 demonstration parameter; one window; not production security")
    with HelutEngine(netlist, "encrypted-demo") as eng:
        t0 = time.perf_counter()
        match = 0
        for byte in window:
            match = eng.regex_feed(byte)
        dt = time.perf_counter() - t0

    ok = int(match) == 1
    print(
        f"[Act III] result={int(match)} expected=1  verdict={'PASS' if ok else 'FAIL'}  "
        f"eval_wall={dt * 1e3:.1f} ms"
    )
    print("          blind-rotate demo path; engine/key setup excluded from timer")
    return ok


def expected_hits(text: bytes, pattern: bytes) -> list[int]:
    width = len(pattern)
    return [
        i
        for i in range(width - 1, len(text))
        if text[i - width + 1 : i + 1] == pattern
    ]


def main() -> int:
    _require_gr()
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--netlist", type=Path, default=None)
    parser.add_argument("--pattern", default=DEFAULT_PATTERN.decode("ascii"))
    parser.add_argument("--payload", default=DEFAULT_PAYLOAD.decode("ascii"))
    parser.add_argument("--noise", type=float, default=0.05, help="AWGN noise_voltage for channel_model")
    parser.add_argument("--batch", type=int, default=10_000, help="Act II repeated overlapping windows")
    parser.add_argument("--skip-batch", action="store_true")
    parser.add_argument("--encrypted-freeze", action="store_true", help="Act III encrypted-demo N=8")
    parser.add_argument("--save-iq", type=Path, default=None, help="optional .npy of loopback IQ")
    args = parser.parse_args()

    pattern = args.pattern.encode("latin-1", errors="replace")
    payload = args.payload.encode("latin-1", errors="replace")
    if not pattern:
        parser.error("--pattern must contain at least one byte")
    netlist = args.netlist or default_ab0cde_netlist()
    lib = load_library()

    print("=" * 72)
    print("HELUT Callsign Edge Matcher  (closed-loop, no OTA / no antenna)")
    print(f"  lib:       {lib.helut_version().decode()}")
    print(f"  netlist:   {netlist}")
    print(f"  pattern:   {pattern!r}  ({len(pattern)} exact ASCII bytes)")
    print(f"  TX payload:{payload!r}")
    print("=" * 72)

    # Act I — local GNU Radio DSP + clear HELUT netlist oracle.
    rx, iq = baseband_loopback(payload, noise=args.noise)
    if args.save_iq is not None:
        np.save(args.save_iq, iq)
        print(f"[Act I] saved post-channel IQ → {args.save_iq}  ({iq.size} complex64 samples)")

    byte_differences = sum(a != b for a, b in zip(payload, rx)) + abs(len(payload) - len(rx))
    print(
        f"[Act I] channel receipt  tx_bytes={len(payload)}  rx_bytes={len(rx)}  "
        f"byte_differences={byte_differences}"
    )

    hits = act1_helut_match(rx, pattern=pattern, netlist=netlist)
    expected_from_rx = expected_hits(rx, pattern)
    expected_from_tx = expected_hits(payload, pattern)
    if hits != expected_from_rx:
        print(f"[Act I] FAIL  HELUT hits={hits}  recovered-byte oracle={expected_from_rx}")
        return 1
    if hits != expected_from_tx:
        print(
            f"[Act I] FAIL  transmitted callsign completions={expected_from_tx} "
            f"did not survive channel; recovered={hits}"
        )
        return 1
    print(
        f"[Act I] PASS  HELUT agrees with recovered bytes; "
        f"transmitted callsign windows survived at {hits}"
    )

    # Act II — explicitly scalar clear/oracle repetition.
    if not args.skip_batch:
        print("-" * 72)
        if not act2_batch(rx, pattern=pattern, batch=args.batch, netlist=netlist):
            return 1

    # Act III — optional, one recovered window at demonstration-size N=8.
    if args.encrypted_freeze:
        print("-" * 72)
        if not act3_encrypted_freeze(rx, pattern=pattern, netlist=netlist):
            return 1

    print("=" * 72)
    print("OK  — callsign envelope demo complete (local loopback; no antenna used)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
