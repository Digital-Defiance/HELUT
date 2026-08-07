import XCTest
@testable import HELUTCore
@testable import HELUTToolKit

final class TuringLoopTests: XCTestCase {

    func testTriangleWalkIsTheThreeEdges() {
        let ends = [(0, 1), (1, 2), (2, 0)]
        let walks = TuringMenuWalks.walks(ends: ends, central: 0)
        XCTAssertEqual(walks.count, 1)
        XCTAssertEqual(Set(walks[0]), Set([0, 1, 2]))
        XCTAssertEqual(walks[0].count, 3)
    }

    func testALoopRejectionIsAClosureRejection() {
        let ends = [(0, 1), (1, 2), (2, 0)]
        // A transposition on the first edge and identities on the other two.
        // The product is the transposition, which fixes no point it moves.
        let identity = [UInt8](0..<26)
        var swap = identity
        swap[0] = 1
        swap[1] = 0
        let scramblers = [swap, identity, identity]
        let walks = TuringMenuWalks.walks(ends: ends, central: 0)
        XCTAssertFalse(TuringMenuWalks.passes(seed: 0, walks: walks, scramblers: scramblers))
        XCTAssertFalse(TuringMenuWalks.passes(seed: 1, walks: walks, scramblers: scramblers))
        XCTAssertTrue(TuringMenuWalks.passes(seed: 2, walks: walks, scramblers: scramblers))

        for seed in 0..<26 {
            let closed = WelchmanBombe.propagateCore(
                ends: ends, scramblers: scramblers, seedLetter: 0, seedValue: seed
            ) != nil
            let loop = TuringMenuWalks.passes(seed: seed, walks: walks, scramblers: scramblers)
            if closed {
                XCTAssertTrue(loop, "seed \(seed) survived the board and failed a walk")
            }
            if !loop {
                XCTAssertFalse(closed, "seed \(seed) failed a walk and survived the board")
            }
        }
    }

    func testCatalogMenuAgreesOnRealScramblers() throws {
        let ciphertext = EnigmaAlphabet.normalize(
            "JCRSAJTGSJEYEXYKKZZSHVUOCTRFRCRPFVYPLKPPLGRHVVBBTBRSXSWXGGTYTVKQNGSCHVGF"
        )
        let menu = try XCTUnwrap(BombeMenuBuilder.menu(
            crib: "NFUNFUUUFLOTTXNULEINSZWONULBEIROTNULSIBE",
            offset: 18,
            ciphertext: ciphertext
        ))
        XCTAssertGreaterThan(menu.loops, 0)
        let walks = TuringMenuWalks.walks(ends: menu.ends, central: menu.central)
        XCTAssertFalse(walks.isEmpty)

        let bombe = WelchmanBombe(
            greek: EnigmaM4Warehouse.beta,
            left: EnigmaWarehouse.rotorI,
            middle: EnigmaWarehouse.rotorII,
            right: EnigmaWarehouse.rotorVIII,
            reflector: EnigmaM4Warehouse.thinB,
            rings: (0, 0, 0, 0),
            maxPlugs: 0
        )
        var killed = 0
        for lane in [0, 3, 26, 100, 676, 17576, 90000] {
            let start = WelchmanMetalEngine.position(forLane: lane)
            let tables = bombe.scramblers(menu: menu, start: start)
            for seed in 0..<26 {
                let closed = WelchmanBombe.propagate(
                    menu: menu, scramblers: tables,
                    seedLetter: menu.central, seedValue: seed
                ) != nil
                let loop = TuringMenuWalks.passes(
                    seed: seed, walks: walks, scramblers: tables
                )
                if !loop { killed += 1 }
                if closed {
                    XCTAssertTrue(loop, "lane \(lane) seed \(seed) survived and failed a walk")
                }
            }
        }
        XCTAssertGreaterThan(killed, 0)
    }

