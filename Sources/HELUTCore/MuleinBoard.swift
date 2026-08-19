import Foundation

// MARK: - The Mulein board: a diagonal board that counts contradictions
//
// ## What this is
//
// A **deletion-tolerant diagonal board**. Given a menu and a candidate rotor setting, it does
// not ask "is this setting consistent?" but:
//
//     How few menu edges must be deleted before this setting closes consistently?
//
// If at most `tolerance` deletions suffice, the setting survives. `tolerance == 0` is
// Welchman's board exactly, bit for bit.
//
// It occupies the same structural slot Welchman's diagonal board did. Turing built the bombe;
// Welchman added a board that changed what the bombe would accept. This adds another board to
// the same machine — it is not a new bombe, and it is deliberately named for the board rather
// than the engine. The engine (kernel, escalator, climber) is a separate thing.
//
// ## Why relays cannot do this, even slowly
//
// This is the part that makes it a *mechanism* rather than an optimisation. On the physical
// bombe a contradiction **is** current finding a second path through the diagonal board: the
// hypothesis short-circuits and the drum advances. Copper cannot answer "how many
// contradictions?" — the relay either lights or it does not. There is no register to count in,
// and no way to ask a wire to keep going after it has already conducted.
//
// Every faithful reimplementation inherits that limitation, including
// `WelchmanBombe.propagate`, which returns `nil` on the first doubled row. That is not a bug;
// it is fidelity. But it is fatal in the presence of garble.
//
// ## Why that matters for this campaign
//
// A single mis-transcribed ciphertext letter contradicts a **true** menu, and an exact board
// then discards the real key without comment. Girard needed two independent transcripts to
// degarble the sister message P1030681, and found an entire four-letter group (`HMHY`) present
// on one copy and absent from the other.
//
// So every exact-crib clean negative in `BREAK_P1030680.md` is a negative about the
// **recorded** ciphertext, not necessarily the transmitted one. A tolerant board is how those
// negatives get re-opened against a transcription error, rather than re-run identically.
//
// ## The first implementation was a total no-op — twice worth recording
//
// Tolerance must be implemented by **removing** edges *before* propagating, never by
// abandoning them mid-flight. The first attempt did the latter and measured as an exact no-op:
// one survivor at every tolerance level. Two causes compounded, and both are easy to
// re-introduce:
//
//   1. **The bad value is already committed.** A garbled edge processed early writes a wrong
//      σ(x) into `live`, which then propagates through other edges *and through the diagonal
//      board*. Restoring the two rows that just conflicted unwinds none of that.
//   2. **The conflict surfaces at the wrong edge.** Whichever edge happens to be visited when
//      the inconsistency becomes visible gets blamed, and that is typically a *correct* edge
//      rather than the garbled one — so dropping it does not help and the real culprit stays.
//
// Enumerating the deleted set is order-independent and reuses the already-validated exact
// closure (`WelchmanBombe.propagateCore`) instead of a second hand-rolled one. There is
// exactly one implementation of the board's logic in this repository, and both the exact and
// tolerant entry points call it.
//
// ## What is proven (known-key grades, not assertions)
//
// **Sensitivity** — P1030684, published key, 27-letter crib at offset 0, letters corrupted
// inside the crib span:
//
//     garbled   tolerance 0   tolerance = g   plugs forced (correct/total)
//           0   KEPT          KEPT            25/25
//           1   LOST          KEPT            25/25
//           2   LOST          KEPT            25/25
//           3   LOST          KEPT            25/25
//
// The `LOST → KEPT` transition is the mechanism working, and it is precisely the check the
// no-op version failed. The plug column matters just as much: a tolerant stop still forces
// **all 25** deductions correctly, while the crib-free climber needs only **4** correct plugs
// to flip its margin positive at 72 letters (Phase 50.6). The two halves compose — a garbled
// true key survives the board *and* is finishable.
//
// **Equivalence in silicon** — the Metal port (see `metalClosureSource`) agrees with this host
// implementation at **0/192 lane mismatches**, at every tolerance, across 45 crib × offset ×
// tolerance cells. Per-shell wall time rises 0.03 s → 0.5 s → ~7 s from tolerance 0 → 1 → 2,
// which is the second no-op check: the extra closures are demonstrably performed, not elided.
//
// ## What it costs, and the rule that was wrong
//
// Tolerance *widens* what survives, so its price is survivor inflation. At crib offset 0 that
// price looked like a clean function of menu size — 16 edges admitted 130,787 of 456,976 lanes
// at tolerance 1, while ≥17 admitted exactly one, and ≥22 admitted one even at tolerance 2.
//
// **That rule was published in an earlier revision and is withdrawn.** Varying the placement
// destroys it: 16 edges costs nothing at offset 15, while 18-edge menus admit 4,301 and 16,019
// survivors at offsets 40 and 65. Crib length does not predict inflation. The menu's **loop
// structure** does, because tolerance spends redundancy and only a loop-rich menu has enough
// to spend. Note which placements detonate — the ones already weak at tolerance 0
// (`t0 = 168`, `t0 = 2,308`). **Tolerance amplifies an under-determined menu rather than
// rescuing it.**
//
// Therefore tolerance is a **per-menu decision, pre-qualified by measurement**, never a global
// switch. `--bombe-tolerance-prequal` is that gate, and it must pass before any arm spends
// GPU-hours. On the target's 24 strongest placements it passes with zero inflation at
// tolerance 1, at a measured 15.3× cost factor.
//
// ## Honest scope — what this does NOT do
//
//   * It is not a decrypt, and it does not assert that P1030680 *is* garbled. Sensitivity is a
//     statement about the board's behaviour under corruption, not evidence of corruption.
//   * Tolerance applies to **menu edges only, not to the diagonal board itself**. It is an
//     algebraic relaxation of the deduction — it does not nominate *which* letters are wrong,
//     and it is not a claim about the ciphertext.
//   * This *type* does not model indels. That is the board's second mechanism and it lives in
//     `SpliceMenu.swift`: a missing four-letter group (Girard's `HMHY`) is a frame shift, so
//     every letter after the splice pairs with a different rotor state. A menu *geometry*
//     change rather than an edge deletion — same board, different half.
//   * Survivor inflation is real and measured. A tolerant board with no discriminator is a
//     ghost factory; this one is only usable because Phase 50 supplies a scorer that provably
//     finishes a true stop and leaves ghosts below the random-setting noise floor.
//
// ## Where the pieces live
//
//   * `MuleinBoard.propagate`            — this file: the host board, drop-subset enumeration
//   * `MuleinBoard.metalClosureSource`   — this file: the MSL the GPU kernel embeds
//   * `WelchmanBombe.propagateCore`      — `WelchmanDiagonalBoard.swift`: the shared closure
//   * `welchman_sweep`                   — `BombeMetal.swift`: the kernel that embeds the MSL
//   * `--garble-board-selftest`          — `GarbleBoardSelfTest.swift`: sensitivity grade
//   * `--garble-gpu`                     — `GarbleBoardSelfTest.swift`: kernel cross-check
//   * `--bombe-tolerance-prequal`        — `TolerancePrequal.swift`: the per-menu cost gate
//
// Ledger: `BREAK_P1030680.md` Phase 51. Report: `writeup.tex`.

