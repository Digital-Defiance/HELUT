import Foundation

// MARK: - Enigma M4 (Kriegsmarine four-rotor)

package enum EnigmaM4Warehouse {
    /// Zusatzwalze β (does not step).
    package static let beta = EnigmaRotorSpec(
        name: "beta",
        wiring: "LEYJVCNIXWPBQMDRTAKZGFUHOS",
        notches: "A" // unused — Greek wheel is static
    )
    /// Zusatzwalze γ (does not step).
    package static let gamma = EnigmaRotorSpec(
        name: "gamma",
        wiring: "FSOKANUERHMBTIYCWLQPZXVGJD",
        notches: "A"
    )

    /// Thin Umkehrwalze B (Bruno).
    package static let thinB: [Int] = EnigmaAlphabet.normalize("ENKQAUYWJICOPBLMDXZVFTHRGS")
    /// Thin Umkehrwalze C (Caesar).
    package static let thinC: [Int] = EnigmaAlphabet.normalize("RDOBJNTKVEHMLFCWZAXGYIPSUQ")

    package static func greek(named name: String) -> EnigmaRotorSpec {
        switch name.uppercased() {
        case "B", "BETA", "β": return beta
        case "C", "GAMMA", "γ": return gamma
        default: preconditionFailure("Unknown Greek wheel '\(name)'")
        }
    }

    package static func thinReflector(named name: String) -> [Int] {
        switch name.uppercased() {
        case "B": return thinB
        case "C": return thinC
        default: preconditionFailure("Unknown thin reflector '\(name)'")
        }
    }
}

/// Daily / message key for Kriegsmarine Enigma M4.
package struct EnigmaM4Key: Sendable {
    package let greek: EnigmaRotorSpec
    /// Left, middle, right (slow → fast) among the three stepping rotors.
    package let rotors: (EnigmaRotorSpec, EnigmaRotorSpec, EnigmaRotorSpec)
    /// Ringstellung: Greek, L, M, R as 0…25.
    package let rings: (Int, Int, Int, Int)
    /// Window positions: Greek, L, M, R as 0…25.
    package var positions: (Int, Int, Int, Int)
    package let plugboard: [Int]
    package let reflector: [Int]

    package init(
        greek: EnigmaRotorSpec,
        rotors: (EnigmaRotorSpec, EnigmaRotorSpec, EnigmaRotorSpec),
        rings: (Int, Int, Int, Int),
        positions: (Int, Int, Int, Int),
        plugboard: [Int],
        reflector: [Int]
    ) {
        self.greek = greek
        self.rotors = rotors
        self.rings = rings
        self.positions = positions
        self.plugboard = plugboard
        self.reflector = reflector
    }

    /// U534 Potsdam (Plaice) daily key for 1 May 1945 (Hörenberg).
    package static func potsdam1May1945(positions: (Int, Int, Int, Int)) -> EnigmaM4Key {
        EnigmaM4Key(
            greek: EnigmaM4Warehouse.gamma,
            rotors: (
                EnigmaWarehouse.rotorIV,
                EnigmaWarehouse.rotorIII,
                EnigmaWarehouse.rotorVIII
            ),
            rings: (
                EnigmaAlphabet.index("A"),
                EnigmaAlphabet.index("A"),
                EnigmaAlphabet.index("C"),
                EnigmaAlphabet.index("U")
            ),
            positions: positions,
            plugboard: EnigmaKey.plugboard(pairs: [
                ("C", "H"), ("E", "J"), ("N", "V"), ("O", "U"), ("T", "Y"),
                ("L", "G"), ("S", "Z"), ("P", "K"), ("D", "I"), ("Q", "B")
            ]),
            reflector: EnigmaM4Warehouse.thinB
        )
    }

    package static func rings(fromLetters letters: String) -> (Int, Int, Int, Int) {
        let chars = Array(letters.uppercased())
        precondition(chars.count == 4)
        return (
            EnigmaAlphabet.index(chars[0]),
            EnigmaAlphabet.index(chars[1]),
            EnigmaAlphabet.index(chars[2]),
            EnigmaAlphabet.index(chars[3])
        )
    }

    package static func positions(fromLetters letters: String) -> (Int, Int, Int, Int) {
        rings(fromLetters: letters)
    }
}

