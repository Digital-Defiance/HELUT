import Foundation
import XCTest
@testable import HELUTCore
@testable import HELUTToolKit

/// Proves the soundness contract behind `Scripts/menu_diagonal_collapse.py` on the real board:
/// a placement is only ever dropped in favour of a menu that (a) contains all of its board
/// constraints and (b) is at least as strong. If both hold, running the keeper tests every
/// hypothesis the dropped menu would have, so the collapse evaluates the same key space at lower
/// GPU cost. The Python tool decides this from assertion sets; this checks the decision against
/// `BombeMenu.constraints`, the same structure the sweep consumes.
final class MenuDiagonalCollapseTests: XCTestCase {
    private let ciphertext = EnigmaAlphabet.normalize(U534MessageP1030680.ciphertext)

    private func menu(_ text: String, _ offset: Int) -> BombeMenu? {
        BombeMenuBuilder.menu(crib: text, offset: offset, ciphertext: ciphertext)
    }

    func testNestedPlacementConstraintsAreSubsetAndWeaker() throws {
        // A real nesting from the 2513-placement catalog: DMXUUUBOOTEY@1 is the 11-char prefix
        // of DMXUUUBOOTEYFXDXUUUAUSB@1 at the same offset.
        let sub = try XCTUnwrap(menu("DMXUUUBOOTEY", 1))
        let sup = try XCTUnwrap(menu("DMXUUUBOOTEYFXDXUUUAUSB", 1))

        XCTAssertTrue(sub.constraints.isSubset(of: sup.constraints),
                      "subset menu's board constraints are not contained in the superset")
        XCTAssertLessThanOrEqual(sub.loops, sup.loops,
                                 "dropped subset must not be stronger than its keeper")
        // The keeper genuinely adds constraints, so this is a real reduction not a rename.
        XCTAssertGreaterThan(sup.constraints.count, sub.constraints.count)
    }

    func testDistinctWindowsAreNotFalselyCollapsed() throws {
        // Two 40-char windows of the same source shifted by one letter (relay fixture) cover
        // DIFFERENT ciphertext positions, so neither is a subset of the other and both must
        // survive. This is the guard against over-collapsing genuinely distinct hypotheses.
        let a = try XCTUnwrap(menu("CHPRUEFENUSDNEUVERSCHLUESSELTABSETENXFUN", 12))
        let b = try XCTUnwrap(menu("HPRUEFENUSDNEUVERSCHLUESSELTABSETENXFUNL", 13))
        XCTAssertFalse(a.constraints.isSubset(of: b.constraints))
        XCTAssertFalse(b.constraints.isSubset(of: a.constraints))
    }

    func testKeepingASupersetTestsEveryConstraintOfTheDropped() throws {
        // The operational meaning of the collapse: every (step, plain, cipher) the dropped menu
        // would put on the board is already on the keeper's board.
        let sub = try XCTUnwrap(menu("DMXUUUBOOTEY", 27))
        let sup = try XCTUnwrap(menu("DMXUUUBOOTEYF", 27))
        for constraint in sub.constraints {
            XCTAssertTrue(sup.constraints.contains(constraint),
                          "keeper is missing a constraint the dropped menu asserts")
        }
    }
}