    func testStepTableMatchesAHandWorkedNotch() throws {
        // Middle notch only at A, right wheel never notches. The first letter steps
        // the middle and the left once, and nothing steps after that.
        let packed = try XCTUnwrap(WelchmanStepTable.pack(
            notchM: [0], notchR: [], horizon: 72
        ))
        let base = 0
        XCTAssertEqual(packed[base], 0)
        XCTAssertEqual(packed[base + 1], WelchmanStepTable.never)
        XCTAssertEqual(packed[base + WelchmanStepTable.leftSlots], 0)
        XCTAssertEqual(packed[base + WelchmanStepTable.leftSlots + 1], WelchmanStepTable.never)

        // Right notch at A, middle notch nowhere near the walk's start. Letter 0 steps
        // the middle only.
        let right = try XCTUnwrap(WelchmanStepTable.pack(
            notchM: [13], notchR: [0], horizon: 72
        ))
        XCTAssertEqual(right[WelchmanStepTable.leftSlots], 0)
        XCTAssertEqual(right[0], WelchmanStepTable.never)
    }

    func testMetalStopsMatchTheHostBoard() throws {
        guard WelchmanMetalEngine(depth: 1) != nil else {
            throw XCTSkip("no Metal device")
        }
        let ciphertext = EnigmaAlphabet.normalize(
            "JCRSAJTGSJEYEXYKKZZSHVUOCTRFRCRPFVYPLKPPLGRHVVBBTBRSXSWXGGTYTVKQNGSCHVGF"
        )
        let menu = try XCTUnwrap(BombeMenuBuilder.menu(
            crib: "NFUNFUUUFLOTTXNULEINSZWONULBEIROTNULSIBE",
            offset: 18,
            ciphertext: ciphertext
        ))
        XCTAssertNotNil(
            WelchmanStepTable.pack(
                notchM: EnigmaWarehouse.rotorIII.notches,
                notchR: EnigmaWarehouse.rotorVIII.notches,
                horizon: menu.stepHorizon
            ),
            "this menu overflows the step table, so the GPU comparison would not exercise it"
        )
        let greek = EnigmaM4Warehouse.gamma
        let left = EnigmaWarehouse.rotorIV
        let middle = EnigmaWarehouse.rotorIII
        let right = EnigmaWarehouse.rotorVIII
        let reflector = EnigmaM4Warehouse.thinB
        let rings = (0, 0, 0, 4)
        guard let engine = WelchmanMetalEngine(depth: 1),
              let survivors = engine.sweep(
                menu: menu, greek: greek, left: left, middle: middle, right: right,
                reflector: reflector, rings: rings
              ) else {
            XCTFail("sweep did not run")
            return
        }
        let bombe = WelchmanBombe(
            greek: greek, left: left, middle: middle, right: right,
            reflector: reflector, rings: rings, maxPlugs: 0
        )
        let adopted = Array(survivors)
        engine.adoptStepTable = false
        engine.wideLoopTest = false
        guard let walked = engine.sweep(
            menu: menu, greek: greek, left: left, middle: middle, right: right,
            reflector: reflector, rings: rings
        ) else {
            XCTFail("notch-walk sweep did not run")
            return
        }
        var adoptedFold: UInt64 = 0
        var walkedFold: UInt64 = 0
        for lane in 0..<WelchmanMetalEngine.laneCount {
            adoptedFold ^= UInt64(adopted[lane]) &+ UInt64(lane)
            walkedFold ^= UInt64(walked[lane]) &+ UInt64(lane)
        }
        XCTAssertEqual(
            adoptedFold, walkedFold,
            "step table and 4-wide loop test changed a stop"
        )

        for lane in [0, 1, 25, 26, 675, 676, 17_576, 100_000, 456_975] {
            let mask = adopted[lane]
            if mask == welchmanUndecidedMask { continue }
            let start = WelchmanMetalEngine.position(forLane: lane)
            let host = bombe.test(menu: menu, start: start)
            var hostMask: UInt32 = 0
            for stop in host {
                hostMask |= UInt32(1) << UInt32(stop.seedValue)
            }
            XCTAssertEqual(
                mask, hostMask,
                "lane \(lane) GPU \(String(mask, radix: 2)) host \(String(hostMask, radix: 2))"
            )
        }
    }
}