/// Four-rotor naval Enigma. Greek wheel is static; L/M/R double-step as on M3.
package struct EnigmaM4Machine {
    package var key: EnigmaM4Key

    package init(key: EnigmaM4Key) {
        self.key = key
    }

    package mutating func process(_ input: Int) -> Int {
        step()
        var value = key.plugboard[input]
        value = rotorForward(value, rotor: key.rotors.2, position: key.positions.3, ring: key.rings.3)
        value = rotorForward(value, rotor: key.rotors.1, position: key.positions.2, ring: key.rings.2)
        value = rotorForward(value, rotor: key.rotors.0, position: key.positions.1, ring: key.rings.1)
        value = rotorForward(value, rotor: key.greek, position: key.positions.0, ring: key.rings.0)
        value = key.reflector[value]
        value = rotorReverse(value, rotor: key.greek, position: key.positions.0, ring: key.rings.0)
        value = rotorReverse(value, rotor: key.rotors.0, position: key.positions.1, ring: key.rings.1)
        value = rotorReverse(value, rotor: key.rotors.1, position: key.positions.2, ring: key.rings.2)
        value = rotorReverse(value, rotor: key.rotors.2, position: key.positions.3, ring: key.rings.3)
        return key.plugboard[value]
    }

    package mutating func processText(_ indices: [Int]) -> [Int] {
        indices.map { process($0) }
    }

    package mutating func processString(_ text: String) -> String {
        EnigmaAlphabet.string(from: processText(EnigmaAlphabet.normalize(text)))
    }

    private mutating func step() {
        let notchRight = key.rotors.2.isAtNotch(position: key.positions.3)
        let notchMiddle = key.rotors.1.isAtNotch(position: key.positions.2)
        if notchMiddle {
            key.positions.1 = (key.positions.1 + 1) % 26
        }
        if notchMiddle || notchRight {
            key.positions.2 = (key.positions.2 + 1) % 26
        }
        key.positions.3 = (key.positions.3 + 1) % 26
    }

    private func rotorForward(_ input: Int, rotor: EnigmaRotorSpec, position: Int, ring: Int) -> Int {
        let offset = (position - ring + 26) % 26
        let shifted = (input + offset) % 26
        let wired = rotor.wiring[shifted]
        return (wired - offset + 26) % 26
    }

    private func rotorReverse(_ input: Int, rotor: EnigmaRotorSpec, position: Int, ring: Int) -> Int {
        let offset = (position - ring + 26) % 26
        let shifted = (input + offset) % 26
        let wired = rotor.inverse[shifted]
        return (wired - offset + 26) % 26
    }
}

// MARK: - M4 ciphertext-only / message-key search (Tier 3 scoring)

package struct M4LaneResult: Sendable {
    package let positions: (Int, Int, Int, Int)
    package let positionsString: String
    package let plaintext: String
    package let score: Double
    package let indexOfCoincidence: Double
}

