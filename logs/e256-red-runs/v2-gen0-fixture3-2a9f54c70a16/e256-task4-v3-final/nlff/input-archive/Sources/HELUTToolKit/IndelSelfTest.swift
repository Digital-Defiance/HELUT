import Foundation
import Metal
import HELUTCore
import HELUTCLI

// MARK: - `--indel-selftest`
//
// Grades the spliced-menu hypothesis on a known key, before any of it is pointed at P1030680.
//
// The experiment mirrors Girard's finding directly: take P1030684, whose key is published, and
// **delete a four-letter group** from its ciphertext to manufacture the transcript a copyist
// would have produced if a group had been dropped. Then ask two questions.
//
//   Sensitivity — does an ordinary menu on the damaged transcript LOSE the true setting, and
//     does a spliced menu with the right (splice, delta) FIND it? If the ordinary menu finds it
//     anyway then the alignment never mattered and this machinery is pointless.
//
//   Specificity — does a spliced menu at the WRONG splice position stay dead? A hypothesis that
//     survives regardless of where it claims the gap was is not a hypothesis, it is a sieve with
//     a hole in it. This is the check that a menu builder can most easily fake, because dropping
//     edges also weakens the menu.
//
// Both are reported. Neither is assumed. Note that unlike tolerance, a splice runs on the exact
// board, so there is no inflation term to price here — only whether the geometry is right.

