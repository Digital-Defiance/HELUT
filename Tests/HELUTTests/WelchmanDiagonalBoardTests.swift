import XCTest
@testable import HELUTCore

/// Graded against P1030684, whose key is published, so every claim here is checkable.
final class WelchmanDiagonalBoardTests: XCTestCase {

    private let ciphertext = EnigmaAlphabet.normalize(
        "RFBYWKIKELDCHBSXUNFJFSNRRVFWASXYLQCQFADYJXNTBMVLRDCGULOWHTBGWUSSOQHG"
        + "AYEDKMJDNGVZNZFOXFKMIBKQNXFDWFIVGCYMJVQCKYQFBHYKZSCJ"
    )
    private let plaintext =
        "VVVUUUVIRSOBENNULEINSXXMITUUUVIRSIBENNULZWOYVIRSIBENNULDREIYZWODREISE"
        + "CHSEINSYZWODREIDREIACHTEINSDREIOITNACHWZSTENPASSIRT"

    private func bombe() -> WelchmanBombe {
        WelchmanBombe(
            greek: EnigmaM4Warehouse.gamma,
            left: EnigmaWarehouse.rotorIV,
            middle: EnigmaWarehouse.rotorIII,
            right: EnigmaWarehouse.rotorVIII,
            reflector: EnigmaM4Warehouse.thinB,
            rings: EnigmaM4Key.rings(fromLetters: "AACU")
        )
    }

    private var trueSetting: (Int, Int, Int, Int) {
        EnigmaM4Key.positions(fromLetters: "VYAA")
    }

    private var trueStecker: [Int] {
        var table = Array(0..<26)
        for pair in ["CH", "EJ", "NV", "OU", "TY", "LG", "SZ", "PK", "DI", "QB"] {
            let letters = Array(pair)
            let a = EnigmaAlphabet.index(letters[0])
            let b = EnigmaAlphabet.index(letters[1])
            table[a] = b
            table[b] = a
        }
        return table
    }

    // MARK: Menu construction

    func testMenuRejectsSelfEncipherment() {
        // A crib equal to the ciphertext collides at every position.
        let crib = EnigmaAlphabet.string(from: Array(ciphertext[0..<10]))
        XCTAssertNil(BombeMenuBuilder.menu(crib: crib, offset: 0, ciphertext: ciphertext))
    }

    func testMenuCountsLoops() {
        let crib = String(plaintext.prefix(25))
        let menu = BombeMenuBuilder.menu(crib: crib, offset: 0, ciphertext: ciphertext)
        XCTAssertNotNil(menu)
        guard let menu else { return }
        XCTAssertEqual(menu.edgeCount, 25)
        // edges − vertices + components, and this crib is known to close 7 loops.
        XCTAssertEqual(menu.loops, 7)
        XCTAssertTrue(menu.letters.contains(menu.central))
    }

    func testMenuRejectsOutOfRangeOffset() {
        XCTAssertNil(BombeMenuBuilder.menu(
            crib: "EINS", offset: ciphertext.count - 2, ciphertext: ciphertext
        ))
    }

    // MARK: The load-bearing property

    func testTrueSettingSurvivesAndForcesCorrectStecker() {
        let engine = bombe()
        let truth = trueStecker
        for length in [10, 16, 25] {
            let crib = String(plaintext.prefix(length))
            guard let menu = BombeMenuBuilder.menu(
                crib: crib, offset: 0, ciphertext: ciphertext
            ) else {
                return XCTFail("menu \(length) failed to build")
            }
            let stops = engine.test(menu: menu, start: trueSetting)
            XCTAssertFalse(stops.isEmpty, "true setting killed at crib length \(length)")

            let matching = stops.first { stop in
                (0..<26).allSatisfy { !stop.determined[$0] || stop.stecker[$0] == truth[$0] }
            }
            XCTAssertNotNil(matching, "no stop matches the real plugboard at length \(length)")
            // The menu must actually pin letters down, not merely fail to object.
            let pinned = (0..<26).filter { matching?.determined[$0] ?? false }.count
            XCTAssertGreaterThanOrEqual(pinned, 15, "only \(pinned) letters deduced")
        }
    }