package enum HostM4Bombe {
    /// Exhaust all 26⁴ window settings for a fixed daily key; rank by language score + IC.
    package static func exhaustMessageKeys(
        ciphertext: [Int],
        dailyKey: EnigmaM4Key,
        scorer: LanguageScorer = LanguageScorer.germanMilitary(),
        topK: Int = 20
    ) -> [M4LaneResult] {
        var best: [M4LaneResult] = []
        best.reserveCapacity(topK)

        for g in 0..<26 {
            for left in 0..<26 {
                for middle in 0..<26 {
                    for right in 0..<26 {
                        var key = dailyKey
                        key.positions = (g, left, middle, right)
                        var machine = EnigmaM4Machine(key: key)
                        let plain = machine.processText(ciphertext)
                        let ic = LanguageScorer.indexOfCoincidence(plain)
                        let score = scorer.score(plain) + ic * 10.0 // IC tip for short naval texts
                        let result = M4LaneResult(
                            positions: (g, left, middle, right),
                            positionsString: EnigmaAlphabet.string(from: [g, left, middle, right]),
                            plaintext: EnigmaAlphabet.string(from: plain),
                            score: score,
                            indexOfCoincidence: ic
                        )
                        Self.insertTop(&best, result, limit: topK)
                    }
                }
            }
        }
        return best.sorted { $0.score > $1.score }
    }

    private static func insertTop(_ array: inout [M4LaneResult], _ item: M4LaneResult, limit: Int) {
        if array.count < limit {
            array.append(item)
            if array.count == limit {
                array.sort { $0.score > $1.score }
            }
            return
        }
        guard let worst = array.last, item.score > worst.score else { return }
        array[limit - 1] = item
        array.sort { $0.score > $1.score }
    }

    /// Fast IC-only pass (no n-grams) — useful as a first sieve.
    package static func exhaustMessageKeysIC(
        ciphertext: [Int],
        dailyKey: EnigmaM4Key,
        topK: Int = 50
    ) -> [M4LaneResult] {
        var bestScores = [Double](repeating: -1, count: topK)
        var bestPos = [(Int, Int, Int, Int)](repeating: (0, 0, 0, 0), count: topK)
        var filled = 0
        var worstIndex = 0

        for g in 0..<26 {
            for left in 0..<26 {
                for middle in 0..<26 {
                    for right in 0..<26 {
                        var key = dailyKey
                        key.positions = (g, left, middle, right)
                        var machine = EnigmaM4Machine(key: key)
                        var freq = [Int](repeating: 0, count: 26)
                        for cipher in ciphertext {
                            let p = machine.process(cipher)
                            freq[p] += 1
                        }
                        let n = Double(ciphertext.count)
                        var numerator = 0.0
                        for count in freq {
                            numerator += Double(count * (count - 1))
                        }
                        let ic = numerator / (n * (n - 1))

                        if filled < topK {
                            bestScores[filled] = ic
                            bestPos[filled] = (g, left, middle, right)
                            filled += 1
                            if filled == topK {
                                worstIndex = bestScores.indices.min(by: { bestScores[$0] < bestScores[$1] })!
                            }
                        } else if ic > bestScores[worstIndex] {
                            bestScores[worstIndex] = ic
                            bestPos[worstIndex] = (g, left, middle, right)
                            worstIndex = bestScores.indices.min(by: { bestScores[$0] < bestScores[$1] })!
                        }
                    }
                }
            }
        }

        var results: [M4LaneResult] = []
        for index in 0..<filled {
            let positions = bestPos[index]
            var key = dailyKey
            key.positions = positions
            var machine = EnigmaM4Machine(key: key)
            let plain = machine.processText(ciphertext)
            results.append(
                M4LaneResult(
                    positions: positions,
                    positionsString: EnigmaAlphabet.string(from: [
                        positions.0, positions.1, positions.2, positions.3
                    ]),
                    plaintext: EnigmaAlphabet.string(from: plain),
                    score: bestScores[index],
                    indexOfCoincidence: bestScores[index]
                )
            )
        }
        return results.sorted { $0.score > $1.score }
    }

    /// Score a decrypt: German bigram log-probability, penalised for deviating from
    /// German's index of coincidence in *either* direction. An IC far above German
    /// (0.075) signals a degenerate letter-run, not a better decrypt.
    package static func attackScore(plaintext: [Int], scorer: LanguageScorer) -> Double {
        let ic = LanguageScorer.indexOfCoincidence(plaintext)
        let bigram = LanguageScorer.bigramScore(plaintext)
        let icPenalty = abs(ic - LanguageScorer.Calibration.germanIC) * 8.0
        var score = bigram - icPenalty
        let text = EnigmaAlphabet.string(from: plaintext)
        // Multi-letter cribs only: short ones like "UUU" fire on degenerate runs.
        let cribs = [
            "EINS", "ZWO", "DREI", "NULL", "VIER", "FUENF", "SECHS", "ACHT", "NEUN",
            "WETTER", "CHEF", "UBOOT", "MELDUNG", "MARINE", "QUADRAT", "KURS", "FEIND",
            "BOOT", "STANDORT", "ANGRIFF", "VONVON"
        ]
        for crib in cribs where text.contains(crib) {
            score += 0.05
        }
        _ = scorer
        return score
    }

    /// How far a decrypt sits between random text and German, as a 0…1 fraction.
    /// Around 1.0 means indistinguishable from the training corpus; ≤0 means random.
    package static func germanLikeness(plaintext: [Int]) -> Double {
        let bigram = LanguageScorer.bigramScore(plaintext)
        let span = LanguageScorer.Calibration.germanMean - LanguageScorer.Calibration.randomMean
        return (bigram - LanguageScorer.Calibration.randomMean) / span
    }

    /// Cribs that almost never appear in bigram-fluent nonsense (72-letter false positives).
    /// Short function words (`UND`, `DER`, `SCH`) are intentionally excluded.
    package static let strongNavalCribs: [String] = [
        "VONVON", "UUU", "EINS", "ZWO", "DREI", "NULL", "VIER", "FUENF", "SECHS", "SIEBEN",
        "ACHT", "NEUN", "WETTER", "CHEF", "UBOOT", "MELDUNG", "MARINE", "QUADRAT", "KURS",
        "FEIND", "STANDORT", "ANGRIFF", "GELEIT", "TORPED", "FUNKSPRUCH", "OBERKOMMANDO"
    ]

    package struct BreakVerdict: Sendable {
        package let isPossibleBreak: Bool
        package let likeness: Double
        package let indexOfCoincidence: Double
        package let icInBand: Bool
        package let strongCribHits: [String]
        package let reason: String
    }

    /// Human-gate for CO candidates. Bigram likeness alone is not enough at 72 letters —
    /// German-shaped noise routinely scores ≥0.95 without naval structure.
    package static func evaluateBreak(plaintext: [Int]) -> BreakVerdict {
        let text = EnigmaAlphabet.string(from: plaintext)
        let likeness = germanLikeness(plaintext: plaintext)
        let ic = LanguageScorer.indexOfCoincidence(plaintext)
        let icInBand = abs(ic - LanguageScorer.Calibration.germanIC) < 0.02
        let hits = strongNavalCribs.filter { text.contains($0) }
        // Also accept Enigma digit-separator convention XX… when paired with a digit word.
        let hasXX = text.contains("XX")
        let digitWord = ["EINS", "ZWO", "DREI", "NULL", "VIER", "FUENF", "SECHS", "ACHT", "NEUN"]
            .contains { text.contains($0) }
        let structured = !hits.isEmpty || (hasXX && digitWord)

        if ic > 0.10 {
            return BreakVerdict(
                isPossibleBreak: false,
                likeness: likeness,
                indexOfCoincidence: ic,
                icInBand: icInBand,
                strongCribHits: hits,
                reason: "NO BREAK. IC \(String(format: "%.4f", ic)) is far above German "
                    + "— degenerate letter-run artifact, not plaintext."
            )
        }
        if likeness >= 0.85 && icInBand && structured {
            return BreakVerdict(
                isPossibleBreak: true,
                likeness: likeness,
                indexOfCoincidence: ic,
                icInBand: icInBand,
                strongCribHits: hits,
                reason: "*** Possible break — strong cribs [\(hits.joined(separator: ", "))] "
                    + "+ German IC/likeness; verify Kenngruppen/Grund ***"
            )
        }
        if likeness >= 0.85 && icInBand && !structured {
            return BreakVerdict(
                isPossibleBreak: false,
                likeness: likeness,
                indexOfCoincidence: ic,
                icInBand: icInBand,
                strongCribHits: hits,
                reason: "NO BREAK. High German-likeness without naval structure "
                    + "(bigram-fluent nonsense at this message length)."
            )
        }
        return BreakVerdict(
            isPossibleBreak: false,
            likeness: likeness,
            indexOfCoincidence: ic,
            icInBand: icInBand,
            strongCribHits: hits,
            reason: "NO BREAK. Candidates are indistinguishable from noise at this message length."
        )
    }
}

