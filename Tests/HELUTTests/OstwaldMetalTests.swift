import XCTest
@testable import HELUTCore
@testable import HELUTToolKit

final class OstwaldMetalTests: XCTestCase {

    func testPerfectMatchingsOnFourLettersAreThree() {
        let matchings = OstwaldExhaust.perfectMatchings([0, 1, 2, 3])
        XCTAssertEqual(matchings.count, 3)
    }

    func testPerfectMatchingsOnEightLettersAre105() {
        let matchings = OstwaldExhaust.perfectMatchings(Array(0..<8))
        XCTAssertEqual(matchings.count, 105)
    }

    func testFourPlugStartsAtExhaustEight() throws {
        let ct = Array(0..<72).map { $0 % 26 }
        let starts = try OstwaldExhaust.fourPlugStarts(
            ciphertext: ct, exhaustLetters: 8, locked: [], bruteAll: false
        )
        XCTAssertEqual(starts.count, 105)
        XCTAssertTrue(starts.allSatisfy { $0.count == 4 })
    }

    func testFourPlugAlphabetCountIs164Million() {
        XCTAssertEqual(OstwaldExhaust.fourPlugIndexPatterns.count, 105)
        XCTAssertEqual(OstwaldExhaust.fourPlugStartCount(letterCount: 8), 105)
        XCTAssertEqual(OstwaldExhaust.fourPlugStartCount(letterCount: 10), 4_725)
        XCTAssertEqual(OstwaldExhaust.fourPlugStartCount(letterCount: 26), 164_038_875)
        XCTAssertEqual(OstwaldProgress.greedyDecrypts(seeded: 4), 671)
        XCTAssertEqual(OstwaldProgress.greedyInsertDecrypts(seeded: 4), 503)
        XCTAssertEqual(OstwaldProgress.unusedPairCount(placed: 4), 153)
    }

    func testFourPlugWaveJobsCapsBelowTrialBudget() {
        let cap48 = OstwaldMemory.maxTrials(budgetBytes: 48 * 1024 * 1024 * 1024)
        XCTAssertEqual(OstwaldExhaust.fourPlugWaveJobs(trialCap: cap48), 524_288)
        XCTAssertLessThan(
            524_288 * (1 + OstwaldProgress.unusedPairCount(placed: 4)),
            cap48
        )
        XCTAssertEqual(OstwaldExhaust.fourPlugWaveJobs(trialCap: 10_000), 8_192)
    }

    func testVisitFourPlugStartsMatchesMaterializedEight() throws {
        let pool = Array(0..<8)
        var visited = 0
        OstwaldExhaust.visitFourPlugStarts(pool: pool) { pairs in
            XCTAssertEqual(pairs.count, 4)
            visited += 1
        }
        XCTAssertEqual(visited, 105)
    }

    func testFourPlugAlphabetRefusesMaterialize() {
        let ct = Array(0..<72).map { $0 % 26 }
        XCTAssertThrowsError(
            try OstwaldExhaust.fourPlugStarts(
                ciphertext: ct, exhaustLetters: 26, locked: [], bruteAll: true
            )
        ) { error in
            XCTAssertEqual(
                error as? OstwaldExhaust.Error,
                .fourPlugWouldMaterialize(count: 164_038_875)
            )
        }
    }

    func testTrueP1030684SettingIndex() {
        let pos = EnigmaM4Key.positions(fromLetters: ControlMessageP1030684.positions)
        XCTAssertEqual(OstwaldAllSettings.index(pos), 385_320)
        XCTAssertEqual(OstwaldAllSettings.letters(pos), ControlMessageP1030684.positions)
    }

    func testFourPlugBruteNeedsEightHotLetters() {
        XCTAssertThrowsError(
            try OstwaldExhaust.startSets(
                ciphertext: Array(repeating: 0, count: 72),
                exhaustLetters: 6,
                exhaustDepth: 2,
                alsoSeeded: [],
                brutePlugs: 4
            )
        ) { error in
            XCTAssertEqual(
                error as? OstwaldExhaust.Error,
                .fourPlugNeedsEightHotLetters(exhaustLetters: 6)
            )
        }
    }

    func testTopUpAlreadyMetReturnsEmptyStart() throws {
        let seeds = [(0, 1), (2, 3), (4, 5), (6, 7)]
        let starts = try OstwaldExhaust.startSets(
            ciphertext: Array(0..<72).map { $0 % 26 },
            exhaustLetters: 6,
            exhaustDepth: 2,
            alsoSeeded: seeds,
            topUpTo: 4
        )
        XCTAssertEqual(starts.count, 1)
        XCTAssertTrue(starts[0].isEmpty)
    }

    func testEmptyBoardUsesMeasuredDepthNotFourPlug() throws {
        let starts = try OstwaldExhaust.startSets(
            ciphertext: Array(0..<72).map { $0 % 26 },
            exhaustLetters: 6,
            exhaustDepth: 2,
            alsoSeeded: [],
            topUpTo: 4
        )
        XCTAssertGreaterThan(starts.count, 1)
        XCTAssertEqual(starts[0].count, 2)
    }

