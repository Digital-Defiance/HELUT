import XCTest
@testable import HELUTCore
@testable import HELUTToolKit

final class OstwaldRankerTests: XCTestCase {

    private var corpusPath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/u534_corpus.json")
            .path
    }

    func testLinearSolveTwoByTwo() throws {
        let x = try XCTUnwrap(OstwaldRanker.solve([[2, 1], [1, 3]], [5, 10]))
        XCTAssertEqual(x[0], 1, accuracy: 1e-9)
        XCTAssertEqual(x[1], 3, accuracy: 1e-9)
    }

    func testFeaturesRankPlaintextAboveRandom() {
        let pt = Array(EnigmaAlphabet.normalize(ControlMessageP1030684.plaintext).prefix(72))
        var rng = SplitMix64(seed: 0xBEEF)
        let random = (0..<72).map { _ in Int(rng.next() % 26) }
        let ptF = OstwaldRanker.features(pt, navalTable: nil)
        let rndF = OstwaldRanker.features(random, navalTable: nil)
        XCTAssertGreaterThan(ptF[0], rndF[0], "IC")
        XCTAssertGreaterThan(ptF[1], rndF[1], "bigram")
        XCTAssertLessThan(ptF[4], rndF[4], "entropy")
    }

    func testLeaveOneOutFitRanksHeldOutPlaintextAboveWrongSetting() throws {
        XCTAssertTrue(GermanTrigrams.isLoaded)
        let controls = OstwaldCurve.loadControls(path: corpusPath)
        XCTAssertGreaterThanOrEqual(controls.count, 8)
        let held = try XCTUnwrap(controls.first { $0.id == "P1030684" } ?? controls.last)
        let model = try XCTUnwrap(
            OstwaldRanker.fit(
                controls: controls, excluding: held.id, window: 72, decoyClimbs: 0
            )
        )
        let ct = Array(held.ciphertext.prefix(72))
        let stripped = EnigmaM4Key(
            greek: held.key.greek, rotors: held.key.rotors, rings: held.key.rings,
            positions: held.key.positions, plugboard: Array(0..<26),
            reflector: held.key.reflector
        )
        let truth = OstwaldCurve.decrypt(key: stripped, ciphertext: ct, pairs: held.truePairs)
        let wrong = EnigmaM4Key(
            greek: held.key.greek, rotors: held.key.rotors, rings: held.key.rings,
            positions: (
                held.key.positions.0, held.key.positions.1,
                held.key.positions.2, (held.key.positions.3 + 13) % 26
            ),
            plugboard: Array(0..<26),
            reflector: held.key.reflector
        )
        let decoy = OstwaldCurve.decrypt(key: wrong, ciphertext: ct, pairs: [])
        XCTAssertGreaterThan(model.score(truth), model.score(decoy))
        XCTAssertEqual(model.excluding, held.id)
    }

    func testBeamWidthOneMatchesGreedyBoard() {
        let key = EnigmaM4Key(
            greek: EnigmaM4Warehouse.gamma,
            rotors: (
                EnigmaWarehouse.rotorIV,
                EnigmaWarehouse.rotorIII,
                EnigmaWarehouse.rotorVIII
            ),
            rings: EnigmaM4Key.rings(fromLetters: ControlMessageP1030684.rings),
            positions: EnigmaM4Key.positions(fromLetters: ControlMessageP1030684.positions),
            plugboard: Array(0..<26),
            reflector: EnigmaM4Warehouse.thinB
        )
        let ct = Array(EnigmaAlphabet.normalize(ControlMessageP1030684.ciphertext).prefix(72))
        let seeded = OstwaldEscalate.parseSteckerPairs(
            Array(ControlMessageP1030684.plugPairs.prefix(4))
        )
        let greedy = OstwaldCurve.climb(
            key: key, ciphertext: ct, scorer: .staged, seeded: seeded, beamWidth: 1
        )
        let beam = OstwaldCurve.climb(
            key: key, ciphertext: ct, scorer: .staged, seeded: seeded, beamWidth: 1
        )
        XCTAssertEqual(greedy.pairs.map { "\($0.0)-\($0.1)" }, beam.pairs.map { "\($0.0)-\($0.1)" })
        XCTAssertEqual(greedy.score, beam.score, accuracy: 1e-9)
    }

    func testAllSettingsIndexRoundtrip() {
        let truth = EnigmaM4Key.positions(fromLetters: ControlMessageP1030684.positions)
        let idx = OstwaldAllSettings.index(truth)
        XCTAssertEqual(OstwaldAllSettings.positions(index: idx).0, truth.0)
        XCTAssertEqual(OstwaldAllSettings.positions(index: idx).1, truth.1)
        XCTAssertEqual(OstwaldAllSettings.positions(index: idx).2, truth.2)
        XCTAssertEqual(OstwaldAllSettings.positions(index: idx).3, truth.3)
        XCTAssertEqual(OstwaldAllSettings.letters(truth), ControlMessageP1030684.positions)
        XCTAssertEqual(OstwaldAllSettings.messageKeys, 456_976)
    }

    func testParseShell() {
        let shell = OstwaldAllSettings.parseShell("B/gamma/IV-III-VIII/AACU")
        XCTAssertEqual(shell?.ukw, "B")
        XCTAssertEqual(shell?.rings, "AACU")
        XCTAssertNil(OstwaldAllSettings.parseShell("B/gamma/IV-III-VIII"))
    }
}