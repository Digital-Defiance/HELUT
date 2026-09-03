import CryptoKit
import Foundation
import XCTest
@testable import HELUTCore

final class Enigma256V3Tests: XCTestCase {
    private let profile = Enigma256V3Profile.gen0
    private let dayIKM = Data("E256-v3 fixture-v5 day IKM 0001".utf8)
    private let daySalt = Data("E256-v3 fixture-v5 day salt".utf8)
    private let messageIKM = Data("E256-v3 fixture-v5 message IKM 0001".utf8)
    private let nonce = Data((0 ..< 16).map(UInt8.init))

    private func deriveState() throws -> Enigma256V3ValidatedState {
        let day = try Enigma256V3KDF.deriveDayKey(
            ikm: dayIKM,
            salt: daySalt,
            profile: profile
        )
        let message = try Enigma256V3KDF.deriveMessageKey(
            masterIKM: messageIKM,
            nonce: nonce,
            profile: profile
        )
        return try Enigma256V3ValidatedState(
            profile: profile,
            day: day,
            message: message
        )
    }

    func testProfileCanonicalIdentityAndDomains() throws {
        let canonical = try XCTUnwrap(String(data: profile.canonicalProfile, encoding: .utf8))
        XCTAssertTrue(canonical.hasSuffix("\n"))
        XCTAssertFalse(canonical.contains("\r"))
        XCTAssertTrue(canonical.contains("bounded_sampler=u16be_reject_high_v1\n"))
        XCTAssertTrue(canonical.contains("domain_encoding=e256_ascii_path_v1\n"))
        XCTAssertTrue(canonical.contains("zero_policy=external_reject_derive_retry_u64le_v1\n"))
        XCTAssertTrue(canonical.contains("real_data_policy=standard_aead_required\n"))
        XCTAssertEqual(
            profile.profileHashHex,
            "0206c00e5084ebafe1f841708d2af3f4a029bcf160f7b22ed63bb5078d376e16"
        )
        XCTAssertEqual(profile.profileHashHex.count, 64)
        XCTAssertEqual(
            profile.compatibilityKey,
            "E256/v3/gen0/\(profile.profileHashHex)/fixture-v5"
        )
        for purpose in [
            "day/plugboard", "day/rotor/00", "day/rotor/15",
            "message/rotor-selection", "message/positions", "message/lfsr-seed",
            "message/center-mask-key", "center-mask/block", "envelope/encryption-key",
            "envelope/mac-key", "traffic/send", "traffic/receive",
            "handshake/transcript", "fixture/v5"
        ] {
            let domain = try XCTUnwrap(String(data: profile.domain(purpose), encoding: .utf8))
            XCTAssertEqual(domain, "E256/v3/gen0/\(profile.profileHashHex)/\(purpose)")
        }
        for invalidPurpose in [
            "day/rotor/16", "day/rotor/+0", "day/rotor/-0",
            "day/rotor/ 0", "day/rotor/0", "unknown"
        ] {
            XCTAssertThrowsError(try profile.domain(invalidPurpose), invalidPurpose)
        }
        print("E256_V3_PROFILE_SHA256=\(profile.profileHashHex)")
    }

    func testRejectionSamplerIsExactlyUniformOverAcceptedUInt16Space() throws {
        for bound in [3, 5, 15, 255, 256] {
            var counts = [Int](repeating: 0, count: bound)
            var rejected = 0
            for raw in 0 ... UInt16.max {
                if let mapped = try Enigma256V3RejectionSampler.map(raw, upperBound: bound) {
                    counts[mapped] += 1
                } else {
                    rejected += 1
                }
            }
            XCTAssertEqual(Set(counts).count, 1, "bound=\(bound)")
            XCTAssertEqual(rejected, 65_536 % bound, "bound=\(bound)")
        }
        XCTAssertThrowsError(try Enigma256V3RejectionSampler.map(0, upperBound: 0))
        XCTAssertThrowsError(try Enigma256V3RejectionSampler.map(0, upperBound: 65_537))
    }

