import Foundation
import HELUTCore
import HELUTCLI

// MARK: - Isolated survivor debug
//
// One hardcoded stop, decrypted end to end, to answer a single question: when a
// Welchman survivor fails to reproduce its own crib, is the machine being set up
// wrong (a state translation bug between bombe and Enigma), or is the stecker the
// bombe handed us simply incomplete?
//
// The two hypotheses make different predictions, which is what makes this decisive:
//   * stepping / translation bug -> the crib breaks down from some position onward,
//     and a KNOWN-GOOD key run through the same initializer also breaks.
//   * partial steckerboard -> the crib fails only at letters the bombe never pinned,
//     and a known-good key with a full 10-plug board comes back perfect.

enum DebugSurvivor {

    private static let steckerPairs = ["AG", "CM", "EJ", "HK", "IQ", "NW", "OR"]
    private static let cribText = "UUUVIRSIBENNULEINS"

    private static func rotor(_ name: String) -> EnigmaRotorSpec {
        M4ThetisAttack.navalRotors.first { $0.name == name } ?? EnigmaWarehouse.rotorI
    }

    static func run() {
        print("=== Isolated survivor debug — P1030680 stop #1 ===")
        print("UKW B, Greek beta, WO VII-V-VIII, rings AAAH, pos PBMK")
        print("stecker \(steckerPairs.joined(separator: " ")) (\(steckerPairs.count) pairs)")
        print()

        var plugboard = Array(0..<26)
        for pair in steckerPairs {
            let chars = Array(pair)
            let a = EnigmaAlphabet.index(chars[0])
            let b = EnigmaAlphabet.index(chars[1])
            plugboard[a] = b
            plugboard[b] = a
        }

        let startPositions = EnigmaAlphabet.normalize("PBMK")
        let key = EnigmaM4Key(
            greek: EnigmaM4Warehouse.greek(named: "B"),
            rotors: (rotor("VII"), rotor("V"), rotor("VIII")),
            rings: EnigmaM4Key.rings(fromLetters: "AAAH"),
            positions: (startPositions[0], startPositions[1], startPositions[2], startPositions[3]),
            plugboard: plugboard,
            reflector: EnigmaM4Warehouse.thinReflector(named: "B")
        )

        let cipher = EnigmaAlphabet.normalize(U534MessageP1030680.ciphertext)
        var machine = EnigmaM4Machine(key: key)

        print("pre-keypress window: \(window(machine.key.positions))  (greek, left, middle, right)")
        let firstOut = machine.process(cipher[0])
        print("after letter 1:      \(window(machine.key.positions))"
            + "   \(EnigmaAlphabet.character(cipher[0])) -> \(EnigmaAlphabet.character(firstOut))")

        // Decrypt from a fresh machine so letter 1 is not consumed twice.
        var full = EnigmaM4Machine(key: key)
        let plainIndices = full.processText(cipher)
        let plaintext = EnigmaAlphabet.string(from: plainIndices)

        print()
        if plaintext.hasPrefix(cribText) {
            print("ASSERT PASS — the crib is reproduced exactly.")
            print("plaintext \(plaintext)")
            return
        }

        let produced = String(plaintext.prefix(18))
        print("ASSERT FAIL — expected prefix \(cribText)")
        print("             produced        \(produced)")
        print()
        print("  crib     \(cribText.map { String($0) }.joined(separator: " "))")
        print("  produced \(produced.map { String($0) }.joined(separator: " "))")
        print("  mismatch \(zip(cribText, produced).map { $0 == $1 ? "." : "X" }.joined(separator: " "))")
        print("  \(zip(cribText, produced).filter { $0 == $1 }.count)/18 agree")

        diagnose(cribText: cribText, produced: produced, plugboard: plugboard, key: key, cipher: cipher)
    }

    // MARK: Hypothesis tests

