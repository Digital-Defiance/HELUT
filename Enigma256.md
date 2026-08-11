# Specification: Enigma 256 (Polymorphic Stream Cipher)

## Abstract

Enigma 256 is a software-defined, hardware-accelerated stream cipher that marries the physical state-machine constraints of historical rotor cryptography with modern asymmetric key exchange and evolutionary logic. By expanding the alphabet to a base-256 byte array, eliminating mechanical stepping flaws, and introducing ephemeral polymorphic wiring via a master key derivation pipeline, this architecture neutralizes all known cryptanalytic attacks against traditional rotor machines. Furthermore, the cipher is secured by a continuous evolutionary hardware loop powered by the HELUT (Homomorphic Edge Look-Up Tensors) engine.

## 1. Architectural Corrections (The Core Machine)

The original electro-mechanical design suffered from physical constraints that leaked mathematical truth. Enigma 256 engineers these flaws out of the state machine entirely.

- **Base-256 Byte Expansion:** The 26-letter alphabet is replaced by the full 256-value byte space (`0x00` to `0xFF`).
- **The Un-Reflector (Self-Mapping Permitted):** The historical reflector guaranteed a letter could never encrypt to itself. The Enigma 256 reflector is redesigned to permit self-mapping ($A \rightarrow A$), permanently blinding ciphertext-only and known-plaintext alignment attacks.
- **Full-Spectrum Plugboard:** The historical plugboard only swapped 10 pairs of letters. The Enigma 256 plugboard acts as a complete base-256 involution, perfectly swapping all 256 bytes into 128 pairs, creating an astronomical secondary search space.
- **Algorithmic LFSR Stepping:** Historical rotors stepped sequentially like an odometer, leaving the left-most rotors static during short transmissions. Enigma 256 drives rotor stepping via a 64-bit Galois LFSR whose **step enables pass through a non-linear filtering function (NLFF)** before advancing rotors.

## 2. Ephemeral Key Distribution (The Handshake)

The historical reliance on pre-printed codebooks allowed physical capture to compromise the network. Enigma 256 eliminates static keys through public-key infrastructure on the **control plane only** (never in the FPGA fabric).

- **Elliptic Curve Diffie-Hellman (ECDH):** Ephemeral **X25519** establishes a classical shared secret (`Enigma256ECDH.swift`).
- **Hybrid post-quantum KEM (macOS 26+):** `IKM_input = X25519_SS ‖ ML-KEM-768_SS` before HKDF (store-now-decrypt-later defense). Optional CryptoKit **X-Wing** path (`Enigma256Hybrid.swift`).
- **Authentication (MitM):** Long-term **Ed25519** identities sign hybrid HELLO/ACK transcripts (`Enigma256Auth.swift`).
- **Perfect Forward Secrecy:** Ephemeral keys and seeds are burned at session end (`burn()`).

## 3. State Initialization & Key Derivation

Extract-and-Expand Key Derivation uses **HKDF-SHA512** (RFC 5869). Domain labels: `enigma256-day-v2`, `enigma256-msg-v2`, `enigma256-ecdh-v2`, `enigma256-mac-v1`.

- **IKM sources:** ECDH, hybrid KEM, or **PBKDF2-HMAC-SHA512** passphrases. Default IKM width **64 bytes**.
- **Day-key OKM:** Fisher–Yates plugboard (128 pairs), 16-rotor virtual pool, self-mapping-permitted reflector.
- **MAC key:** Separate HKDF expand (`enigma256-mac-v1`) for AEAD tags — never reused as stream keying material.

## 4. Message Transmission, AEAD & Nonce Discipline

- **Active slot:** Per-message nonce → Walzenlage (4 of 16), Grundstellung, LFSR seed via micro-HKDF.
- **AEAD:** Wire and file containers (`E256` ver=2) carry **HMAC-SHA512** (32-byte truncated tag) over `nonce ‖ ciphertext`. Receivers **verify the tag before** any SoftBus/AXI stream into the FPGA — closing bit-flip malleability.
- **Nonce reuse ban:** `Enigma256ProtectedSession` packs `random[8] ‖ counter_be[8]` and rejects re-issue of the same nonce under one session key. Same IKM+nonce must never produce a second keystream.

## 5. Non-Linear LFSR Stepping (NLFF)