    func testIndependentPurposeStreamsAndDerivationAreDeterministic() throws {
        var plugA = try Enigma256V3PurposeStream(
            ikm: dayIKM,
            salt: daySalt,
            profile: profile,
            purpose: "day/plugboard"
        )
        var plugB = try Enigma256V3PurposeStream(
            ikm: dayIKM,
            salt: daySalt,
            profile: profile,
            purpose: "day/plugboard"
        )
        var rotor = try Enigma256V3PurposeStream(
            ikm: dayIKM,
            salt: daySalt,
            profile: profile,
            purpose: "day/rotor/00"
        )
        let plugA128 = try plugA.read(count: 128)
        let plugB128 = try plugB.read(count: 128)
        XCTAssertEqual(plugA128, plugB128)
        let plugTail = try plugA.read(count: 64)
        let rotorHead = try rotor.read(count: 64)
        XCTAssertNotEqual(plugTail, rotorHead)

        let dayA = try Enigma256V3KDF.deriveDayKey(
            ikm: dayIKM,
            salt: daySalt,
            profile: profile
        )
        let dayB = try Enigma256V3KDF.deriveDayKey(
            ikm: dayIKM,
            salt: daySalt,
            profile: profile
        )
        XCTAssertEqual(dayA, dayB)
        XCTAssertEqual(Set(dayA.rotorPoolFwd.map { Data($0) }).count, 16)

        let messageA = try Enigma256V3KDF.deriveMessageKey(
            masterIKM: messageIKM,
            nonce: nonce,
            profile: profile
        )
        let messageB = try Enigma256V3KDF.deriveMessageKey(
            masterIKM: messageIKM,
            nonce: nonce,
            profile: profile
        )
        XCTAssertEqual(messageA, messageB)
        XCTAssertEqual(Set(messageA.rotorIndices).count, 4)
        XCTAssertNotEqual(messageA.lfsrSeed, 0)

        // The v3 lane never reads the legacy mutable selector.
        let original = Enigma256Generation.current
        defer { Enigma256Generation.current = original }
        Enigma256Generation.current = .v2Gen0
        let messageAfterLegacyRebind = try Enigma256V3KDF.deriveMessageKey(
            masterIKM: messageIKM,
            nonce: nonce,
            profile: profile
        )
        XCTAssertEqual(messageAfterLegacyRebind, messageA)
    }

    func testDerivedZeroRetriesButExternalZeroRejects() throws {
        XCTAssertEqual(
            try Enigma256V3KDF.firstNonzeroDerivedLFSR(candidates: [0, 0, 0xA5]),
            0xA5
        )
        XCTAssertThrowsError(
            try Enigma256V3KDF.firstNonzeroDerivedLFSR(candidates: [0, 0])
        ) { error in
            XCTAssertEqual(error as? Enigma256V3Error, .insufficientDerivedState)
        }

        XCTAssertThrowsError(
            try Enigma256V3MessageKey(
                profile: profile,
                rotorIndices: [0, 1, 2, 3],
                positions: [0, 0, 0, 0],
                lfsrSeed: 0,
                centerMaskKey: Data(repeating: 0, count: 32)
            )
        ) { error in
            XCTAssertEqual(error as? Enigma256V3Error, .zeroLFSRState)
        }
        XCTAssertThrowsError(
            try Enigma256V3KDF.deriveMessageKey(
                masterIKM: messageIKM,
                nonce: Data(),
                profile: profile
            )
        )
    }

