import Foundation
import HELUTCore
import HELUTCLI

// MARK: - `--ostwald-escalate` : finish what the bombe started
//
// The measured result that motivates this (Phase 50.6): at 72 letters — P1030680's exact
// length, below the published 78-letter record for crib-free attacks — the staged climb
// recovers the full key and 100% of the plaintext once something hands it 8 correct plugs,
// and its margin over wrong settings goes positive at 4. A Welchman stop arrives with the
// stecker its menu forced, which is 7–12 plugs.
//
// So this is not a crib-free break of P1030680, and it must not be described as one. What
// it is: a far better *escalator* than the GA the quarantine tier currently feeds. Phase 22
// pushed soft-band stops into a stochastic hill-climb and got 0 survivors at a ~60%
// coincidence ceiling. The climber's job here is narrower and much better posed — the shell
// is fixed by the stop, several plugs are already forced, and only the remainder is
// searched.
//
// Logic of the test: if a quarantined stop is the *true* key, its forced plugs are correct,
// the climb finishes, and the plaintext appears. If it is a ghost, its forced plugs are
// wrong, and no amount of climbing rescues it. That is a clean decision on each candidate.

private struct EscalateManifest: Decodable {
    struct Candidate: Decodable {
        let ukw: String
        let greek: String
        let wheelOrder: String
        let rings: String
        let positions: String
        let steckerPairs: [String]
        let menuCrib: String
        let menuOffset: Int
        let ic: Double
        let tailScore: Double
        let source: String
    }
    let target: String
    let ciphertext: String
    let candidates: [Candidate]
}