The stepping engine is a 64-bit Galois LFSR (primitive taps 64, 63, 61, 60 → feedback `0xD800_0000_0000_0000`).

Raw single-bit taps would leak LFSR state into observable rotor motion (Berlekamp–Massey). Instead, each step enable is a **non-linear fold**:

```
step_r1 = (lfsr[0]  & lfsr[7])  ^ lfsr[12]
step_r2 = (lfsr[15] & lfsr[22]) ^ lfsr[29]
step_r3 = (lfsr[31] & lfsr[38]) ^ lfsr[45]
step_r4 = (lfsr[47] & lfsr[54]) ^ lfsr[61]
```

Swift oracle (`Enigma256LFSR.stepMask`) and `enigma_256_core.v` agree. Scramble-then-step order is unchanged.

## 6. Evolutionary Hardware & Polymorphic Adversarial Loops

- **Red Team (HELUT):** Homomorphic Edge Look-Up Tensor engines breed alien netlists against the current generation.
- **Blue Team:** Monitors time-to-crack; mutates LFSR / pool generation and rolls updates to field fabric.

### 7. Commodity Silicon Deployment (COTS)

#### 7.1 Hardware Agnosticism

COTS SoCs with CPU (PS) + programmable logic (PL). No custom ASIC.

#### 7.2 The Hardware/Software Boundary

- **Control Plane:** Hybrid KEM / ECDH, Ed25519, PBKDF2, HKDF-SHA512, AEAD, nonce guard, `E2W1` wire, TCP.
- **Data Plane:** `enigma_256_core` BRAM + NLFF LFSR stream. Tables load via **AXI4-Stream burst** (`enigma_256_axis_tables.v`, 2,560 bytes) or legacy AXI-Lite beats. Optional **stream jitter** (`SCA_CTRL`) disrupts DPA trace alignment; full dual-rail / masked LUTs remain a high-assurance synthesis option.

#### 7.3 Decentralized Field Upgrades

Mutation parameters ship as software; nodes recompile and flash local fabric.

## 8. Implementation Status & TensorLUT Boundary

- **Oracle / core:** `Enigma256.swift` ↔ `enigma_256_core.v` (NLFF stepping). Golden co-sim: `Scripts/enigma256_sim.sh`.
- **Session / AEAD:** `Enigma256Context`, `Enigma256AEAD`, `Enigma256ProtectedSession`; `E256` ver=2 containers.
- **AXI:** Lite + **AXIS table burst** (`enigma_256_axis_tables.v` wired into `enigma_256_axi.v`; CTRL[1] arms). SoftBus burst + jitter. Co-sim: `Scripts/enigma256_axi_sim.sh` (default AXIS; `LITE=1` legacy).
- **Handshake:** X25519, hybrid ML-KEM / X-Wing, Ed25519-signed hybrid wire frames.
- **Wire / TCP / PSK:** `Enigma256Wire` (AEAD DATA). TCP default = **hybrid+AEAD** on macOS 26+ (`--enigma256-classical` for X25519-only; `--enigma256-passphrase` for PSK). Identity `--enigma256-identity` / `--enigma256-identity-out`; trust `--enigma256-trust`.
- **Yosys / TensorLUT:** FPGA path keeps BRAMs (`Scripts/enigma256_synth.sh`). Red Team NLFF cone (`Scripts/enigma256_tensorlut.sh`): baseline crypto 0; λ=0 explore + discrete polish recovers binary elite (`squeeze_survived: true` in `logs/tensorlut-enigma256-nlff.log`). Full-core BRAM soft-map deferred.
- **Red Team hold (updated):** Golden + AXI AXIS co-sim pass; TensorLUT is pointed at the NLFF cone on purpose — not a premature full-core melt.

## 9. Protocol gap closure

| Area | Vulnerability | Severity | Fix shipped |
|------|----------------|----------|-------------|
| LFSR stepping | Raw taps → Berlekamp–Massey | High | NLFF fold in core + Swift |
| Data integrity | Bit-flip malleability | High | HMAC-SHA512 AEAD; verify before fabric |
| Key state | Nonce-reuse keystream collision | Critical | Monotonic counter + reject reuse |
| Hardware bus | 2,560 AXI-Lite table writes | Medium | AXIS / SoftBus burst load |
| Side-channel | BRAM address DPA | Medium | Stream jitter + dual-rail noted for HA builds |
