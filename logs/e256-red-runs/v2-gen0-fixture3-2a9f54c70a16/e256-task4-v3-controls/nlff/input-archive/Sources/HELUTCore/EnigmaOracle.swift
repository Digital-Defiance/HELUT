import Foundation

// MARK: - Enigma letter helpers

package enum EnigmaAlphabet {
    package static let size = 26

    package static func index(_ character: Character) -> Int {
        let upper = Character(character.uppercased())
        guard let ascii = upper.asciiValue, ascii >= 65, ascii <= 90 else {
            preconditionFailure("Enigma letter out of range: \(character)")
        }
        return Int(ascii - 65)
    }

    package static func character(_ index: Int) -> Character {
        let clamped = ((index % size) + size) % size
        return Character(UnicodeScalar(65 + clamped)!)
    }

    package static func normalize(_ text: String) -> [Int] {
        text.uppercased().compactMap { character -> Int? in
            guard let ascii = character.asciiValue, ascii >= 65, ascii <= 90 else { return nil }
            return Int(ascii - 65)
        }
    }

    package static func string(from indices: [Int]) -> String {
        String(indices.map { character($0) })
    }
}

// MARK: - Rotor / reflector tables (historical Wehrmacht)

package struct EnigmaRotorSpec: Sendable {
    package let name: String
    package let wiring: [Int] // forward permutation
    package let inverse: [Int]
    /// Turnover notches (window letter indices). Naval VI–VIII have two.
    package let notches: [Int]

    package init(name: String, wiring: String, notches: String) {
        precondition(wiring.count == 26)
        precondition(!notches.isEmpty)
        let forward = EnigmaAlphabet.normalize(wiring)
        var inverse = [Int](repeating: 0, count: 26)
        for (input, output) in forward.enumerated() {
            inverse[output] = input
        }
        self.name = name
        self.wiring = forward
        self.inverse = inverse
        self.notches = EnigmaAlphabet.normalize(notches)
    }

    package init(name: String, wiring: String, notch: Character) {
        self.init(name: name, wiring: wiring, notches: String(notch))
    }

    package func isAtNotch(position: Int) -> Bool {
        notches.contains(position)
    }
}

package enum EnigmaWarehouse {
    package static let rotorI = EnigmaRotorSpec(name: "I", wiring: "EKMFLGDQVZNTOWYHXUSPAIBRCJ", notch: "Q")
    package static let rotorII = EnigmaRotorSpec(name: "II", wiring: "AJDKSIRUXBLHWTMCQGZNPYFVOE", notch: "E")
    package static let rotorIII = EnigmaRotorSpec(name: "III", wiring: "BDFHJLCPRTXVZNYEIWGAKMUSQO", notch: "V")
    package static let rotorIV = EnigmaRotorSpec(name: "IV", wiring: "ESOVPZJAYQUIRHXLNFTGKDCMWB", notch: "J")
    package static let rotorV = EnigmaRotorSpec(name: "V", wiring: "VZBRGITYUPSDNHLXAWMJQOFECK", notch: "Z")
    package static let rotorVI = EnigmaRotorSpec(name: "VI", wiring: "JPGVOUMFYQBENHZRDKASXLICTW", notches: "MZ")
    package static let rotorVII = EnigmaRotorSpec(name: "VII", wiring: "NZJHGRCXMYSWBOUFAIVLPEKQDT", notches: "MZ")
    package static let rotorVIII = EnigmaRotorSpec(name: "VIII", wiring: "FKQHTLXOCBJSPDZRAMEWNIUYGV", notches: "MZ")

    package static let reflectorA: [Int] = EnigmaAlphabet.normalize("EJMZALYXVBWFCRQUONTSPIKHGD")
    package static let reflectorB: [Int] = EnigmaAlphabet.normalize("YRUHQSLDPXNGOKMIEBFZCWVJAT")

    package static func rotor(named name: String) -> EnigmaRotorSpec {
        switch name.uppercased() {
        case "I", "1": return rotorI
        case "II", "2": return rotorII
        case "III", "3": return rotorIII
        case "IV", "4": return rotorIV
        case "V", "5": return rotorV
        case "VI", "6": return rotorVI
        case "VII", "7": return rotorVII
        case "VIII", "8": return rotorVIII
        default: preconditionFailure("Unknown rotor '\(name)'")
        }
    }

    package static func reflector(named name: String) -> [Int] {
        switch name.uppercased() {
        case "A": return reflectorA
        case "B": return reflectorB
        default: preconditionFailure("Unknown reflector '\(name)'")
        }
    }

    /// Ring numbers as published (01…26) → 0…25 indices.
    package static func rings(fromNumbers numbers: [Int]) -> (Int, Int, Int) {
        precondition(numbers.count == 3)
        let mapped = numbers.map { value -> Int in
            precondition((1...26).contains(value))
            return value - 1
        }
        return (mapped[0], mapped[1], mapped[2])
    }
}