// MARK: - Stecker hill-climb (Gillogly sequential plugs)

package enum SteckerHillclimb {
    /// Greedy sequential plugs, maximising **German bigram log-probability**.
    ///
    /// Raw IC must not be used here: IC is maximised by a maximally peaked letter
    /// distribution, so an IC hill-climb converges on plaintexts that are one letter
    /// repeated (IC ≈ 0.15 versus German ≈ 0.075). The bigram model penalises those runs.
    package static func climb(
        ciphertext: [Int],
        baseKey: EnigmaM4Key,
        maxPlugs: Int = 10
    ) -> (plugboard: [Int], pairs: [(Character, Character)], ic: Double, plaintext: [Int]) {
        var plugboard = EnigmaKey.identityPlugboard()
        var pairs: [(Character, Character)] = []
        var used = Set<Int>()
        var currentScore = decryptBigramScore(
            ciphertext: ciphertext,
            key: keyWith(baseKey, plugboard: plugboard)
        )

        for _ in 0..<maxPlugs {
            var bestScore = -Double.greatestFiniteMagnitude
            var bestA = -1
            var bestB = -1
            for a in 0..<26 where !used.contains(a) {
                for b in (a + 1)..<26 where !used.contains(b) {
                    var trial = plugboard
                    trial[a] = b
                    trial[b] = a
                    let score = decryptBigramScore(
                        ciphertext: ciphertext,
                        key: keyWith(baseKey, plugboard: trial)
                    )
                    if score > bestScore {
                        bestScore = score
                        bestA = a
                        bestB = b
                    }
                }
            }
            guard bestA >= 0, bestScore > currentScore else { break }
            plugboard[bestA] = bestB
            plugboard[bestB] = bestA
            used.insert(bestA)
            used.insert(bestB)
            currentScore = bestScore
            pairs.append((EnigmaAlphabet.character(bestA), EnigmaAlphabet.character(bestB)))
        }

        var machine = EnigmaM4Machine(key: keyWith(baseKey, plugboard: plugboard))
        let plain = machine.processText(ciphertext)
        let ic = LanguageScorer.indexOfCoincidence(plain)
        return (plugboard, pairs, ic, plain)
    }

    private static func keyWith(_ key: EnigmaM4Key, plugboard: [Int]) -> EnigmaM4Key {
        EnigmaM4Key(
            greek: key.greek,
            rotors: key.rotors,
            rings: key.rings,
            positions: key.positions,
            plugboard: plugboard,
            reflector: key.reflector
        )
    }

    private static func decryptBigramScore(ciphertext: [Int], key: EnigmaM4Key) -> Double {
        var machine = EnigmaM4Machine(key: key)
        var previous = -1
        var total = 0.0
        var count = 0
        for cipher in ciphertext {
            let plain = machine.process(cipher)
            if previous >= 0 {
                total += LanguageScorer.germanBigramLogProbs[previous * 26 + plain]
                count += 1
            }
            previous = plain
        }
        return count == 0 ? -10 : total / Double(count)
    }
}

