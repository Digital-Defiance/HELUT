# Security

HELUT is a **research** stack (netlist-clocked torus FHE, TensorLUT, Enigma256 SoftBus, and a historical Enigma campaign). It is **not** a production key-management product.

## What this repo is not claiming

- Production security from the calibrated ~176-bit HELUT figure. Quote **C23** / **H1**: prod-n1024-s16 is HELUT 175.7 vs Sage estimator 180.2; four other anchors disagree by >16 bits.
- That trivial / oracle Metal graphs are FHE.
- A decrypt of P1030680 / U-534. Campaign negatives stay printed (`BREAK_P1030680.md`).
- Side-channel or quantum analysis.

Author's note: [`OPPENHEIMER.md`](OPPENHEIMER.md).

## Reporting

If you find a **vulnerability in this software** (RCE, secret leak in the repo, unsafe default that contradicts the claim sheet):

- Open a GitHub security advisory on [Digital-Defiance/HELUT](https://github.com/Digital-Defiance/HELUT), or
- Email Digital Defiance through the contact on [digitaldefiance.org](https://digitaldefiance.org).

Please do **not** file a “you haven’t broken P1030680” issue as a vulnerability. That is an open historical problem (**H7**), not a CVE.

Do not send production secrets or third-party ciphertexts you are not authorized to process.
