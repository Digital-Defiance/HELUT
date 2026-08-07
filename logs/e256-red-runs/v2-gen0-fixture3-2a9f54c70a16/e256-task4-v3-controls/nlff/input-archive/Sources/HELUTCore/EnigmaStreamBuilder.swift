import Foundation

/// Builds TensorLUT `AdversarialStreamTarget`s for `enigma_m4_core` wire map.
package enum EnigmaStreamBuilder {
    /// `resetn`
    package static let wireResetN: Int32 = 3
    /// `ciphertext_char[7:0]` LSB → MSB
    package static let wireCT: [Int32] = Array(4...11)
    /// `plaintext_char[4:0]` live letter bits
    package static let wirePT: [Int32] = Array(12...16)

    /// `rotor_r` Q wires (LSB →)
    package static let rotorR: [Int32] = [37, 34, 42, 41, 39]
    /// `rotor_m` Q wires
    package static let rotorM: [Int32] = [72, 69, 81, 83, 82, 78, 77, 75]
    /// `rotor_l` Q wires
    package static let rotorL: [Int32] = [52, 62, 61, 64, 63, 57, 58, 55]

    /// Converts A–Z cribs + Grundstellung (L/M/R windows 0…25) into a TensorLUT stream target.
    ///
    /// Each step: `resetn=1` + 8 CT bits in; expected = 5 PT bits out.
    package static func buildTarget(
        ciphertext: String,
        plaintext: String,
        left: Int,
        middle: Int,
        right: Int
    ) -> AdversarialStreamTarget {
        let ct = EnigmaAlphabet.normalize(ciphertext)
        let pt = EnigmaAlphabet.normalize(plaintext)
        precondition(ct.count == pt.count, "ciphertext/plaintext length mismatch")
        precondition(ct.count > 0, "empty crib")
        precondition((0...25).contains(left) && (0...25).contains(middle) && (0...25).contains(right))

        var inputSequence: [[[Float]]] = []
        var expectedSequence: [[[Float]]] = []
        inputSequence.reserveCapacity(ct.count)
        expectedSequence.reserveCapacity(ct.count)

        for i in ct.indices {
            var stepInputs: [Float] = [1.0] // resetn
            let ctVal = ct[i]
            for bit in 0..<8 {
                stepInputs.append(Float((ctVal >> bit) & 1))
            }
            inputSequence.append([stepInputs])

            var stepExpected: [Float] = []
            let ptVal = pt[i]
            for bit in 0..<5 {
                stepExpected.append(Float((ptVal >> bit) & 1))
            }
            expectedSequence.append([stepExpected])
        }

        var initialDFFs: [Int32: Float] = [:]
        bindRotor(val: right, wires: rotorR, into: &initialDFFs)
        bindRotor(val: middle, wires: rotorM, into: &initialDFFs)
        bindRotor(val: left, wires: rotorL, into: &initialDFFs)

        return AdversarialStreamTarget(
            inputWireIDs: [wireResetN] + wireCT,
            outputWireIDs: wirePT,
            inputSequence: inputSequence,
            expectedSequence: expectedSequence,
            initialDFFStates: initialDFFs
        )
    }

    /// Convenience: `(r, m, l)` window letters as in naval notation (fast→slow still seeded L/M/R).
    package static func buildTarget(
        ciphertext: String,
        plaintext: String,
        grundstellung: (r: Int, m: Int, l: Int)
    ) -> AdversarialStreamTarget {
        buildTarget(
            ciphertext: ciphertext,
            plaintext: plaintext,
            left: grundstellung.l,
            middle: grundstellung.m,
            right: grundstellung.r
        )
    }

    private static func bindRotor(val: Int, wires: [Int32], into map: inout [Int32: Float]) {
        for (idx, wire) in wires.enumerated() {
            map[wire] = Float((val >> idx) & 1)
        }
    }
}
