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
    /// Day-key plugboard and XOR center maps are involutions; zero/nonzero
    /// masks have exactly 256/0 fixed points.
    case dayKeyAndCenterInvolutions
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
            lfsrSeed: max(1, UInt64(rng.next()) | 1),
            centerMaskKey: Data(repeating: 0xB2, count: Enigma256CenterMask.keyLength)
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
            lfsrSeed: max(1, UInt64(rng.next()) | 1),
            centerMaskKey: Data(repeating: 0xB3, count: Enigma256CenterMask.keyLength)
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

    /// Lemma: derived day-key plugboard and finite XOR-center contracts.
    package static func checkDayKeyAndCenterInvolutions() -> Bool {
        let day = fixtureDay()
        guard isInvolution(day.plugboard, allowFixedPoints: false) else { return false }
        for mask: UInt8 in [0, 1, 0xA5, 0xFF] {
            let center = (0 ... 255).map {
                Enigma256CenterMask.apply(UInt8($0), mask: mask)
            }
            guard isInvolution(center, allowFixedPoints: mask == 0) else { return false }
            let fixedPoints = center.indices.filter { Int(center[$0]) == $0 }.count
            guard fixedPoints == (mask == 0 ? 256 : 0) else { return false }
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
            && profile.centerConstruction == Enigma256Generation.centerConstructionIdentifier
            && profile.centerMaskKeyKDF == Enigma256Generation.centerMaskKeyKDFIdentifier
            && profile.centerMaskPRF == Enigma256Generation.centerMaskPRFIdentifier
            && profile.centerMaskKeyDomain == Enigma256Generation.centerMaskKeyDomainIdentifier
            && profile.centerMaskBlockDomain == Enigma256Generation.centerMaskBlockDomainIdentifier
            && profile.centerMaskCounter == Enigma256Generation.centerMaskCounterIdentifier
            && profile.centerMaskExtraction == Enigma256Generation.centerMaskExtractionIdentifier
            && profile.centerMapOrder == Enigma256Generation.centerMapOrderIdentifier
            && profile.formula == .nativeReversible16
            && profile.components.count == 8
            && profile.components.allSatisfy { $0.ones == 64 }
            && profile.folds.count == 4
            && profile.folds.flatMap(\.taps).sorted() == Array(0 ..< 64)
            && profile.folds.flatMap({ [$0.leftComponent, $0.rightComponent] }) == Array(0 ..< 8)
            && profile.profileHashHex == Enigma256Generation.v2Gen0ProfileSHA256
            && profile.dayInfo != profile.messageInfo
            && profile.messageInfo != profile.centerMaskKeyInfo
            && profile.centerMaskKeyInfo != profile.centerMaskBlockInfo
    }

    /// Issue the full Pillar III formal certificate.
    package static func certificate() -> Enigma256FormalCertificate {
        let steps: [Enigma256ProofStep] = [
            .init(lemma: .scrambleBijection, holds: checkScrambleBijection()),
            .init(lemma: .scrambleReciprocity, holds: checkScrambleReciprocity()),
            .init(lemma: .streamRoundTrip, holds: checkStreamRoundTrip()),
            .init(lemma: .dayKeyAndCenterInvolutions, holds: checkDayKeyAndCenterInvolutions()),
            .init(lemma: .nativeProfileIntegrity, holds: checkNativeProfileIntegrity())
        ]
        return Enigma256FormalCertificate(
            steps: steps,
            hypotheses: [
                "Scramble path is A_i^-1(A_i(x) XOR k_i) with A_i = plugboard plus four forward rotors",
                "For a frozen byte position, XOR by k_i is an involution with 256 fixed points iff k_i is zero, otherwise none",
                "k_i is one lane of a profile-bound HMAC-SHA256 block selected by a UInt64 big-endian block counter",
                "The absolute byte counter and the pre-step NLFF mask each advance exactly once per accepted payload byte",
                "NLFF/profile integrity and finite center checks do not prove HMAC security or IND-CPA security",
                "Checks are exhaustive only for finite table/center properties; sampled state checks are bounded evidence"
            ]
        )
    }
}
