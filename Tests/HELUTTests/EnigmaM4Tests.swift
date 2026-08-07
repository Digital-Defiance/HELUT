import XCTest
@testable import HELUTCore

final class EnigmaM4Tests: XCTestCase {

    func testM4DecryptsBrokenU534P1030684() {
        // https://enigma.hoerenberg.com/ — Potsdam 1 May 1945, message key VYAA
        let key = EnigmaM4Key.potsdam1May1945(
            positions: EnigmaM4Key.positions(fromLetters: "VYAA")
        )
        var machine = EnigmaM4Machine(key: key)
        let ct = EnigmaAlphabet.normalize(
            "RFBYWKIKELDCHBSXUNFJFSNRRVFWASXYLQCQFADYJXNTBMVLRDCGULOWHTBGWUSSOQHGAYEDKMJDNGVZNZFOXFKMIBKQNXFDWFIVGCYMJVQCKYQFBHYKZSCJ"
        )
        let plain = machine.processString(
            EnigmaAlphabet.string(from: ct)
        )
        let expected =
            "VVVUUUVIRSOBENNULEINSXXMITUUUVIRSIBENNULZWOYVIRSIBENNULDREIYZWODREISECHSEINSYZWODREIDREIACHTEINSDREIOITNACHWZSTENPASSIRT"
        XCTAssertEqual(plain, expected)
    }

    func testM4MessageKeyExhaustRecoversVYAA() {
        let ct = EnigmaAlphabet.normalize(
            "RFBYWKIKELDCHBSXUNFJFSNRRVFWASXYLQCQFADYJXNTBMVLRDCGULOWHTBGWUSSOQHGAYEDKMJDNGVZNZFOXFKMIBKQNXFDWFIVGCYMJVQCKYQFBHYKZSCJ"
        )
        let daily = EnigmaM4Key.potsdam1May1945(positions: (0, 0, 0, 0))
        let top = HostM4Bombe.exhaustMessageKeys(ciphertext: ct, dailyKey: daily, topK: 5)
        XCTAssertFalse(top.isEmpty)
        XCTAssertEqual(top[0].positionsString, "VYAA")
        XCTAssertTrue(top[0].plaintext.hasPrefix("VVVUUUVIRSOBENNULEINS"))
    }

    func testGirardPotsdamIndicatorGrundMNNS() {
        // Indicator procedure uses the original ring setting VCCH (Girard / Hörenberg).
        // Body decrypts of P1030684 use AACU; both are documented for 1 May 1945 Potsdam.
        var key = EnigmaM4Key(
            greek: EnigmaM4Warehouse.gamma,
            rotors: (
                EnigmaWarehouse.rotorIV,
                EnigmaWarehouse.rotorIII,
                EnigmaWarehouse.rotorVIII
            ),
            rings: EnigmaM4Key.rings(fromLetters: "VCCH"),
            positions: EnigmaM4Key.positions(fromLetters: "MNNS"),
            plugboard: EnigmaKey.plugboard(pairs: [
                ("C", "H"), ("E", "J"), ("N", "V"), ("O", "U"), ("T", "Y"),
                ("L", "G"), ("S", "Z"), ("P", "K"), ("D", "I"), ("Q", "B")
            ]),
            reflector: EnigmaM4Warehouse.thinB
        )
        var machine = EnigmaM4Machine(key: key)
        XCTAssertEqual(machine.processString("ELKC"), "OEDM")

        key.positions = EnigmaM4Key.positions(fromLetters: "DGUG")
        machine = EnigmaM4Machine(key: key)
        XCTAssertEqual(machine.processString("PUYY"), "SEDM")
    }

    func testCribDragKeepsTruePlacementOnKnownMessage() {
        // P1030684 is broken, so we know both sides: the true crib offset must survive.
        let ct = EnigmaAlphabet.normalize(
            "RFBYWKIKELDCHBSXUNFJFSNRRVFWASXYLQCQFADYJXNTBMVLRDCGULOWHTBGWUSSOQHGAYEDKMJDNGVZNZFOXFKMIBKQNXFDWFIVGCYMJVQCKYQFBHYKZSCJ"
        )
        let plain =
            "VVVUUUVIRSOBENNULEINSXXMITUUUVIRSIBENNULZWOYVIRSIBENNULDREIYZWODREISECHSEINSYZWODREIDREIACHTEINSDREIOITNACHWZSTENPASSIRT"
        let trueOffset = 23 // "MITUUUVIRSIBEN…"
        let crib = String(Array(plain)[trueOffset..<(trueOffset + 12)])
        let placement = M4CribDrag.drag(crib: crib, ciphertext: ct)
        XCTAssertTrue(
            placement.offsets.contains(trueOffset),
            "Crib-drag eliminated the true offset \(trueOffset) for '\(crib)'"
        )
        // A length-L crib should eliminate roughly 1 - (25/26)^L of offsets (~37% at L=12).
        XCTAssertGreaterThan(
            placement.eliminationRate,
            0.2,
            "No-self-encrypt rule eliminated implausibly few offsets"
        )
    }

