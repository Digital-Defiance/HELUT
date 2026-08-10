# Specification: Enigma 256 (Polymorphic Stream Cipher)

## Abstract

Enigma 256 is a software-defined, hardware-accelerated stream cipher that marries the physical state-machine constraints of historical rotor cryptography with modern asymmetric key exchange and evolutionary logic. By expanding the alphabet to a base-256 byte array, eliminating mechanical stepping flaws, and introducing ephemeral polymorphic wiring via a master key derivation pipeline, this architecture neutralizes all known cryptanalytic attacks against traditional rotor machines. Furthermore, the cipher is secured by a continuous evolutionary hardware loop powered by the HELUT (Homomorphic Edge Look-Up Tensors) engine.

## 1. Architectural Corrections (The Core Machine)

The original electro-mechanical design suffered from physical constraints that leaked mathematical truth. Enigma 256 engineers these flaws out of the state machine entirely.

- **Base-256 Byte Expansion:** The 26-letter alphabet is replaced by the full 256-value byte space (`0x00` to `0xFF`).
- **The Un-Reflector (Self-Mapping Permitted):** The historical reflector guaranteed a letter could never encrypt to itself. The Enigma 256 reflector is redesigned to permit self-mapping ($A \rightarrow A$), permanently blinding ciphertext-only and known-plaintext alignment attacks.
- **Full-Spectrum Plugboard:** The historical plugboard only swapped 10 pairs of letters. The Enigma 256 plugboard acts as a complete base-256 involution, perfectly swapping all 256 bytes into 128 pairs, creating an astronomical secondary search space.
- **Algorithmic LFSR Stepping:** Historical rotors stepped sequentially like an odometer, leaving the left-most rotors static during short transmissions. Enigma 256 drives rotor stepping via a non-linear Galois Linear Feedback Shift Register (LFSR). All rotors step simultaneously and unpredictably on every byte.

## 2. Ephemeral Key Distribution (The Handshake)

The historical reliance on pre-printed codebooks allowed physical capture to compromise the network. Enigma 256 eliminates static keys through public-key infrastructure.

- **Elliptic Curve Diffie-Hellman (ECDH):** Sending and receiving nodes execute an open ECDH handshake to establish a shared mathematical secret over an insecure channel.
- **Perfect Forward Secrecy:** Upon termination of the transmission or session, the ephemeral private keys and resulting seeds are permanently burned from memory. Hardware capture yields no historical decrypt capabilities.

## 3. State Initialization & Key Derivation

To initialize the Enigma 256 state machine, the protocol utilizes an Extract-and-Expand Key Derivation architecture (HKDF / RFC 5869).

- **Input-Agnostic Extraction:** The system accepts Initial Keying Material (IKM) from any source (ECDH secret, codebook, etc.). Human-readable passphrases must first be processed through a computationally intensive function like PBKDF2 or Argon2.
- **HKDF Expansion (The Day Key Blueprint):** The HKDF `Expand` module expands the extracted pseudorandom key into a deterministic, high-entropy stream of Output Keying Material (OKM). This stream dictates the heavy, static physical state of the machine for the session.
  - **The Base-256 Plugboard (128 Bytes):** The stream drives a deterministic Fisher-Yates shuffle to pair all 256 byte values.
  - **The Virtual Rotor Pool (4,096 Bytes):** The stream drives Fisher-Yates shuffles to generate 16 completely distinct 256-byte core rotors.
  - **The Reflector (256 Bytes):** The stream generates the single self-mapping reflector.

## 4. Message Transmission & The Active Slot (Walzenlage)

To avoid regenerating the heavy 4-kilobyte rotor pool for every packet, the protocol resurrects the historical concept of the "Message Key."

- **The Nonce:** Every transmission is prepended with a random, plaintext IV/Nonce.
- **Message State Selection:** The Nonce is combined with the master secret to quickly derive a micro-stream of configuration bytes for that specific message:
  - **Rotor Selection & Order:** Selects 4 active rotors out of the 16-rotor Virtual Pool, establishing the *Walzenlage* (Wheel Order).
  - **Grundstellung:** Sets the initial rotational starting positions (`0x00` to `0xFF`) for the 4 active rotors.
  - **LFSR Seed:** Initializes the 64-bit Galois LFSR state.

## 5. Non-Linear LFSR Stepping Mechanism

The Enigma 256 stepping engine is decoupled from the rotors themselves. It is driven by a 64-bit Galois LFSR, which operates using internal XORs and allows for parallel tap computation, massively increasing throughput over conventional Fibonacci configurations.

- **Primitive Polynomials:** To ensure maximum-length periods before the stepping pattern repeats, the LFSR is governed by primitive polynomials over the Galois field GF(2).
- **The Stepping Clock:** For every byte of plaintext ingested, the LFSR clocks. The resulting output bits dictate precisely which of the 4 active rotors step forward, ensuring dynamic, highly non-linear positional shifts that completely destroy the static-rotor assumptions historically relied upon by the Welchman diagonal board.

## 6. Evolutionary Hardware & Polymorphic Adversarial Loops

To guarantee that Enigma 256 outpaces advancements in automated cryptanalysis, its silicon execution is secured by a continuously operating "Red Team vs. Blue Team" evolutionary algorithm pipeline.

- **The Red Team (HELUT Cryptanalysis):** A massive array of **Homomorphic Edge Look-Up Tensor (HELUT)** engines acts as the automated adversary. The HELUT engine uses genetic algorithms to breed "alien" Boolean netlists, aggressively mutating its own Metal compute shaders to find early-exit logic, zero-cycle SAT predictors, and optimized menu graph topologies capable of breaking the current Enigma 256 generation.
- **The Blue Team (Polymorphic Logic Generator):** An evolutionary logic generator oversees the Enigma 256 silicon. It constantly monitors the Red Team's "time-to-crack" metrics.
- **Automated Threat Mutation:** If HELUT evolves a tensor reduction that brings the decryption time below an acceptable operational threshold, the Blue Team instantly reacts. It procedural breeds new LFSR stepping taps, modifies the procedural rotor generation algorithms, and rolls the polymorphic updates directly to the field hardware. This creates a living cipher—a software-defined state machine that continuously rewrites its own physical DNA to outrun the algorithms hunting it.

### 7. Commodity Silicon Deployment (COTS)

#### 7.1 Hardware Agnosticism

Enigma 256 is designed strictly for Commercial Off-The-Shelf (COTS) System-on-Chip (SoC) architectures containing both a traditional CPU (Processing System) and programmable gate arrays (Programmable Logic). It requires no custom ASIC fabrication.

#### 7.2 The Hardware/Software Boundary

- **The Control Plane (Software):** Ephemeral key exchange (ECDH), Master Secret derivation (PBKDF2/Argon2), and HKDF expansion are executed purely in software on standard ARM/RISC-V cores. This allows the system to leverage existing, peer-reviewed open-source cryptographic libraries for network handshakes.
- **The Data Plane (Hardware):** The expanded HKDF stream is pushed via standard AXI memory-mapped interfaces to the FPGA fabric. The `enigma_256_core` executes entirely in programmable logic, ensuring gigabit throughput and physical isolation from the host operating system.

#### 7.3 Decentralized Field Upgrades

Because the cipher relies on polymorphic logic rather than static physical hardware, the "mutation parameters" (such as new LFSR polynomial taps or modified HKDF expansion rules) can be pushed as over-the-air software updates. The receiving node simply recompiles the Verilog bitstream locally and flashes its own FPGA fabric, fundamentally altering the physical execution of the cryptography without requiring new hardware deployment.

