import XCTest
@testable import HELUTCore

final class EnigmaBombeValidationTests: XCTestCase {

    // MARK: - Tier 1: Synthetic ground-truth sandbox

    func testOracleRoundTripControlPhrase() {
        let plaintext = "KEINEBESONDERENEREIGNISSE"
        let plugs: [(Character, Character)] = [
            ("A", "M"), ("B", "C"), ("D", "F"), ("G", "H"), ("I", "J"),
            ("K", "L"), ("N", "O"), ("P", "Q"), ("R", "S"), ("T", "U")
        ]
        let key = EnigmaKey(
            rotors: (EnigmaWarehouse.rotorI, EnigmaWarehouse.rotorII, EnigmaWarehouse.rotorIII),
            rings: (0, 0, 0),
            positions: (
                EnigmaAlphabet.index("A"),
                EnigmaAlphabet.index("B"),
                EnigmaAlphabet.index("C")
            ),
            plugboard: EnigmaKey.plugboard(pairs: plugs)
        )
        var enc = EnigmaMachine(key: key)
        let ciphertext = enc.processString(plaintext)
        var dec = EnigmaMachine(key: key)
        let recovered = dec.processString(ciphertext)
        XCTAssertEqual(recovered, plaintext)
        XCTAssertNotEqual(ciphertext, plaintext)
    }

    func testTier1InjectedHypothesisHostBombe() {
        let plaintext = "KEINEBESONDERENEREIGNISSE"
        let plugs: [(Character, Character)] = [
            ("A", "M"), ("B", "C"), ("D", "F"), ("G", "H"), ("I", "J"),
            ("K", "L"), ("N", "O"), ("P", "Q"), ("R", "S"), ("T", "U")
        ]
        let correctPositions = (
            EnigmaAlphabet.index("A"),
            EnigmaAlphabet.index("B"),
            EnigmaAlphabet.index("C")
        )
        let baseKey = EnigmaKey(
            rotors: (EnigmaWarehouse.rotorI, EnigmaWarehouse.rotorII, EnigmaWarehouse.rotorIII),
            rings: (0, 0, 0),
            positions: correctPositions,
            plugboard: EnigmaKey.plugboard(pairs: plugs)
        )
        var machine = EnigmaMachine(key: baseKey)
        let ciphertext = EnigmaAlphabet.normalize(machine.processString(plaintext))

        let batch = 10_000
        let correctLane = 42
        let positions: [(Int, Int, Int)] = (0..<batch).map { lane in
            if lane == correctLane { return correctPositions }
            // Deterministic wrong keys — never collide with ABC.
            let left = (lane * 7 + 3) % 26
            let middle = (lane * 11 + 5) % 26
            let right = (lane * 13 + 9) % 26
            let candidate = (left, middle, right)
            if candidate == correctPositions {
                return ((left + 1) % 26, middle, right)
            }
            return candidate
        }

        let results = HostEnigmaBombe.run(
            ciphertext: ciphertext,
            baseKey: baseKey,
            positionsPerLane: positions
        )

        XCTAssertEqual(results.count, batch)
        XCTAssertEqual(results[correctLane].plaintextString, plaintext)

        for result in results where result.lane != correctLane {
            XCTAssertNotEqual(
                result.plaintextString,
                plaintext,
                "False positive on lane \(result.lane)"
            )
        }

        let board = LanguageScorer.detectSpikes(results: results, margin: 0.8)
        XCTAssertEqual(board.winner?.lane, correctLane)
        XCTAssertTrue(board.spikes.contains(where: { $0.lane == correctLane }))
    }