    func testThrowingWiringValidationRejectsEveryInvariantClass() throws {
        let identity = [UInt8](0 ... 255)
        var paired = identity
        for index in stride(from: 0, to: 256, by: 2) {
            paired[index] = UInt8(index + 1)
            paired[index + 1] = UInt8(index)
        }

        XCTAssertThrowsError(
            try Enigma256V3Wiring(
                profile: profile,
                plugboard: Array(identity.dropLast()),
                r1Fwd: identity, r1Rev: identity,
                r2Fwd: identity, r2Rev: identity,
                r3Fwd: identity, r3Rev: identity,
                r4Fwd: identity, r4Rev: identity
            )
        ) { error in
            XCTAssertEqual(
                error as? Enigma256V3Error,
                .tableLength(name: "plugboard", actual: 255)
            )
        }

        XCTAssertThrowsError(
            try Enigma256V3Wiring(
                profile: profile,
                plugboard: identity,
                r1Fwd: identity, r1Rev: identity,
                r2Fwd: identity, r2Rev: identity,
                r3Fwd: identity, r3Rev: identity,
                r4Fwd: identity, r4Rev: identity
            )
        ) { error in
            XCTAssertEqual(error as? Enigma256V3Error, .plugboardFixedPoint(index: 0))
        }

        var duplicate = identity
        duplicate[1] = 0
        XCTAssertThrowsError(
            try Enigma256V3Wiring(
                profile: profile,
                plugboard: paired,
                r1Fwd: duplicate, r1Rev: identity,
                r2Fwd: identity, r2Rev: identity,
                r3Fwd: identity, r3Rev: identity,
                r4Fwd: identity, r4Rev: identity
            )
        ) { error in
            XCTAssertEqual(error as? Enigma256V3Error, .notPermutation("r1_fwd"))
        }

        var badInverse = identity
        badInverse.swapAt(0, 1)
        XCTAssertThrowsError(
            try Enigma256V3Wiring(
                profile: profile,
                plugboard: paired,
                r1Fwd: identity, r1Rev: badInverse,
                r2Fwd: identity, r2Rev: identity,
                r3Fwd: identity, r3Rev: identity,
                r4Fwd: identity, r4Rev: identity
            )
        ) { error in
            XCTAssertEqual(
                error as? Enigma256V3Error,
                .rotorPairNotInverse(rotor: 1, index: 0)
            )
        }
    }

    func testMessageValidationRejectsDuplicateAndOutOfRangeRotors() throws {
        XCTAssertThrowsError(
            try Enigma256V3MessageKey(
                profile: profile,
                rotorIndices: [0, 1, 1, 3],
                positions: [0, 0, 0, 0],
                lfsrSeed: 1,
                centerMaskKey: Data(repeating: 0, count: 32)
            )
        ) { error in
            XCTAssertEqual(error as? Enigma256V3Error, .duplicateRotorIndex(1))
        }
        XCTAssertThrowsError(
            try Enigma256V3MessageKey(
                profile: profile,
                rotorIndices: [0, 1, 2, 16],
                positions: [0, 0, 0, 0],
                lfsrSeed: 1,
                centerMaskKey: Data(repeating: 0, count: 32)
            )
        ) { error in
            XCTAssertEqual(error as? Enigma256V3Error, .rotorIndexOutOfRange(16))
        }
    }

    func testV3ReciprocityAndLongStateCheckpoints() throws {
        let state = try deriveState()
        var encryptor = try Enigma256V3Machine(state: state)
        var decryptor = try Enigma256V3Machine(state: state)
        let plaintext = (0 ..< 1_024).map { UInt8(truncatingIfNeeded: ($0 * 73) ^ ($0 >> 2)) }
        let ciphertext = try encryptor.process(plaintext)
        let recovered = try decryptor.process(ciphertext)
        XCTAssertEqual(recovered, plaintext)
        XCTAssertNotEqual(ciphertext, plaintext)
        XCTAssertEqual(encryptor.absoluteByteCounter, 1_024)

        let checkpoints: [Int: UInt64] = [
            0: state.message.lfsrSeed,
            1: Enigma256LFSR(seed: state.message.lfsrSeed).next
        ]
        var machine = try Enigma256V3Machine(state: state)
        for clock in 0 ... 1_024 {
            if let expected = checkpoints[clock] { XCTAssertEqual(machine.lfsr, expected) }
            if clock != 1_024 { _ = try machine.process(0) }
        }
        XCTAssertEqual(machine.lfsr, encryptor.lfsr)
        XCTAssertEqual(machine.positions, encryptor.positions)
    }

    func testCounterExhaustionRejectsWithoutWrap() throws {
        let state = try deriveState()
        var machine = try Enigma256V3Machine(
            state: state,
            absoluteByteCounter: UInt64.max
        )
        XCTAssertThrowsError(try machine.process(0)) { error in
            XCTAssertEqual(error as? Enigma256V3Error, .counterExhausted)
        }
        XCTAssertEqual(machine.absoluteByteCounter, UInt64.max)
        XCTAssertEqual(machine.lfsr, state.message.lfsrSeed)
    }
}
