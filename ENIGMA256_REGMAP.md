# Enigma 256 Core — Host Register Map

Software control plane programs `enigma_256_core` over a memory-mapped AXI-lite
window, with an optional **AXI4-Stream table burst** for day-slot loads. Addresses
below are offsets from the core base. The Swift bitbang model is
`Enigma256CoreHandle` / `Enigma256SoftBus` in HELUTCore.

## Bring-up sequence

1. **Reset** — assert `rst_n` low then high.
2. **Load tables** — prefer AXIS burst (`enigma_256_axis_tables.v`, 2,560 bytes) or SoftBus `programTablesBurst`. Legacy path: for `wr_sel = 0…9`, write 256 bytes via `WR_*`.
3. **Load message key** — write `INIT_LFSR_*` and `INIT_R*_POS`.
4. **Pulse `LOAD_STATE`** — capture LFSR + Grundstellung into the stream engine.
5. **Stream** — present each byte on `DATA_IN` with `VALID_IN` for one cycle; read `DATA_OUT` when `VALID_OUT` is high. Optional `SCA_CTRL` enables stream jitter to disrupt DPA alignment.

Do not assert `VALID_IN` during table writes or `LOAD_STATE`.

## Register map

| Offset | Name | Access | Width | Description |
|--------|------|--------|-------|-------------|
| `0x00` | `CTRL` | W1C / RW | 32 | bit0: pulse `LOAD_STATE` (W1C). bit8: soft reset (optional). |
| `0x04` | `WR_SEL` | RW | 32 | Table select `0…9` (see below). |
| `0x08` | `WR_ADDR` | RW | 32 | Byte address `0…255` within the selected table. |
| `0x0C` | `WR_DATA` | RW | 32 | Data byte; writing commits one BRAM write (`wr_en` pulse). |
| `0x10` | `INIT_LFSR_LO` | RW | 32 | LFSR seed bits `[31:0]`. |
| `0x14` | `INIT_LFSR_HI` | RW | 32 | LFSR seed bits `[63:32]`. All-zero seed is coerced to `1` in RTL. |
| `0x18` | `INIT_R1_POS` | RW | 32 | Rotor 1 Grundstellung (`0x00…0xFF`). |
| `0x1C` | `INIT_R2_POS` | RW | 32 | Rotor 2. |
| `0x20` | `INIT_R3_POS` | RW | 32 | Rotor 3. |
| `0x24` | `INIT_R4_POS` | RW | 32 | Rotor 4. |
| `0x28` | `DATA_IN` | RW | 32 | Stream input byte (low 8 bits). |
| `0x2C` | `DATA_OUT` | RO | 32 | Stream output byte (low 8 bits). |
| `0x30` | `STATUS` | RO | 32 | bit0: `VALID_OUT`. bit1: busy (optional). |
| `0x34` | `SCA_CTRL` | RW | 32 | bit0: enable stream jitter (DPA alignment break). |
| `0x38` | `BURST_STATUS` | RO | 32 | Last AXIS/SoftBus table burst byte count (2,560 when complete). |

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
| 9 | Un-reflector |

## Streaming contract

- Cipher body is reciprocal under the same day key + nonce.
- Wire/file containers use **HMAC-SHA512 AEAD** (verify tag before streaming into fabric).
- LFSR step enables use an **NLFF** fold, not raw bit taps.
- LFSR + offsets advance **after** the scramble for that beat.

## Related artifacts

- RTL core: `enigma_256_core.v`
- AXI4-Lite wrapper: `enigma_256_axi.v`
- AXIS table burst: `enigma_256_axis_tables.v`
- Soft MMIO + driver: `Enigma256SoftBus` / `Enigma256AXIDriver`
- AEAD + nonce guard: `Enigma256AEAD.swift` / `Enigma256ProtectedSession`
- Golden dump: `swift run helut --enigma256-golden`
- Core co-sim: `Scripts/enigma256_sim.sh`
- AXI co-sim: `Scripts/enigma256_axi_sim.sh`