    func testTier1CleartextNetlistMatchesOracleAndIsolatesCorrectLane() throws {
        guard let path = resolveEnigmaNetlistPathForCore() else {
            throw XCTSkip("enigma_netlist.json not found")
        }

        let plaintext = "KEINEBESONDERENEREIGNISSE"
        let correct = (
            EnigmaAlphabet.index("A"),
            EnigmaAlphabet.index("B"),
            EnigmaAlphabet.index("C")
        )
        var oracle = EnigmaMachine(key: .helutBaseline(positions: correct))
        let ciphertext = EnigmaAlphabet.normalize(oracle.processString(plaintext))

        // Single-lane: synthesized netlist ≡ software oracle.
        let harness = EnigmaNetlistHarness(netlistPath: path)
        harness.seedGrundstellung(left: correct.0, middle: correct.1, right: correct.2)
        let netlistPlain = harness.process(ciphertext: ciphertext)
        XCTAssertEqual(EnigmaAlphabet.string(from: netlistPlain), plaintext)

        // Injected hypothesis across a dense batch (subset of 10k space for CI runtime).
        let batch = 512
        let correctLane = 17
        var recoveredLane: Int?
        let laneHarness = EnigmaNetlistHarness(netlistPath: path)
        for lane in 0..<batch {
            let positions: (Int, Int, Int)
            if lane == correctLane {
                positions = correct
            } else {
                positions = HostEnigmaBombe.helutGrundstellung(lane: lane + 100)
                if positions == correct {
                    continue
                }
            }
            laneHarness.seedGrundstellung(left: positions.0, middle: positions.1, right: positions.2)
            let plain = EnigmaAlphabet.string(from: laneHarness.process(ciphertext: ciphertext))
            if plain == plaintext {
                XCTAssertNil(recoveredLane, "Multiple lanes recovered plaintext")
                recoveredLane = lane
            }
        }
        XCTAssertEqual(recoveredLane, correctLane)
    }

    // MARK: - Tier 2: Historical vectors + crib targeting

    func testTier2HistoricalFHPQXDecrypts() {
        let key = Self.historicalFHPQXKey()
        var machine = EnigmaMachine(key: key)
        let ciphertext = EnigmaAlphabet.normalize(
            "FDZCJJDKVWPYFDWPOQZGTJQYYXAFRHSQESE"
        )
        let plain = machine.processText(ciphertext)
        let head = EnigmaAlphabet.string(from: Array(plain.prefix(20)))
        XCTAssertEqual(head, "ANXPANZXGRUPPEXVIERX")
    }

    func testTier2FranklinHeathManual1930() {
        // http://wiki.franklinheath.co.uk/index.php/Enigma/Sample_Messages
        let key = EnigmaKey(
            rotors: (
                EnigmaWarehouse.rotorII,
                EnigmaWarehouse.rotorI,
                EnigmaWarehouse.rotorIII
            ),
            rings: EnigmaWarehouse.rings(fromNumbers: [24, 13, 22]),
            positions: (
                EnigmaAlphabet.index("A"),
                EnigmaAlphabet.index("B"),
                EnigmaAlphabet.index("L")
            ),
            plugboard: EnigmaKey.plugboard(pairs: [
                ("A", "M"), ("F", "I"), ("N", "V"), ("P", "S"), ("T", "U"), ("W", "Z")
            ]),
            reflector: EnigmaWarehouse.reflectorA
        )
        var machine = EnigmaMachine(key: key)
        let ciphertext = EnigmaAlphabet.normalize(
            "GCDSEAHUGWTQGRKVLFGXUCALXVYMIGMMNMFDXTGNVHVRMMEVOUYFZSLRHDRRXFJWCFHUHMUNZEFRDISIKBGPMYVXUZ"
        )
        let plain = EnigmaAlphabet.string(from: machine.processText(ciphertext))
        XCTAssertTrue(
            plain.hasPrefix("FEINDLIQEINFANTERIEKOLONNEBEOBAQTET"),
            "1930 manual decrypt failed: \(plain.prefix(40))"
        )
    }

