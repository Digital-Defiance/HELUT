import Foundation
import HELUTCore
import HELUTCLI

// MARK: - `--garble-board-selftest`
//
// Grades the tolerant diagonal board on a known key with deliberately corrupted ciphertext.
// Two things have to be true for a tolerant board to be worth building, and they pull against
// each other:
//
//   Sensitivity — with t garbled letters inside the crib span, the exact board (tolerance 0)
//     must LOSE the true setting, and a board with tolerance >= t must KEEP it. If the exact
//     board keeps it anyway, garble was never the problem and this is wasted machinery.
//
//   Specificity — tolerance also admits wrong settings. Each extra unit of tolerance inflates
//     the stop count, and that inflation is the price. It has to be a price the escalator can
//     pay: a ghost must still land below the noise floor, and there must not be so many that
//     the host drowns (the failure mode that stalled Phase 16 arm 2 at 7M/s).
//
// Both numbers are reported. Neither is assumed.

func runGarbleBoardSelfTest() {
    let clean = EnigmaAlphabet.normalize(ControlMessageP1030684.ciphertext)
    let plain = EnigmaAlphabet.normalize(ControlMessageP1030684.plaintext)
    let truth = EnigmaM4Key.positions(fromLetters: ControlMessageP1030684.positions)
    let trueStecker = ControlMessageP1030684.trueStecker
    let cribLength = intFlag("--garble-crib") ?? 27
    let maxTolerance = intFlag("--garble-tolerance") ?? 4

    print("=== Tolerant diagonal board — known-key garble grade ===")
    print("control       : P1030684 (published key), \(clean.count) letters")
    print("crib          : first \(cribLength) letters of the true plaintext, offset 0")
    print("true shell    : UKW B / Greek gamma / IV-III-VIII / rings "
        + "\(ControlMessageP1030684.rings) / pos \(ControlMessageP1030684.positions)")
    print()
    print("A tolerant board drops up to `t` menu edges that contradict the rest of the board,")
    print("on the hypothesis that a dropped edge is a mis-transcribed ciphertext letter.")
    print("tolerance 0 is the historical board exactly.")
    print()

    let bombe = ControlMessageP1030684.bombe(maxPlugs: 10)

    /// Corrupt `count` ciphertext letters inside the crib span, avoiding self-encipherment
    /// (which would make the placement illegal rather than merely garbled) and avoiding
    /// no-op substitutions.
    func garble(_ count: Int) -> ([Int], [Int]) {
        var text = clean
        var positions: [Int] = []
        guard count > 0 else { return (text, positions) }
        // Spread the corruptions through the span rather than clustering them.
        let stride = max(1, cribLength / (count + 1))
        var at = stride
        while positions.count < count && at < cribLength {
            var replacement = (text[at] + 7) % 26
            if replacement == plain[at] { replacement = (replacement + 1) % 26 }
            if replacement != text[at] {
                text[at] = replacement
                positions.append(at)
            }
            at += stride
        }
        return (text, positions)
    }

    print("SENSITIVITY — does the true setting survive its own garbled ciphertext?")
    print("  garbled  tolerance=0        tolerance=g       plugs forced (correct/total)")
    for garbles in 0...maxTolerance {
        let (text, spots) = garble(garbles)
        let cribText = EnigmaAlphabet.string(from: Array(plain[0..<cribLength]))
        guard let menu = BombeMenuBuilder.menu(
            crib: cribText, offset: 0, ciphertext: text
        ) else {
            print("  \(garbles): menu illegal under this corruption — skipped")
            continue
        }
        let tables = bombe.scramblers(menu: menu, start: truth)

        func survives(_ tolerance: Int) -> (Bool, Int, Int) {
            for value in 0..<26 {
                guard let result = MuleinBoard.propagate(
                    menu: menu, scramblers: tables,
                    seedLetter: menu.central, seedValue: value, tolerance: tolerance
                ) else { continue }
                var correct = 0, forced = 0
                for x in 0..<26 where result.live[x] != 0 {
                    forced += 1
                    if result.live[x].trailingZeroBitCount == trueStecker[x] { correct += 1 }
                }
                if forced > 0 { return (true, correct, forced) }
            }
            return (false, 0, 0)
        }

        let exact = survives(0)
        let tolerant = survives(garbles)
        print(String(format: "  %7d  %-17@ %-17@ %d/%d",
                     garbles,
                     (exact.0 ? "KEPT" : "LOST") as NSString,
                     (tolerant.0 ? "KEPT" : "LOST") as NSString,
                     tolerant.1, tolerant.2))
        if garbles > 0 && spots.count == garbles {
            print("           corrupted positions \(spots)")
        }
    }

    print()
    print("SPECIFICITY — what does tolerance cost in surviving wrong settings?")
    print("Sampling 26³ window positions at the true shell on the CLEAN ciphertext.")
    print("  tolerance   survivors/17576    inflation vs exact")
    let cribText = EnigmaAlphabet.string(from: Array(plain[0..<cribLength]))
    guard let cleanMenu = BombeMenuBuilder.menu(
        crib: cribText, offset: 0, ciphertext: clean
    ) else { return }

    var baseline = 0
    for tolerance in 0...min(maxTolerance, 3) {
        let counter = LockedCounter()
        DispatchQueue.concurrentPerform(iterations: 26) { l in
            var local = 0
            for m in 0..<26 {
                for r in 0..<26 {
                    let start = (truth.0, l, m, r)
                    let tables = bombe.scramblers(menu: cleanMenu, start: start)
                    for value in 0..<26 {
                        if MuleinBoard.propagate(
                            menu: cleanMenu, scramblers: tables,
                            seedLetter: cleanMenu.central, seedValue: value,
                            tolerance: tolerance
                        ) != nil {
                            local += 1
                            break
                        }
                    }
                }
            }
            counter.add(local)
        }
        let survivors = counter.value
        if tolerance == 0 { baseline = max(survivors, 1) }
        print(String(format: "  %9d   %14d    %.1fx",
                     tolerance, survivors, Double(survivors) / Double(baseline)))
        fflush(stdout)
    }

    print()
    print("Read both columns together. Sensitivity without specificity is a ghost factory;")
    print("the inflation factor is what the crib-free escalator has to pay for, and it only")
    print("pays if a ghost still lands below the random-setting noise floor.")
}