    func testCribDragRejectsSelfEncryptingPlacements() {
        let ct = EnigmaAlphabet.normalize(U534MessageP1030680.ciphertext)
        for placement in M4CribDrag.dragAll(ciphertext: ct) {
            let crib = EnigmaAlphabet.normalize(placement.crib)
            for offset in placement.offsets {
                for index in crib.indices {
                    XCTAssertNotEqual(
                        crib[index],
                        ct[offset + index],
                        "Self-encryption survived crib-drag: '\(placement.crib)' @\(offset)"
                    )
                }
            }
        }
    }

    func testEvaluateBreakRejectsBigramFluentNonsense() {
        // Exact #1 false positive from the AAAA 336-WO sweep (likeness ~0.98, IC German-band,
        // only UND/SCH — must not be reported as a possible break).
        let nonsense = EnigmaAlphabet.normalize(
            "GOEEHGFEUSAEHBSIMYCHAGEISPPLENEHAGTZEUNXSBETTESLEGETDNUNDEWUECQKESCHWMEI"
        )
        let verdict = HostM4Bombe.evaluateBreak(plaintext: nonsense)
        XCTAssertFalse(verdict.isPossibleBreak, verdict.reason)
        XCTAssertTrue(verdict.strongCribHits.isEmpty, "Unexpected strong cribs: \(verdict.strongCribHits)")
        XCTAssertTrue(verdict.reason.contains("without naval structure"))
    }

    func testEvaluateBreakAcceptsKnownNavalPlaintext() {
        let german = EnigmaAlphabet.normalize(
            "VVVUUUVIRSOBENNULEINSXXMITUUUVIRSIBENNULZWOYVIRSIBENNULDREIYZWODREISECHSEINS"
        )
        let verdict = HostM4Bombe.evaluateBreak(plaintext: german)
        XCTAssertTrue(verdict.isPossibleBreak, verdict.reason)
        XCTAssertTrue(verdict.strongCribHits.contains("EINS") || verdict.strongCribHits.contains("UUU"))
    }

    func testScorerSeparatesGermanFromDegenerateHighICText() {
        // Regression for a false positive: an IC-maximising hill-climb produced this
        // letter-run "plaintext" with IC 0.149 (double German) and it was reported as a
        // possible break. The bigram model must rank it no better than random text.
        let german = EnigmaAlphabet.normalize(
            "VVVUUUVIRSOBENNULEINSXXMITUUUVIRSIBENNULZWOYVIRSIBENNULDREIYZWODREISECHSEINS"
        )
        let degenerate = EnigmaAlphabet.normalize(
            "KLHUXHUFUXOUUFIHOBUTKUMHURUCQDLXXUUUUJHWKSMSXMXUUUUUUKUFUOUSAUHDCIUUUYBD"
        )
        let germanLikeness = HostM4Bombe.germanLikeness(plaintext: german)
        let degenerateLikeness = HostM4Bombe.germanLikeness(plaintext: degenerate)

        XCTAssertGreaterThan(germanLikeness, 0.75, "Known German plaintext must score as German")
        XCTAssertLessThan(
            degenerateLikeness,
            0.25,
            "Degenerate letter-run scored \(degenerateLikeness) — false-positive guard failed"
        )
        // Its IC is high precisely because it is degenerate, so IC alone must not decide.
        XCTAssertGreaterThan(LanguageScorer.indexOfCoincidence(degenerate), 0.10)
    }

    func testBigramScoreRejectsSingleLetterRun() {
        let run = [Int](repeating: EnigmaAlphabet.index("U"), count: 72)
        XCTAssertEqual(LanguageScorer.indexOfCoincidence(run), 1.0, accuracy: 1e-9)
        XCTAssertLessThan(
            HostM4Bombe.germanLikeness(plaintext: run),
            0.25,
            "A constant letter run has maximal IC and must still score as non-German"
        )
    }

    func testP1030680IsNotPotsdamMessageKeySpaceWinner() {
        // Sanity: Thetis traffic should not decrypt as clear naval German under Potsdam.
        let ct = EnigmaAlphabet.normalize(U534MessageP1030680.ciphertext)
        let daily = EnigmaM4Key.potsdam1May1945(positions: (0, 0, 0, 0))
        let top = HostM4Bombe.exhaustMessageKeys(ciphertext: ct, dailyKey: daily, topK: 3)
        XCTAssertFalse(top.isEmpty)
        let preview = top[0].plaintext
        let navalCribHits = ["VVVUUU", "VONVON", "UUUVIR", "EINSXX"].filter { preview.contains($0) }
        XCTAssertTrue(
            navalCribHits.isEmpty,
            "Unexpected Potsdam naval crib on Thetis CT: \(preview.prefix(48)) hits=\(navalCribHits)"
        )
    }
}