    func testStartSetsAlphabetFourPlugThrowsMaterialize() {
        XCTAssertThrowsError(
            try OstwaldExhaust.startSets(
                ciphertext: Array(0..<72).map { $0 % 26 },
                exhaustLetters: 26,
                exhaustDepth: 1,
                alsoSeeded: [],
                brutePlugs: 4,
                bruteAll: true
            )
        ) { error in
            XCTAssertEqual(
                error as? OstwaldExhaust.Error,
                .fourPlugWouldMaterialize(count: 164_038_875)
            )
        }
    }

    func testWelchmanShapedEtaFloor() {
        // Same arithmetic as BombeSweep: 2.076e11 settings / 50e6 /s → 69.2 min.
        let line = OstwaldProgress.floorLine(
            decrypts: 207_600_000_000,
            perSecond: 50_000_000
        )
        XCTAssertTrue(line.hasPrefix("ETA floor (~"), line)
        XCTAssertTrue(line.contains("50M decrypts/s"), line)
        XCTAssertTrue(line.contains("69.2 min"), line)
    }

    func testRoundLineKeepsInt64Decrypts() {
        let live = OstwaldProgress.liveLine(
            elapsed: 1881,
            decryptsDone: 2_147_483_648,
            decryptsTotal: 82_511_554_125
        )
        let line = OstwaldProgress.roundLine(
            round: 1, active: 524_288, decryptsDone: 2_147_483_648, live: live
        )
        XCTAssertTrue(line.contains("2147483648 decrypts"), line)
        XCTAssertFalse(line.contains("-"), line)
    }

    func testLiveEtaLineShape() {
        let line = OstwaldProgress.liveLine(
            elapsed: 1227,
            decryptsDone: 1227 * 42_300_000,
            decryptsTotal: 207_600_000_000
        )
        XCTAssertTrue(line.contains("1227s"), line)
        XCTAssertTrue(line.contains("ETA"), line)
        XCTAssertTrue(line.contains("min"), line)
    }

    func testGappedWalkDummyStepsChangeThePlaintext() {
        let key = controlKey(plugboard: Array(0..<26))
        let ct = Array(EnigmaAlphabet.normalize(ControlMessageP1030684.ciphertext).prefix(72))
        let dense = OstwaldCurve.decrypt(key: key, ciphertext: ct, pairs: [], walk: .dense)
        let gapped = OstwaldCurve.decrypt(
            key: key, ciphertext: ct, pairs: [], walk: .leadingGap(4)
        )
        XCTAssertNotEqual(dense, gapped)
        XCTAssertEqual(dense.count, 72)
        XCTAssertEqual(gapped.count, 72)
    }

    func testMetalScoresMatchCPUWhenDeviceExists() throws {
        let key = controlKey(plugboard: Array(0..<26))
        let ct = Array(EnigmaAlphabet.normalize(ControlMessageP1030684.ciphertext).prefix(72))
        guard let engine = OstwaldMetalEngine.make(key: key, ciphertext: ct) else {
            throw XCTSkip("no Metal device")
        }
        let identity = Array(0..<26)
        let plugged = ControlMessageP1030684.trueStecker
        let tables = [identity, plugged]
        for mode in [OstwaldScoreMode.ic, .bigram, .trigram] {
            let metal = engine.scores(plugTables: tables, mode: mode, walk: .dense)
            let cpu = engine.cpuScores(
                trials: tables.map {
                    OstwaldTrial(positions: key.positions, plugboard: $0, leadingHoles: 0)
                },
                mode: mode
            )
            XCTAssertEqual(metal.count, 2, "mode \(mode)")
            for index in metal.indices {
                XCTAssertEqual(
                    metal[index], cpu[index], accuracy: 1e-4,
                    "mode \(mode) table \(index)"
                )
            }
        }
        let metalGap = engine.scores(
            plugTables: tables, mode: .bigram, walk: .leadingGap(4)
        )
        let dense = engine.scores(plugTables: tables, mode: .bigram, walk: .dense)
        XCTAssertNotEqual(metalGap[0], dense[0], accuracy: 1e-5)
    }

    private func controlKey(plugboard: [Int]) -> EnigmaM4Key {
        EnigmaM4Key(
            greek: EnigmaM4Warehouse.gamma,
            rotors: (
                EnigmaWarehouse.rotorIV,
                EnigmaWarehouse.rotorIII,
                EnigmaWarehouse.rotorVIII
            ),
            rings: EnigmaM4Key.rings(fromLetters: ControlMessageP1030684.rings),
            positions: EnigmaM4Key.positions(fromLetters: ControlMessageP1030684.positions),
            plugboard: plugboard,
            reflector: EnigmaM4Warehouse.thinB
        )
    }
}