func runIndelSelfTest() {
    let clean = EnigmaAlphabet.normalize(ControlMessageP1030684.ciphertext)
    let plain = EnigmaAlphabet.normalize(ControlMessageP1030684.plaintext)
    let truth = EnigmaM4Key.positions(fromLetters: ControlMessageP1030684.positions)
    let trueStecker = ControlMessageP1030684.trueStecker
    let cribLength = intFlag("--indel-crib") ?? 27
    let delta = intFlag("--indel-delta") ?? SpliceMenuBuilder.transmissionGroup
    // Where the group is deleted, in transmitted coordinates. Chosen inside the crib span by
    // default so the straddling case — the harder one — is what gets graded.
    let gapAt = intFlag("--indel-gap-at") ?? 12
    let bombe = ControlMessageP1030684.bombe(maxPlugs: 10)

    print("=== Spliced menus (indel hypothesis) — known-key grade ===")
    print("control    : P1030684 (published key), \(clean.count) letters")
    print("true shell : UKW B / Greek gamma / IV-III-VIII / rings "
        + "\(ControlMessageP1030684.rings) / pos \(ControlMessageP1030684.positions)")
    print("experiment : delete a \(delta)-letter group at transmitted position \(gapAt),")
    print("             then attack the damaged transcript.")
    print()
    print("An indel is NOT a substitution. Every surviving letter is correct; they sit at")
    print("shifted positions, so each edge after the splice needs a different scrambler.")
    print("That is a menu-geometry change and it runs on the EXACT board — no tolerance,")
    print("no survivor inflation, nothing relaxed.")
    print()

    // The damaged transcript: `clean` is the transmitted text T here, and deleting a group
    // produces the recording R that a copyist would have left behind.
    guard gapAt >= 0, gapAt + delta <= clean.count else {
        print("gap does not fit inside the control ciphertext")
        return
    }
    var recorded = clean
    let lost = Array(recorded[gapAt..<(gapAt + delta)])
    recorded.removeSubrange(gapAt..<(gapAt + delta))
    print("lost group : \(EnigmaAlphabet.string(from: lost))"
        + "   recording is now \(recorded.count) letters, transmitted was \(clean.count)")
    print()

    /// Does the true setting survive this menu on the exact board, and how many plugs does it
    /// force correctly? Tolerance is deliberately 0 throughout: this grades geometry, not the
    /// Mulein board.
    func survives(_ menu: BombeMenu) -> (kept: Bool, correct: Int, forced: Int) {
        let tables = bombe.scramblers(menu: menu, start: truth)
        for value in 0..<26 {
            guard let live = WelchmanBombe.propagate(
                menu: menu, scramblers: tables, seedLetter: menu.central, seedValue: value
            ) else { continue }
            var correct = 0, forced = 0
            for x in 0..<26 where live[x] != 0 {
                forced += 1
                if live[x].trailingZeroBitCount == trueStecker[x] { correct += 1 }
            }
            if forced > 0 { return (true, correct, forced) }
        }
        return (false, 0, 0)
    }

    // The crib is a claim about the TRANSMITTED message, so it is lifted from the plaintext at
    // its true transmitted offset. Place it so it straddles the gap, which is the case an
    // ordinary menu cannot survive.
    let cribStart = max(0, gapAt - cribLength / 2)
    guard cribStart + cribLength <= plain.count else {
        print("crib does not fit"); return
    }
    let cribText = EnigmaAlphabet.string(from: Array(plain[cribStart..<(cribStart + cribLength)]))
    print("crib       : \(cribText)")
    print("             \(cribLength) letters at transmitted offset \(cribStart)"
        + " (straddles the gap at \(gapAt))")
    print()

    print("SENSITIVITY")
    print("  menu                                          kept   plugs (correct/forced)")

    // 1. Ordinary menu on the damaged transcript, at the naive recorded offset. This is what
    //    every arm in the campaign would have run.
    if let naive = BombeMenuBuilder.menu(
        crib: cribText, offset: cribStart, ciphertext: recorded
    ) {
        let result = survives(naive)
        print(String(format: "  %-45@ %-6@ %d/%d",
                     "ordinary menu, recorded offset (what we run today)" as NSString,
                     (result.kept ? "KEPT" : "LOST") as NSString,
                     result.correct, result.forced))
    } else {
        print("  ordinary menu, recorded offset                 ILLEGAL (self-encipherment)")
    }

    // 2. Ordinary menu on the *undamaged* transcript — the upper bound, proving the crib and
    //    shell are right and that only the transcript is at fault.
    if let ideal = BombeMenuBuilder.menu(
        crib: cribText, offset: cribStart, ciphertext: clean
    ) {
        let result = survives(ideal)
        print(String(format: "  %-45@ %-6@ %d/%d",
                     "ordinary menu on the UNDAMAGED text (bound)" as NSString,
                     (result.kept ? "KEPT" : "LOST") as NSString,
                     result.correct, result.forced))
    }

    // 3. The spliced menu with the true (splice, delta). This is the claim.
    if let spliced = SpliceMenuBuilder.menu(
        crib: cribText, transmittedOffset: cribStart, ciphertext: recorded,
        splice: gapAt, delta: delta, minimumEdges: 8
    ) {
        let result = survives(spliced)
        print(String(format: "  %-45@ %-6@ %d/%d",
                     "SPLICED menu, true splice+delta" as NSString,
                     (result.kept ? "KEPT" : "LOST") as NSString,
                     result.correct, result.forced))
        print("    edges \(spliced.edgeCount) (of \(cribLength) crib letters;"
            + " \(cribLength - spliced.edgeCount) fell in the gap), loops \(spliced.loops)")
    } else {
        print("  SPLICED menu, true splice+delta                ILLEGAL")
    }

    print()
    print("SPECIFICITY — a wrong splice must NOT rescue the setting.")
    print("Three outcomes are tracked separately, because lumping them together is how this")
    print("test goes vacuous: a wrong splice that is ILLEGAL was never put on the board at all,")
    print("so counting it as 'rejected' would be claiming credit the board did not earn.")
    print()

    /// Probe every group-aligned splice at a given crib length, classifying each.
    ///
    /// `illegal` is a real filter and worth its own column — re-pairing a crib against shifted
    /// ciphertext usually creates a self-encipherment, which Enigma forbids, so the alignment
    /// dies before the bombe sees it. But it is *not* evidence about the board, and a run where
    /// every wrong splice is illegal proves nothing about specificity.
    func probe(cribLength probeLength: Int) -> (legal: Int, kept: Int, illegal: Int, rows: [String]) {
        // The crib MUST straddle the gap or the splice position is not a live parameter at
        // all: everything before the gap is byte-identical in the damaged and undamaged
        // transcripts, so a crib that stops short of it yields the same correct menu for every
        // splice and the test measures nothing. An earlier version of this probe kept the
        // sensitivity crib's start while shortening the length, which quietly walked the crib
        // off the gap and reported 28/28 "wrong splices surviving" — all of them the same
        // correct menu.
        let start = max(0, gapAt - probeLength / 2)
        guard start + probeLength <= plain.count,
              start < gapAt, gapAt < start + probeLength else { return (0, 0, 0, []) }
        let text = EnigmaAlphabet.string(
            from: Array(plain[start..<(start + probeLength)])
        )
        let cribStart = start
        var legal = 0, kept = 0, illegal = 0
        var rows: [String] = []
        for candidate in stride(from: 0, through: max(0, recorded.count - delta),
                                by: SpliceMenuBuilder.transmissionGroup) {
            let isTruth = candidate == gapAt
            guard let menu = SpliceMenuBuilder.menu(
                crib: text, transmittedOffset: cribStart, ciphertext: recorded,
                splice: candidate, delta: delta, minimumEdges: 8
            ) else {
                if !isTruth { illegal += 1 }
                // Built by concatenation, not String(format:). `%s` expects a C string
                // pointer, and handing it a Swift String segfaults.
                let note = isTruth ? "   <- TRUE SPLICE, PROBLEM" : ""
                rows.append("  \(String(format: "%6d", candidate))       -   "
                    + "illegal (self-encipherment)" + note)
                continue
            }
            let result = survives(menu)
            if !isTruth {
                legal += 1
                if result.kept { kept += 1 }
            }
            rows.append(String(format: "  %6d   %5d   %@%@", candidate, menu.edgeCount,
                               (result.kept ? "KEPT" : "dead at the board") as NSString,
                               (isTruth ? "   <- true splice" : "") as NSString))
        }
        return (legal, kept, illegal, rows)
    }

    // Shorten from the sensitivity crib only as far as 16 letters, never below. A shorter crib
    // self-enciphers less often, so it is how a wrong splice gets onto the board at all — but
    // below 16 the menu is a ghost factory by this campaign's own measurement (the menu-627
    // false alarm was 14 letters and produced 193M raw stops), so ANY result there is
    // uninformative and must not be reported as specificity.
    var probeLength = cribLength
    var result = probe(cribLength: probeLength)
    while result.legal == 0 && probeLength > 16 {
        probeLength -= 1
        result = probe(cribLength: probeLength)
    }

    print("  crib length \(probeLength) (from \(cribLength); floor is 16, below which any menu"
        + " is a ghost factory and proves nothing)")
    print("  splice   edges   outcome")
    for row in result.rows { print(row) }
    print()
    print("  wrong splices killed by legality alone : \(result.illegal)")
    print("  wrong splices actually put on the board: \(result.legal)")
    print("  of those, surviving                    : \(result.kept)")
    if result.legal == 0 {
        print()
        print("  BOARD-SPECIFICITY IS UNMEASURED HERE, and that is a finding rather than a")
        print("  failure. Every wrong splice was eliminated by self-encipherment before the")
        print("  bombe was asked, so this run says nothing about what the board would do with")
        print("  a legal-but-wrong splice.")
        print()
        print("  Why that asymmetry is favourable, structurally:")
        print("    * Enigma never encodes a letter to itself, so a menu built from the TRUE")
        print("      crib at the TRUE offset with the TRUE splice is *always* legal — it is")
        print("      reconstructing real plain/cipher pairs. Legality can never reject the")
        print("      truth.")
        print("    * A wrong splice re-pairs the crib against shifted ciphertext, and over 16+")
        print("      positions it almost always hits a self-encipherment. Here that killed")
        print("      \(result.illegal) of \(result.illegal) wrong candidates for free, with no GPU at all.")
        print()
        print("  So the splice search is largely self-pruning, which is good for cost. But the")
        print("  discrimination is coming from the cipher's own constraint, NOT from the board,")
        print("  and legality prunes by coincidence rather than by correctness. A hit therefore")
        print("  still needs independent confirmation, exactly as a short-crib stop does.")
    } else if result.kept == 0 {
        print()
        print("  Non-vacuous: \(result.legal) wrong splices reached the board and all died.")
        print("  The splice position is therefore a real, falsifiable parameter — a spliced")
        print("  menu is a MORE specific hypothesis than an ordinary one, not a looser one.")
    } else {
        print()
        print("  ⚠️  \(result.kept) wrong splice(s) survived. The splice position is not fully")
        print("      determined by the board, so a hit must be confirmed independently.")
    }

    print()
    print("ENUMERATION COST — how many distinct hypotheses one crib actually generates")
    let enumerated = SpliceMenuBuilder.indelMenus(
        crib: cribText, ciphertext: recorded, deltas: [delta], minimumEdges: 16
    )
    print("  distinct spliced menus for this crib: \(enumerated.count)")
    if let best = enumerated.first {
        print("  strongest: \(best.description)")
    }
    let straddling = enumerated.filter { $0.straddlesGap }.count
    print("  straddling \(straddling), post-gap \(enumerated.count - straddling)")
    print("  (a crib entirely BEFORE the gap is byte-identical to an ordinary menu and is")
    print("   skipped: it is not new key space and every prior arm already swept it)")
}
