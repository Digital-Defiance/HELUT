# Enigma 256 Core — Host Register Map

Software programs `enigma_256_core` through a memory-mapped AXI-Lite window, with an optional **AXI4-Stream table burst** for active day-slot loads. Addresses below are offsets from the core base. The Swift model is `Enigma256CoreHandle` / `Enigma256SoftBus` in HELUTCore.

This map is for live compatibility tuple:

`E256/v2/gen0/fa246e9cba9009a4799e5a81722a9b14e9a67293d9621b45985c5f3e620865d4/fixture-v4`

The hardware is an experimental datapath, not a self-contained cryptographic protocol endpoint.

## Bring-up sequence

1. **Reset** — assert `rst_n` low, then high.
2. **Load tables** — prefer the AXIS burst (`enigma_256_axis_tables.v`, **2,304 bytes**) or SoftBus `programTablesBurst`. The legacy path selects `wr_sel = 0…8` and writes 256 bytes through `WR_*` for each of the nine tables.
3. **Load message state** — write `INIT_LFSR_*`, `INIT_R*_POS`, and the initial absolute counter (normally zero) through `BYTE_COUNTER_LO` then `BYTE_COUNTER_HI`.
4. **Pulse `LOAD_STATE`** — capture LFSR, Grundstellung, and expected absolute counter into the stream engine.
5. **Stream atomic tuples** — wait until status bit 1 (`busy`) is clear before staging/committing a beat. Then write counter low, counter high, `CENTER_MASK`, and `DATA_IN` last. Writing `DATA_IN` snapshots `(payload, centerMask, absoluteByteCounter)` as one pending tuple. Do not commit another `DATA_IN` while busy; wait for completion, read `DATA_OUT` when status bit 0 is high, and check status bit 3 before the next beat.

Do not assert/commit `DATA_IN` during table writes, `LOAD_STATE`, or while status bit 1 is set. The wrapper has one pending-tuple slot, so violating this back-pressure rule can replace a jitter-delayed payload. A counter mismatch is a schedule error, not a retry with a different mask.

## Register map

| Offset | Name | Access | Width | Description |
|--------|------|--------|-------|-------------|
| `0x00` | `CTRL` | W1C / RW | 32 | bit0: pulse `LOAD_STATE`; bit1: arm AXIS table burst; bit8: clear latched stream output. |
| `0x04` | `WR_SEL` | RW | 32 | Table selector `0…8` (see below). There is no selector 9. |
| `0x08` | `WR_ADDR` | RW | 32 | Byte address `0…255` within the selected table. |
| `0x0C` | `WR_DATA` | RW | 32 | Data byte; writing commits one BRAM write (`wr_en`) when AXIS is not busy. |
| `0x10` | `INIT_LFSR_LO` | RW | 32 | LFSR seed bits `[31:0]`. |
| `0x14` | `INIT_LFSR_HI` | RW | 32 | LFSR seed bits `[63:32]`; an all-zero seed is coerced to `1`. |
| `0x18` | `INIT_R1_POS` | RW | 32 | Rotor 1 Grundstellung (`0x00…0xFF`). |
| `0x1C` | `INIT_R2_POS` | RW | 32 | Rotor 2 Grundstellung. |
| `0x20` | `INIT_R3_POS` | RW | 32 | Rotor 3 Grundstellung. |
| `0x24` | `INIT_R4_POS` | RW | 32 | Rotor 4 Grundstellung. |
| `0x28` | `DATA_IN` | WO / RW model | 32 | Low 8 bits are the payload byte. Writing this register commits and atomically snapshots the staged counter and center mask. |
| `0x2C` | `DATA_OUT` | RO | 32 | Low 8 bits are the latest accepted output byte. |
| `0x30` | `STATUS` | RO | 32 | bit0: output valid; bit1: payload busy; bit2: AXIS table load done; bit3: schedule error. |
| `0x34` | `SCA_CTRL` | RW | 32 | bit0: enable optional stream-presentation jitter. This mechanism is not evidence of side-channel resistance. |
| `0x38` | `BURST_STATUS` | RO | 32 | AXIS/SoftBus table byte count; **2,304** when the nine-table burst completes. |
| `0x3C` | `CENTER_MASK` | RW | 32 | Low 8 bits are host-derived `k_i`; stage before `DATA_IN`. |
| `0x40` | `BYTE_COUNTER_LO` | RW | 32 | Absolute byte counter bits `[31:0]`; write first for each beat. |
| `0x44` | `BYTE_COUNTER_HI` | RW | 32 | Absolute byte counter bits `[63:32]`; write second for each beat. The semantic UInt64 counter is transported low-register then high-register, while the HMAC block counter encoding is big-endian. |