// MARK: - `--garble-gpu`
//
// The same known-key grade, run in the Metal kernel, plus a lane-by-lane cross-check against
// the host board. The host arm above is the reference: it is the implementation whose
// sensitivity was measured, so the kernel is graded against it rather than trusted. A tolerant
// board is only worth putting in silicon if the silicon agrees with it exactly.
//
// Cost note, since it is easy to scare yourself with the combinatorics: one shell is 26^4
// lanes, which at the measured 45.4M settings/s is ~10ms. Tolerance multiplies closures per
// seed by 1 + E + C(E,2) + C(E,3), so a single shell is ~0.3s at tolerance 1 and ~33s at
// tolerance 3. It is a full *ring sweep* that gets expensive, not this.

func runGarbleBoardGPUGrade() {
    let clean = EnigmaAlphabet.normalize(ControlMessageP1030684.ciphertext)
    let plain = EnigmaAlphabet.normalize(ControlMessageP1030684.plaintext)
    let truth = EnigmaM4Key.positions(fromLetters: ControlMessageP1030684.positions)
    let cribLength = intFlag("--garble-crib") ?? 27
    let requested = intFlag("--garble-tolerance") ?? 2
    let maxTolerance = min(requested, welchmanMaxTolerance)
    let bombe = ControlMessageP1030684.bombe(maxPlugs: 10)
    // Placement matters: the inflation threshold is a property of the menu's loop structure,
    // not of crib length alone, and loop structure changes with where the crib sits.
    let offset = max(0, min(intFlag("--garble-offset") ?? 0, clean.count - cribLength))

    print("=== Tolerant diagonal board — Metal kernel grade ===")
    print("control       : P1030684 (published key), \(clean.count) letters")
    print("crib          : \(cribLength) letters of the true plaintext at offset \(offset)")
    print("tolerance cap : \(maxTolerance) (kernel MAX_TOL = \(welchmanMaxTolerance))")
    print()

    guard let engine = WelchmanMetalEngine(depth: 1) else {
        print("no Metal device available — cannot grade the kernel")
        return
    }

    let trueLane = truth.0 * 17576 + truth.1 * 676 + truth.2 * 26 + truth.3

    /// Full 26-bit host mask, no plug sieve, so it matches the kernel configured the same way.
    func hostMask(_ menu: BombeMenu, _ start: (Int, Int, Int, Int), _ tolerance: Int) -> UInt32 {
        let tables = bombe.scramblers(menu: menu, start: start)
        var mask: UInt32 = 0
        for value in 0..<26 {
            if MuleinBoard.propagate(
                menu: menu, scramblers: tables,
                seedLetter: menu.central, seedValue: value, tolerance: tolerance
            ) != nil {
                mask |= UInt32(1) << UInt32(value)
            }
        }
        return mask
    }

    /// One shell on the GPU. Plug sieves off: the host reference applies none, and a
    /// cross-check against a differently-configured engine would prove nothing.
    func gpuSweep(_ menu: BombeMenu, _ tolerance: Int) -> ([UInt32], Double)? {
        engine.sieve = WelchmanSieve(
            maxPlugs: 0, exactPlugs: 0,
            skipMiddleRingCovered: false, garbleTolerance: tolerance
        )
        let began = Date()
        guard let buffer = engine.sweep(
            menu: menu, greek: bombe.greek, left: bombe.left,
            middle: bombe.middle, right: bombe.right,
            reflector: bombe.reflector, rings: bombe.rings
        ) else { return nil }
        let elapsed = Date().timeIntervalSince(began)
        return (Array(buffer), elapsed)
    }

    func garble(_ count: Int) -> ([Int], [Int]) {
        var text = clean
        var positions: [Int] = []
        guard count > 0 else { return (text, positions) }
        let stride = max(1, cribLength / (count + 1))
        var at = offset + stride
        while positions.count < count && at < offset + cribLength {
            var replacement = (text[at] + 7) % 26
            if replacement == plain[at] { replacement = (replacement + 1) % 26 }
            if replacement != text[at] {
                text[at] = replacement
                positions.append(at)
            }
            at += stride
        }
        return (text, positions)
    }

    let cribText = EnigmaAlphabet.string(from: Array(plain[offset..<(offset + cribLength)]))

    print("SENSITIVITY (kernel) — does the true lane survive its own garbled ciphertext?")
    print("  garbled   tol=0    tol=g    host tol=g   agree")
    for garbles in 0...maxTolerance {
        let (text, _) = garble(garbles)
        guard let menu = BombeMenuBuilder.menu(
            crib: cribText, offset: offset, ciphertext: text
        ) else {
            print("  \(garbles): menu illegal under this corruption — skipped")
            continue
        }
        guard let exact = gpuSweep(menu, 0), let tolerant = gpuSweep(menu, garbles) else {
            print("  \(garbles): GPU sweep failed (menu may exceed \(welchmanMaxEdges) edges)")
            continue
        }
        let gpuExact = exact.0[trueLane]
        let gpuTol = tolerant.0[trueLane]
        let host = hostMask(menu, truth, garbles)
        let undecided = gpuTol == welchmanUndecidedMask
        let agree = undecided ? "undecided" : (gpuTol == host ? "yes" : "NO")
        print(String(format: "  %7d   %-6@   %-6@   %-10@   %@",
                     garbles,
                     (gpuExact != 0 ? "KEPT" : "LOST") as NSString,
                     (gpuTol != 0 ? "KEPT" : "LOST") as NSString,
                     (host != 0 ? "KEPT" : "LOST") as NSString,
                     agree as NSString))
    }

    print()
    print("SPECIFICITY + CROSS-CHECK (kernel) — clean ciphertext, all 26^4 lanes.")
    print("The 26^3 slice at the true Greek position is the same population the host arm")
    print("sampled, so those survivor counts are directly comparable.")
    guard let cleanMenu = BombeMenuBuilder.menu(
        crib: cribText, offset: offset, ciphertext: clean
    ) else { return }
    // Edge count is the quantity that actually governs inflation: tolerance spends the
    // menu's redundancy, so what matters is how much redundancy there was to spend.
    print("menu          : crib \(cribLength) letters -> \(cleanMenu.edgeCount) edges")
    print("  tol   lanes surviving   26^3 slice   undecided   GPU s   settings/s   mismatches")

    // Deterministic spread through the 26^3 slice, coprime with 17576 so it does not
    // degenerate onto one wheel, plus the true lane itself.
    var sampleLanes: [Int] = [trueLane]
    var index = 0
    while sampleLanes.count < 192 {
        sampleLanes.append(truth.0 * 17576 + (index * 1379) % 17576)
        index += 1
    }

    for tolerance in 0...maxTolerance {
        guard let (masks, elapsed) = gpuSweep(cleanMenu, tolerance) else {
            print("  \(tolerance): GPU sweep failed")
            continue
        }
        var surviving = 0
        var sliceSurviving = 0
        var undecided = 0
        for lane in 0..<masks.count {
            if masks[lane] == welchmanUndecidedMask { undecided += 1; continue }
            if masks[lane] != 0 {
                surviving += 1
                if lane / 17576 == truth.0 { sliceSurviving += 1 }
            }
        }
        var mismatches = 0
        for lane in sampleLanes where masks[lane] != welchmanUndecidedMask {
            let (g, l, m, r) = WelchmanMetalEngine.position(forLane: lane)
            if hostMask(cleanMenu, (g, l, m, r), tolerance) != masks[lane] { mismatches += 1 }
        }
        let rate = Double(WelchmanMetalEngine.laneCount) / max(elapsed, 1e-9)
        print(String(format: "  %3d   %14d   %10d   %9d   %5.2f   %10.3gM   %d/%d",
                     tolerance, surviving, sliceSurviving, undecided,
                     elapsed, rate / 1e6, mismatches, sampleLanes.count))
        fflush(stdout)
    }

    print()
    print("Mismatches must be 0/\(sampleLanes.count). The kernel is not a second opinion on the")
    print("board — it is the same board at scale, and any disagreement is a kernel bug, not a")
    print("finding. Survivor inflation is the real cost and it is measured, not assumed.")
}
