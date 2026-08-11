# Enigma 256 Core — Host Register Map

Software control plane programs `enigma_256_core` over a memory-mapped AXI-lite
(or equivalent) window. Addresses below are offsets from the core base. The
Swift bitbang model is `Enigma256CoreHandle` in `Enigma256Session.swift`.

## Bring-up sequence

1. **Reset** — assert `rst_n` low then high.
2. **Load tables** — for `wr_sel = 0…9`, write 256 bytes via `WR_*` (see table map).
3. **Load message key** — write `INIT_LFSR_*` and `INIT_R*_POS`.
4. **Pulse `LOAD_STATE`** — capture LFSR + Grundstellung into the stream engine.
5. **Stream** — present each byte on `DATA_IN` with `VALID_IN` for one cycle; read `DATA_OUT` when `VALID_OUT` is high (same cycle as the registered update in the RTL).

Do not assert `VALID_IN` during table writes or `LOAD_STATE`.

## Register map

| Offset | Name | Access | Width | Description |
|--------|------|--------|-------|-------------|
| `0x00` | `CTRL` | W1C / RW | 32 | bit0: pulse `LOAD_STATE` (W1C). bit1: reserved. bit8: soft reset (optional). |
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

Wire-level ports on the Verilog module map 1:1 to these fields; an AXI adapter
is responsible for strobing `wr_en` / `load_state` / `valid_in` for a single
cycle per commit.

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

Active-slot tables come from the day-key pool after message-key Walzenlage
selection (HKDF over IKM ∥ nonce). Host software (`Enigma256Context`) derives
tables; the fabric only stores the four active rotors plus plugboard/reflector.

## Streaming contract

- Cipher is reciprocal: encrypt and decrypt are the same operation under the
  same day key + nonce (reload tables/message key before the reverse pass).
- One plaintext/ciphertext byte per accepted `VALID_IN` beat.
- LFSR + offsets advance **after** the scramble for that beat (Swift oracle and
  RTL agree; see golden co-sim).

## Related artifacts

- RTL: `enigma_256_core.v`
- Bitbang: `Enigma256CoreHandle`
- Golden dump: `swift run helut --enigma256-golden`
- File crypt: `swift run helut --enigma256-crypt …`