package enum MuleinBoard {

    /// Largest tolerance the GPU kernel enumerates.
    ///
    /// This is **structural, not a tuning knob**: Metal has no recursion, so drop-subsets are
    /// unrolled as explicit nested loops and the nesting depth is fixed at compile time. The
    /// host implementation below has no such limit, so it is the fallback above this value.
    ///
    /// It is also where the cost lives — see `closuresPerSeed`.
    package static let maxTolerance = 3

    /// Closures a lane must run per seed hypothesis at a given tolerance.
    ///
    /// The board is evaluated once per candidate drop-set, so the count is the number of
    /// subsets of size ≤ `tolerance`: `1 + E + C(E,2) + C(E,3)`. For a 27-edge menu that is
    /// 28× at tolerance 1, 379× at 2 and 3304× at 3.
    ///
    /// This is a *ceiling*, not the measured cost. Two prunings bring it down substantially:
    /// the seed-attachment guard rejects drop-sets cheaply, and most closures die on an early
    /// contradiction rather than running to fixpoint. Measured factor on 40-edge target menus
    /// at tolerance 1 is **15.3×** against a ceiling of 41×.
    package static func closuresPerSeed(edges: Int, tolerance: Int) -> Int {
        guard edges > 0, tolerance > 0 else { return 1 }
        var total = 1
        var choose = 1
        for k in 1...min(tolerance, edges) {
            choose = choose * (edges - k + 1) / k
            total += choose
        }
        return total
    }

    /// Propagate σ(`seedLetter`) = `seedValue`, tolerating up to `tolerance` deleted edges.
    ///
    /// Returns the deduced `live` rows together with the edges that had to be deleted, or
    /// `nil` if no drop-set of size ≤ `tolerance` closes. `tolerance: 0` delegates to the
    /// historical exact board and is bit-for-bit identical to it.
    ///
    /// Drop-sets are enumerated smallest-first and lexicographically, so the returned set is
    /// the first minimal one found. Only *existence* reaches a survivor mask, so the host and
    /// the GPU agree on verdicts even where they would pick different sets.
    ///
    /// Deletion happens **before** propagation, for the two reasons in the file header. Do not
    /// "optimise" this into an in-flight abandonment; that version measured as a no-op.
    package static func propagate(
        menu: BombeMenu,
        scramblers: [[UInt8]],
        seedLetter: Int,
        seedValue: Int,
        tolerance: Int
    ) -> (live: [UInt32], droppedEdges: [Int])? {
        // Tolerance 0 is the historical board. Route it to the exact entry point rather than
        // running a one-element enumeration, so the common path cannot drift from Welchman's.
        guard tolerance > 0 else {
            guard let live = WelchmanBombe.propagate(
                menu: menu, scramblers: scramblers,
                seedLetter: seedLetter, seedValue: seedValue
            ) else { return nil }
            return (live, [])
        }

        let indices = Array(menu.ends.indices)

        for dropCount in 1...tolerance {
            var chosen = [Int](repeating: 0, count: dropCount)

            /// Enumerate combinations of `dropCount` edge indices, testing each reduced board.
            func recurse(_ depth: Int, _ start: Int) -> (live: [UInt32], droppedEdges: [Int])? {
                if depth == dropCount {
                    let drop = Set(chosen)
                    var ends: [(Int, Int)] = []
                    var tables: [[UInt8]] = []
                    ends.reserveCapacity(indices.count - dropCount)
                    tables.reserveCapacity(indices.count - dropCount)
                    for index in indices where !drop.contains(index) {
                        ends.append(menu.ends[index])
                        tables.append(scramblers[index])
                    }
                    // The seed letter must still touch a surviving edge. Without this guard a
                    // reduced board can constrain nothing at all, and then *every* setting
                    // "survives" trivially — which is a silent way to turn the sweep into a
                    // random number generator.
                    guard ends.contains(where: { $0.0 == seedLetter || $0.1 == seedLetter })
                    else { return nil }
                    guard let live = WelchmanBombe.propagateCore(
                        ends: ends, scramblers: tables,
                        seedLetter: seedLetter, seedValue: seedValue
                    ) else { return nil }
                    return (live, chosen.sorted())
                }
                for candidate in start..<indices.count {
                    chosen[depth] = indices[candidate]
                    if let hit = recurse(depth + 1, candidate + 1) { return hit }
                }
                return nil
            }

            if let hit = recurse(0, 0) { return hit }
        }
        return nil
    }

    /// Metal Shading Language for the tolerant closure, embedded by `welchman_sweep`.
    ///
    /// Kept here rather than in the kernel file so the board's logic — host and GPU — lives in
    /// one place. `BombeMetal.swift` owns the *sweep* (trail construction, scrambler
    /// tabulation, plug sieves, lane addressing); this owns the *board*.
    ///
    /// The emitted functions mirror `WelchmanBombe.propagateCore` edge for edge and in the same
    /// visit order, so a tolerance-0 call is the historical board bit for bit. That equivalence
    /// is what `--garble-gpu` checks, and it is why a disagreement is a kernel bug rather than
    /// a finding.
    ///
    /// - Parameters:
    ///   - maxEdges: menu edge ceiling, must match the kernel's `MAX_EDGES`.
    ///   - tolerance: unroll depth, must match `maxTolerance`.
    package static func metalClosureSource(maxEdges: Int, tolerance: Int) -> String {
        precondition(tolerance <= 3, "MSL drop-set loops are unrolled to depth 3")
        // `dropMask` is 64-bit because MAX_EDGES (40) exceeds 32.
        return """
        // ---- Mulein board (deletion-tolerant diagonal board) -------------------------
        // Generated by MuleinBoard.metalClosureSource. See MuleinBoard.swift for why a
        // relay cannot implement this and for the sensitivity/specificity grades.

        /// The board closure over an explicit drop set. `dropMask` bit `e` removes edge `e`
        /// *before* propagating — removal, not mid-flight abandonment. See MuleinBoard.swift:
        /// the abandonment version measured as an exact no-op.
        inline bool mulein_closure(
            thread const uchar *scram,
            constant uchar *edgeA,
            constant uchar *edgeB,
            uint edgeCount,
            ulong dropMask,
            uint central,
            uint seed,
            thread uint *outLive,
            thread ulong *activeOut
        ) {
            // `activeOut` accumulates the edges that actually MODIFIED `live` before this call
            // returned. It is the whole performance story for tolerance, and it is sound:
            //
            //   With `live` seeded from a single bit, most edges are no-ops on early passes --
            //   their endpoints hold nothing to propagate. If the closure contradicts without
            //   edge e ever having written to `live`, then removing e leaves the propagation
            //   byte-identical up to that point, so the SAME contradiction fires. Dropping e
            //   cannot help.
            //
            //   Therefore any drop set that rescues this setting must intersect the active set,
            //   and enumerating only active edges is complete as well as cheap. On a wrong
            //   setting the active set is a short propagation chain -- a handful of edges rather
            //   than all 40 -- which is where the speedup comes from.
            //
            // The host board in MuleinBoard.propagate deliberately does NOT do this. It stays a
            // blind enumeration so that the GPU-vs-host cross-check is a proof that this prune
            // preserves verdicts, rather than two implementations sharing an assumption.
            ulong active = 0ul;
            uint live[26];
            for (uint i = 0u; i < 26u; ++i) { live[i] = 0u; }
            live[central] = 1u << seed;

            bool changed = true;
            while (changed) {
                changed = false;

                // Menu edges, both directions, in host order.
                for (uint e = 0u; e < edgeCount; ++e) {
                    if (((dropMask >> e) & 1ul) != 0ul) { continue; }
                    uint a = uint(edgeA[e]);
                    uint b = uint(edgeB[e]);

                    uint mask = live[a];
                    uint image = 0u;
                    while (mask != 0u) {
                        uint bit = uint(ctz(mask));
                        mask &= mask - 1u;
                        image |= 1u << uint(scram[e * 26u + bit]);
                    }
                    if ((image & ~live[b]) != 0u) {
                        live[b] |= image;
                        active |= 1ul << e;
                        if (popcount(live[b]) > 1) { *activeOut = active; return false; }
                        changed = true;
                    }

                    mask = live[b];
                    image = 0u;
                    while (mask != 0u) {
                        uint bit = uint(ctz(mask));
                        mask &= mask - 1u;
                        image |= 1u << uint(scram[e * 26u + bit]);
                    }
                    if ((image & ~live[a]) != 0u) {
                        live[a] |= image;
                        active |= 1ul << e;
                        if (popcount(live[a]) > 1) { *activeOut = active; return false; }
                        changed = true;
                    }
                }

                // Welchman's diagonal: sigma is an involution, so sigma(x)=y implies
                // sigma(y)=x. This is the half that makes one seed constrain the whole board.
                for (uint x = 0u; x < 26u; ++x) {
                    uint mask = live[x];
                    while (mask != 0u) {
                        uint y = uint(ctz(mask));
                        mask &= mask - 1u;
                        uint bit = 1u << x;
                        if ((live[y] & bit) == 0u) {
                            live[y] |= bit;
                            // The diagonal board is not a menu edge, so it contributes nothing
                            // to `active` -- but a contradiction discovered here still has to
                            // export whatever edges got us to this state.
                            if (popcount(live[y]) > 1) { *activeOut = active; return false; }
                            changed = true;
                        }
                    }
                }
            }

            for (uint i = 0u; i < 26u; ++i) { outLive[i] = live[i]; }
            *activeOut = active;
            return true;
        }

        /// The seed letter must still touch a surviving edge, or the reduced board constrains
        /// nothing and every setting "survives" trivially. Same guard as the host.
        inline bool mulein_seed_attached(
            constant uchar *edgeA,
            constant uchar *edgeB,
            uint edgeCount,
            ulong dropMask,
            uint central
        ) {
            for (uint e = 0u; e < edgeCount; ++e) {
                if (((dropMask >> e) & 1ul) != 0ul) { continue; }
                if (uint(edgeA[e]) == central || uint(edgeB[e]) == central) { return true; }
            }
            return false;
        }

        /// Existence test: is there a drop set of at most `tolerance` edges under which the
        /// board closes? Smallest-first and lexicographic, matching the host. Loops are
        /// unrolled because Metal has no recursion, which is why MAX_TOL is structural.
        /// Existence test: is there a drop set of at most `tolerance` edges under which the
        /// board closes? Conflict-directed rather than blind.
        ///
        /// Only edges in the failing closure's **active set** are candidates, because any drop
        /// set that rescues the setting must intersect it (see `mulein_closure`). That is a
        /// completeness-preserving prune, not a heuristic, and it is the difference between
        /// trying 40 subsets and trying the handful of edges that actually did anything.
        ///
        /// Loops are unrolled because Metal has no recursion, which is why MAX_TOL is structural.
        inline bool mulein_tolerant_closure(
            thread const uchar *scram,
            constant uchar *edgeA,
            constant uchar *edgeB,
            uint edgeCount,
            uint tolerance,
            uint central,
            uint seed,
            thread uint *outLive
        ) {
            ulong active0 = 0ul;
            if (mulein_closure(scram, edgeA, edgeB, edgeCount, 0ul,
                               central, seed, outLive, &active0)) {
                return true;
            }
            if (tolerance == 0u) { return false; }

            // Candidates for the first deletion: the active set of the exact failure.
            ulong cand1 = active0;
            while (cand1 != 0ul) {
                uint i = uint(ctz(cand1));
                cand1 &= cand1 - 1ul;
                ulong mask = 1ul << i;
                if (!mulein_seed_attached(edgeA, edgeB, edgeCount, mask, central)) { continue; }
                ulong active1 = 0ul;
                if (mulein_closure(scram, edgeA, edgeB, edgeCount, mask,
                                   central, seed, outLive, &active1)) {
                    return true;
                }
                if (tolerance < 2u) { continue; }

                // Second deletion: the active set of the failure *after* dropping i. Same
                // argument applies recursively. Pairs may be visited twice ({i,j} and {j,i}),
                // which costs a factor of two and still beats C(40,2) = 780 by two orders.
                ulong cand2 = active1;
                while (cand2 != 0ul) {
                    uint j = uint(ctz(cand2));
                    cand2 &= cand2 - 1ul;
                    if (j == i) { continue; }
                    ulong mask2 = mask | (1ul << j);
                    if (!mulein_seed_attached(edgeA, edgeB, edgeCount, mask2, central)) { continue; }
                    ulong active2 = 0ul;
                    if (mulein_closure(scram, edgeA, edgeB, edgeCount, mask2,
                                       central, seed, outLive, &active2)) {
                        return true;
                    }
                    if (tolerance < 3u) { continue; }

                    ulong cand3 = active2;
                    while (cand3 != 0ul) {
                        uint k = uint(ctz(cand3));
                        cand3 &= cand3 - 1ul;
                        if (k == i || k == j) { continue; }
                        ulong mask3 = mask2 | (1ul << k);
                        if (!mulein_seed_attached(edgeA, edgeB, edgeCount, mask3, central)) { continue; }
                        ulong active3 = 0ul;
                        if (mulein_closure(scram, edgeA, edgeB, edgeCount, mask3,
                                           central, seed, outLive, &active3)) {
                            return true;
                        }
                    }
                }
            }
            return false;
        }
        // ---- end Mulein board --------------------------------------------------------
        """
    }
}
