import CryptoKit
import Foundation
import XCTest
@testable import HELUTCore
@testable import HELUTToolKit

final class Enigma256Tests: XCTestCase {
    override func setUp() {
        super.setUp()
        Enigma256Generation.current = .v2Gen0
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// Allows scratch-first validation before fixture-v4 is atomically promoted.
    private var profileFixtureURL: URL {
        if let path = ProcessInfo.processInfo.environment["E256_PROFILE_PATH"] {
            return URL(fileURLWithPath: path, relativeTo: repositoryRoot).standardizedFileURL
        }
        return repositoryRoot.appendingPathComponent("Fixtures/enigma256_generation.json")
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private typealias E256LinearMap = [UInt64]

    private func apply(_ map: E256LinearMap, to value: UInt64) -> UInt64 {
        var value = value
        var result: UInt64 = 0
        while value != 0 {
            let bit = value.trailingZeroBitCount
            result ^= map[bit]
            value &= value &- 1
        }
        return result
    }

    /// `outer(inner(x))`, represented by images of the 64 basis vectors.
    private func compose(_ outer: E256LinearMap, _ inner: E256LinearMap) -> E256LinearMap {
        inner.map { apply(outer, to: $0) }
    }

    private func power(_ map: E256LinearMap, exponent: UInt64) -> E256LinearMap {
        var exponent = exponent
        var base = map
        var result = (0 ..< 64).map { UInt64(1) << $0 }
        while exponent != 0 {
            if exponent & 1 == 1 { result = compose(base, result) }
            base = compose(base, base)
            exponent >>= 1
        }
        return result
    }

    private func rank(_ columns: E256LinearMap) -> Int {
        var pivots = [UInt64](repeating: 0, count: 64)
        var rank = 0
        for column in columns {
            var value = column
            while value != 0 {
                let pivot = 63 - value.leadingZeroBitCount
                if pivots[pivot] == 0 {
                    pivots[pivot] = value
                    rank += 1
                    break
                }
                value ^= pivots[pivot]
            }
        }
        return rank
    }

    func testLFSRKnownVectorsAndInverse() {
        let vectors: [(UInt64, UInt64)] = [
            (0x0000_0000_0000_0000, 0x0000_0000_0000_0000),
            (0x0000_0000_0000_0001, 0xD800_0000_0000_0000),
            (0x8000_0000_0000_0000, 0x4000_0000_0000_0000),
            (0x0123_4567_89AB_CDEF, 0xD891_A2B3_C4D5_E6F7)
        ]
        for (state, expected) in vectors {
            let next = Enigma256LFSR(seed: state).next
            XCTAssertEqual(next, expected, String(format: "state=%016llx", state))
            XCTAssertEqual(Enigma256LFSR(seed: next).previous, state)
        }
    }

    func testLFSRLongKnownTrajectory() {
        let checkpoints: [Int: UInt64] = [
            0: 0x0123_4567_89AB_CDEF,
            1: 0xD891_A2B3_C4D5_E6F7,
            2: 0xB448_D159_E26A_F37B,
            58: 0x612E_CBB1_347B_9EE4,
            59: 0x3097_65D8_9A3D_CF72,
            60: 0x184B_B2EC_4D1E_E7B9,
            64: 0xC284_BB2E_C4D1_EE7B,
            128: 0xC0BE_3A6E_926E_3A6E,
            1_024: 0x16F2_ABBB_E666_3B1C
        ]
        var lfsr = Enigma256LFSR(seed: checkpoints[0]!)
        for clock in 0 ... 1_024 {
            if let expected = checkpoints[clock] {
                XCTAssertEqual(lfsr.state, expected, "clock=\(clock)")
            }
            if clock != 1_024 { lfsr.clock() }
        }
    }

    func testLFSRTransitionHasFullRankAndMaximalOrder() {
        let transition = (0 ..< 64).map { Enigma256LFSR(seed: UInt64(1) << $0).next }
        let identity = (0 ..< 64).map { UInt64(1) << $0 }
        XCTAssertEqual(rank(transition), 64)
        XCTAssertEqual(rank(power(transition, exponent: 59)), 64, "old transition collapsed to rank five here")

        // 2^64 - 1 = 3·5·17·257·641·65537·6700417.
        let order = UInt64.max
        XCTAssertEqual(power(transition, exponent: order), identity)
        for factor: UInt64 in [3, 5, 17, 257, 641, 65_537, 6_700_417] {
            XCTAssertNotEqual(
                power(transition, exponent: order / factor),
                identity,
                "transition order is missing prime factor \(factor)"
            )
        }
    }

    func testLFSRNonzeroTrajectoryDoesNotLockOrShortCycle() {
        var lfsr = Enigma256LFSR(seed: 0x0123_4567_89AB_CDEF)
        var seen = Set<UInt64>()
        for clock in 0 ..< 4_096 {
            XCTAssertNotEqual(lfsr.state, 0, "zero lock at clock \(clock)")
            XCTAssertTrue(seen.insert(lfsr.state).inserted, "short cycle at clock \(clock)")
            lfsr.clock()
        }
    }

    func testIdentityWiringIsReciprocalAndSteps() {
        let centerMaskKey = Data(repeating: 0x5A, count: Enigma256CenterMask.keyLength)
        var enc = Enigma256Machine(
            wiring: .identity,
            lfsrSeed: 0x0123_4567_89AB_CDEF,
            positions: (1, 2, 3, 4),
            centerMaskKey: centerMaskKey
        )
        var dec = enc
        let plain: [UInt8] = Array(0 ... 255) + [0xA5, 0x5A, 0x00, 0xFF]
        let cipher = enc.process(plain)
        let recovered = dec.process(cipher)
        XCTAssertEqual(recovered, plain)
        // With identity outer tables, the stream is the profile-bound k_i
        // schedule; reciprocal processing must not degenerate to identity.
        XCTAssertNotEqual(cipher, plain)
        XCTAssertNotEqual(enc.lfsr.state, 0x0123_4567_89AB_CDEF)
        XCTAssertEqual(enc.absoluteByteCounter, UInt64(plain.count))
    }

    func testCenterMaskScheduleMatchesIndependentVectors() {
        let profile = Enigma256Generation.v2Gen0
        let ikm = Data("helut-enigma256-golden-ikm-v1!!!!".utf8)
        let nonce = Data([0xE2, 0x56, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05,
                          0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D])
        let message = Enigma256KDF.deriveMessageKey(
            masterIKM: ikm,
            nonce: nonce,
            info: profile.messageInfo,
            centerMaskKeyInfo: profile.centerMaskKeyInfo
        )
        XCTAssertEqual(
            hex(message.centerMaskKey),
            "80ed6710f40876647eb9cfa9acddd7ff9641b0f149edd3b86c35650ecc9e28e6"
        )
        XCTAssertEqual(
            hex(Data(Enigma256CenterMask.block(
                key: message.centerMaskKey,
                generation: profile,
                blockCounter: 0
            ))),
            "929d778c74252dc7937c35a9c97b8376afed71e6ef41de99ebdbe36de977046f"
        )
        XCTAssertEqual(
            Enigma256CenterMask.mask(
                key: message.centerMaskKey,
                generation: profile,
                absoluteByteCounter: 0
            ),
            0x92
        )
        XCTAssertEqual(
            Enigma256CenterMask.mask(
                key: message.centerMaskKey,
                generation: profile,
                absoluteByteCounter: 31
            ),
            0x6F
        )
        XCTAssertEqual(
            Enigma256CenterMask.mask(
                key: message.centerMaskKey,
                generation: profile,
                absoluteByteCounter: 32
            ),
            0xA7
        )
    }

    func testFrozenScrambleDoesNotAdvanceAndAcceptedByteUsesPreStepCounter() {
        let key = Enigma256KDF.deriveMessageKey(
            masterIKM: Data("helut-enigma256-golden-ikm-v1!!!!".utf8),
            nonce: Data([0xE2, 0x56, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05,
                         0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D])
        ).centerMaskKey
        var machine = Enigma256Machine(
            wiring: .identity,
            lfsrSeed: 0x8000_0000_0000_0001,
            positions: (0, 0, 0, 0),
            centerMaskKey: key,
            absoluteByteCounter: 31
        )
        let lfsrBefore = machine.lfsr.state
        let offsetsBefore = (machine.offsetR1, machine.offsetR2, machine.offsetR3, machine.offsetR4)
        XCTAssertEqual(machine.currentCenterMask, 0x6F)
        XCTAssertEqual(machine.scramble(0x42), 0x42 ^ 0x6F)
        XCTAssertEqual(machine.absoluteByteCounter, 31)
        XCTAssertEqual(machine.lfsr.state, lfsrBefore)
        XCTAssertEqual(machine.offsetR1, offsetsBefore.0)
        XCTAssertEqual(machine.offsetR2, offsetsBefore.1)
        XCTAssertEqual(machine.offsetR3, offsetsBefore.2)
        XCTAssertEqual(machine.offsetR4, offsetsBefore.3)

        let expectedStepMask = machine.currentStepMask
        let trace = machine.processTraced(0x42)
        XCTAssertEqual(trace.absoluteByteCounterBefore, 31)
        XCTAssertEqual(trace.absoluteByteCounterAfter, 32)
        XCTAssertEqual(trace.centerMask, 0x6F)
        XCTAssertEqual(trace.centerOutput, trace.centerInput ^ trace.centerMask)
        XCTAssertEqual(trace.output, 0x42 ^ 0x6F)
        XCTAssertEqual(machine.absoluteByteCounter, 32)
        XCTAssertEqual(machine.lfsr.state, Enigma256LFSR(seed: lfsrBefore).next)
        XCTAssertEqual(machine.offsetR1, offsetsBefore.0 &+ (expectedStepMask.0 ? 1 : 0))
    }

    func testCounterUsesFinalPermittedByteWithoutWrapping() {
        var machine = Enigma256Machine(
            wiring: .identity,
            lfsrSeed: 1,
            positions: (0, 0, 0, 0),
            centerMaskKey: Data(repeating: 0xA5, count: Enigma256CenterMask.keyLength),
            absoluteByteCounter: UInt64.max - 1
        )
        let trace = machine.processTraced(0)
        XCTAssertEqual(trace.absoluteByteCounterBefore, UInt64.max - 1)
        XCTAssertEqual(trace.absoluteByteCounterAfter, UInt64.max)
        XCTAssertEqual(machine.absoluteByteCounter, UInt64.max)
        // A subsequent accepted byte is deliberately a precondition failure;
        // the state reaches exhaustion rather than wrapping to counter zero.
    }

    func testHKDFDayAndMessageRoundTrip() {
        let master = Data("helut-enigma256-test-ikm-32bytes!!".utf8)
        let day = Enigma256KDF.deriveDayKey(ikm: master, salt: Data("salt".utf8))
        XCTAssertEqual(day.rotorPoolFwd.count, 16)
        XCTAssertTrue(isInvolution(day.plugboard))
        for i in 0 ..< 16 {
            XCTAssertTrue(isInverse(day.rotorPoolFwd[i], day.rotorPoolRev[i]))
        }

        let nonce = Data((0 ..< 16).map { UInt8($0) ^ 0xA5 })
        let msg = Enigma256KDF.deriveMessageKey(masterIKM: master, nonce: nonce)
        XCTAssertNotEqual(msg.lfsrSeed, 0)
        XCTAssertEqual(msg.centerMaskKey.count, Enigma256CenterMask.keyLength)

        var enc = Enigma256Machine(day: day, message: msg)
        var dec = Enigma256Machine(day: day, message: msg)
        let plain = Array("ENIGMA256 polymorphic stream cipher golden".utf8)
        let cipher = enc.process(plain)
        XCTAssertNotEqual(cipher, plain)
        XCTAssertEqual(dec.process(cipher), plain)
    }

    func testDistinctNoncesYieldDistinctCiphertext() {
        let master = Data(repeating: 0x11, count: 32)
        let day = Enigma256KDF.deriveDayKey(ikm: master)
        let plain = Array(repeating: UInt8(0x55), count: 64)

        let m0 = Enigma256KDF.deriveMessageKey(masterIKM: master, nonce: Data(repeating: 0, count: 12))
        let m1 = Enigma256KDF.deriveMessageKey(masterIKM: master, nonce: Data(repeating: 1, count: 12))
        XCTAssertNotEqual(m0.lfsrSeed, m1.lfsrSeed)

        var a = Enigma256Machine(day: day, message: m0)
        var b = Enigma256Machine(day: day, message: m1)
        XCTAssertNotEqual(a.process(plain), b.process(plain))
    }

    func testPlugboardInvolutionProperty() {
        let entropy = Data((0 ..< 512).map { UInt8(truncatingIfNeeded: $0 &* 17 &+ 3) })
        let pb = Enigma256KDF.involution(from: entropy, allowFixedPoints: false)
        XCTAssertTrue(isInvolution(pb))
        // No fixed points when allowFixedPoints is false (perfect matching).
        for i in 0 ..< 256 {
            XCTAssertNotEqual(Int(pb[i]), i)
        }
    }

    func testConjugatedXORCenterIsReciprocalWithExpectedFixedPoints() {
        let machine = Enigma256Machine(
            wiring: .identity,
            lfsrSeed: 1,
            positions: (0, 0, 0, 0),
            centerMaskKey: Data(repeating: 0, count: Enigma256CenterMask.keyLength)
        )
        for mask: UInt8 in [0x00, 0x01, 0xA5, 0xFF] {
            let outputs = (0 ... 255).map {
                machine.scramble(UInt8($0), centerMask: mask)
            }
            XCTAssertEqual(Set(outputs).count, 256)
            for input in 0 ... 255 {
                let ciphertext = outputs[input]
                XCTAssertEqual(machine.scramble(ciphertext, centerMask: mask), UInt8(input))
            }
            XCTAssertEqual(
                outputs.indices.filter { outputs[$0] == UInt8($0) }.count,
                mask == 0 ? 256 : 0
            )
            XCTAssertEqual(outputs, (0 ... 255).map { UInt8($0) ^ mask })
        }
    }

    func testWiringValidationRejectsMalformedTables() throws {
        let valid = Enigma256Wiring.identity
        XCTAssertNoThrow(try valid.validate())

        var duplicate = valid
        duplicate.r1Fwd[1] = duplicate.r1Fwd[0]
        XCTAssertThrowsError(try duplicate.validate()) { error in
            XCTAssertEqual(error as? Enigma256WiringValidationError, .notPermutation("r1_fwd"))
        }

        var wrongInverse = valid
        wrongInverse.r2Rev.swapAt(2, 3)
        XCTAssertThrowsError(try wrongInverse.validate()) { error in
            guard let wiringError = error as? Enigma256WiringValidationError,
                  case .rotorPairNotInverse(rotor: 2, _) = wiringError else {
                return XCTFail("unexpected error: \(error)")
            }
        }

        var nonInvolutivePlugboard = valid
        nonInvolutivePlugboard.plugboard[0] = 1
        nonInvolutivePlugboard.plugboard[1] = 2
        nonInvolutivePlugboard.plugboard[2] = 0
        XCTAssertThrowsError(try nonInvolutivePlugboard.validate()) { error in
            XCTAssertEqual(
                error as? Enigma256WiringValidationError,
                .plugboardNotInvolution(index: 0)
            )
        }
    }

    func testPlaintextEqualityOccursExactlyOnZeroCenterMasks() {
        let observations = 65_536
        let context = Enigma256Context(
            ikm: Data("enigma256-zero-mask-calibration-v4".utf8),
            profile: .v2Gen0
        )
        let nonce = Data("zero-mask-nonce-v4".utf8)
        let (message, wiring) = context.messageState(nonce: nonce)
        var machine = Enigma256Machine(
            wiring: wiring,
            lfsrSeed: message.lfsrSeed,
            positions: message.positions,
            centerMaskKey: message.centerMaskKey,
            generation: context.profile
        )

        var equalityCount = 0
        var zeroMaskCount = 0
        for _ in 0 ..< observations {
            let trace = machine.processTraced(0)
            if trace.output == 0 { equalityCount += 1 }
            if trace.centerMask == 0 { zeroMaskCount += 1 }
        }
        XCTAssertEqual(
            equalityCount,
            zeroMaskCount,
            "A_i^-1(A_i(x) XOR k_i) fixes x exactly when k_i is zero"
        )

        // Diagnostic only: this bounded deterministic transcript should remain
        // consistent with the schedule's expected 1/256 zero-byte frequency.
        let probability = 1.0 / 256.0
        let expected = Double(observations) * probability
        let sigma = sqrt(Double(observations) * probability * (1 - probability))
        let deviation = abs(Double(zeroMaskCount) - expected)
        XCTAssertLessThanOrEqual(deviation, 6 * sigma)
        print(
            String(
                format: "E256 fixture-v4 zero masks/equalities: %d/%d (%.8f), z=%.3f",
                zeroMaskCount,
                observations,
                Double(zeroMaskCount) / Double(observations),
                deviation / sigma
            )
        )
    }

    // MARK: - Helpers

    private func isInvolution(_ t: [UInt8]) -> Bool {
        guard t.count == 256 else { return false }
        for i in 0 ..< 256 {
            if Int(t[Int(t[i])]) != i { return false }
        }
        return true
    }

    private func isInverse(_ fwd: [UInt8], _ rev: [UInt8]) -> Bool {
        guard fwd.count == 256, rev.count == 256 else { return false }
        for i in 0 ..< 256 {
            if Int(rev[Int(fwd[i])]) != i { return false }
            if Int(fwd[Int(rev[i])]) != i { return false }
        }
        return true
    }

    func testGoldenBundleRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("enigma256-golden-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let session = Enigma256Bridge.makeGoldenSession()
        XCTAssertEqual(session.plaintext.count, Enigma256Bridge.goldenTraceLength)
        _ = try Enigma256Bridge.writeGoldenBundle(session: session, to: dir)
        let loaded = try Enigma256Bridge.loadAndVerify(bundle: dir, profile: session.profile)
        XCTAssertEqual(loaded.ciphertext, session.ciphertext)
        XCTAssertEqual(loaded.plaintext, session.plaintext)
        XCTAssertEqual(loaded.wiring.plugboard, session.wiring.plugboard)

        let manifestData = try Data(contentsOf: dir.appendingPathComponent("manifest.json"))
        let manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        )
        XCTAssertEqual(manifest["schema"] as? String, "E256-KAT-MANIFEST-4")
        XCTAssertEqual(manifest["trace_schema"] as? String, "E256-KAT-TRACE-4")
        let artifacts = try XCTUnwrap(manifest["artifacts"] as? [String: String])
        XCTAssertEqual(artifacts.count, 25)
        XCTAssertNil(artifacts["tables/reflector.hex"])
        XCTAssertNil(artifacts["trace/center_mode.hex"])
        XCTAssertNotNil(artifacts["trace/center_mask.hex"])
        XCTAssertNotNil(artifacts["trace/byte_counter_before.hex"])
        XCTAssertNotNil(artifacts["trace/byte_counter_after.hex"])

        let vh = try String(contentsOf: dir.appendingPathComponent("tb_params.vh"), encoding: .utf8)
        XCTAssertTrue(
            vh.contains(String(format: "%016llx", session.message.lfsrSeed)),
            "tb_params.vh must embed the full 64-bit LFSR seed"
        )
        XCTAssertTrue(vh.contains("ENIGMA256_COUNTER = 64'h0000000000000000"))
    }

    func testGoldenBundleRejectsSchema3Identity() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("enigma256-legacy-reject-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let session = Enigma256Bridge.makeGoldenSession()
        try Enigma256Bridge.writeGoldenBundle(session: session, to: dir)

        let manifestURL = dir.appendingPathComponent("manifest.json")
        var manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        )
        manifest["schema"] = "E256-KAT-MANIFEST-3"
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: manifestURL, options: .atomic)

