import XCTest
@testable import HELUTCore
@testable import HELUTToolKit

final class OstwaldBreakBarTests: XCTestCase {

    private let naval = EnigmaAlphabet.normalize(
        "VVVUUUVIRSOBENNULEINSXXMITUUUVIRSIBENNULZWO"
    )

    func testEmptyCribIsNotExact() {
        XCTAssertFalse(
            OstwaldBreakBar.cribExact(
                anchors: [BombeMenuAnchor(text: "", offset: 0)],
                plaintext: naval
            )
        )
    }

    func testShortCribIsNotExact() {
        XCTAssertEqual(OstwaldBreakBar.minAttestedCrib, 16)
        XCTAssertFalse(
            OstwaldBreakBar.cribExact(
                anchors: [BombeMenuAnchor(text: "VVVUUUVIRSOBENN", offset: 0)],
                plaintext: naval
            )
        )
    }

    func testSixteenLetterCribExact() {
        let crib = "VVVUUUVIRSOBENNU"
        XCTAssertEqual(crib.count, 16)
        XCTAssertTrue(
            OstwaldBreakBar.cribExact(
                anchors: [BombeMenuAnchor(text: crib, offset: 0)],
                plaintext: naval
            )
        )
    }

    func testWrongSixteenLetterCribIsNotExact() {
        XCTAssertFalse(
            OstwaldBreakBar.cribExact(
                anchors: [BombeMenuAnchor(text: "KEINEBESONDERENE", offset: 0)],
                plaintext: naval
            )
        )
    }

    func testEmptyCribCannotClearTheBarEvenWithGermanIC() {
        XCTAssertFalse(
            OstwaldBreakBar.clears(
                cribExact: false,
                ic: 0.0657,
                tail: -2.9671,
                pairCount: 10
            )
        )
        XCTAssertTrue(
            OstwaldBreakBar.clears(
                cribExact: true,
                ic: 0.0657,
                tail: -2.9671,
                pairCount: 10
            )
        )
    }

    func testP1030680WorkingPriorIsOperationalStripeNotPotsdam() {
        let shell = OstwaldAllSettings.workingPriorShell
        XCTAssertEqual(shell.ukw, "B")
        XCTAssertEqual(shell.greek, "beta")
        XCTAssertEqual(shell.wheelOrder, "IV-III-VIII")
        XCTAssertEqual(shell.rings, "AAAA")
        XCTAssertNotEqual(shell.rings, "AACU")
    }

    func testP1030680CiphertextIsSeventyTwoLetters() {
        XCTAssertEqual(U534MessageP1030680.ciphertext.count, 72)
    }

    func testBombeCLIRoutesP1030680Control() {
        XCTAssertTrue(
            HelutBombeCLI.handles(["--ostwald-all-settings", "--ostwald-control", "p1030680"])
        )
    }
}
