# E256-X0 proof-carrying H4 evolution policy

<!-- E256-X0-H4-EVOLUTION-CONTRACT-START -->
## X0.1 Status, predecessor, and freeze boundary

This marker is the frozen pre-implementation contract for **E256-X0**, a pure-standard-library, exact-integer transition-policy certificate over the already certified E256-H H4 row-offset catalog. X0 is a proof-carrying policy experiment: it derives the complete safe-transition graph, verifies a deterministic twelve-selector path certificate, and records graph diagnostics. It does not change the cipher, select a production schedule, or promote E256-063.

The predecessor H4 sequence receipt is `logs/e256-hardware-h4-sequence-gate.json`, raw SHA-256 `9d06dcca6d83d1f9bcc04806f8fbb1e12cf7b66f390069fe3b4ad90edeaf34e6`, deterministic-payload SHA-256 `4562482417cb2917208cf37f8c4441efbdde602230d878ba49d249b017822064`, and complete-record SHA-256 `4e53a53caa1da8bee7f45c572f6208624fd02703d358cdfb52ca9a31c98e0bae`. It validly found 737,280 failing placements among 1,474,560 mixed three-round windows in the preregistered arithmetic family. The first witness remains printed in that receipt and in the H4 architecture record. This adverse result parks unrestricted arithmetic switching; it does not imply that every transition policy fails.

After that receipt was banked, a read-only exploratory regrouping disclosed that `d=0` was the only arithmetic stride with zero failed window classes. That fact is prior disclosure, not an X0 blind prediction. X0 must reconstruct it exactly from the complete prior census mapping and label it as such.

At this freeze point, `directives/e256-x0-h4-evolution-preregistration.json`, `Scripts/e256_x0_h4_evolution_gate.py`, `logs/e256-x0-h4-evolution-gate.json`, and `build/e256-x0-h4-evolution/` did not exist. No X0 output or diagnostic had been executed or selected. The machine preregistration must be written and its raw SHA-256 recorded outside this marker before implementation begins. Existing H4 RTL, testbench, runner, preregistration, receipt, and architecture marker are immutable predecessors, not X0 implementation files.

## X0.2 Frozen catalog and exact compositional law

Let `C[0]...C[383]` be the exact ordered `deterministic_payload.results.h4_wiring.certified_set` from `logs/e256-hardware-candidate-gate.json`. Its canonical compact-JSON SHA-256 is `199f1f7bddccf19ce5aa0bde0987441735d628354140d53ebdfec538d7b3f5ed`; its first, fixed, and last entries are respectively `(0,1,2,5)`, `(0,1,3,4)` at index 1, and `(7,6,5,2)`. There are 384 ordered tuples: all 24 row permutations of each of 16 four-element supports. Catalog order and tuple order are load-bearing.

For a tuple `w=(w_0,w_1,w_2,w_3)`, write `S(w)={w_0,w_1,w_2,w_3}` in `Z_8`. For three actual round selectors `x,y,z`, exact literal dependency propagation gives this column law: output column `c` depends on original-row-`a` columns

`{ c + x_a + y_b + z_k mod 8 : b,k in {0,1,2,3} }`.

Consequently, all 32 output bytes depend structurally on all 32 input bytes if and only if

`S(y) + S(z) = Z_8`.

The criterion is independent of `x`; it says nothing about value cancellation or active-S-box counts. X0 must establish this law by agreement between two separately implemented oracles:

1. an 8-bit support-mask sumset oracle using modular rotations; and
2. literal three-round, 32-lane dependency propagation using the actual ordered tuples and all-nonzero AES MixColumns support.

The literal oracle must grade all 147,456 ordered `(i,j)` pairs using `[C[0],C[i],C[j]]`, with no filtering. Exact dependency vectors, not only pass/fail bits, must agree with the closed-form law. First-selector invariance must additionally be checked for all 384 first selectors across all 256 ordered support-class pairs. Translation invariance must be checked for all eight translations of every ordered support-class pair.

