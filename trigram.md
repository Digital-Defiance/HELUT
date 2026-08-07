# Final Phase: The Post-Bombe Discriminator

## Context
Our Metal-accelerated Welchman Diagonal Board is fully operational and works perfectly. By running 18 to 24-letter cribs (like `UUUVIRSIBENNULEINS`), it successfully reduces 143.7 billion M4 rotor settings down to a handful of survivors (usually 6 to 12). 

However, 18 letters is just short of the unicity distance, meaning it leaves "ghost" solutions. These ghosts perfectly satisfy the 18-letter plugboard constraint, but the remaining 54 letters of the decrypt degrade into random noise (e.g., `UUUEIRIIVENNULEINCMBV...`).

## Objective
Write a `PostBombeDiscriminator` in Swift that hooks into the output of our Welchman sweep. It will take the handful of survivors from the SAT solver, decrypt the full 72-letter ciphertext, and use our authentic naval trigram tables to automatically identify the true key from the ghosts.

## Implementation Steps

### 1. Hook the Welchman Output
In `BombeSweep.swift` (or where the Welchman board emits its confirmed survivors), intercept the `BombeSurvivor` objects before they are printed to the console.
- We already have the deduced 10-plug Steckerboard.
- We already have the exact UKW, Greek Wheel, Wheel Order, Rings, and Starting Position.

### 2. Full Decryption
For each survivor, initialize an `EnigmaM4` instance with those exact deduced settings.
- Run the full 72-letter target ciphertext (`JCRSA...HVGF`) through the machine to get the full 72-letter plaintext string.

### 3. The Trigram Sieve
- Pass the full 72-letter plaintext into our existing authentic Enigma-decrypt trigram scorer. 
- **Crucial Logic:** We don't care about the score of the crib portion (we know that part is valid). The discriminator must evaluate the *entire* string, punishing the ghost solutions whose non-crib tails devolve into random letter distributions.

### 4. Output the Winner
- Rank the survivors by their trigram score.
- The ghost solutions will score near the noise floor for the last 54 letters. The true key will have a massively elevated score because the tail will contain authentic German syntax.
- Print the #1 ranked survivor in a highly visible "POTENTIAL BREAK" terminal block, displaying the full plaintext, the exact settings, and the recovered Grundstellung/Message Key.

## Rules
- Do not touch the Metal kernel. The GPU logic is locked and perfect.
- Keep the logic synchronous and appended only to the end of the batch run.