// MARK: - Crib-dragging (indicator-free)

package struct M4CribPlacement: Sendable {
    package let crib: String
    /// Offsets into the ciphertext where the crib can legally sit.
    package let offsets: [Int]
    package let totalOffsets: Int

    package var isImpossible: Bool { offsets.isEmpty }
    package var eliminationRate: Double {
        totalOffsets == 0 ? 0 : 1.0 - Double(offsets.count) / Double(totalOffsets)
    }
}

/// Turing's classic crib-drag: Enigma's reflector makes self-encryption impossible,
/// so any offset where crib[i] == ciphertext[offset + i] is eliminated with zero rotor work.
package enum M4CribDrag {
    /// Kriegsmarine stock phrases. Cribs are indicator-independent by construction.
    package static let navalCribs: [String] = [
        "WETTERVORHERSAGE",
        "WETTER",
        "KEINEBESONDERENEREIGNISSE",
        "OBERKOMMANDODERWEHRMACHT",
        "ANSTEUERUNGSFEUER",
        "VONVON",
        "UUUBOOT",
        "UBOOT",
        "BOOT",
        "CHEF",
        "MELDUNG",
        "FEINDLICHER",
        "GELEITZUG",
        "MARINE",
        "QUADRAT",
        "STANDORT",
        "EINSEINS",
        "NULLNULL",
        "FUNKTELEGRAMM",
        "KURS"
    ]

    /// All offsets where `crib` can sit without any letter encrypting to itself.
    package static func viableOffsets(crib: [Int], ciphertext: [Int]) -> [Int] {
        guard !crib.isEmpty, ciphertext.count >= crib.count else { return [] }
        var offsets: [Int] = []
        let last = ciphertext.count - crib.count
        for offset in 0...last {
            var collides = false
            for index in crib.indices where crib[index] == ciphertext[offset + index] {
                collides = true
                break
            }
            if !collides {
                offsets.append(offset)
            }
        }
        return offsets
    }

    package static func drag(crib: String, ciphertext: [Int]) -> M4CribPlacement {
        let letters = EnigmaAlphabet.normalize(crib)
        let total = ciphertext.count >= letters.count ? ciphertext.count - letters.count + 1 : 0
        return M4CribPlacement(
            crib: crib,
            offsets: viableOffsets(crib: letters, ciphertext: ciphertext),
            totalOffsets: total
        )
    }

    package static func dragAll(
        ciphertext: [Int],
        cribs: [String] = navalCribs
    ) -> [M4CribPlacement] {
        cribs.map { drag(crib: $0, ciphertext: ciphertext) }
    }
}