## X0.3 Canonical safe graph and root

The safe graph has nodes `0...383` in certified-list order and directed edge `i -> j` exactly when `S(C[i])+S(C[j])=Z_8`. The relation is expected to be symmetric as a consequence of commutative addition, but the encoder and verifier must retain directed rows and test symmetry rather than assume it.

The canonical edge bitset is 384 consecutive rows of 48 bytes. Destination `j` is encoded in row `i`, byte `j//8`, bit `1 << (j%8)`; unused bits do not exist because 384 is byte-aligned. The complete bitset is exactly 18,432 bytes. Its graph root is

`SHA256("E256-X0/H4-safe-graph/v1" || 0x00 || u16be(384) || raw32(certified_list_sha256) || edge_bitset)`.

The receipt carries schema `E256-X0-H4-SAFE-GRAPH-1`, the exact bitset hex, bitset SHA-256, graph root, row count, row-byte count, and edge count. A verifier must reconstruct every row and root from the frozen catalog; it must not trust supplied edges, degrees, or witnesses.

The prior arithmetic census provides a consistency fact, not a blind X0 prediction: for `(b,d)` the transition controlling the three-round class is `(i,j)=(b+d,b+2d) mod 384`, with inverse `d=j-i mod 384` and `b=2i-j mod 384`. X0 must prove that this is a bijection over all 147,456 classes, recover exactly 73,728 safe and 73,728 unsafe ordered pairs, recover exactly 737,280 failed placements after the frozen factor of ten, reproduce the prior first witness, and recover the disclosed zero-failure stride set. Any disagreement invalidates the harness.

## X0.4 Frozen diagnostics and support quotient

Diagnostics are outcomes, not selection thresholds. X0 must record:

- complete directed in-degree and out-degree vectors and exact histograms;
- loop, off-diagonal, same-support, and support-changing directed edge counts;
- symmetry, edge-count, row-width, and graph-root closure;
- deterministic strongly connected components of the full 384-node graph;
- the first unsafe ordered pair in lexicographic `(i,j)` order;
- the first support-changing safe two-cycle in lexicographic `(i,j)` order with `i<j`;
- the exact 16-node support quotient, whose nodes are support masks in ascending numeric order and whose edge rule is the same modular sumset criterion;
- deterministic strongly connected components of that quotient;
- an exact dynamic-programming search for the lexicographically least quotient Hamiltonian cycle anchored at quotient node 0, including the closing edge; and
- exact full-graph walk counts `sum(A^k)` for `k in {1,2,3,11}`. Each count is accompanied only by integer `floor(log2)` and `ceil(log2)` bounds computed from bit lengths; floating point is forbidden.

Both `FULL_SUPPORT_QUOTIENT_HAMILTONIAN_CYCLE_FOUND` and `FULL_SUPPORT_QUOTIENT_HAMILTONIAN_CYCLE_NOT_FOUND` are valid graded outcomes. One versus multiple SCCs is likewise a finding. Missing an SCC or cycle observation is a validity failure.

## X0.5 Proof-carrying twelve-selector path

The path-certificate schema is `E256-X0-H4-PATH-CERTIFICATE-1`. It contains the safe-graph root, exactly twelve catalog indices, and exactly twelve matching 12-bit tuple codes, where tuple `(o_0,o_1,o_2,o_3)` encodes as `o_0 | (o_1 << 3) | (o_2 << 6) | (o_3 << 9)`.

Path selection is deterministic and cannot cherry-pick after execution. If the quotient Hamiltonian cycle exists, take its first twelve quotient nodes and lift each to the lowest catalog index with that support. Otherwise, take the lexicographically first support-changing safe two-cycle and alternate its endpoints to length twelve; if no such pair exists, repeat the lowest safe loop to length twelve. The known prior edge count makes absence of every fallback edge an integrity contradiction.

