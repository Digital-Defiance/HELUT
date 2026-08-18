import Foundation

// MARK: - Spliced menus: the indel hypothesis
//
// ## What this is, and why it is *not* the Mulein board
//
// Transcription error is edit distance, and edit distance has two halves that need entirely
// different machinery:
//
//   * **Substitution** — a letter read wrong (`U` as `N`). The letter is wrong at a position we
//     know. Fix: delete that menu edge. That is `MuleinBoard`, and it *relaxes the deduction*
//     while the crib-position → rotor-step alignment stays fixed.
//
//   * **Indel** — a group dropped from (or duplicated into) the transcript. Every letter is
//     **correct**; they simply sit at **shifted positions**. Nothing needs relaxing. What
//     changes is *which scrambler each edge uses*, because the rotor had advanced further than
//     the recorded index suggests.
//
// So these are siblings, not parent and child. The indel side is the cheaper and better-evidenced
// one, for three reasons worth stating before the code:
//
//   1. **It needs no new board.** The Metal kernel already selects a scrambler per edge from a
//      step array (`edgeStep[]`), and `BombeMenu.steps` is already a separate array from
//      `BombeMenu.ends`. A spliced menu therefore runs on Welchman's **exact** board, unchanged.
//   2. **Therefore zero survivor inflation.** Tolerance widens what survives and needs a
//      per-menu pre-qualification gate; a splice does not widen anything. It is simply a
//      different, *more specific*, falsifiable hypothesis. There are more menus, not more stops
//      per menu.
//   3. **It is what Girard actually found.** Degarbling the sister message P1030681 turned up an
//      entire four-letter group, `HMHY`, present on the Schlüsselzettel copy and blank on the
//      plain-paper copy. By contrast isolated substitution garble across our 48 controls is only
//      4 controls / 8 events — too thin to fit a confusion model on (Phase 50.9).
//
// ## The model
//
// Let `R` be the **recorded** ciphertext (72 letters for P1030680) and `T` the **transmitted**
// one. The hypothesis is that `δ` letters went missing from the transcript at `T`-position `p`:
//
//     R[j] = T[j]        for j < p
//     R[j] = T[j + δ]    for j >= p
//
// so `T` is `δ` letters longer than `R`, and `T[p ..< p+δ]` is **lost** — those letters are on
// nobody's paper and cannot be recovered by any amount of search.
//
// A crib hypothesis is a claim about `T`. For crib `C` of length `L` sitting at `T`-offset `q`,
// each crib index `i` gives:
//
//     rotor step  = q + i                          (always a T coordinate: the rotor does not
//                                                   care what the transcriber wrote down)
//     cipher letter:
//         q+i <  p       ->  R[q+i]                (before the gap: indices agree)
//         q+i >= p + δ   ->  R[q+i-δ]              (after the gap: index shifted back by δ)
//         otherwise      ->  LOST, drop this edge  (inside the gap)
//
// **The step number and the ciphertext index diverge.** That divergence is the whole mechanism,
// and it is why this cannot be expressed as a plain `menu(crib:offset:ciphertext:)` call: an
// ordinary menu has `step == cipherIndex` by construction.
//
// Read the "after the gap" case carefully, because it is the interesting one: it uses the same
// ciphertext letters an ordinary menu at `R`-offset `q-δ` would use, but with every step number
// `δ` higher. Same letters, different machine states. That is key space no arm in this campaign
// has ever touched.
//
// ## Why the search is small
//
// Kriegsmarine traffic was transmitted in four-letter groups, and what Girard found missing was
// a *group*, not four arbitrary letters. So the splice sits on a group boundary: `p ≡ 0 mod 4`.
// For `δ = 4` that is ~17 candidate splice points across a 72-letter message rather than 72, and
// most (crib, offset) pairs collapse further — see `indelMenus`.
//
// ## Honest scope
//
// This builds *menus*. It is not a decrypt, it asserts nothing about P1030680's transcript, and
// a negative from it eliminates the enumerated (δ, p, q) hypotheses and nothing more. It must be
// graded on a known key with a synthetically deleted group before it is pointed at the target —
// see `--indel-selftest`.