// MARK: - U534 unbroken target

package enum U534MessageP1030680 {
    package static let id = "P1030680"
    package static let date = "1945-05-01"
    package static let indicators = ("VROL", "NMKA")
    /// Ciphertext body without indicator groups.
    package static let ciphertext =
        "JCRSAJTGSJEYEXYKKZZSHVUOCTRFRCRPFVYPLKPPLGRHVVBBTBRSXSWXGGTYTVKQNGSCHVGF"
    package static let suspectedKeyNet = "M-Thetis"
    package static let sourceURL =
        "https://enigma.hoerenberg.com/index.php?cat=Unbroken&page=P1030680"

    /// Operator's mistaken Potsdam attempts (Girard) — useful regression on indicator math.
    package static let girardPotsdamAttempt = (
        verfahrenOEDM: "OEDM",
        messageKeyELKC: "ELKC",
        grundMNNS: "MNNS",
        verfahrenSEDM: "SEDM",
        messageKeyPUYY: "PUYY",
        grundDGUG: "DGUG"
    )
}

/// One attack candidate after msg-key exhaust + stecker hill-climb.
package struct M4GilloglyCandidate: Sendable {
    package let thinReflector: String
    package let greek: String
    package let wheelOrder: String
    package let rings: String
    package let positions: String
    package let steckerPairs: String
    package let indexOfCoincidence: Double
    package let score: Double
    package let plaintext: String
}