The verifier reconstructs the catalog, graph bitset, and root; checks all indices and tuple codes; and independently checks all eleven adjacent transitions. It trusts no supplied edge witness. Repeated nodes are legal and reverse-path rejection is forbidden because the graph is symmetric. A passing certificate proves only that every contiguous three-round window represented by those adjacent transitions has structural all-to-all byte dependency. It does not certify a four-round activity bound or a production round schedule.

## X0.6 Frozen controls and validity

Every control below must be detected through the same strict loaders, algebraic oracles, graph decoder, root verifier, diagnostic checker, or path verifier used by the main result:

1. reorder two catalog entries;
2. supply a stale catalog hash;
3. mutate one tuple element;
4. duplicate one tuple offset;
5. insert an out-of-range tuple offset;
6. use `S(x)+S(y)` instead of `S(y)+S(z)`;
7. use XOR instead of addition in the sumset;
8. use the wrong modulus;
9. omit one support element;
10. flip one graph bit;
11. reverse destination-bit order within each byte;
12. omit one graph row;
13. duplicate one graph row;
14. supply a stale graph root;
15. forge a graph root over mutated bytes;
16. insert the first unsafe edge;
17. remove the first safe edge;
18. filter one ordered pair from the 147,456-pair corpus;
19. mismatch one tuple code and catalog index;
20. use an out-of-range path index;
21. truncate the path;
22. insert the known first unsafe transition;
23. omit the required SCC/cycle observation.

Catalog mutation controls must fail before graph acceptance. Graph-byte controls must fail reconstruction or root closure. Path controls must fail certificate verification rather than being silently repaired. Harness validity requires exact predecessor/source identities, strict duplicate-key/non-finite JSON rejection, exact catalog order and hash, complete 147,456-pair algebraic/literal agreement, exact prior-census reconstruction, canonical graph encoding/root closure, every required diagnostic, a verified twelve-selector certificate with eleven safe transitions, all 23 controls detected, and deterministic receipt reproduction. Adverse SCC or Hamiltonian findings do not invalidate an otherwise complete harness.

## X0.7 Receipt, verdicts, and non-claims

The receipt schema is `E256-X0-H4-EVOLUTION-GATE-1`, status `OPEN_PROGRESS`, at `logs/e256-x0-h4-evolution-gate.json`. The scratch directory is `build/e256-x0-h4-evolution/`. The only Make entry points are `make e256-x0-h4-evolution` and `make e256-x0-h4-evolution-check`. The deterministic payload sections, in addition to schema and status, are exactly `integrity`, `catalog`, `algebraic_equivalence`, `prior_census_reconstruction`, `safe_graph`, `support_quotient`, `diagnostics`, `path_certificate_controls`, `verdicts`, and `non_claims`. The payload digest is SHA-256 of canonical compact sorted-key JSON. The complete-record hash is computed with `record_sha256` set to null. `--check` must regenerate and compare byte-identical deterministic payload bytes and digest.

A valid receipt reports `SAFE_TRANSITION_GRAPH_DERIVED_AND_PATH_CERTIFIED` once graph closure and the twelve-selector certificate pass, independently of SCC/cycle findings. That verdict is a bounded structural policy result only. X0 deliberately stops before any mixed four-round/25-active-S-box claim and leaves open differential, linear, truncated-differential, integral, algebraic, cube, related-key, cancellation/value-feasibility, side-channel, and fault analysis. It selects no production round count, schedule, evolution rule, key/XOF derivation, architecture, storage organization, RTL enforcement mechanism, Metal/FHE path, physical FPGA target, suite, protocol, security level, or standard.

The existing `wide_trail_manifest` is fixed-selector/local and contains literal proof-obligation booleans; it has no mixed-walk input and cannot certify X0 walks. X0 is pure standard-library host analysis. It is not RTL, Yosys, vendor place-and-route, Metal, encrypted execution, FHE, or a self-modifying cipher. Standard reviewed AEAD remains mandatory for real data. E256-063 remains OPEN. No C/H/N row, claim epoch, site assertion, campaign record, or video voiceover moves merely because X0 executes.
<!-- E256-X0-H4-EVOLUTION-CONTRACT-END -->