/// Daily / message key for a three-rotor Wehrmacht Enigma I / M3.
package struct EnigmaKey: Sendable {
    /// Left, middle, right rotor specs (slow → fast).
    package let rotors: (EnigmaRotorSpec, EnigmaRotorSpec, EnigmaRotorSpec)
    /// Ringstellung left/middle/right as 0…25 (A=0 / ring 01).
    package let rings: (Int, Int, Int)
    /// Window / Grundstellung left/middle/right as 0…25 (A=0).
    package var positions: (Int, Int, Int)
    /// Steckerbrett permutation (identity if empty).
    package let plugboard: [Int]
    /// Reflector permutation (A or B for I/M3).
    package let reflector: [Int]

    package static func identityPlugboard() -> [Int] {
        Array(0..<26)
    }

    package static func plugboard(pairs: [(Character, Character)]) -> [Int] {
        var map = identityPlugboard()
        for (leftChar, rightChar) in pairs {
            let left = EnigmaAlphabet.index(leftChar)
            let right = EnigmaAlphabet.index(rightChar)
            precondition(map[left] == left && map[right] == right, "Plug clash involving \(leftChar)/\(rightChar)")
            map[left] = right
            map[right] = left
        }
        return map
    }

    /// HELUT Verilog baseline: L=I, M=II, R=III, rings AAA, empty stecker, reflector B.
    package static func helutBaseline(positions: (Int, Int, Int)) -> EnigmaKey {
        EnigmaKey(
            rotors: (EnigmaWarehouse.rotorI, EnigmaWarehouse.rotorII, EnigmaWarehouse.rotorIII),
            rings: (0, 0, 0),
            positions: positions,
            plugboard: identityPlugboard(),
            reflector: EnigmaWarehouse.reflectorB
        )
    }

    package init(
        rotors: (EnigmaRotorSpec, EnigmaRotorSpec, EnigmaRotorSpec),
        rings: (Int, Int, Int),
        positions: (Int, Int, Int),
        plugboard: [Int],
        reflector: [Int] = EnigmaWarehouse.reflectorB
    ) {
        self.rotors = rotors
        self.rings = rings
        self.positions = positions
        self.plugboard = plugboard
        self.reflector = reflector
    }
}

/// Faithful three-rotor Enigma (double-stepping), matching `enigma_core.v` when rings=AAA and stecker empty.
package struct EnigmaMachine {
    package var key: EnigmaKey

    package init(key: EnigmaKey) {
        self.key = key
    }

    package mutating func reset(positions: (Int, Int, Int)) {
        key.positions = positions
    }

    /// Encrypt/decrypt one letter (Enigma is involutory). Steps first, then scrambles.
    package mutating func process(_ input: Int) -> Int {
        step()
        var value = key.plugboard[input]
        value = rotorForward(value, rotor: key.rotors.2, position: key.positions.2, ring: key.rings.2)
        value = rotorForward(value, rotor: key.rotors.1, position: key.positions.1, ring: key.rings.1)
        value = rotorForward(value, rotor: key.rotors.0, position: key.positions.0, ring: key.rings.0)
        value = key.reflector[value]
        value = rotorReverse(value, rotor: key.rotors.0, position: key.positions.0, ring: key.rings.0)
        value = rotorReverse(value, rotor: key.rotors.1, position: key.positions.1, ring: key.rings.1)
        value = rotorReverse(value, rotor: key.rotors.2, position: key.positions.2, ring: key.rings.2)
        return key.plugboard[value]
    }

    package mutating func processText(_ indices: [Int]) -> [Int] {
        indices.map { process($0) }
    }

    package mutating func processString(_ text: String) -> String {
        EnigmaAlphabet.string(from: processText(EnigmaAlphabet.normalize(text)))
    }

    private mutating func step() {
        let notchRight = key.rotors.2.isAtNotch(position: key.positions.2)
        let notchMiddle = key.rotors.1.isAtNotch(position: key.positions.1)
        // Double-stepping: middle steps on its own notch or right's notch; left on middle's notch.
        if notchMiddle {
            key.positions.0 = (key.positions.0 + 1) % 26
        }
        if notchMiddle || notchRight {
            key.positions.1 = (key.positions.1 + 1) % 26
        }
        key.positions.2 = (key.positions.2 + 1) % 26
    }

    private func rotorForward(_ input: Int, rotor: EnigmaRotorSpec, position: Int, ring: Int) -> Int {
        let offset = (position - ring + 26) % 26
        let shifted = (input + offset) % 26
        let wired = rotor.wiring[shifted]
        return (wired - offset + 26) % 26
    }

    private func rotorReverse(_ input: Int, rotor: EnigmaRotorSpec, position: Int, ring: Int) -> Int {
        let offset = (position - ring + 26) % 26
        let shifted = (input + offset) % 26
        let wired = rotor.inverse[shifted]
        return (wired - offset + 26) % 26
    }
}

// MARK: - Host-side Bombe (cleartext batch decrypt)

package struct BombeLaneResult: Sendable {
    package let lane: Int
    package let positions: (Int, Int, Int)
    package let plaintext: [Int]
    package let plaintextString: String
    package let score: Double
    package let indexOfCoincidence: Double
}

package enum HostEnigmaBombe {
    /// Decrypt `ciphertext` under `baseKey` for each lane's Grundstellung; score with language model.
    package static func run(
        ciphertext: [Int],
        baseKey: EnigmaKey,
        positionsPerLane: [(Int, Int, Int)],
        scorer: LanguageScorer = LanguageScorer.germanMilitary()
    ) -> [BombeLaneResult] {
        precondition(!positionsPerLane.isEmpty)
        return positionsPerLane.enumerated().map { lane, positions in
            var key = baseKey
            key.positions = positions
            var machine = EnigmaMachine(key: key)
            let plain = machine.processText(ciphertext)
            let ic = LanguageScorer.indexOfCoincidence(plain)
            let score = scorer.score(plain)
            return BombeLaneResult(
                lane: lane,
                positions: positions,
                plaintext: plain,
                plaintextString: EnigmaAlphabet.string(from: plain),
                score: score,
                indexOfCoincidence: ic
            )
        }
    }

    /// Lane 0…batch-1 map used by HELUT-Bombe harness (unique triples for first 10_000).
    package static func helutGrundstellung(lane: Int) -> (Int, Int, Int) {
        let rotorR = lane % 26
        let rotorM = (lane / 26) % 26
        let rotorL = (lane / (26 * 26)) % 26
        return (rotorL, rotorM, rotorR) // L, M, R
    }
}