    func testWrongSettingsAreKilled() {
        let engine = bombe()
        let crib = String(plaintext.prefix(20))
        guard let menu = BombeMenuBuilder.menu(crib: crib, offset: 0, ciphertext: ciphertext)
        else { return XCTFail("menu failed to build") }

        // Neighbours of the truth, one wheel off in each axis.
        let truth = trueSetting
        let wrong: [(Int, Int, Int, Int)] = [
            ((truth.0 + 1) % 26, truth.1, truth.2, truth.3),
            (truth.0, (truth.1 + 1) % 26, truth.2, truth.3),
            (truth.0, truth.1, (truth.2 + 1) % 26, truth.3),
            (truth.0, truth.1, truth.2, (truth.3 + 1) % 26)
        ]
        for setting in wrong {
            XCTAssertTrue(
                engine.isDead(menu: menu, start: setting),
                "wrong setting \(setting) was not eliminated"
            )
        }
        XCTAssertFalse(engine.isDead(menu: menu, start: truth))
    }

    /// A 16-letter menu should leave the truth essentially alone. Swept over the
    /// 26³ stepping-wheel space at the true Greek position; the full 26⁴ behaves the
    /// same and is covered by `--welchman-rehearsal`.
    func testLongMenuLeavesFewSurvivors() {
        let engine = bombe()
        let crib = String(plaintext.prefix(16))
        guard let menu = BombeMenuBuilder.menu(crib: crib, offset: 0, ciphertext: ciphertext)
        else { return XCTFail("menu failed to build") }

        let truth = trueSetting
        var survivors = 0
        var foundTruth = false
        for l in 0..<26 {
            for m in 0..<26 {
                for r in 0..<26 where !engine.isDead(menu: menu, start: (truth.0, l, m, r)) {
                    survivors += 1
                    if (l, m, r) == (truth.1, truth.2, truth.3) { foundTruth = true }
                }
            }
        }
        XCTAssertTrue(foundTruth, "the true setting was eliminated")
        XCTAssertLessThan(survivors, 20, "\(survivors) survivors — menu is too weak")
    }

    // MARK: Diagonal board semantics

    func testDiagonalBoardEnforcesInvolution() {
        let engine = bombe()
        let crib = String(plaintext.prefix(20))
        guard let menu = BombeMenuBuilder.menu(crib: crib, offset: 0, ciphertext: ciphertext)
        else { return XCTFail("menu failed to build") }
        let tables = engine.scramblers(menu: menu, start: trueSetting)

        for seed in 0..<26 {
            guard let live = WelchmanBombe.propagate(
                menu: menu, scramblers: tables, seedLetter: menu.central, seedValue: seed
            ) else { continue }
            for x in 0..<26 where live[x] != 0 {
                XCTAssertEqual(live[x].nonzeroBitCount, 1, "σ(\(x)) is multi-valued")
                let y = live[x].trailingZeroBitCount
                // Involution: the reverse wire must be lit too.
                XCTAssertEqual(live[y].trailingZeroBitCount, x)
                XCTAssertEqual(live[y].nonzeroBitCount, 1)
            }
        }
    }

    func testScramblerMatchesMachineWithoutPlugs() {
        // The unsteckered scrambler must reproduce a plugless M4 exactly.
        let engine = bombe()
        let crib = String(plaintext.prefix(8))
        guard let menu = BombeMenuBuilder.menu(crib: crib, offset: 0, ciphertext: ciphertext)
        else { return XCTFail("menu failed to build") }
        let tables = engine.scramblers(menu: menu, start: trueSetting)

        var reference = EnigmaM4Machine(key: EnigmaM4Key(
            greek: EnigmaM4Warehouse.gamma,
            rotors: (EnigmaWarehouse.rotorIV, EnigmaWarehouse.rotorIII, EnigmaWarehouse.rotorVIII),
            rings: EnigmaM4Key.rings(fromLetters: "AACU"),
            positions: trueSetting,
            plugboard: EnigmaKey.identityPlugboard(),
            reflector: EnigmaM4Warehouse.thinB
        ))
        for index in menu.steps.indices {
            let input = 7
            let expected = reference.process(input)
            XCTAssertEqual(Int(tables[index][input]), expected,
                           "scrambler disagrees with the machine at step \(index)")
        }
    }
}
