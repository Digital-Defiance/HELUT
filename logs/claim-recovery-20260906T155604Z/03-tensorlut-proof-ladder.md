# Receipt 03 — TensorLUT bounded proof ladder

Result: **PASS on the named fixtures, with an explicit search/resource boundary**  
Artifact: prebuilt `helutPackageTests` bundle  
SHA-256: `d339f1933249d51d808000df2e4ce0312029f00e2060896579537df8fb925ce6`

## A. Implementation-level formal certificate

```bash
xcrun xctest -XCTest \
  HELUTTests.TFHESeamTests/testTensorLUTFormalCertificate \
  .build/arm64-apple-macosx/release/helutPackageTests.xctest
```

Observed: 1 test, 0 failures, 0.001 seconds; child return code `0`.

Defensible claim: the six stated implementation-level checks for the objective, MSE term, binary penalty, threshold emitter, involution structure, and freeze-mask exclusion hold under the certificate's hypotheses. This is not GA convergence or arbitrary-netlist completeness.

## B. Full melt-scaling suite

```bash
xcrun xctest -XCTest \
  HELUTTests.TensorLUTMeltScalingTests \
  .build/arm64-apple-macosx/release/helutPackageTests.xctest
```

Observed: 5 tests, 0 failures, 125.522 seconds; child return code `0`.

### Fixed 4-bit, 8-LUT adder; growing melt region

At the 120-generation/population-48 budget:

- 2/8 melted: `PROVED`, fitness `0`, zero fractional entries; erased baseline `REFUTED`.
- 4/8 melted: `PROVED`, fitness `0`, zero fractional entries; erased baseline `REFUTED`.
- 6/8 melted: `PROVED`, fitness `0`, zero fractional entries; erased baseline `REFUTED`.
- 8/8 melted: `REFUTED`, fitness `-16`, zero fractional entries.

For the same 8/8 cold start, increasing the budget from 120 to 500 generations changed the fixture result from `REFUTED` to `PROVED` with fitness `0` and zero fractional entries. This is a measured budget lever on one deterministic fixture, not completeness.

### Sampled 8-bit, 16-LUT adder; top two LUTs erased

- 64/65,536 training rows (0.10%): `PROVED`, fitness `0`; search 7.29 seconds.
- 256/65,536 (0.39%): `PROVED`; search 8.28 seconds.
- 1,024/65,536 (1.56%): `PROVED`; search 11.75 seconds.
- Every emitted searched result was checked over the full Boolean domain by Yosys/SAT; every erased baseline was `REFUTED`.

Defensible claim: on this fixed ripple-adder fixture, search did not enumerate the input domain, yet the emitted discrete result was independently proven equivalent over all 65,536 assignments. The test's printed phrase `search cost DECOUPLES from input space` is treated as a fixture label, **not** accepted here as an asymptotic or general complexity theorem.

### Resource result

The hand-designed 4-bit source contained 8 TensorLUT cells and mapped to 6 LUTs under the stated `abc -lut 6` recipe. The discovered 2/8, 4/8, and 6/8 variants also mapped to 6 LUTs. Result: **no LUT-count difference under this recipe**. No area, depth, power, timing, or physical implementation win follows.

## C. Sequential repair

```bash
xcrun xctest -XCTest \
  HELUTTests.TensorLUTYosysRoundTripTests/testMeltedSequentialTransitionIsRediscoveredAndFormallyProven \
  .build/arm64-apple-macosx/release/helutPackageTests.xctest
```

Observed: 1 test, 0 failures, 9.885 seconds; child return code `0`.

Markers:

```text
TENSORLUT_SEQUENTIAL_EQUIV ok: erased transition refuted; search recovered q_next=q XOR x behind 1 DFF; post-ABC equiv_induct proved every matched Boolean state and all enable/reset/input combinations
TENSORLUT_SEQUENTIAL_EQUIV negative control: one discovered INIT bit flipped; induction left Q unproved and bounded SAT produced the reset → x=0 → divergent-Q counterexample
```

Defensible claim: for the named positive-edge one-DFF transition relation, search recovered the erased XOR next-state LUT and post-ABC induction proved the matched Boolean transition; a one-bit corruption produced a concrete divergence trace.

## Combined public boundary

Analytic completeness remains limited to the stated separable/snap hypotheses. End-to-end SAT-backed repair now extends beyond two tables on bounded ripple-adder fixtures and includes one narrowly defined DFF transition. Arbitrary topology, GA completeness, coupled state machines, and general logic simplification remain open.