package enum SpliceMenuBuilder {

    /// Historical group size for Kriegsmarine transmission, and therefore the natural unit for a
    /// dropped group. Splice positions are constrained to multiples of this.
    package static let transmissionGroup = 4

    /// One spliced menu, or nil if the hypothesis is illegal or too weak to be worth a sweep.
    ///
    /// - Parameters:
    ///   - crib: the plaintext hypothesis, a claim about the *transmitted* message.
    ///   - transmittedOffset: where the crib sits in `T` coordinates (`q` above).
    ///   - ciphertext: the **recorded** ciphertext `R`.
    ///   - splice: `T`-position where letters went missing (`p` above).
    ///   - delta: how many letters went missing (`δ` above). Zero returns the ordinary menu.
    ///   - minimumEdges: reject menus left too short by the gap. A short menu is a ghost factory
    ///     (the campaign's menu-627 false alarm was 14 letters), so the default matches the
    ///     campaign's `--bombe-min-crib 16`.
    package static func menu(
        crib: String,
        transmittedOffset: Int,
        ciphertext: [Int],
        splice: Int,
        delta: Int,
        minimumEdges: Int = 16
    ) -> BombeMenu? {
        let letters = EnigmaAlphabet.normalize(crib)
        guard !letters.isEmpty, transmittedOffset >= 0, delta >= 0, splice >= 0 else { return nil }

        // δ = 0 is no indel at all; hand it to the ordinary builder so there is one code path
        // for the no-hypothesis case and it cannot drift.
        guard delta > 0 else {
            return BombeMenuBuilder.menu(
                crib: crib, offset: transmittedOffset, ciphertext: ciphertext
            )
        }

        var steps: [Int] = []
        var ends: [(Int, Int)] = []
        steps.reserveCapacity(letters.count)
        ends.reserveCapacity(letters.count)

        for index in letters.indices {
            let tPos = transmittedOffset + index

            // Inside the gap the ciphertext letter was never written down. No search recovers
            // it, so the edge is genuinely absent rather than merely unknown.
            if tPos >= splice && tPos < splice + delta { continue }

            let rIndex = tPos < splice ? tPos : tPos - delta
            guard rIndex >= 0, rIndex < ciphertext.count else { return nil }

            let plain = letters[index]
            let cipher = ciphertext[rIndex]
            // Enigma never encrypts a letter to itself. Re-checked here because the splice
            // changes which ciphertext letter each crib letter faces, so legality under the
            // ordinary alignment says nothing about legality under this one.
            if plain == cipher { return nil }

            steps.append(tPos)
            ends.append((plain, cipher))
        }

        guard ends.count >= minimumEdges else { return nil }
        return BombeMenuBuilder.assemble(
            crib: crib, offset: transmittedOffset, steps: steps, ends: ends
        )
    }

    /// A distinct spliced hypothesis, tagged so a hit can be reported as an actual claim about
    /// the transcript rather than an opaque menu.
    package struct SplicedMenu: Sendable {
        package let menu: BombeMenu
        /// `T`-position where letters are hypothesised missing.
        package let splice: Int
        /// How many letters are hypothesised missing.
        package let delta: Int
        /// Crib position in `T` coordinates.
        package let transmittedOffset: Int
        /// True when the crib spans the gap, so some edges were dropped as unrecoverable.
        package let straddlesGap: Bool

        package var description: String {
            "\(menu.crib)@T\(transmittedOffset) splice=\(splice) delta=\(delta)"
                + " edges=\(menu.edgeCount) loops=\(menu.loops)"
                + (straddlesGap ? " straddling" : " post-gap")
        }
    }

    /// Every distinct spliced menu for one crib, deduplicated.
    ///
    /// The enumeration is smaller than it first looks, because most `(splice, offset)` pairs are
    /// not distinct hypotheses:
    ///
    ///   * **Crib entirely before the gap** (`p >= q + L`): the menu is byte-identical to the
    ///     ordinary menu at that offset, which every prior arm has already swept. Skipped — it
    ///     is not new key space and re-running it would inflate the arm for nothing.
    ///   * **Crib entirely after the gap** (`p + δ <= q`): the menu depends only on `δ`, not on
    ///     `p`. All such splices collapse to **one** menu. This is the case that opens untested
    ///     space: same letters, every step number `δ` higher.
    ///   * **Crib straddling the gap** (`q < p < q + L`): one menu per group-aligned `p`, each
    ///     dropping the edges that fall in the gap.
    ///
    /// - Parameters:
    ///   - deltas: gap sizes to try. `[4]` is Girard's case, a lost four-letter group. Smaller
    ///     values model a partial-group slip and are strictly more speculative.
    ///   - groupSize: splice alignment. 4 encodes the historical transmission grouping; 1
    ///     removes the constraint at ~4x the menu count.
    package static func indelMenus(
        crib: String,
        ciphertext: [Int],
        deltas: [Int] = [transmissionGroup],
        groupSize: Int = transmissionGroup,
        minimumEdges: Int = 16
    ) -> [SplicedMenu] {
        let letters = EnigmaAlphabet.normalize(crib)
        guard !letters.isEmpty else { return [] }
        let length = letters.count
        let step = max(1, groupSize)

        var out: [SplicedMenu] = []
        // Dedupe on the actual edge content: different (p, q) pairs can describe the same menu,
        // and sweeping a duplicate is pure waste.
        var seen = Set<String>()

        for delta in deltas where delta > 0 {
            // T is delta letters longer than the recording.
            let transmittedLength = ciphertext.count + delta
            guard length <= transmittedLength else { continue }

            for offset in 0...(transmittedLength - length) {
                var splices: [Int] = []

                // Post-gap: collapses to a single representative, since the menu does not depend
                // on where before the crib the gap sat. Require room for the gap to exist.
                if offset >= delta {
                    splices.append(0)
                }
                // Straddling: group-aligned splices strictly inside the crib span.
                var p = ((offset / step) + 1) * step
                while p < offset + length {
                    if p >= 0 { splices.append(p) }
                    p += step
                }

                for splice in splices {
                    guard let built = menu(
                        crib: crib, transmittedOffset: offset, ciphertext: ciphertext,
                        splice: splice, delta: delta, minimumEdges: minimumEdges
                    ) else { continue }

                    let key = built.steps.map(String.init).joined(separator: ",")
                        + "|" + built.ends.map { "\($0.0)-\($0.1)" }.joined(separator: ",")
                    guard seen.insert(key).inserted else { continue }

                    out.append(SplicedMenu(
                        menu: built,
                        splice: splice,
                        delta: delta,
                        transmittedOffset: offset,
                        straddlesGap: splice > offset && splice < offset + length
                    ))
                }
            }
        }

        // Deduction power first, exactly as the ordinary catalog is ranked: loops, then edges.
        out.sort {
            $0.menu.loops != $1.menu.loops
                ? $0.menu.loops > $1.menu.loops
                : $0.menu.edgeCount > $1.menu.edgeCount
        }
        return out
    }
}
