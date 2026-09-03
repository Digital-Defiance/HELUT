import Foundation

// MARK: - Enigma256 SoftBus formal surface (Pillar III)
//
// Machine-checkable checks for bounded reciprocity / bijection / native-profile integrity.
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
    /// Day-key plugboard and base reflector are fixed-point-free involutions;
    /// the reserved-pair center has exactly 0/2 fixed points by mode.
    case dayKeyInvolutions
    /// The frozen E256-v2/gen0 native profile satisfies its structural identity contract.
    case nativeProfileIntegrity
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

    /// Lemma: derived day-key plugboard / base-reflector / center contracts.
    package static func checkDayKeyInvolutions() -> Bool {
        let day = fixtureDay()
        guard isInvolution(day.plugboard, allowFixedPoints: false) else { return false }
        guard isInvolution(day.reflector, allowFixedPoints: false) else { return false }
        guard day.reflector[0] == 1, day.reflector[1] == 0 else { return false }
        for mode in [false, true] {
            let center = (0 ... 255).map {
                Enigma256Center.apply(UInt8($0), baseReflector: day.reflector, mode: mode)
            }
            guard isInvolution(center, allowFixedPoints: mode) else { return false }
            let fixedPoints = center.indices.filter { Int(center[$0]) == $0 }.count
            guard fixedPoints == (mode ? 2 : 0) else { return false }
        }
        return true
    }

    /// Structural check for the frozen native profile; this is not a cryptographic proof.
    package static func checkNativeProfileIntegrity() -> Bool {
        let profile = Enigma256Generation.v2Gen0
        guard (try? profile.validate()) != nil else { return false }
        return profile.family == "E256"
            && profile.suiteVersion == 2
            && profile.id == 0
            && profile.fixtureSchemaVersion == Enigma256Generation.supportedFixtureSchemaVersion
            && profile.lfsrTransition == Enigma256Generation.transitionIdentifier
            && profile.updateOrder == Enigma256Generation.updateOrderIdentifier
            && profile.reflectorDerivation == Enigma256Generation.reflectorDerivationIdentifier
            && profile.centerReservedPairRule == Enigma256Generation.centerReservedPairRuleIdentifier
            && profile.centerMode == Enigma256Generation.centerModeIdentifier
            && profile.centerMapOrder == Enigma256Generation.centerMapOrderIdentifier
            && profile.formula == .nativeReversible16
            && profile.components.count == 8
            && profile.components.allSatisfy { $0.ones == 64 }
            && profile.folds.count == 4
            && profile.folds.flatMap(\.taps).sorted() == Array(0 ..< 64)
            && profile.folds.flatMap({ [$0.leftComponent, $0.rightComponent] }) == Array(0 ..< 8)
            && profile.profileHashHex == Enigma256Generation.v2Gen0ProfileSHA256
            && profile.dayInfo != profile.messageInfo
    }

    /// Issue the full Pillar III formal certificate.
    package static func certificate() -> Enigma256FormalCertificate {
        let steps: [Enigma256ProofStep] = [
            .init(lemma: .scrambleBijection, holds: checkScrambleBijection()),
            .init(lemma: .scrambleReciprocity, holds: checkScrambleReciprocity()),
            .init(lemma: .streamRoundTrip, holds: checkStreamRoundTrip()),
            .init(lemma: .dayKeyInvolutions, holds: checkDayKeyInvolutions()),
            .init(lemma: .nativeProfileIntegrity, holds: checkNativeProfileIntegrity())
        ]
        return Enigma256FormalCertificate(
            steps: steps,
            hypotheses: [
                "Scramble path is plugboard → rotors fwd → schema-3 center → rotors rev → plugboard",
                "Base reflector is fixed-point-free with 0↔1 reserved; center mode has exactly 0/2 fixed points",
                "Center mode is parity of the four pre-step enables and the same mask advances offsets",
                "NLFF profile integrity covers the frozen E256-v2/gen0 identity and structure only",
                "Native component balance and tap partition are not an IND-CPA proof",
                "Checks are exhaustive only for finite table/center properties; sampled state checks are bounded evidence"
            ]
        )
    }
}