**X0 preregistration freeze.** The machine-readable preregistration was written after the inclusive marker above and before any X0 runner, receipt, or scratch artifact. Its raw-file SHA-256 is `d39759bc2677fa17227ea129fc3ec20791a749cec2b9cdd33aa18c45df338711`; the immutable inclusive marker SHA-256 it pins is `1ef354e9b933838eb3e74b32b202e4693f1bfdd62379f10dbc6a8673b3383962`.

## X0.8 Execution result — safe graph with two closed support components (OPEN)

The frozen gate executed validly and reproduced with `make e256-x0-h4-evolution-check`. Receipt `logs/e256-x0-h4-evolution-gate.json` has schema `E256-X0-H4-EVOLUTION-GATE-1`, status `OPEN_PROGRESS`, raw-file SHA-256 `8db5f21b6e0a7249fa9b558c02a989324911575e91704b5e096e2749744ac2c9`, deterministic-payload SHA-256 `35060c802427046f5f4630c6b9db6401d8ac90c4649fc0cf088d3f35f31b1b44`, and original complete-record SHA-256 `3b77fa3747818ed974e39b67b54cbbeeeb6b442bf5781b4e7f846776a96c8110`. The standard-library runner source SHA-256 is `d011419ca4a712101481162748c4fcafe960d733582ffd2e2fd635f7a99fd602`.

Both independent implementations closed exactly: all **147,456** ordered catalog pairs had byte-for-byte agreement between literal three-round dependency propagation and the law `S(y)+S(z)=Z8`; **98,304** first-selector cases and **2,048** translations also agreed. The resulting 18,432-byte graph bitset has SHA-256 `33752c5f7a689fbeb031b0a5b7f8e80b0849dc4d8962ce04a74e1f73bb5fe0c3` and root `d7e44b625acc693a28469dd993edfe3bf8cd7a4b966275a70ad7cf3941e4a80a`.

Exactly **73,728/147,456** directed pairs are safe under this structural criterion. Every catalog node has in-degree and out-degree 192. The directed counts are 384 loops, 73,344 off-diagonal edges, 9,216 same-support edges, and 64,512 support-changing edges. The full graph splits into **two 192-node SCCs**. Its 16-node support quotient likewise splits into **two 8-node SCCs**, and the preregistered exact subset DP returned **`FULL_SUPPORT_QUOTIENT_HAMILTONIAN_CYCLE_NOT_FOUND`**. This is a valid adverse topology finding: no safe walk can cross those support components, so X0 does not provide one cycle covering all 16 supports.

The frozen fallback rule therefore emitted the twelve-selector certificate `[0,3,0,3,0,3,0,3,0,3,0,3]`, alternating tuples `(0,1,2,5)` and `(0,1,4,7)` with tuple codes 2696 and 3848. The verifier reconstructed the catalog, graph, and root and accepted **11/11** adjacent transitions without trusting supplied edge witnesses. This proves only that those eleven represented contiguous three-round windows have structural all-to-all byte dependency.

The prior arithmetic census reconstructed exactly: 73,728 failed classes, 737,280 failed placements, the original first witness, and disclosed zero-failure stride set `[0]`. All **23/23** planted controls were detected. Exact walk counts and integer-only log bounds are retained in the receipt; they are combinatorial counts, not attack work factors.

The machine verdict is **`SAFE_TRANSITION_GRAPH_DERIVED_AND_PATH_CERTIFIED`**, but no production policy is selected. In particular, the two-component graph and alternating fallback path are not a self-evolving cipher, schedule recommendation, mixed four-round/25-active-S-box theorem, security result, RTL enforcement mechanism, Metal/FHE execution, or physical-hardware result. Differential, linear, truncated, integral, algebraic, cube, related-key, cancellation/value-feasibility, side-channel, and fault work remain open. **E256-063 remains OPEN**, no C/H/N row or public epoch moves, and reviewed standard AEAD remains mandatory for real data.