func runOstwaldEscalate() {
    guard let path = stringFlag("--ostwald-escalate") else {
        print("usage: --ostwald-escalate <quarantine.json>")
        return
    }
    guard let data = FileManager.default.contents(atPath: path),
          let manifest = try? JSONDecoder().decode(EscalateManifest.self, from: data) else {
        print("could not read quarantine manifest at \(path)")
        return
    }

    let ciphertext = EnigmaAlphabet.normalize(manifest.ciphertext)
    let scorer = ClimbScorer(rawValue: stringFlag("--ostwald-scorer") ?? "staged") ?? .staged
    let exhaustLetters = intFlag("--ostwald-exhaust", allowZero: true) ?? 0
    let keepSeeded = intFlag("--ostwald-keep", allowZero: true) ?? 0

    print("=== Ostwald escalation of bombe stops ===")
    print("manifest      : \(path)")
    print("target        : \(manifest.target) (\(ciphertext.count) letters)")
    print("candidates    : \(manifest.candidates.count)")
    print("scorer        : \(scorer.rawValue)   trigram model: \(GermanTrigrams.sourceDescription)")
    print("seeding       : " + (keepSeeded > 0
        ? "first \(keepSeeded) forced plug(s) held fixed, remainder re-climbed"
        : "all forced plugs held fixed (--ostwald-keep N to free the rest)"))
    if exhaustLetters > 0 {
        print("exhaustion    : \(exhaustLetters) high-frequency letters")
    }
    print("break bar     : crib exact ∧ IC ≥ \(PostBombeDiscriminator.icFloor) ∧ "
        + "tail > \(PostBombeDiscriminator.breakThreshold)")
    print()

    // Noise floor: climb at random settings of the same shape, so an escalated score can be
    // read against something rather than admired on its own.
    var generator = SplitMix64(seed: 0xC0FFEE)
    var floorScores: [Double] = []
    if let first = manifest.candidates.first {
        let triple = rotorTriple(first.wheelOrder)
        for _ in 0..<12 {
            let key = EnigmaM4Key(
                greek: EnigmaM4Warehouse.greek(named: first.greek == "beta" ? "B" : "C"),
                rotors: triple,
                rings: EnigmaM4Key.rings(fromLetters: first.rings),
                positions: (Int(generator.next() % 26), Int(generator.next() % 26),
                            Int(generator.next() % 26), Int(generator.next() % 26)),
                plugboard: Array(0..<26),
                reflector: EnigmaM4Warehouse.thinReflector(named: first.ukw)
            )
            floorScores.append(
                OstwaldCurve.climb(key: key, ciphertext: ciphertext, scorer: scorer).score
            )
        }
    }
    let floorMean = floorScores.reduce(0, +) / Double(max(floorScores.count, 1))
    let floorBest = floorScores.max() ?? -.infinity
    print(String(format: "noise floor   : mean %.4f, best of %d random settings %.4f",
                 floorMean, floorScores.count, floorBest))
    print()

    struct Result {
        let index: Int
        let candidate: EscalateManifest.Candidate
        let score: Double
        let ic: Double
        let tail: Double
        let plaintext: String
        let pairs: [(Int, Int)]
        let cribExact: Bool
    }

    var results: [Result] = []
    for (index, candidate) in manifest.candidates.enumerated() {
        let forced = candidate.steckerPairs.compactMap { token -> (Int, Int)? in
            let letters = Array(token)
            guard letters.count == 2 else { return nil }
            let a = EnigmaAlphabet.index(letters[0])
            let b = EnigmaAlphabet.index(letters[1])
            guard a >= 0, a < 26, b >= 0, b < 26, a != b else { return nil }
            return (min(a, b), max(a, b))
        }
        let seeded = keepSeeded > 0 ? Array(forced.prefix(keepSeeded)) : forced
        let key = EnigmaM4Key(
            greek: EnigmaM4Warehouse.greek(named: candidate.greek == "beta" ? "B" : "C"),
            rotors: rotorTriple(candidate.wheelOrder),
            rings: EnigmaM4Key.rings(fromLetters: candidate.rings),
            positions: EnigmaM4Key.positions(fromLetters: candidate.positions),
            plugboard: Array(0..<26),
            reflector: EnigmaM4Warehouse.thinReflector(named: candidate.ukw)
        )
        let climbed = OstwaldCurve.climbExhaustive(
            key: key, ciphertext: ciphertext, scorer: scorer,
            exhaustLetters: exhaustLetters, alsoSeeded: seeded
        )
        let crib = EnigmaAlphabet.normalize(candidate.menuCrib)
        let end = candidate.menuOffset + crib.count
        let exact = end <= climbed.plain.count
            && Array(climbed.plain[candidate.menuOffset..<end]) == crib
        results.append(
            Result(
                index: index, candidate: candidate,
                score: climbed.score,
                ic: LanguageScorer.indexOfCoincidence(climbed.plain),
                tail: GermanTrigrams.score(climbed.plain),
                plaintext: EnigmaAlphabet.string(from: climbed.plain),
                pairs: climbed.pairs, cribExact: exact
            )
        )
    }

    let ranked = results.sorted { $0.score > $1.score }
    print("top escalated candidates by climbed score:")
    print("   #  climbed      IC     tail  crib  shell / position")
    for result in ranked.prefix(12) {
        print(String(format: "  %2d  %7.4f  %.4f  %7.4f  %@   %@/%@/%@ %@ %@",
                     result.index,
                     result.score, result.ic, result.tail,
                     result.cribExact ? "ok " : "BAD",
                     result.candidate.ukw as NSString,
                     result.candidate.greek as NSString,
                     result.candidate.wheelOrder as NSString,
                     result.candidate.rings as NSString,
                     result.candidate.positions as NSString))
        print("      \(String(result.plaintext.prefix(72)))")
    }
    print()

    // Victory conditions, unchanged from the campaign's standing definition.
    let breaks = ranked.filter {
        $0.cribExact
            && $0.ic >= PostBombeDiscriminator.icFloor
            && $0.tail > PostBombeDiscriminator.breakThreshold
            && $0.pairs.count <= 10
    }
    if breaks.isEmpty {
        let best = ranked.first
        print("NO BREAK — no escalated candidate clears crib-exact ∧ IC ≥ "
            + "\(PostBombeDiscriminator.icFloor) ∧ tail > \(PostBombeDiscriminator.breakThreshold).")
        if let best {
            print(String(format: "  best climbed %.4f (noise best %.4f, Δ %+.4f) "
                         + "IC %.4f tail %.4f",
                         best.score, floorBest, best.score - floorBest, best.ic, best.tail))
            if best.score <= floorBest {
                print("  and it does not even clear the random-setting floor, so these stops")
                print("  are ghosts as far as this scorer can tell.")
            }
        }
        print()
        print("Read this narrowly. It says the quarantined stops in this file are not the")
        print("key. It does not bound the escalator, which is graded separately on known")
        print("keys (Phase 50.6): given 4+ correct plugs it clears the bar at 72 letters.")
    } else {
        print("*** \(breaks.count) CANDIDATE(S) CLEAR THE BREAK BAR ***")
        for result in breaks {
            print(String(format: "  IC %.4f tail %.4f pairs %d",
                         result.ic, result.tail, result.pairs.count))
            print("  \(result.candidate.ukw)/\(result.candidate.greek)/"
                + "\(result.candidate.wheelOrder) rings \(result.candidate.rings) "
                + "pos \(result.candidate.positions)")
            print("  \(result.plaintext)")
            print("  VERIFY BY HAND before this is recorded as a break.")
        }
    }
}

private func rotorTriple(
    _ wheelOrder: String
) -> (EnigmaRotorSpec, EnigmaRotorSpec, EnigmaRotorSpec) {
    let names = wheelOrder.split(separator: "-").map(String.init)
    guard names.count == 3 else {
        return (EnigmaWarehouse.rotorI, EnigmaWarehouse.rotorII, EnigmaWarehouse.rotorIII)
    }
    func rotor(_ name: String) -> EnigmaRotorSpec {
        M4ThetisAttack.navalRotors.first { $0.name == name } ?? EnigmaWarehouse.rotorI
    }
    return (rotor(names[0]), rotor(names[1]), rotor(names[2]))
}