## `WR_SEL` table map

| `wr_sel` | Contents |
|----------|----------|
| 0 | Plugboard involution |
| 1 | Rotor 1 forward |
| 2 | Rotor 1 reverse |
| 3 | Rotor 2 forward |
| 4 | Rotor 2 reverse |
| 5 | Rotor 3 forward |
| 6 | Rotor 3 reverse |
| 7 | Rotor 4 forward |
| 8 | Rotor 4 reverse |

The active slot therefore contains **9 unique 256-byte tables / 2,304 bytes**. Each payload still performs **10 serial table accesses** because the plugboard is used at entry and exit.

## Host schedule and trust boundary

For absolute byte index `i`, the host derives profile-bound HMAC-SHA256 block `floor(i / 32)` using a **UInt64 big-endian block counter** and selects digest lane `i mod 32` as `centerMask = k_i`. The host—not RTL—owns the HMAC key and computation.

After the previous tuple completes and status bit 1 is clear, the exact per-beat MMIO order is:

1. write `BYTE_COUNTER_LO` (`0x40`);
2. write `BYTE_COUNTER_HI` (`0x44`);
3. write `CENTER_MASK` (`0x3C`);
4. write payload to `DATA_IN` (`0x28`) to commit the tuple.

Poll status after commit; do not issue the next `DATA_IN` write until bit 1 returns clear. The single pending slot is not a queue.

The AXI wrapper copies all three staged values into pending registers on the `DATA_IN` write. Optional jitter delays that complete pending tuple; it does not resample fields independently. The core compares the transported counter with its expected counter before applying `A_i^-1(A_i(x) XOR k_i)`. A mismatch sets status bit 3 and produces no accepted output/state advance.

`UInt64.max` is the exhausted state. `UInt64.max - 1` is the final accepted pre-counter; after that beat, the expected counter is `UInt64.max`, and another payload must not be submitted. Counter wrap/reuse is forbidden.

Wire/file containers separately use **HMAC-SHA512** authentication and must verify before streaming into fabric. That outer tag is distinct from the HMAC-SHA256 center-mask schedule. RTL does not implement either HMAC and cannot prove that a supplied mask is authentic; it validates only tuple order through the absolute counter.

## Golden bundle and validation

Preferred release command:

```bash
.build/release/helut-e256 --enigma256-golden
```

With no `--enigma256-out`, it writes to scratch storage:

`build/hardware/Enigma256/enigma256_golden`

The umbrella `.build/release/helut --enigma256-golden` remains a compatibility entry point. An explicitly requested canonical output path, `Fixtures/enigma256_golden`, is guarded: publication is refused unless the supplied profile compatibility key matches the canonical profile key. Normal reproduction should use the scratch default rather than overwrite canonical fixtures.

The bounded fixture-v4 receipt is `logs/e256-v2-gen0-fixture-v4-validation.json`: 1,024 payload bytes, 9 tables, 10 trace files, 25 artifacts; formal 1/1 and `Enigma256Tests` 49/49. These are implementation/parity checks, not a protocol-security result.

## Related artifacts

- RTL core: `Hardware/RTL/Enigma256/enigma_256_core.v`
- AXI4-Lite wrapper: `Hardware/RTL/Enigma256/enigma_256_axi.v`
- AXIS table burst: `Hardware/RTL/Enigma256/enigma_256_axis_tables.v`
- Soft MMIO + driver: `Enigma256SoftBus` / `Enigma256AXIDriver`
- Host center schedule: `Enigma256CenterMask` / `Enigma256AXIDriver.transfer`
- Authenticated container + nonce guard: `Enigma256AEAD.swift` / `Enigma256ProtectedSession`
- Core co-sim: `Scripts/enigma256_sim.sh`
- AXI co-sim: `Scripts/enigma256_axi_sim.sh`
