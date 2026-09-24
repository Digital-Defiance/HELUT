import XCTest
@testable import HELUTCore

/// Enigma I is not M4 with a wheel pulled out. The Greek wheel is static, but the
/// thin UKW was cut to be used *with* it. Compatibility is one parking:
/// β at window A / ring A + thin B ≡ thick B; γ at A/A + thin C ≡ thick C.
final class EnigmaICompatibilityTests: XCTestCase {

    private let phrase = "KEINEBESONDERENEREIGNISSE"
    private let plugs: [(Character, Character)] = [
        ("A", "M"), ("B", "C"), ("D", "F"), ("G", "H"), ("I", "J"),
        ("K", "L"), ("N", "O"), ("P", "Q"), ("R", "S"), ("T", "U")
    ]
    /// Cross-checked with `Tests/python/test_enigma_i_compat.py` (Python I3).
    private let i3ThickBCiphertext = "HNVUSQZJIDSUHTXLZUTMUTMLH"
    private let i3ThickCCiphertext = "ZASFURJBLPUCBZKVHFAEMAAEL"

    func testBetaThinBAtAAEqualsThickB() {
        XCTAssertEqual(
            greekThenThin(greek: EnigmaM4Warehouse.beta, thin: EnigmaM4Warehouse.thinB),
            EnigmaWarehouse.reflectorB
        )
    }

    func testGammaThinCAtAAEqualsThickC() {
        XCTAssertEqual(
            greekThenThin(greek: EnigmaM4Warehouse.gamma, thin: EnigmaM4Warehouse.thinC),
            EnigmaWarehouse.reflectorC
        )
    }

    func testWrongGreekThinPairIsNotThickBOrC() {
        let betaThinC = greekThenThin(greek: EnigmaM4Warehouse.beta, thin: EnigmaM4Warehouse.thinC)
        let gammaThinB = greekThenThin(greek: EnigmaM4Warehouse.gamma, thin: EnigmaM4Warehouse.thinB)
        XCTAssertNotEqual(betaThinC, EnigmaWarehouse.reflectorB)
        XCTAssertNotEqual(betaThinC, EnigmaWarehouse.reflectorC)
        XCTAssertNotEqual(gammaThinB, EnigmaWarehouse.reflectorB)
        XCTAssertNotEqual(gammaThinB, EnigmaWarehouse.reflectorC)
    }

    func testGreekOffAIsNotThickB() {
        XCTAssertNotEqual(
            greekThenThin(
                greek: EnigmaM4Warehouse.beta,
                thin: EnigmaM4Warehouse.thinB,
                position: EnigmaAlphabet.index("B")
            ),
            EnigmaWarehouse.reflectorB
        )
        XCTAssertNotEqual(
            greekThenThin(
                greek: EnigmaM4Warehouse.beta,
                thin: EnigmaM4Warehouse.thinB,
                ring: EnigmaAlphabet.index("B")
            ),
            EnigmaWarehouse.reflectorB
        )
    }

    func testParkedBetaThinBDecryptsLikeEnigmaIThickB() {
        XCTAssertEqual(processI3(reflector: EnigmaWarehouse.reflectorB), i3ThickBCiphertext)
        XCTAssertEqual(
            processParkedM4(greek: EnigmaM4Warehouse.beta, thin: EnigmaM4Warehouse.thinB),
            i3ThickBCiphertext
        )
    }

    func testParkedGammaThinCDecryptsLikeEnigmaIThickC() {
        XCTAssertEqual(processI3(reflector: EnigmaWarehouse.reflectorC), i3ThickCCiphertext)
        XCTAssertEqual(
            processParkedM4(greek: EnigmaM4Warehouse.gamma, thin: EnigmaM4Warehouse.thinC),
            i3ThickCCiphertext
        )
    }

    func testGreekWindowBDoesNotMatchEnigmaI() {
        var m4 = parkedM4Key(greek: EnigmaM4Warehouse.beta, thin: EnigmaM4Warehouse.thinB)
        m4.positions.0 = EnigmaAlphabet.index("B")
        var machine = EnigmaM4Machine(key: m4)
        XCTAssertNotEqual(machine.processString(phrase), i3ThickBCiphertext)
    }

    func testEnigmaIRoundTrip() {
        var enc = EnigmaMachine(key: i3Key(reflector: EnigmaWarehouse.reflectorB))
        let ct = enc.processString(phrase)
        var dec = EnigmaMachine(key: i3Key(reflector: EnigmaWarehouse.reflectorB))
        XCTAssertEqual(dec.processString(ct), phrase)
        XCTAssertNotEqual(ct, phrase)
    }

    func testReflectorNamedCIsThickC() {
        XCTAssertEqual(EnigmaWarehouse.reflector(named: "C"), EnigmaWarehouse.reflectorC)
    }

    private func i3Key(reflector: [Int]) -> EnigmaKey {
        EnigmaKey(
            rotors: (EnigmaWarehouse.rotorI, EnigmaWarehouse.rotorII, EnigmaWarehouse.rotorIII),
            rings: (0, 0, 0),
            positions: (
                EnigmaAlphabet.index("A"),
                EnigmaAlphabet.index("B"),
                EnigmaAlphabet.index("C")
            ),
            plugboard: EnigmaKey.plugboard(pairs: plugs),
            reflector: reflector
        )
    }

    private func parkedM4Key(greek: EnigmaRotorSpec, thin: [Int]) -> EnigmaM4Key {
        EnigmaM4Key(
            greek: greek,
            rotors: (EnigmaWarehouse.rotorI, EnigmaWarehouse.rotorII, EnigmaWarehouse.rotorIII),
            rings: (0, 0, 0, 0),
            positions: (
                EnigmaAlphabet.index("A"),
                EnigmaAlphabet.index("A"),
                EnigmaAlphabet.index("B"),
                EnigmaAlphabet.index("C")
            ),
            plugboard: EnigmaKey.plugboard(pairs: plugs),
            reflector: thin
        )
    }

    private func processI3(reflector: [Int]) -> String {
        var machine = EnigmaMachine(key: i3Key(reflector: reflector))
        return machine.processString(phrase)
    }

    private func processParkedM4(greek: EnigmaRotorSpec, thin: [Int]) -> String {
        var machine = EnigmaM4Machine(key: parkedM4Key(greek: greek, thin: thin))
        return machine.processString(phrase)
    }

    private func greekThenThin(
        greek: EnigmaRotorSpec,
        thin: [Int],
        position: Int = 0,
        ring: Int = 0
    ) -> [Int] {
        (0..<26).map { input in
            let offset = (position - ring + 26) % 26
            var value = (greek.wiring[(input + offset) % 26] - offset + 26) % 26
            value = thin[value]
            return (greek.inverse[(value + offset) % 26] - offset + 26) % 26
        }
    }
}