    func testTier2FranklinHeathBarbarossaParts() {
        let plugs: [(Character, Character)] = [
            ("A", "V"), ("B", "S"), ("C", "G"), ("D", "L"), ("F", "U"),
            ("H", "Z"), ("I", "N"), ("K", "M"), ("O", "W"), ("R", "X")
        ]
        let rings = EnigmaWarehouse.rings(fromNumbers: [2, 21, 12])
        let rotors = (
            EnigmaWarehouse.rotorII,
            EnigmaWarehouse.rotorIV,
            EnigmaWarehouse.rotorV
        )

        var part1 = EnigmaMachine(
            key: EnigmaKey(
                rotors: rotors,
                rings: rings,
                positions: (
                    EnigmaAlphabet.index("B"),
                    EnigmaAlphabet.index("L"),
                    EnigmaAlphabet.index("A")
                ),
                plugboard: EnigmaKey.plugboard(pairs: plugs)
            )
        )
        let ct1 = EnigmaAlphabet.normalize(
            "EDPUDNRGYSZRCXNUYTPOMRMBOFKTBZREZKMLXLVEFGUEYSIOZVEQMIKUBPMMYLKLTTDEISMDICAGYKUACTCDOMOHWXMUUIAUBSTSLRNBZSZWNRFXWFYSSXJZVIJHIDISHPRKLKAYUPADTXQSPINQMATLPIFSVKDASCTACDPBOPVHJK"
        )
        let p1 = EnigmaAlphabet.string(from: part1.processText(ct1))
        XCTAssertTrue(p1.hasPrefix("AUFKLXABTEILUNGXVONXKURTINOWAX"), p1)

        var part2 = EnigmaMachine(
            key: EnigmaKey(
                rotors: rotors,
                rings: rings,
                positions: (
                    EnigmaAlphabet.index("L"),
                    EnigmaAlphabet.index("S"),
                    EnigmaAlphabet.index("D")
                ),
                plugboard: EnigmaKey.plugboard(pairs: plugs)
            )
        )
        let ct2 = EnigmaAlphabet.normalize(
            "SFBWDNJUSEGQOBHKRTAREEZMWKPPRBXOHDROEQGBBGTQVPGVKBVVGBIMHUSZYDAJQIROAXSSSNREHYGGRPISEZBOVMQIEMMZCYSGQDGRERVBILEKXYQIRGIRQNRDNVRXCYYTNJR"
        )
        let p2 = EnigmaAlphabet.string(from: part2.processText(ct2))
        XCTAssertTrue(p2.hasPrefix("DREIGEHTLANGSAMABERSIQERVORWAERTSX"), p2)
    }

    func testTier2FranklinHeathScharnhorst() {
        // https://cryptocellar.org/bgac/scharnhorst.html — UKW B, wheels 368, rings AHM, key UZV
        let key = EnigmaKey(
            rotors: (
                EnigmaWarehouse.rotorIII,
                EnigmaWarehouse.rotorVI,
                EnigmaWarehouse.rotorVIII
            ),
            rings: EnigmaWarehouse.rings(fromNumbers: [1, 8, 13]),
            positions: (
                EnigmaAlphabet.index("U"),
                EnigmaAlphabet.index("Z"),
                EnigmaAlphabet.index("V")
            ),
            plugboard: EnigmaKey.plugboard(pairs: [
                ("A", "N"), ("E", "Z"), ("H", "K"), ("I", "J"), ("L", "R"),
                ("M", "Q"), ("O", "T"), ("P", "V"), ("S", "W"), ("U", "X")
            ])
        )
        var machine = EnigmaMachine(key: key)
        let ciphertext = EnigmaAlphabet.normalize(
            "YKAENZAPMSCHZBFOCUVMRMDPYCOFHADZIZMEFXTHFLOLPZLFGGBOTGOXGRETDWTJIQHLMXVJWKZUASTR"
        )
        let plain = EnigmaAlphabet.string(from: machine.processText(ciphertext))
        XCTAssertTrue(plain.hasPrefix("STEUEREJTANAFJORDJANSTANDORTQU"), plain)
        XCTAssertTrue(plain.contains("SCHARNHORST"), plain)
    }

    func testTier2CryptoCellar1930IndicatorRecoversABL() {
        // Outer Grundstellung FOL encrypts doubled message key ABLABL → PKPJXI (indicator).
        let key = EnigmaKey(
            rotors: (
                EnigmaWarehouse.rotorII,
                EnigmaWarehouse.rotorI,
                EnigmaWarehouse.rotorIII
            ),
            rings: EnigmaWarehouse.rings(fromNumbers: [24, 13, 22]),
            positions: (
                EnigmaAlphabet.index("F"),
                EnigmaAlphabet.index("O"),
                EnigmaAlphabet.index("L")
            ),
            plugboard: EnigmaKey.plugboard(pairs: [
                ("A", "M"), ("F", "I"), ("N", "V"), ("P", "S"), ("T", "U"), ("W", "Z")
            ]),
            reflector: EnigmaWarehouse.reflectorA
        )
        var machine = EnigmaMachine(key: key)
        let indicator = machine.processString("ABLABL")
        XCTAssertEqual(indicator, "PKPJXI")
    }