    private static func diagnose(
        cribText: String,
        produced: String,
        plugboard: [Int],
        key: EnigmaM4Key,
        cipher: [Int]
    ) {
        // Test 1 — are the failures confined to letters the bombe never pinned?
        let steckered = Set(steckerPairs.flatMap { $0.map { EnigmaAlphabet.index($0) } })
        var mismatchLetters: Set<Character> = []
        var mismatchesOnUnpinned = 0
        var mismatchCount = 0
        for (index, (expected, got)) in zip(cribText, produced).enumerated() where expected != got {
            mismatchCount += 1
            mismatchLetters.insert(expected)
            let cribPinned = steckered.contains(EnigmaAlphabet.index(expected))
            let cipherPinned = steckered.contains(cipher[index])
            if !cribPinned || !cipherPinned { mismatchesOnUnpinned += 1 }
        }
        print()
        print("--- Test 1: do the failures land on unpinned letters? ---")
        let pinned = steckered.sorted().map { String(EnigmaAlphabet.character($0)) }.joined()
        print("  stecker pins \(steckered.count) letters: \(pinned)")
        print("  free letters: "
            + (0..<26).filter { !steckered.contains($0) }
                .map { String(EnigmaAlphabet.character($0)) }.joined())
        print("  mismatching crib letters: \(mismatchLetters.sorted().map(String.init).joined())")
        print("  \(mismatchesOnUnpinned)/\(mismatchCount) mismatches involve a letter the bombe never pinned")

        // Test 2 — does a known-good key survive the same initializer?
        print()
        print("--- Test 2: same code path, known-good full key (P1030684) ---")
        let controlPositions = EnigmaAlphabet.normalize(ControlMessageP1030684.positions)
        var controlPlugs = Array(0..<26)
        for pair in ControlMessageP1030684.plugPairs {
            let chars = Array(pair)
            let a = EnigmaAlphabet.index(chars[0])
            let b = EnigmaAlphabet.index(chars[1])
            controlPlugs[a] = b
            controlPlugs[b] = a
        }
        let controlKey = EnigmaM4Key(
            greek: EnigmaM4Warehouse.greek(named: "C"),
            rotors: (rotor("IV"), rotor("III"), rotor("VIII")),
            rings: EnigmaM4Key.rings(fromLetters: ControlMessageP1030684.rings),
            positions: (controlPositions[0], controlPositions[1],
                        controlPositions[2], controlPositions[3]),
            plugboard: controlPlugs,
            reflector: EnigmaM4Warehouse.thinReflector(named: "B")
        )
        var controlMachine = EnigmaM4Machine(key: controlKey)
        let controlPlain = EnigmaAlphabet.string(
            from: controlMachine.processText(
                EnigmaAlphabet.normalize(ControlMessageP1030684.ciphertext)
            )
        )
        let controlOK = controlPlain == EnigmaAlphabet.string(
            from: EnigmaAlphabet.normalize(ControlMessageP1030684.plaintext)
        )
        print("  \(controlPlain)")
        print("  known plaintext reproduced: \(controlOK)")

        // Test 3 — does the machine step the way the bombe assumed?
        print()
        print("--- Test 3: machine window trail vs the bombe's assumed trail ---")
        let bombe = WelchmanBombe(
            greek: EnigmaM4Warehouse.greek(named: "B"),
            left: rotor("VII"), middle: rotor("V"), right: rotor("VIII"),
            reflector: EnigmaM4Warehouse.thinReflector(named: "B"),
            rings: EnigmaM4Key.rings(fromLetters: "AAAH"),
            maxPlugs: 10
        )
        let assumed = bombe.positionTrail(start: key.positions, length: 18)
        var walker = EnigmaM4Machine(key: key)
        var agree = 0
        var firstDivergence = -1
        for index in 0..<18 {
            _ = walker.process(cipher[index])
            let actual = (walker.key.positions.1, walker.key.positions.2, walker.key.positions.3)
            let expected = assumed[index]
            if actual == expected {
                agree += 1
            } else if firstDivergence < 0 {
                firstDivergence = index
                print("  first divergence at letter \(index + 1): "
                    + "machine \(triple(actual)) vs bombe \(triple(expected))")
            }
        }
        print("  \(agree)/18 window positions agree")

        print()
        print("=== Verdict ===")
        if controlOK && agree == 18 && mismatchesOnUnpinned == mismatchCount {
            print("  Partial steckerboard, not a state translation bug.")
            print("  The initializer and the stepping are correct: a known-good full key")
            print("  decrypts perfectly through this exact code path, and every window")
            print("  position matches what the bombe assumed. The crib fails only where")
            print("  the plugboard is missing, because the bombe seeds one letter and so")
            print("  only pins the menu component that letter can reach.")
        } else if !controlOK || agree < 18 {
            print("  State translation bug confirmed — a known-good key also fails,")
            print("  or the machine does not step the way the bombe assumed.")
        } else {
            print("  Mixed signal: the control passes and stepping agrees, but some")
            print("  mismatches sit on pinned letters. Inspect those positions directly.")
        }
    }

    private static func window(_ positions: (Int, Int, Int, Int)) -> String {
        EnigmaAlphabet.string(from: [positions.0, positions.1, positions.2, positions.3])
    }

    private static func triple(_ value: (Int, Int, Int)) -> String {
        EnigmaAlphabet.string(from: [value.0, value.1, value.2])
    }
}
