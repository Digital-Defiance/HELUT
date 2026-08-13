Here is four-dimensional, speculative territory for **after** the reproducible core
(see `research-trajectory.md`). None of this is a current claim — no SING log, no
certificate, no campaign grade until an avenue graduates into `REPRODUCE.md`.

### 1. "Prompt Injection Immunity": Genetically Evolving Zero-Knowledge LLM Guardrails (`fhe-evolve` + Local LLMs)

- **The Concept:** Right now, people try to stop LLM prompt injections using other LLMs or brittle system prompts. What if you evolve a tiny neural or logic-gate firewall in the *encrypted* domain (`fhe-evolve`) that sits between an untrusted user prompt and a local model (Ollama)?
- **Why it’s crazy:** The firewall circuit evaluates completely in the dark on raw token tensors. It doesn't just scan for regex patterns; it mutates its own boolean gate topology using evolutionary algorithms (`fhe-evolve`) based on adversarial inputs it successfully blocked. You are training an AI defense system using genetic mutation over homomorphic ciphertexts where **neither the user prompt, the model weights, nor the defense mutation rules are ever decrypted in memory.**

### 2. The "Dark Web of Code": Self-Mutating Encrypted Binaries (`HELUT` + `PicoRV32`)

- **The Concept:** You already booted an encrypted RISC-V core (`picorv32`) inside an `MPSGraph`. What happens if you feed that CPU a binary that rewrites its own instructions while remaining fully encrypted?
- **Why it’s crazy:** You build a polymorphic, self-modifying software engine that executes inside an Apple Neural Engine. The host machine running the NPU sees a uniform stream of tensor multiplications, but inside the dark virtual machine, the CPU is decrypting, mutating, and executing code that the underlying operating system cannot inspect, debug, or breakpoint. You are running **malware-class self-modification physics inside an AI hardware accelerator for privacy**.

### 3. Distributed "Neural" Honey-Tokens: Decentralized Zero-Knowledge Surveillance Traps (BrightChain Integration)

- **The Concept:** Take the batched regex search (`Application #2`) and BrightChain's zero-knowledge ledger architecture. Imagine deploying a "honey-token" ledger where 100,000 corporate documents are continuously searched against thousands of attacker patterns *simultaneously in a single encrypted tensor pass* every time a node syncs.
- **Why it’s crazy:** Instead of a server scanning logs for data exfiltration, the global ledger itself is a living, breathing neural/logic tensor graph. If an attacker queries the encrypted database, the database doesn't just return data—it evaluates an encrypted trapdoor circuit that triggers a defensive state transition across the decentralized mesh **without the storage node ever knowing what file was searched or what trigger was tripped.**

### 4. Genetic Hardware Synthesis: Evolving Circuit Netlists on the Fly (`fhe-evolve` + Yosys)

- **The Concept:** Instead of writing Verilog by hand and passing it to Yosys, you use `fhe-evolve` to mutate truth tables and gate connections directly, compiling them dynamically via Yosys API bindings into `MPSGraph` loops to solve complex optimization problems on the fly.
- **Why it’s crazy:** The software rewrites its own hardware architecture while running. If the M4 Max encounters a new type of encrypted stream, the system uses genetic algorithms to evolve a custom ASIC gate-netlist in memory, compiles it into `MPSGraph` seconds later, and processes the stream through hardware it just invented.

### 5. Metal-Tick DPA: BGPUcap Power on Live Graphs Only (`bgpucap` + Controlled Fixtures)

Parked mid-term pillar from `research-trajectory.md` — not a claim until fixtures, sync, and attack grades land in `REPRODUCE.md`.

- **The Concept:** Treat the live Metal / `MPSGraph` FHE pipeline as the device under test. Capture GPU-side power (bgpucap-style) **only** while a known, tick-synchronized Metal graph is executing controlled fixtures — fixed plaintext/ciphertext pairs, fixed key schedules, fixed netlist clocks — so traces align to graph ticks rather than wall-clock noise. Run classical differential power analysis (and related CPA/MIA variants) against those aligned traces to try to break or surface weaknesses in existing algorithms as they actually run on Apple silicon (bootstrap, blind rotate, LUT eval, Enigma256 SoftBus paths, etc.).
- **Scope guardrails:** Live Metal graphs only (no offline synthetic power models as the attack surface); controlled fixtures only (no opportunistic capture of arbitrary workloads); tick sync is mandatory so differentials are gate-/LUT-phase aligned.
- **Why it’s crazy:** Homomorphic evaluation is supposed to look like uniform tensor math to the host. If Metal-tick–synced power still leaks key- or plaintext-dependent structure through bgpucap, you are doing side-channel cryptanalysis against FHE *as deployed on an NPU/GPU graph*, not against a textbook circuit in SPICE. A successful distinguish or key-recovery grade would be a new class of “encrypted but still radiates” finding; a clean negative on honest fixtures is also science — it hardens the claim that the graph is power-flat under the fixture set.