    func testTier2CribTargetsSiegfriedWindow() {
        let key = Self.historicalFHPQXKey()
        let ciphertext = EnigmaAlphabet.normalize(
            String(
                "FDZCJJDKVWPYFDWPOQZGTJQYYXAFRHSQESERKGJBWBYPEOOKFMMPOMKQDDOLCPKHYP"
                    .filter { $0.isLetter }
            )
        )
        let crib = EnigmaAlphabet.normalize("SIEGFRRIED")
        // Brute a small window of offsets around known start; score crib hits.
        var hit = false
        let truePos = key.positions
        for deltaL in -1...1 {
            for deltaM in -1...1 {
                for deltaR in -1...1 {
                    var trial = key
                    trial.positions = (
                        (truePos.0 + deltaL + 26) % 26,
                        (truePos.1 + deltaM + 26) % 26,
                        (truePos.2 + deltaR + 26) % 26
                    )
                    var machine = EnigmaMachine(key: trial)
                    let plain = machine.processText(ciphertext)
                    let text = EnigmaAlphabet.string(from: plain)
                    if text.contains("SIEGFRRIED") || text.contains("SIEGFR") {
                        if trial.positions == truePos {
                            hit = true
                        }
                    }
                }
            }
        }
        XCTAssertTrue(hit)
        _ = crib
    }

    // MARK: - Tier 3: Statistical scoreboard

    func testTier3ScoreboardSpikesOnGermanPlaintext() {
        let plain = EnigmaAlphabet.normalize("KEINEBESONDERENEREIGNISSE")
        let random = (0..<plain.count).map { _ in Int.random(in: 0..<26) }
        let scorer = LanguageScorer.germanMilitary()
        let plainScore = scorer.score(plain)
        let randomScore = scorer.score(random)
        let plainIC = LanguageScorer.indexOfCoincidence(plain)
        let randomIC = LanguageScorer.indexOfCoincidence(random)
        XCTAssertGreaterThan(plainScore, randomScore)
        XCTAssertGreaterThan(plainIC, 0.05)
        XCTAssertLessThan(randomIC, 0.05)
    }

    func testTier3HistoricalMessageScoreboardRanksCorrectKey() {
        let key = Self.historicalFHPQXKey()
        let ciphertext = EnigmaAlphabet.normalize(
            String(
                "FDZCJJDKVWPYFDWPOQZGTJQYYXAFRHSQESERKGJBWBYPEOOKFMMPOMK"
                    .filter { $0.isLetter }
            )
        )
        let correct = key.positions
        var positions: [(Int, Int, Int)] = [correct]
        for lane in 1..<200 {
            positions.append(HostEnigmaBombe.helutGrundstellung(lane: lane + 50))
        }
        let results = HostEnigmaBombe.run(
            ciphertext: ciphertext,
            baseKey: key,
            positionsPerLane: positions
        )
        let board = LanguageScorer.detectSpikes(results: results, margin: 0.5)
        XCTAssertEqual(board.winner?.positions.0, correct.0)
        XCTAssertEqual(board.winner?.positions.1, correct.1)
        XCTAssertEqual(board.winner?.positions.2, correct.2)
        XCTAssertTrue(board.winner!.plaintextString.hasPrefix("ANXPANZXGRUPPE"))
    }

    // MARK: - Fixtures

    private static func historicalFHPQXKey() -> EnigmaKey {
        EnigmaKey(
            rotors: (
                EnigmaWarehouse.rotorIV,
                EnigmaWarehouse.rotorII,
                EnigmaWarehouse.rotorIII
            ),
            rings: (
                EnigmaAlphabet.index("G"),
                EnigmaAlphabet.index("T"),
                EnigmaAlphabet.index("O")
            ),
            positions: (
                EnigmaAlphabet.index("S"),
                EnigmaAlphabet.index("D"),
                EnigmaAlphabet.index("V")
            ),
            plugboard: EnigmaKey.plugboard(pairs: [
                ("A", "D"), ("E", "H"), ("G", "Y"), ("I", "M"), ("K", "N"),
                ("L", "R"), ("O", "Z"), ("Q", "V"), ("T", "X"), ("U", "W")
            ])
        )
    }
}