package enum M4ThetisAttack {
    /// Naval rotors available to M4 (I–VIII).
    package static let navalRotors: [EnigmaRotorSpec] = [
        EnigmaWarehouse.rotorI, EnigmaWarehouse.rotorII, EnigmaWarehouse.rotorIII,
        EnigmaWarehouse.rotorIV, EnigmaWarehouse.rotorV, EnigmaWarehouse.rotorVI,
        EnigmaWarehouse.rotorVII, EnigmaWarehouse.rotorVIII
    ]

    /// A named, explicitly-hypothetical restriction of the search space.
    ///
    /// M-Thetis was never broken and its key sheets are lost, so there is **no** published
    /// Thetis Walzenlage/Ringstellung to constrain to. Every subspace below is a prior
    /// borrowed from neighbouring nets; if the prior is wrong the true key is excluded.
    package struct Subspace: Sendable {
        package let name: String
        package let rationale: String
        package let wheelOrders: [(EnigmaRotorSpec, EnigmaRotorSpec, EnigmaRotorSpec)]
        package let ringVariants: [(Int, Int, Int, Int)]

        package var keyCount: Int { wheelOrders.count * ringVariants.count * 4 }
    }

    /// Permutations of the Potsdam 1 May 1945 wheel set {IV, III, VIII}.
    package static func potsdamNeighbourhood() -> Subspace {
        let wheels = [EnigmaWarehouse.rotorIV, EnigmaWarehouse.rotorIII, EnigmaWarehouse.rotorVIII]
        var orders: [(EnigmaRotorSpec, EnigmaRotorSpec, EnigmaRotorSpec)] = []
        for a in wheels {
            for b in wheels where b.name != a.name {
                for c in wheels where c.name != a.name && c.name != b.name {
                    orders.append((a, b, c))
                }
            }
        }
        return Subspace(
            name: "potsdam-neighbourhood",
            rationale: "Same U-boat, same day, same wheel set as Potsdam P1030684 — assumes Thetis shared wheels",
            wheelOrders: orders,
            ringVariants: [
                (0, 0, 0, 0),
                EnigmaM4Key.rings(fromLetters: "AACU"),
                EnigmaM4Key.rings(fromLetters: "VCCH")
            ]
        )
    }

    /// Naval convention prior: VI–VIII (two-notch) frequently loaded on M4 boats.
    package static func navalTwoNotchPrior() -> Subspace {
        var orders: [(EnigmaRotorSpec, EnigmaRotorSpec, EnigmaRotorSpec)] = []
        let twoNotch = [EnigmaWarehouse.rotorVI, EnigmaWarehouse.rotorVII, EnigmaWarehouse.rotorVIII]
        for order in allWheelOrders() where twoNotch.contains(where: { $0.name == order.2.name }) {
            orders.append(order)
        }
        return Subspace(
            name: "naval-two-notch-right",
            rationale: "VI/VII/VIII on the fast wheel — common Kriegsmarine loading, ordering prior only",
            wheelOrders: orders,
            ringVariants: [(0, 0, 0, 0)]
        )
    }

    /// Unconstrained: every wheel order, rings AAAA.
    package static func fullSpace() -> Subspace {
        Subspace(
            name: "full",
            rationale: "No historical assumption — 336 wheel orders × 2 Greek × 2 UKW",
            wheelOrders: allWheelOrders(),
            ringVariants: [(0, 0, 0, 0)]
        )
    }

    /// All P(8,3) = 336 ordered triples.
    package static func allWheelOrders() -> [(EnigmaRotorSpec, EnigmaRotorSpec, EnigmaRotorSpec)] {
        var orders: [(EnigmaRotorSpec, EnigmaRotorSpec, EnigmaRotorSpec)] = []
        for a in navalRotors {
            for b in navalRotors where b.name != a.name {
                for c in navalRotors where c.name != a.name && c.name != b.name {
                    orders.append((a, b, c))
                }
            }
        }
        return orders
    }

    /// Right-ring naval prior: rings AAA× for × = A…Z.
    package static func rightRingSweep() -> Subspace {
        Subspace(
            name: "rings-right",
            rationale: "Only the rightmost ring varies — common naval free-ring prior",
            wheelOrders: allWheelOrders(),
            ringVariants: (0..<26).map { (0, 0, 0, $0) }
        )
    }

    /// Full WO with same-day Potsdam ring settings (body AACU + indicator VCCH) plus AAAA.
    package static func fullWithPotsdamRings() -> Subspace {
        Subspace(
            name: "full-potsdam-rings",
            rationale: "All 336 WO × rings AAAA/AACU/VCCH from 1 May 1945 Potsdam traffic",
            wheelOrders: allWheelOrders(),
            ringVariants: [
                (0, 0, 0, 0),
                EnigmaM4Key.rings(fromLetters: "AACU"),
                EnigmaM4Key.rings(fromLetters: "VCCH")
            ]
        )
    }

    /// Parse ring strings like `AAAA,AACU,VCCH` into Ringstellung tuples.
    package static func parseRingsList(_ text: String) -> [(Int, Int, Int, Int)] {
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
        return parts.filter { !$0.isEmpty }.map { EnigmaM4Key.rings(fromLetters: String($0)) }
    }

    package static func subspace(named name: String) -> Subspace {
        switch name.lowercased() {
        case "potsdam", "potsdam-neighbourhood":
            return potsdamNeighbourhood()
        case "two-notch", "naval-two-notch", "naval-two-notch-right":
            return navalTwoNotchPrior()
        case "rings-right", "right-ring":
            return rightRingSweep()
        case "full-potsdam-rings", "potsdam-rings":
            return fullWithPotsdamRings()
        case "full", "all":
            return fullSpace()
        default:
            preconditionFailure(
                "Unknown subspace '\(name)'. Use: potsdam, two-notch, rings-right, full-potsdam-rings, full"
            )
        }
    }

    /// Full CO attack: for each WO × Greek × UKW × rings, top-K msg-keys by IC → stecker climb → score.
    package static func crack(
        ciphertext: [Int],
        wheelOrders: [(EnigmaRotorSpec, EnigmaRotorSpec, EnigmaRotorSpec)]? = nil,
        ringVariants: [(Int, Int, Int, Int)] = [(0, 0, 0, 0)],
        topK: Int = 40,
        msgKeyTopK: Int = 1,
        maxPlugs: Int = 10,
        scorer: LanguageScorer = .germanMilitary(),
        progress: (@Sendable (String) -> Void)? = nil
    ) -> [M4GilloglyCandidate] {
        let orders = wheelOrders ?? allWheelOrders()
        let greeks: [(String, EnigmaRotorSpec)] = [
            ("beta", EnigmaM4Warehouse.beta),
            ("gamma", EnigmaM4Warehouse.gamma)
        ]
        let reflectors: [(String, [Int])] = [
            ("B", EnigmaM4Warehouse.thinB),
            ("C", EnigmaM4Warehouse.thinC)
        ]
        let identity = EnigmaKey.identityPlugboard()
        let globalBestBox = LockedCandidates(limit: topK)
        let keysPerDaily = max(1, msgKeyTopK)

        DispatchQueue.concurrentPerform(iterations: orders.count) { orderIndex in
            let order = orders[orderIndex]
            let woName = "\(order.0.name)-\(order.1.name)-\(order.2.name)"
            if orderIndex % 12 == 0 {
                progress?("WO \(orderIndex + 1)/\(orders.count) \(woName)")
            }
            for rings in ringVariants {
                let ringsString = EnigmaAlphabet.string(from: [rings.0, rings.1, rings.2, rings.3])
                for (greekName, greek) in greeks {
                    for (ukwName, reflector) in reflectors {
                        let daily = EnigmaM4Key(
                            greek: greek,
                            rotors: order,
                            rings: rings,
                            positions: (0, 0, 0, 0),
                            plugboard: identity,
                            reflector: reflector
                        )
                        let local = HostM4Bombe.exhaustMessageKeysIC(
                            ciphertext: ciphertext,
                            dailyKey: daily,
                            topK: keysPerDaily
                        )
                        for bestPos in local {
                            var climbedKey = daily
                            climbedKey.positions = bestPos.positions
                            let climbed = SteckerHillclimb.climb(
                                ciphertext: ciphertext,
                                baseKey: climbedKey,
                                maxPlugs: maxPlugs
                            )
                            let score = HostM4Bombe.attackScore(
                                plaintext: climbed.plaintext,
                                scorer: scorer
                            )
                            let pairString = climbed.pairs
                                .map { "\($0.0)\($0.1)" }
                                .joined(separator: " ")
                            let candidate = M4GilloglyCandidate(
                                thinReflector: ukwName,
                                greek: greekName,
                                wheelOrder: woName,
                                rings: ringsString,
                                positions: bestPos.positionsString,
                                steckerPairs: pairString.isEmpty ? "(none)" : pairString,
                                indexOfCoincidence: climbed.ic,
                                score: score,
                                plaintext: EnigmaAlphabet.string(from: climbed.plaintext)
                            )
                            globalBestBox.insert(candidate)
                        }
                    }
                }
            }
        }
        return globalBestBox.snapshot()
    }

    /// Kept for smoke tests: identity-stecker IC sieve only.
    package static func gilloglySieve(
        ciphertext: [Int],
        wheelOrders: [(EnigmaRotorSpec, EnigmaRotorSpec, EnigmaRotorSpec)]? = nil,
        topK: Int = 30,
        progress: (@Sendable (String) -> Void)? = nil
    ) -> [M4GilloglyCandidate] {
        crack(
            ciphertext: ciphertext,
            wheelOrders: wheelOrders,
            ringVariants: [(0, 0, 0, 0)],
            topK: topK,
            msgKeyTopK: 1,
            maxPlugs: 0,
            progress: progress
        )
    }
}

private final class LockedCandidates: @unchecked Sendable {
    private let lock = NSLock()
    private var array: [M4GilloglyCandidate] = []
    private let limit: Int

    init(limit: Int) {
        self.limit = limit
    }

    func insert(_ candidate: M4GilloglyCandidate) {
        lock.lock()
        defer { lock.unlock() }
        if array.count < limit {
            array.append(candidate)
            if array.count == limit { array.sort { $0.score > $1.score } }
            return
        }
        guard let worst = array.last, candidate.score > worst.score else { return }
        array[limit - 1] = candidate
        array.sort { $0.score > $1.score }
    }

    func snapshot() -> [M4GilloglyCandidate] {
        lock.lock()
        defer { lock.unlock() }
        return array.sorted { $0.score > $1.score }
    }
}
