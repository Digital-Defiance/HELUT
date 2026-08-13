import Foundation

// MARK: - Enigma256 SoftBus formal surface (Pillar III)
//
// Machine-checkable lemmas for reciprocity / bijection / fail-closed generation.
// Red-team grades (TensorLUT, KPA, ent) are separate empirical evidence.
// This is not a security proof against all adversaries — structural SoftBus contract.

/// Named lemmas for polymorphic SoftBus ciphers.
package enum Enigma256Lemma: String, Sendable {
    /// Frozen-state scramble is a permutation of {0…255}.
    case scrambleBijection
    /// Frozen-state scramble is an involution (encrypt ≡ decrypt under same state).
    case scrambleReciprocity
    /// Stream encrypt-then-decrypt recovers plaintext under identical day+message keys.
    case streamRoundTrip
    /// Day-key plugboard is a fixed-point-free involution; un-reflector is an involution.
    case dayKeyInvolutions
    /// Generation harden rejects coupledCubic6 (fail-closed toward independent cubic6).
    case failClosedCoupling
}

package struct Enigma256ProofStep: Sendable, Equatable {
    package var lemma: Enigma256Lemma
    package var holds: Bool
    package var note: String

    package init(lemma: Enigma256Lemma, holds: Bool, note: String = "") {
        self.lemma = lemma
        self.holds = holds
        self.note = note
    }
}

/// Certificate that E256 SoftBus contracts satisfy the structural lemmas.
package struct Enigma256FormalCertificate: Sendable, Equatable {
    package var steps: [Enigma256ProofStep]
    package var hypotheses: [String]

    package var allHold: Bool { steps.allSatisfy(\.holds) }

    package init(steps: [Enigma256ProofStep], hypotheses: [String]) {
        self.steps = steps
        self.hypotheses = hypotheses
    }

    package func assertValid(file: StaticString = #file, line: UInt = #line) {
        precondition(allHold, "Enigma256FormalCertificate failed at \(file):\(line)")
    }
}

/// Prove / check Pillar III structural lemmas (not an IND-CPA proof).
package enum Enigma256Formal {
    private static func fixtureDay() -> Enigma256DayKey {
        Enigma256KDF.deriveDayKey(
            ikm: Data("enigma256-formal-certificate-v1".utf8)
        )
    }

    /// Lemma: scramble under a frozen machine is bijective.
    package static func checkScrambleBijection(states: Int = 4, seed: UInt64 = 0xE256_B1) -> Bool {
        let day = fixtureDay()
        let report = Enigma256Bijection.sweep(
            day: day, states: states, streamBytes: 0, seed: seed
        )
        return report.failure == nil && report.statesChecked == states
    }

    /// Lemma: scramble² = id on every byte (reciprocity).
    package static func checkScrambleReciprocity(seed: UInt32 = 0xE256_B2) -> Bool {
        let day = fixtureDay()
        var rng = LCG32(state: seed)
        let message = Enigma256MessageKey(
            rotorIndices: (0, 1, 2, 3),
            positions: (
                UInt8(truncatingIfNeeded: rng.next()),
                UInt8(truncatingIfNeeded: rng.next()),
                UInt8(truncatingIfNeeded: rng.next()),
                UInt8(truncatingIfNeeded: rng.next())
            ),
            lfsrSeed: max(1, UInt64(rng.next()) | 1)
        )
        let machine = Enigma256Machine(day: day, message: message)
        return Enigma256Bijection.verifyFrozenScramble(machine) == nil
    }

    /// Lemma: stream round-trip under identical keys.
    package static func checkStreamRoundTrip(bytes: Int = 128, seed: UInt32 = 0xE256_B3) -> Bool {
        let day = fixtureDay()
        var rng = LCG32(state: seed)
        let message = Enigma256MessageKey(
            rotorIndices: (4, 5, 6, 7),
            positions: (1, 2, 3, 4),
            lfsrSeed: max(1, UInt64(rng.next()) | 1)
        )
        var plain = [UInt8](repeating: 0, count: bytes)
        for i in 0 ..< bytes {
            plain[i] = UInt8(truncatingIfNeeded: rng.next())
        }
        return Enigma256Bijection.verifyStreamRoundTrip(
            day: day, message: message, streamBytes: bytes, plaintext: plain
        ) == nil
    }

    private static func isInvolution(_ table: [UInt8], allowFixedPoints: Bool) -> Bool {
        guard table.count == 256 else { return false }
        for i in 0 ..< 256 {
            let j = Int(table[i])
            if Int(table[j]) != i { return false }
            if !allowFixedPoints && j == i { return false }
        }
        return true
    }

    /// Lemma: derived day-key plugboard / reflector involution contracts.
    package static func checkDayKeyInvolutions() -> Bool {
        let day = fixtureDay()
        guard isInvolution(day.plugboard, allowFixedPoints: false) else { return false }
        guard isInvolution(day.reflector, allowFixedPoints: true) else { return false }
        return true
    }

    /// Lemma: harden fail-closes coupledCubic6 → independent gen3 cubic6.
    package static func checkFailClosedCoupling() -> Bool {
        let coupled = Enigma256Generation(
            id: 99,
            formula: .coupledCubic6,
            folds: Enigma256Generation.gen3Cubic.folds
        )
        let hardened = coupled.hardenedCubic()
        if hardened.formula == .coupledCubic6 { return false }
        if hardened.formula != .cubic6 { return false }
        // Independent cubic: leaf expressions must not share coupled assign form.
        let lines = hardened.nlffAssignLines()
        if lines.contains("nlff_f1 ^") { return false }
        return true
    }

    /// Issue the full Pillar III formal certificate.
    package static func certificate() -> Enigma256FormalCertificate {
        let steps: [Enigma256ProofStep] = [
            .init(lemma: .scrambleBijection, holds: checkScrambleBijection()),
            .init(lemma: .scrambleReciprocity, holds: checkScrambleReciprocity()),
            .init(lemma: .streamRoundTrip, holds: checkStreamRoundTrip()),
            .init(lemma: .dayKeyInvolutions, holds: checkDayKeyInvolutions()),
            .init(lemma: .failClosedCoupling, holds: checkFailClosedCoupling())
        ]
        return Enigma256FormalCertificate(
            steps: steps,
            hypotheses: [
                "Scramble path is plugboard → rotors fwd → un-reflector → rotors rev → plugboard",
                "Day-key tables are involutions (plugboard fixed-point-free; reflector may fix)",
                "NLFF retaps do not alter the frozen scramble combinational path",
                "Fail-closed means coupledCubic6 is rejected by harden — not IND-CPA",
                "Lemmas are structural SoftBus contracts — not a claim against all Red pressure"
            ]
        )
    }
}
