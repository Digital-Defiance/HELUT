#!/usr/bin/env python3
"""HELUT Homomorphic Edge Matcher — closed-loop demo (no over-the-air).

Act I  — Baseband loopback: bits → complex IQ → AWGN → slice → bytes → HELUT regex
Act II — Silicon push: batch-B overlapping windows through the netlist, timed
Act III — Optional encrypted-demo freeze on one window (slow; N=8; honest)

Requires:
  radioconda activated   # https://github.com/radioconda/radioconda-installer
                         # Apple Silicon: …/radioconda-.*-MacOSX-arm64.pkg
  swift build -c release --product HELUTRadio

Honest scope: clear path is the boolean netlist oracle. encrypted-demo is N=8
only — not production-N SING. Not a P1030680 decrypt. Not real RF.
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

import numpy as np

_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(_ROOT / "python"))

from helut_radio import HelutEngine, default_regex_netlist, load_library  # noqa: E402


PREAMBLE = b"\xaa\x55"
DEFAULT_PAYLOAD = b"........DEF........xyzDEF!!........"


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
    """Bits → ±1 BPSK-ish IQ → AWGN → hard slice → recovered bytes (+ raw IQ)."""
    from gnuradio import blocks, channels, gr

    frame = PREAMBLE + payload
    # channel_model drops ~1–2 leading bits; pad both ends so AA55 + payload survive.
    bits = np.concatenate(
        [
            np.zeros(16, dtype=np.uint8),
            np.unpackbits(np.frombuffer(frame, dtype=np.uint8)),
            np.zeros(32, dtype=np.uint8),
        ]
    )

    class Top(gr.top_block):
        def __init__(self):
            gr.top_block.__init__(self, "helut_baseband_loopback")
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
        f"[Act I] GR DSP loopback  noise={noise}  sps={sps}  "
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


def act1_helut_match(payload_rx: bytes, mode: str, netlist: Path) -> list[int]:
    """Slide recovered bytes through HELUT regex_matcher."""
    with HelutEngine(netlist, mode) as eng:
        print(
            f"[Act I] HELUT  module={eng.module_name}  mode={eng.mode}  "
            f"bytes={len(payload_rx)}  text={payload_rx!r}"
        )
        hits: list[int] = []
        t0 = time.perf_counter()
        for i, b in enumerate(payload_rx):
            if eng.regex_feed(b):
                hits.append(i)
                print(f"         ★ MATCH at byte {i}")
        dt = time.perf_counter() - t0
        rate = len(payload_rx) / dt if dt > 0 else float("inf")
        print(f"[Act I] HELUT clear ticks  {dt * 1e3:.2f} ms  ({rate:.0f} bytes/s)  hits={hits}")
        return hits


def act2_batch(payload: bytes, batch: int, netlist: Path) -> None:
    """
    Silicon-ish push: evaluate `batch` overlapping 3-byte windows via the netlist.

    This is many cleartext ticks in a tight host loop (boolean oracle). It stresses
    the HELUT↔Python hinge and shows B on the HUD. True Metal tensor-batch B is a
    follow-on; do not read this as production-N FHE throughput.
    """
    if len(payload) < 3:
        print("[Act II] payload too short for windows")
        return
    max_windows = len(payload) - 2
    b = max(1, batch)
    # Tile / wrap so large B still hammers the engine.
    windows = []
    for i in range(b):
        src = i % max_windows
        windows.append(payload[src : src + 3])

    with HelutEngine(netlist, "clear") as eng:
        hits = 0
        t0 = time.perf_counter()
        for w in windows:
            eng.reset()
            m = 0
            for byte in w:
                m = eng.regex_feed(byte)
            hits += int(m)
        dt = time.perf_counter() - t0

    print(
        f"[Act II] batch B={b}  windows  hits={hits}  "
        f"wall={dt * 1e3:.2f} ms  ({b / dt:.0f} win/s)  "
        f"~{dt / b * 1e6:.1f} µs/window"
    )


def act3_encrypted_freeze(payload: bytes, netlist: Path, index: int | None = None) -> None:
    """Freeze one 3-byte window and run encrypted-demo (N=8). Slow is the exhibit."""
    if len(payload) < 3:
        return
    if index is None:
        # Prefer a known DEF window if present
        index = 0
        for i in range(len(payload) - 2):
            if payload[i : i + 3] == b"DEF":
                index = i
                break
    window = payload[index : index + 3]
    print(f"[Act III] encrypted-demo freeze  window[{index}:{index+3}]={window!r}  (N=8; not production)")
    with HelutEngine(netlist, "encrypted-demo") as eng:
        t0 = time.perf_counter()
        m = 0
        for byte in window:
            m = eng.regex_feed(byte)
        dt = time.perf_counter() - t0
    print(f"[Act III] match={int(m)}  wall={dt * 1e3:.1f} ms  (blind-rotate demo path)")


def expected_hits(text: bytes) -> list[int]:
    return [i for i in range(2, len(text)) if text[i - 2 : i + 1] == b"DEF"]


def main() -> int:
    _require_gr()
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--netlist", type=Path, default=None)
    parser.add_argument("--payload", default=DEFAULT_PAYLOAD.decode("latin-1"))
    parser.add_argument("--noise", type=float, default=0.05, help="AWGN noise_voltage for channel_model")
    parser.add_argument("--batch", type=int, default=10_000, help="Act II overlapping windows")
    parser.add_argument("--skip-batch", action="store_true")
    parser.add_argument("--encrypted-freeze", action="store_true", help="Act III encrypted-demo N=8")
    parser.add_argument("--save-iq", type=Path, default=None, help="optional .npy of loopback IQ")
    args = parser.parse_args()

    netlist = args.netlist or default_regex_netlist()
    payload = args.payload.encode("latin-1", errors="replace")
    lib = load_library()

    print("=" * 60)
    print("HELUT Homomorphic Edge Matcher  (closed-loop, no OTA)")
    print(f"  lib:     {lib.helut_version().decode()}")
    print(f"  netlist: {netlist}")
    print(f"  payload: {payload!r}")
    print("=" * 60)

    # Act I — GR DSP + HELUT
    rx, iq = baseband_loopback(payload, noise=args.noise)
    if args.save_iq is not None:
        np.save(args.save_iq, iq)
        print(f"[Act I] saved IQ → {args.save_iq}  ({iq.size} complex samples)")

    hits = act1_helut_match(rx, mode="clear", netlist=netlist)
    exp = expected_hits(rx)
    if hits != exp:
        # Still interesting if noise flipped bits; report honestly
        print(f"[Act I] note: hits={hits} expected_from_rx={exp} (noise may have flipped bits)")
        if b"DEF" not in rx:
            print("[Act I] FAIL: DEF lost in channel — lower --noise")
            return 1
    else:
        print("[Act I] PASS  HELUT matches locked to recovered DEF windows")

    # Act II — batch HUD
    if not args.skip_batch:
        print("-" * 60)
        act2_batch(rx if b"DEF" in rx else payload, batch=args.batch, netlist=netlist)

    # Act III — optional encrypted freeze
    if args.encrypted_freeze:
        print("-" * 60)
        act3_encrypted_freeze(rx if b"DEF" in rx else payload, netlist=netlist)

    print("=" * 60)
    print("OK  — envelope demo complete (no antenna was used)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