        XCTAssertThrowsError(
            try Enigma256Bridge.loadAndVerify(bundle: dir, profile: session.profile)
        ) { error in
            guard case Enigma256Bridge.BridgeError.legacyFixtureIdentity = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testGoldenBundleFailedStagingPreservesDestination() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("enigma256-atomic-\(UUID().uuidString)", isDirectory: true)
        let destination = parent.appendingPathComponent("bundle", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let sentinel = destination.appendingPathComponent("sentinel.txt")
        try Data("preserve-existing-v3".utf8).write(to: sentinel)

        var invalid = Enigma256Bridge.makeGoldenSession()
        invalid.ciphertext[0] ^= 1
        XCTAssertThrowsError(
            try Enigma256Bridge.writeGoldenBundle(session: invalid, to: destination)
        )
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("preserve-existing-v3".utf8))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: destination.appendingPathComponent("manifest.json").path)
        )
    }

    func testCanonicalGoldenPublicationRejectsMismatchedProfile() throws {
        let canonicalProfile = try Enigma256Generation.load(from: profileFixtureURL)
        let canonicalOutput = repositoryRoot
            .appendingPathComponent("Fixtures/enigma256_golden", isDirectory: true)
        let scratchOutput = FileManager.default.temporaryDirectory
            .appendingPathComponent("enigma256-scratch-\(UUID().uuidString)", isDirectory: true)
        let mismatchedKey = canonicalProfile.compatibilityKey.replacingOccurrences(
            of: canonicalProfile.profileHashHex,
            with: String(repeating: "0", count: 64)
        )

        XCTAssertThrowsError(
            try enigma256ValidateGoldenPublication(
                suppliedCompatibilityKey: mismatchedKey,
                outputURL: canonicalOutput,
                canonicalCompatibilityKey: canonicalProfile.compatibilityKey,
                canonicalOutputURL: canonicalOutput
            )
        ) { error in
            XCTAssertEqual(
                error as? Enigma256GoldenPublicationError,
                .canonicalBundleProfileMismatch(
                    expected: canonicalProfile.compatibilityKey,
                    supplied: mismatchedKey
                )
            )
        }
        XCTAssertNoThrow(
            try enigma256ValidateGoldenPublication(
                suppliedCompatibilityKey: mismatchedKey,
                outputURL: scratchOutput,
                canonicalCompatibilityKey: canonicalProfile.compatibilityKey,
                canonicalOutputURL: canonicalOutput
            )
        )
    }

    func testProfileKATSplitPublicationFailsClosed() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("enigma256-split-release-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = Enigma256Bridge.makeGoldenSession()
        try Enigma256Bridge.writeGoldenBundle(session: session, to: directory)

        let sessionURL = directory.appendingPathComponent("session.json")
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: sessionURL)) as? [String: Any]
        )
        var compatibility = try XCTUnwrap(object["compatibility"] as? [String: Any])
        compatibility["profile_sha256"] = String(repeating: "0", count: 64)
        object["compatibility"] = compatibility
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            .write(to: sessionURL, options: .atomic)

        XCTAssertThrowsError(
            try Enigma256Bridge.loadAndVerify(bundle: directory, profile: session.profile)
        ) { error in
            guard case Enigma256Bridge.BridgeError.profileMismatch = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("manifest.json").path))
    }

    func testTableSelCoversNineBRAMs() {
        XCTAssertEqual(Enigma256TableSel.allCases.count, 9)
        let w = Enigma256Wiring.identity
        for sel in Enigma256TableSel.allCases {
            XCTAssertEqual(Enigma256Bridge.table(w, sel: sel).count, 256)
        }
    }

    func testSessionSealOpenRoundTrip() throws {
        let ctx = Enigma256Context(ikm: Data("session-api-ikm-32-bytes!!!!!!".utf8), salt: Data("s".utf8))
        let plain = Array("control-plane seal/open".utf8)
        let box = ctx.seal(plain, nonce: Data(repeating: 0x42, count: 16))
        XCTAssertNotEqual(box.ciphertext, plain)
        XCTAssertEqual(ctx.open(box), plain)

        let encoded = box.encode()
        let decoded = try Enigma256SealedBox.decode(encoded)
        XCTAssertEqual(decoded.nonce, box.nonce)
        XCTAssertEqual(ctx.open(decoded), plain)
    }

    func testCoreHandleMatchesContextSeal() {
        let ctx = Enigma256Context(ikm: Data(repeating: 0xAB, count: 32))
        let nonce = Data((0 ..< 12).map { UInt8($0) })
        let plain = Array("AXI bitbang parity".utf8)
        let box = ctx.seal(plain, nonce: nonce)

        let handle = Enigma256CoreHandle()
        handle.configure(context: ctx, nonce: nonce)
        XCTAssertEqual(handle.transfer(plain), box.ciphertext)
        handle.configure(context: ctx, nonce: nonce)
        XCTAssertEqual(handle.transfer(box.ciphertext), plain)
        XCTAssertTrue(handle.transactionLog.contains(.loadState))
        XCTAssertTrue(handle.transactionLog.contains(.tableBurst(byteCount: 9 * 256)))
    }

    func testAXISoftBusMatchesContextSeal() {
        let ctx = Enigma256Context(ikm: Data("axi-softbus-ikm-32-bytes!!!!!!!".utf8))
        let nonce = Data(repeating: 0x7E, count: 16)
        let plain = Array("register-map bring-up vector".utf8)
        let want = ctx.seal(plain, nonce: nonce).ciphertext

        let bus = Enigma256SoftBus()
        let drv = Enigma256AXIDriver(bus: bus)
        drv.configure(context: ctx, nonce: nonce)
        XCTAssertEqual(drv.transfer(plain), want)

        // Reciprocal via same MMIO path.
        drv.configure(context: ctx, nonce: nonce)
        XCTAssertEqual(drv.transfer(want), plain)
        XCTAssertEqual(bus.lastBurstBytes, 9 * 256)
    }

    func testAXIRegOffsetsMatchDoc() {
        XCTAssertEqual(Enigma256Reg.ctrl.offset, 0x00)
        XCTAssertEqual(Enigma256Reg.wrData.offset, 0x0C)
        XCTAssertEqual(Enigma256Reg.dataIn.offset, 0x28)
        XCTAssertEqual(Enigma256Reg.status.offset, 0x30)
        XCTAssertEqual(Enigma256Reg.scaCtrl.offset, 0x34)
        XCTAssertEqual(Enigma256Reg.burstStatus.offset, 0x38)
        XCTAssertEqual(Enigma256Reg.centerMask.offset, 0x3C)
        XCTAssertEqual(Enigma256Reg.byteCounterLo.offset, 0x40)
        XCTAssertEqual(Enigma256Reg.byteCounterHi.offset, 0x44)
    }

    func testECDHPairedChannelsSealOpenAndBurn() throws {
        let (alice, bob) = try Enigma256Handshake.paired(salt: Data("session-salt".utf8))
        XCTAssertEqual(alice.context?.ikm, bob.context?.ikm)
        XCTAssertEqual(alice.local.publicKeyRaw.count, 32)

        let plain = Array("ecdh control-plane plaintext".utf8)
        let box = try alice.seal(plain, nonce: Data(repeating: 0x11, count: 16))
        XCTAssertEqual(try bob.open(box), plain)
        XCTAssertEqual(try alice.open(box), plain)

        // Distinct peer keys → distinct IKM.
        let (carol, _) = try Enigma256Handshake.paired()
        XCTAssertNotEqual(alice.context?.ikm, carol.context?.ikm)

        alice.burn()
        bob.burn()
        XCTAssertTrue(alice.isBurned)
        XCTAssertThrowsError(try alice.seal(plain)) { err in
            XCTAssertEqual(err as? Enigma256ECDHError, .burned)
        }
    }

    func testECDHFeedsAXISoftBus() throws {
        let (alice, bob) = try Enigma256Handshake.paired()
        let nonce = Data(repeating: 0x5A, count: 12)
        let plain = Array("ecdh→axi day-key".utf8)
        let box = try alice.seal(plain, nonce: nonce)

        let bus = Enigma256SoftBus()
        let drv = Enigma256AXIDriver(bus: bus)
        drv.configure(context: bob.context!, nonce: nonce)
        XCTAssertEqual(drv.transfer(box.ciphertext), plain)
    }

    func testWireFrameRoundTrip() throws {
        var buf = Data()
        let frame = Enigma256Frame.hello(publicKey: Data(repeating: 0xAB, count: 32), salt: Data("xy".utf8))
        buf.append(frame.encode())
        let parsed = try Enigma256Frame.parse(from: &buf)
        XCTAssertTrue(buf.isEmpty)
        let hello = try Enigma256Frame.parseHello(parsed!)
        XCTAssertEqual(hello.pub.count, 32)
        XCTAssertEqual(hello.salt, Data("xy".utf8))
    }

    func testWireInProcessSessionSoftBus() throws {
        let messages: [[UInt8]] = [
            Array("first wire datagram".utf8),
            Array("second".utf8),
            Array(repeating: 0x7F, count: 64)
        ]
        let got = try Enigma256WireSession.runInProcess(messages: messages, decryptViaSoftBus: true)
        XCTAssertEqual(got, messages)
    }

    func testWireInProcessSessionChannelOnly() throws {
        let messages = [Array("no softbus path".utf8)]
        let got = try Enigma256WireSession.runInProcess(messages: messages, decryptViaSoftBus: false)
        XCTAssertEqual(got, messages)
    }

    func testTCPLocalhostSession() throws {
        let port = UInt16.random(in: 26000 ... 26999)
        let plain = Array("tcp localhost softbus".utf8)
        let gate = DispatchGroup()
        var serverError: Error?
        var clientError: Error?
        var received: [UInt8]?

        gate.enter()
        DispatchQueue.global().async {
            defer { gate.leave() }
            do {
                let transport = try Enigma256TCPTransport.accept(port: port, timeout: 20)
                defer { transport.close() }
                let peer = Enigma256WirePeer(transport: transport, decryptViaSoftBus: true)
                try peer.handshakeAsResponder()
                received = try peer.receivePlaintext()
                do { _ = try peer.receivePlaintext() }
                catch Enigma256WireError.closed {}
            } catch {
                serverError = error
            }
        }

        Thread.sleep(forTimeInterval: 0.3)

        gate.enter()
        DispatchQueue.global().async {
            defer { gate.leave() }
            do {
                let transport = try Enigma256TCPTransport.connect(host: "127.0.0.1", port: port, timeout: 10)
                defer { transport.close() }
                let peer = Enigma256WirePeer(transport: transport, decryptViaSoftBus: true)
                try peer.handshakeAsInitiator(salt: Data("tcp-test".utf8))
                try peer.sendPlaintext(plain)
                try peer.close()
            } catch {
                clientError = error
            }
        }

        let ok = gate.wait(timeout: .now() + 30)
        XCTAssertEqual(ok, .success)
        XCTAssertNil(serverError, "server: \(String(describing: serverError))")
        XCTAssertNil(clientError, "client: \(String(describing: clientError))")
        XCTAssertEqual(received, plain)
    }

    func testPassphrasePBKDF2DeterministicAndDistinct() throws {
        let salt = Data("fixed-salt-16b!!".utf8)
        let a = try Enigma256Passphrase.deriveIKM(passphrase: "correct horse", salt: salt, iterations: 10_000)
        let b = try Enigma256Passphrase.deriveIKM(passphrase: "correct horse", salt: salt, iterations: 10_000)
        let c = try Enigma256Passphrase.deriveIKM(passphrase: "wrong battery", salt: salt, iterations: 10_000)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 64)
        XCTAssertNotEqual(a, c)
    }

    func testPassphraseContextSealOpen() throws {
        let salt = Data("ctx-salt".utf8)
        let ctx = try Enigma256Passphrase.openContext(
            passphrase: "helut-demo-pass",
            salt: salt,
            iterations: 8_000
        )
        let plain = Array("pbkdf2 sealed".utf8)
        let box = ctx.seal(plain, nonce: Data(repeating: 9, count: 16))
        XCTAssertEqual(ctx.open(box), plain)
    }

    func testWireInProcessPSKSession() throws {
        let messages = [Array("psk wire datagram".utf8)]
        let got = try Enigma256WireSession.runInProcessPSK(
            passphrase: "shared-secret-phrase",
            messages: messages,
            salt: Data("psk-salt-bytes!!".utf8),
            iterations: 5_000,
            decryptViaSoftBus: true
        )
        XCTAssertEqual(got, messages)
    }

    func testHKDFUsesSHA512Chunking() {
        let okm = Enigma256KDF.hkdf(
            ikm: Data("ikm".utf8),
            salt: Data("salt".utf8),
            info: Data("info".utf8),
            length: 256 * 64
        )
        XCTAssertEqual(okm.count, 256 * 64)
        XCTAssertNotEqual(Data(okm.prefix(64)), Data(okm.suffix(64)))
    }

    func testHybridX25519MLKEMPaired() throws {
        guard #available(macOS 26.0, *) else { return }
        let salt = Data("hybrid-salt".utf8)
        let (alice, bob) = try Enigma256HybridHandshake.paired(salt: salt)
        XCTAssertEqual(alice.context?.ikm, bob.context?.ikm)
        XCTAssertEqual(alice.context?.ikm.count, 64)
        let plain = Array("hybrid pq seal".utf8)
        let box = try alice.seal(plain, nonce: Data(repeating: 3, count: 16))
        XCTAssertEqual(try bob.open(box), plain)
        alice.burn()
        bob.burn()
    }

    func testXWingPairedIKM() throws {
        guard #available(macOS 26.0, *) else { return }
        let (a, b) = try Enigma256XWingHandshake.paired(salt: Data("xwing".utf8))
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 64)
    }

    func testEd25519IdentityBindsTranscript() throws {
        let id = Enigma256Identity()
        let msg = Enigma256Transcript.handshake(
            role: "initiator",
            suite: 2,
            ephemeralBlob: Data(repeating: 1, count: 64),
            salt: Data("s".utf8)
        )
        let sig = try id.sign(msg)
        try Enigma256Identity.verify(publicKeyRaw: id.publicKeyRaw, message: msg, signature: sig)
        XCTAssertThrowsError(
            try Enigma256Identity.verify(
                publicKeyRaw: id.publicKeyRaw,
                message: Data("tampered".utf8),
                signature: sig
            )
        )
    }

    func testWireInProcessHybridAuthenticated() throws {
        guard #available(macOS 26.0, *) else { return }
        let messages = [Array("hybrid wire datagram".utf8), Array("two".utf8)]
        let got = try Enigma256WireSession.runInProcessHybrid(
            messages: messages,
            decryptViaSoftBus: true,
            requireTrust: true
        )
        XCTAssertEqual(got, messages)
    }

    func testV2Gen0NativeStepMaskKnownVectors() {
        let profile = Enigma256Generation.v2Gen0
        let vectors: [(UInt64, [Bool])] = [
            (0x0000_0000_0000_0000, [false, false, false, false]),
            (0x0000_0000_0000_0001, [false, true, false, false]),
            (0x0123_4567_89AB_CDEF, [true, false, true, false]),
            (0xFFFF_FFFF_FFFF_FFFF, [true, false, true, false]),
            (0xD891_A2B3_C4D5_E6F7, [true, false, true, true]),
            (0xB448_D159_E26A_F37B, [false, true, true, true]),
            (0x612E_CBB1_347B_9EE4, [false, false, true, true]),
            (0x3097_65D8_9A3D_CF72, [false, false, true, true]),
            (0x184B_B2EC_4D1E_E7B9, [true, false, false, false]),
            (0xC284_BB2E_C4D1_EE7B, [true, false, false, true]),
            (0xC0BE_3A6E_926E_3A6E, [false, false, false, true]),
            (0x16F2_ABBB_E666_3B1C, [false, false, false, false]),
            (0x8000_0000_0000_0001, [false, true, false, false]),
            (0xA5A5_A5A5_A5A5_A5A5, [false, true, false, false])
        ]
        for (state, expected) in vectors {
            let mask = Enigma256LFSR(seed: state).stepMask(using: profile)
            XCTAssertEqual([mask.0, mask.1, mask.2, mask.3], expected)
        }
    }

    func testV2Gen0ProfileContract() throws {
        let profile = Enigma256Generation.v2Gen0
        XCTAssertNoThrow(try profile.validate())
        XCTAssertEqual(profile.family, "E256")
        XCTAssertEqual(profile.suiteVersion, 2)
        XCTAssertEqual(profile.id, 0)
        XCTAssertEqual(profile.fixtureSchemaVersion, 4)
        XCTAssertEqual(profile.lfsrTransition, Enigma256Generation.transitionIdentifier)
        XCTAssertEqual(profile.updateOrder, Enigma256Generation.updateOrderIdentifier)
        XCTAssertEqual(profile.centerConstruction, Enigma256Generation.centerConstructionIdentifier)
        XCTAssertEqual(profile.centerMaskKeyKDF, Enigma256Generation.centerMaskKeyKDFIdentifier)
        XCTAssertEqual(profile.centerMaskPRF, Enigma256Generation.centerMaskPRFIdentifier)
        XCTAssertEqual(profile.centerMaskKeyDomain, Enigma256Generation.centerMaskKeyDomainIdentifier)
        XCTAssertEqual(profile.centerMaskBlockDomain, Enigma256Generation.centerMaskBlockDomainIdentifier)
        XCTAssertEqual(profile.centerMaskCounter, Enigma256Generation.centerMaskCounterIdentifier)
        XCTAssertEqual(profile.centerMaskExtraction, Enigma256Generation.centerMaskExtractionIdentifier)
        XCTAssertEqual(profile.centerMapOrder, Enigma256Generation.centerMapOrderIdentifier)
        XCTAssertEqual(profile.formula, .nativeReversible16)
        XCTAssertEqual(profile.components.count, 8)
        XCTAssertTrue(profile.components.allSatisfy { $0.ones == 64 })
        XCTAssertEqual(Set(profile.components.map(\.truthHex)).count, 8)
        XCTAssertEqual(profile.folds.count, 4)
        XCTAssertEqual(profile.folds.flatMap(\.taps).sorted(), Array(0 ..< 64))
        XCTAssertEqual(
            profile.folds.flatMap { [$0.leftComponent, $0.rightComponent] },
            Array(0 ..< 8)
        )
        XCTAssertEqual(profile.profileHashHex, Enigma256Generation.v2Gen0ProfileSHA256)
        XCTAssertEqual(profile.declaredProfileSHA256, profile.profileHashHex)
        XCTAssertEqual(
            profile.compatibilityKey,
            "E256/v2/gen0/\(profile.profileHashHex)/fixture-v4"
        )
        XCTAssertEqual(
            Enigma256Generation.historicalSchema2CompatibilityKey,
            "E256/v2/gen0/6734d50d5e985edea4278a897a42e03ec0cf220cc4014bbeb3c3197e2ab83eac/fixture-v2"
        )
        XCTAssertEqual(
            Enigma256Generation.historicalSchema3CompatibilityKey,
            "E256/v2/gen0/2a9f54c70a1619805a911758158f1e2204b0fd96c35102a9db5f4575aeb40cb0/fixture-v3"
        )
        XCTAssertEqual(
            String(decoding: profile.dayInfo, as: UTF8.self),
            "E256/v2/gen0/day/\(profile.profileHashHex)"
        )
        XCTAssertEqual(
            String(decoding: profile.messageInfo, as: UTF8.self),
            "E256/v2/gen0/message/\(profile.profileHashHex)"
        )
        XCTAssertEqual(
            String(decoding: profile.centerMaskKeyInfo, as: UTF8.self),
            "E256/v2/gen0/center-mask-key/\(profile.profileHashHex)"
        )
        XCTAssertEqual(
            String(decoding: profile.centerMaskBlockInfo, as: UTF8.self),
            "E256/v2/gen0/center-mask-block/\(profile.profileHashHex)"
        )
        XCTAssertNotEqual(profile.dayInfo, profile.messageInfo)
        XCTAssertNotEqual(profile.messageInfo, profile.centerMaskKeyInfo)
        XCTAssertNotEqual(profile.centerMaskKeyInfo, profile.centerMaskBlockInfo)
    }

    func testV2Gen0FixtureAndReceiptMatchFrozenProfile() throws {
        let profile = Enigma256Generation.v2Gen0
        let fixtureURL = profileFixtureURL
        XCTAssertEqual(try Enigma256Generation.load(from: fixtureURL), profile)

        let receiptURL = repositoryRoot.appendingPathComponent(profile.receipt)
        let receiptData = try Data(contentsOf: receiptURL)
        let receiptDigest = SHA256.hash(data: receiptData)
            .map { String(format: "%02x", $0) }
            .joined()
        XCTAssertEqual(receiptDigest, profile.receiptSHA256)

        guard let receipt = try JSONSerialization.jsonObject(with: receiptData) as? [String: Any],
              let components = receipt["components"] as? [[String: Any]],
              let folds = receipt["folds"] as? [[String: Any]] else {
            return XCTFail("malformed native-NLFF receipt")
        }
        XCTAssertEqual(receipt["status"] as? String, "ACCEPTED_RESEARCH_PROFILE")
        XCTAssertEqual(receipt["transition"] as? String, "(state >> 1) xor (lsb ? 0xD800000000000000 : 0)")
        XCTAssertEqual(receipt["formula"] as? String, "dual_balanced_reversible_nlff16")
        XCTAssertEqual(
            components.compactMap { $0["truth_hex"] as? String },
            profile.components.map(\.truthHex)
        )
        XCTAssertEqual(folds.count, profile.folds.count)
        for (index, fold) in folds.enumerated() {
            let taps = (fold["taps"] as? [Any])?.compactMap { ($0 as? NSNumber)?.intValue }
            XCTAssertEqual(taps, profile.folds[index].taps)
            XCTAssertEqual((fold["left_component"] as? NSNumber)?.intValue, profile.folds[index].leftComponent)
            XCTAssertEqual((fold["right_component"] as? NSNumber)?.intValue, profile.folds[index].rightComponent)
        }
    }

    func testV2GenerationFixtureRejectsLegacyAndMismatchedIdentity() throws {
        let fixtureURL = profileFixtureURL
        let fixture = try String(contentsOf: fixtureURL, encoding: .utf8)
        let decoder = JSONDecoder()

        let legacy = fixture.replacingOccurrences(
            of: "native_reversible_16",
            with: "cubic6"
        )
        XCTAssertThrowsError(try decoder.decode(Enigma256Generation.self, from: Data(legacy.utf8)))

        let wrongSchemaText = fixture.replacingOccurrences(
            of: "\"fixture_schema_version\": 4",
            with: "\"fixture_schema_version\": 3"
        )
        let wrongSchema = try decoder.decode(Enigma256Generation.self, from: Data(wrongSchemaText.utf8))
        XCTAssertThrowsError(try wrongSchema.validate()) { error in
            XCTAssertEqual(error as? Enigma256GenerationError, .unsupportedFixtureSchema(3))
        }

        let wrongHashText = fixture.replacingOccurrences(
            of: Enigma256Generation.v2Gen0ProfileSHA256,
            with: String(repeating: "0", count: 64)
        )
        let wrongHash = try decoder.decode(Enigma256Generation.self, from: Data(wrongHashText.utf8))
        XCTAssertThrowsError(try wrongHash.validate())
    }

    func testV2NativeFoldsAreBalancedAndFirstOrderCorrelationImmune() {
        let profile = Enigma256Generation.v2Gen0
        for (foldIndex, fold) in profile.folds.enumerated() {
            var outputOnes = 0
            var conditionedOutputOnes = Array(repeating: [0, 0], count: 16)
            for assignment in 0 ..< (1 << 16) {
                var state: UInt64 = 0
                for localBit in 0 ..< 16 where (assignment & (1 << localBit)) != 0 {
                    state |= UInt64(1) << UInt64(fold.taps[localBit])
                }
                if fold.evaluate(state, components: profile.components) {
                    outputOnes += 1
                    for localBit in 0 ..< 16 {
                        conditionedOutputOnes[localBit][(assignment >> localBit) & 1] += 1
                    }
                }
            }
            XCTAssertEqual(outputOnes, 1 << 15, "fold \(foldIndex) must be exactly balanced")
            for localBit in 0 ..< 16 {
                XCTAssertEqual(
                    conditionedOutputOnes[localBit],
                    [1 << 14, 1 << 14],
                    "fold \(foldIndex) correlates with local input \(localBit)"
                )
            }
        }
    }

    func testV2Gen0VerilogWrapperContract() {
        let profile = Enigma256Generation.v2Gen0
        let verilog = profile.emitNLFFComboVerilog()
        XCTAssertTrue(verilog.contains("profile_sha256=\(profile.profileHashHex)"))
        XCTAssertTrue(
            verilog.contains(
                "`include \"Generated/Profiles/Enigma256/enigma_256_nlff_v2.vh\""
            )
        )
        XCTAssertTrue(verilog.contains("assign step_r1 = e256_nlff_step_r1;"))
        XCTAssertTrue(verilog.contains("assign step_r4 = e256_nlff_step_r4;"))
    }

    func testV2Gen0StepRates() {
        let stats = Enigma256Generation.v2Gen0.stepEnableStats(steps: 50_000)
        XCTAssertTrue(stats.meanRateOK)
        XCTAssertTrue(stats.rateFloorOK, "v2/gen0 should keep all rotors active")
        XCTAssertTrue(stats.independenceOK, "v2/gen0 should keep low pairwise step correlation")
    }

    func testAEADRejectsBitFlip() throws {
        let ctx = Enigma256Context(ikm: Data(repeating: 0x5A, count: 32), salt: Data("mac".utf8))
        let plain = Array("authenticated payload".utf8)
        var box = ctx.sealAEAD(plain, nonce: Data(repeating: 1, count: 16))
        XCTAssertEqual(try ctx.openAEAD(box), plain)
        box.ciphertext[0] ^= 0x01
        XCTAssertThrowsError(try ctx.openAEAD(box)) { err in
            XCTAssertEqual(err as? Enigma256AEADError, .authenticationFailed)
        }
    }

    func testProtectedSessionNonceReuseRejected() throws {
        let session = Enigma256ProtectedSession(ikm: Data(repeating: 0x11, count: 32))
        let nonce = Data(repeating: 0x22, count: 16)
        _ = try session.seal(Array("a".utf8), nonce: nonce)
        XCTAssertThrowsError(try session.seal(Array("b".utf8), nonce: nonce)) { err in
            XCTAssertEqual(err as? Enigma256AEADError, .nonceReused)
        }
        let box = try session.seal(Array("c".utf8))
        XCTAssertEqual(box.tag?.count, 32)
        XCTAssertEqual(try session.open(box), Array("c".utf8))
    }

    func testAEADContainerRoundTrip() throws {
        let ctx = Enigma256Context(ikm: Data("aead-container-ikm-32-bytes!!!!".utf8))
        let box = ctx.seal(Array("v2".utf8))
        let decoded = try Enigma256SealedBox.decode(box.encode())
        XCTAssertEqual(decoded.tag?.count, 32)
        XCTAssertEqual(try ctx.openAEAD(decoded), Array("v2".utf8))
    }

    func testBijectionSweepHoldsOnSample() {
        let ikm = Data("enigma256-bijection-unit-ikm-v1!".utf8)
        let day = Enigma256KDF.deriveDayKey(ikm: ikm, salt: Data("unit".utf8))
        let report = Enigma256Bijection.sweep(
            day: day,
            states: 2_000,
            streamBytes: 32,
            seed: 0xB13E_0001
        )
        XCTAssertNil(report.failure, report.failure.map { "\($0)" } ?? "")
        XCTAssertEqual(report.statesChecked, 2_000)
    }
}
