import CryptoKit
import Foundation

// MARK: - E256-v3 frozen research profile
//
// E256-v3 is intentionally incompatible with the historical v1/v2 lanes. It
// is an experimental construction and must not protect real data. Standard
// AEAD remains mandatory outside the research harness.

package enum Enigma256V3Error: Error, Equatable, CustomStringConvertible {
    case invalidProfileHash(expected: String, actual: String)
    case invalidDomain(String)
    case invalidNonceLength(actual: Int)
    case invalidBound(Int)
    case streamCounterExhausted
    case insufficientDerivedState
    case tableLength(name: String, actual: Int)
    case notPermutation(String)
    case plugboardNotInvolution(index: Int)
    case plugboardFixedPoint(index: Int)
    case rotorPairNotInverse(rotor: Int, index: Int)
    case duplicateDayRotor(Int)
    case rotorPoolCount(forward: Int, reverse: Int)
    case rotorIndexOutOfRange(Int)
    case duplicateRotorIndex(Int)
    case zeroLFSRState
    case centerMaskKeyLength(actual: Int)
    case counterExhausted

    package var description: String {
        switch self {
        case let .invalidProfileHash(expected, actual):
            return "E256-v3 profile mismatch: expected \(expected), got \(actual)"
        case let .invalidDomain(domain):
            return "invalid E256-v3 domain: \(domain)"
        case let .invalidNonceLength(actual):
            return "E256-v3 nonce must be 16 bytes, got \(actual)"
        case let .invalidBound(bound):
            return "invalid E256-v3 sampler bound: \(bound)"
        case .streamCounterExhausted:
            return "E256-v3 purpose stream counter exhausted"
        case .insufficientDerivedState:
            return "E256-v3 derivation did not produce a valid state"
        case let .tableLength(name, actual):
            return "E256-v3 table \(name) must contain 256 bytes, got \(actual)"
        case let .notPermutation(name):
            return "E256-v3 table \(name) is not a permutation"
        case let .plugboardNotInvolution(index):
            return "E256-v3 plugboard is not an involution at \(index)"
        case let .plugboardFixedPoint(index):
            return "E256-v3 plugboard has a forbidden fixed point at \(index)"
        case let .rotorPairNotInverse(rotor, index):
            return "E256-v3 rotor \(rotor) tables are not inverse at \(index)"
        case let .duplicateDayRotor(rotor):
            return "E256-v3 day rotor \(rotor) duplicates an earlier rotor"
        case let .rotorPoolCount(forward, reverse):
            return "E256-v3 day pool must contain 16 pairs, got \(forward)/\(reverse)"
        case let .rotorIndexOutOfRange(index):
            return "E256-v3 rotor index is out of range: \(index)"
        case let .duplicateRotorIndex(index):
            return "E256-v3 message repeats rotor index \(index)"
        case .zeroLFSRState:
            return "E256-v3 external LFSR state zero is forbidden"
        case let .centerMaskKeyLength(actual):
            return "E256-v3 center-mask key must be 32 bytes, got \(actual)"
        case .counterExhausted:
            return "E256-v3 absolute byte counter exhausted"
        }
    }
}

/// Immutable semantic profile. There is deliberately no mutable `current`,
/// activation API, or generation-only compatibility selector in the v3 lane.
package struct Enigma256V3Profile: Sendable, Equatable {
    package static let family = "E256"
    package static let suiteVersion = 3
    package static let generation = 0
    package static let fixtureSchemaVersion = 5
    package static let canonicalEncoding = "e256_key_value_lf_v1"
    package static let domainEncoding = "e256_ascii_path_v1"
    package static let KDF = "hkdf_sha512_rfc5869_v1"
    package static let purposeStream = "hmac_sha512_purpose_u64be_counter_v1"
    package static let boundedSampler = "u16be_reject_high_v1"
    package static let zeroPolicy = "external_reject_derive_retry_u64le_v1"
    package static let nonceLength = 16
    package static let centerMaskKeyLength = 32
    package static let centerMaskBlockLength = 32

    /// Independently recomputed from the 2,161 canonical profile bytes by
    /// Swift/CryptoKit and Python/hashlib before fixture-v5 generation.
    package static let frozenProfileSHA256 =
        "0206c00e5084ebafe1f841708d2af3f4a029bcf160f7b22ed63bb5078d376e16"

    package static let gen0 = Enigma256V3Profile()

    private static let fixedDomains: Set<String> = [
        "day/plugboard",
        "message/rotor-selection",
        "message/positions",
        "message/lfsr-seed",
        "message/center-mask-key",
        "center-mask/block",
        "envelope/encryption-key",
        "envelope/mac-key",
        "traffic/send",
        "traffic/receive",
        "handshake/transcript",
        "fixture/v5"
    ]

    private init() {}

    private var canonicalFields: [(String, String)] {
        var fields: [(String, String)] = [
            ("bounded_sampler", Self.boundedSampler),
            ("canonical_profile_encoding", Self.canonicalEncoding),
            ("center_construction", Enigma256Generation.centerConstructionIdentifier),
            ("center_map_order", Enigma256Generation.centerMapOrderIdentifier),
            ("center_mask_block_length", String(Self.centerMaskBlockLength)),
            ("center_mask_counter", Enigma256Generation.centerMaskCounterIdentifier),
            ("center_mask_extraction", Enigma256Generation.centerMaskExtractionIdentifier),
            ("center_mask_key_length", String(Self.centerMaskKeyLength)),
            ("center_mask_prf", Enigma256Generation.centerMaskPRFIdentifier),
            ("domain_encoding", Self.domainEncoding),
            ("domain_registry", "day/plugboard,day/rotor/{index_u8_2dec},message/rotor-selection,message/positions,message/lfsr-seed,message/center-mask-key,center-mask/block,envelope/encryption-key,envelope/mac-key,traffic/send,traffic/receive,handshake/transcript,fixture/v5"),
            ("envelope", "encrypt_then_mac_hmac_sha256_independent_keys_v1"),
            ("family", Self.family),
            ("fixture_schema_version", String(Self.fixtureSchemaVersion)),
            ("generation", String(Self.generation)),
            ("kdf", Self.KDF),
            ("lfsr_transition", Enigma256Generation.transitionIdentifier),
            ("nonce_length", String(Self.nonceLength)),
            ("nlff_formula", Enigma256NLFFFormula.nativeReversible16.rawValue),
            ("nlff_receipt_sha256", "5c5bc931a145048037ec420b2c0c47ff310570e963bd45b8262f18a1640f0027"),
            ("plugboard_policy", "fixed_point_free_involution_v1"),
            ("purpose_stream", Self.purposeStream),
            ("raw_security_target", "nonce_respecting_ind_cpa_target_conditional_hkdf_hmac_prf"),
            ("real_data_policy", "standard_aead_required"),
            ("rotor_policy", "permutation_inverse_pair_v1"),
            ("rotor_selection", "four_distinct_without_replacement_v1"),
            ("suite_version", String(Self.suiteVersion)),
            ("update_order", Enigma256Generation.updateOrderIdentifier),
            ("zero_policy", Self.zeroPolicy)
        ]
        for (index, component) in Enigma256Generation.v2Gen0.components.enumerated() {
            fields.append((String(format: "nlff_component_%02d", index), component.truthHex))
        }
        for (index, fold) in Enigma256Generation.v2Gen0.folds.enumerated() {
            let taps = fold.taps.map(String.init).joined(separator: ".")
            fields.append((
                String(format: "nlff_fold_%02d", index),
                "\(taps):\(fold.leftComponent):\(fold.rightComponent)"
            ))
        }
        return fields.sorted { lhs, rhs in lhs.0 < rhs.0 }
    }

    package var canonicalProfile: Data {
        let text = canonicalFields.map { key, value in
            precondition(!key.contains("=") && !key.contains("\n"))
            precondition(!value.contains("\n"))
            return "\(key)=\(value)\n"
        }.joined()
        return Data(text.utf8)
    }

    package var profileHashHex: String {
        Self.sha256Hex(canonicalProfile)
    }

    package var compatibilityKey: String {
        "\(Self.family)/v\(Self.suiteVersion)/gen\(Self.generation)/\(profileHashHex)/fixture-v\(Self.fixtureSchemaVersion)"
    }

    package func validateFrozenIdentity() throws {
        guard !Self.frozenProfileSHA256.isEmpty else { return }
        guard profileHashHex == Self.frozenProfileSHA256 else {
            throw Enigma256V3Error.invalidProfileHash(
                expected: Self.frozenProfileSHA256,
                actual: profileHashHex
            )
        }
    }

    /// Canonical profile-bound domain. Indexed day rotors are the only dynamic
    /// domain family; all other purposes must be in the frozen registry.
    package func domain(_ purpose: String) throws -> Data {
        let rotorDomain: Bool
        let prefix = "day/rotor/"
        let purposeBytes = Array(purpose.utf8)
        let prefixBytes = Array(prefix.utf8)
        if purposeBytes.count == prefixBytes.count + 2,
           purposeBytes.starts(with: prefixBytes) {
            let tens = purposeBytes[prefixBytes.count]
            let ones = purposeBytes[prefixBytes.count + 1]
            if (0x30 ... 0x39).contains(tens), (0x30 ... 0x39).contains(ones) {
                rotorDomain = Int(tens - 0x30) * 10 + Int(ones - 0x30) < 16
            } else {
                rotorDomain = false
            }
        } else {
            rotorDomain = false
        }
        guard Self.fixedDomains.contains(purpose) || rotorDomain,
              purpose.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value <= 0x7E }),
              !purpose.contains(".."),
              !purpose.hasPrefix("/"),
              !purpose.hasSuffix("/") else {
            throw Enigma256V3Error.invalidDomain(purpose)
        }
        return Data("E256/v3/gen0/\(profileHashHex)/\(purpose)".utf8)
    }

    package func stepMask(state: UInt64) -> (Bool, Bool, Bool, Bool) {
        Enigma256Generation.v2Gen0.stepMask(state: state)
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Profile-bound deterministic streams and unbiased bounded sampling

package struct Enigma256V3PurposeStream: Sendable {
    package let purpose: String
    private let key: Data
    private let blockDomain: Data
    private var blockCounter: UInt64 = 0
    private var buffer: [UInt8] = []
    private var offset = 0
    package private(set) var bytesConsumed = 0

    package init(
        ikm: Data,
        salt: Data,
        profile: Enigma256V3Profile,
        purpose: String
    ) throws {
        let domain = try profile.domain(purpose)
        var keyInfo = domain
        keyInfo.append(0)
        keyInfo.append(contentsOf: Data("stream-key".utf8))
        self.key = HKDF<SHA512>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: ikm),
            salt: salt,
            info: keyInfo,
            outputByteCount: 64
        ).withUnsafeBytes { Data($0) }
        var blockDomain = domain
        blockDomain.append(0)
        blockDomain.append(contentsOf: Data("stream-block".utf8))
        self.blockDomain = blockDomain
        self.purpose = purpose
    }

    package mutating func readByte() throws -> UInt8 {
        if offset == buffer.count {
            guard blockCounter != UInt64.max else {
                throw Enigma256V3Error.streamCounterExhausted
            }
            var message = blockDomain
            message.append(0)
            var counterBE = blockCounter.bigEndian
            withUnsafeBytes(of: &counterBE) { message.append(contentsOf: $0) }
            buffer = Array(HMAC<SHA512>.authenticationCode(
                for: message,
                using: SymmetricKey(data: key)
            ))
            offset = 0
            blockCounter += 1
        }
        let byte = buffer[offset]
        offset += 1
        bytesConsumed += 1
        return byte
    }

    package mutating func read(count: Int) throws -> [UInt8] {
        guard count >= 0 else { throw Enigma256V3Error.insufficientDerivedState }
        var output: [UInt8] = []
        output.reserveCapacity(count)
        for _ in 0 ..< count { output.append(try readByte()) }
        return output
    }

    package mutating func readUInt16BE() throws -> UInt16 {
        (UInt16(try readByte()) << 8) | UInt16(try readByte())
    }

    package mutating func readUInt64LE() throws -> UInt64 {
        var value: UInt64 = 0
        for shift in stride(from: 0, to: 64, by: 8) {
            value |= UInt64(try readByte()) << UInt64(shift)
        }
        return value
    }
}

package enum Enigma256V3RejectionSampler {
    /// Frozen `u16be_reject_high_v1` decision. Values in the high incomplete
    /// interval are rejected, so every accepted residue has equal multiplicity.
    package static func map(_ value: UInt16, upperBound: Int) throws -> Int? {
        guard (1 ... 65_536).contains(upperBound) else {
            throw Enigma256V3Error.invalidBound(upperBound)
        }
        let space = 65_536
        let limit = space - (space % upperBound)
        let integer = Int(value)
        guard integer < limit else { return nil }
        return integer % upperBound
    }

    package static func sample(
        upperBound: Int,
        from stream: inout Enigma256V3PurposeStream
    ) throws -> Int {
        while true {
            let value = try stream.readUInt16BE()
            if let mapped = try map(value, upperBound: upperBound) { return mapped }
        }
    }
}

// MARK: - Throwing profile-bound table and state types

package struct Enigma256V3Wiring: Sendable, Equatable {
    package let profileHash: String
    package let plugboard: [UInt8]
    package let r1Fwd: [UInt8]
    package let r1Rev: [UInt8]
    package let r2Fwd: [UInt8]
    package let r2Rev: [UInt8]
    package let r3Fwd: [UInt8]
    package let r3Rev: [UInt8]
    package let r4Fwd: [UInt8]
    package let r4Rev: [UInt8]

    package init(
        profile: Enigma256V3Profile,
        plugboard: [UInt8],
        r1Fwd: [UInt8], r1Rev: [UInt8],
        r2Fwd: [UInt8], r2Rev: [UInt8],
        r3Fwd: [UInt8], r3Rev: [UInt8],
        r4Fwd: [UInt8], r4Rev: [UInt8]
    ) throws {
        self.profileHash = profile.profileHashHex
        self.plugboard = plugboard
        self.r1Fwd = r1Fwd
        self.r1Rev = r1Rev
        self.r2Fwd = r2Fwd
        self.r2Rev = r2Rev
        self.r3Fwd = r3Fwd
        self.r3Rev = r3Rev
        self.r4Fwd = r4Fwd
        self.r4Rev = r4Rev
        try validate(profile: profile)
    }

    package func validate(profile: Enigma256V3Profile) throws {
        guard profileHash == profile.profileHashHex else {
            throw Enigma256V3Error.invalidProfileHash(
                expected: profile.profileHashHex,
                actual: profileHash
            )
        }
        let tables: [(String, [UInt8])] = [
            ("plugboard", plugboard),
            ("r1_fwd", r1Fwd), ("r1_rev", r1Rev),
            ("r2_fwd", r2Fwd), ("r2_rev", r2Rev),
            ("r3_fwd", r3Fwd), ("r3_rev", r3Rev),
            ("r4_fwd", r4Fwd), ("r4_rev", r4Rev)
        ]
        for (name, table) in tables {
            guard table.count == 256 else {
                throw Enigma256V3Error.tableLength(name: name, actual: table.count)
            }
            guard Set(table).count == 256 else {
                throw Enigma256V3Error.notPermutation(name)
            }
        }
        for index in 0 ..< 256 {
            guard Int(plugboard[Int(plugboard[index])]) == index else {
                throw Enigma256V3Error.plugboardNotInvolution(index: index)
            }
            guard Int(plugboard[index]) != index else {
                throw Enigma256V3Error.plugboardFixedPoint(index: index)
            }
        }
        let pairs = [(r1Fwd, r1Rev), (r2Fwd, r2Rev), (r3Fwd, r3Rev), (r4Fwd, r4Rev)]
        for (rotor, pair) in pairs.enumerated() {
            for index in 0 ..< 256 {
                guard Int(pair.1[Int(pair.0[index])]) == index,
                      Int(pair.0[Int(pair.1[index])]) == index else {
                    throw Enigma256V3Error.rotorPairNotInverse(rotor: rotor + 1, index: index)
                }
            }
        }
    }
}

package struct Enigma256V3DayKey: Sendable, Equatable {
    package let profileHash: String
    package let plugboard: [UInt8]
    package let rotorPoolFwd: [[UInt8]]
    package let rotorPoolRev: [[UInt8]]

    package init(
        profile: Enigma256V3Profile,
        plugboard: [UInt8],
        rotorPoolFwd: [[UInt8]],
        rotorPoolRev: [[UInt8]]
    ) throws {
        guard rotorPoolFwd.count == 16, rotorPoolRev.count == 16 else {
            throw Enigma256V3Error.rotorPoolCount(
                forward: rotorPoolFwd.count,
                reverse: rotorPoolRev.count
            )
        }
        self.profileHash = profile.profileHashHex
        self.plugboard = plugboard
        self.rotorPoolFwd = rotorPoolFwd
        self.rotorPoolRev = rotorPoolRev
        try Self.validatePlugboard(plugboard)
        var seen = Set<Data>()
        for rotor in 0 ..< 16 {
            try Self.validateRotor(
                forward: rotorPoolFwd[rotor],
                reverse: rotorPoolRev[rotor],
                rotor: rotor
            )
            guard seen.insert(Data(rotorPoolFwd[rotor])).inserted else {
                throw Enigma256V3Error.duplicateDayRotor(rotor)
            }
        }
    }

    package func wiring(
        for message: Enigma256V3MessageKey,
        profile: Enigma256V3Profile
    ) throws -> Enigma256V3Wiring {
        try message.validate(profile: profile)
        guard profileHash == profile.profileHashHex else {
            throw Enigma256V3Error.invalidProfileHash(
                expected: profile.profileHashHex,
                actual: profileHash
            )
        }
        let indices = message.rotorIndices
        return try Enigma256V3Wiring(
            profile: profile,
            plugboard: plugboard,
            r1Fwd: rotorPoolFwd[indices[0]], r1Rev: rotorPoolRev[indices[0]],
            r2Fwd: rotorPoolFwd[indices[1]], r2Rev: rotorPoolRev[indices[1]],
            r3Fwd: rotorPoolFwd[indices[2]], r3Rev: rotorPoolRev[indices[2]],
            r4Fwd: rotorPoolFwd[indices[3]], r4Rev: rotorPoolRev[indices[3]]
        )
    }

    private static func validatePlugboard(_ table: [UInt8]) throws {
        guard table.count == 256 else {
            throw Enigma256V3Error.tableLength(name: "plugboard", actual: table.count)
        }
        guard Set(table).count == 256 else {
            throw Enigma256V3Error.notPermutation("plugboard")
        }
        for index in 0 ..< 256 {
            guard Int(table[Int(table[index])]) == index else {
                throw Enigma256V3Error.plugboardNotInvolution(index: index)
            }
            guard Int(table[index]) != index else {
                throw Enigma256V3Error.plugboardFixedPoint(index: index)
            }
        }
    }

    private static func validateRotor(
        forward: [UInt8],
        reverse: [UInt8],
        rotor: Int
    ) throws {
        for (name, table) in [("rotor_\(rotor)_fwd", forward), ("rotor_\(rotor)_rev", reverse)] {
            guard table.count == 256 else {
                throw Enigma256V3Error.tableLength(name: name, actual: table.count)
            }
            guard Set(table).count == 256 else {
                throw Enigma256V3Error.notPermutation(name)
            }
        }
        for index in 0 ..< 256 {
            guard Int(reverse[Int(forward[index])]) == index,
                  Int(forward[Int(reverse[index])]) == index else {
                throw Enigma256V3Error.rotorPairNotInverse(rotor: rotor, index: index)
            }
        }
    }
}

package struct Enigma256V3MessageKey: Sendable, Equatable {
    package let profileHash: String
    package let rotorIndices: [Int]
    package let positions: [UInt8]
    package let lfsrSeed: UInt64
    package let centerMaskKey: Data

    package init(
        profile: Enigma256V3Profile,
        rotorIndices: [Int],
        positions: [UInt8],
        lfsrSeed: UInt64,
        centerMaskKey: Data
    ) throws {
        self.profileHash = profile.profileHashHex
        self.rotorIndices = rotorIndices
        self.positions = positions
        self.lfsrSeed = lfsrSeed
        self.centerMaskKey = centerMaskKey
        try validate(profile: profile)
    }

    package func validate(profile: Enigma256V3Profile) throws {
        guard profileHash == profile.profileHashHex else {
            throw Enigma256V3Error.invalidProfileHash(
                expected: profile.profileHashHex,
                actual: profileHash
            )
        }
        guard rotorIndices.count == 4 else {
            throw Enigma256V3Error.rotorPoolCount(
                forward: rotorIndices.count,
                reverse: 4
            )
        }
        var seen = Set<Int>()
        for index in rotorIndices {
            guard (0 ..< 16).contains(index) else {
                throw Enigma256V3Error.rotorIndexOutOfRange(index)
            }
            guard seen.insert(index).inserted else {
                throw Enigma256V3Error.duplicateRotorIndex(index)
            }
        }
        guard positions.count == 4 else {
            throw Enigma256V3Error.tableLength(name: "positions", actual: positions.count)
        }
        guard lfsrSeed != 0 else { throw Enigma256V3Error.zeroLFSRState }
        guard centerMaskKey.count == Enigma256V3Profile.centerMaskKeyLength else {
            throw Enigma256V3Error.centerMaskKeyLength(actual: centerMaskKey.count)
        }
    }
}

package struct Enigma256V3ValidatedState: Sendable, Equatable {
    package let profile: Enigma256V3Profile
    package let day: Enigma256V3DayKey
    package let message: Enigma256V3MessageKey
    package let wiring: Enigma256V3Wiring

    package init(
        profile: Enigma256V3Profile,
        day: Enigma256V3DayKey,
        message: Enigma256V3MessageKey
    ) throws {
        try profile.validateFrozenIdentity()
        guard day.profileHash == profile.profileHashHex else {
            throw Enigma256V3Error.invalidProfileHash(
                expected: profile.profileHashHex,
                actual: day.profileHash
            )
        }
        try message.validate(profile: profile)
        self.profile = profile
        self.day = day
        self.message = message
        self.wiring = try day.wiring(for: message, profile: profile)
    }
}

// MARK: - E256-v3 derivation

package enum Enigma256V3KDF {
    package static func deriveDayKey(
        ikm: Data,
        salt: Data,
        profile: Enigma256V3Profile
    ) throws -> Enigma256V3DayKey {
        try profile.validateFrozenIdentity()
        var plugboardStream = try Enigma256V3PurposeStream(
            ikm: ikm,
            salt: salt,
            profile: profile,
            purpose: "day/plugboard"
        )
        let plugboardOrder = try fisherYatesOrder(count: 256, stream: &plugboardStream)
        var plugboard = [UInt8](repeating: 0, count: 256)
        for pair in stride(from: 0, to: 256, by: 2) {
            let left = plugboardOrder[pair]
            let right = plugboardOrder[pair + 1]
            plugboard[left] = UInt8(right)
            plugboard[right] = UInt8(left)
        }

        var forward: [[UInt8]] = []
        var reverse: [[UInt8]] = []
        forward.reserveCapacity(16)
        reverse.reserveCapacity(16)
        for rotor in 0 ..< 16 {
            var stream = try Enigma256V3PurposeStream(
                ikm: ikm,
                salt: salt,
                profile: profile,
                purpose: String(format: "day/rotor/%02d", rotor)
            )
            let order = try fisherYatesOrder(count: 256, stream: &stream)
            var fwd = [UInt8](repeating: 0, count: 256)
            var rev = [UInt8](repeating: 0, count: 256)
            for (source, destination) in order.enumerated() {
                fwd[source] = UInt8(destination)
                rev[destination] = UInt8(source)
            }
            forward.append(fwd)
            reverse.append(rev)
        }
        return try Enigma256V3DayKey(
            profile: profile,
            plugboard: plugboard,
            rotorPoolFwd: forward,
            rotorPoolRev: reverse
        )
    }

    package static func deriveMessageKey(
        masterIKM: Data,
        nonce: Data,
        profile: Enigma256V3Profile
    ) throws -> Enigma256V3MessageKey {
        try profile.validateFrozenIdentity()
        guard nonce.count == Enigma256V3Profile.nonceLength else {
            throw Enigma256V3Error.invalidNonceLength(actual: nonce.count)
        }

        var selectionStream = try Enigma256V3PurposeStream(
            ikm: masterIKM,
            salt: nonce,
            profile: profile,
            purpose: "message/rotor-selection"
        )
        var available = Array(0 ..< 16)
        var selected: [Int] = []
        selected.reserveCapacity(4)
        for _ in 0 ..< 4 {
            let picked = try Enigma256V3RejectionSampler.sample(
                upperBound: available.count,
                from: &selectionStream
            )
            selected.append(available.remove(at: picked))
        }

        var positionStream = try Enigma256V3PurposeStream(
            ikm: masterIKM,
            salt: nonce,
            profile: profile,
            purpose: "message/positions"
        )
        let positions = try positionStream.read(count: 4)

        var lfsrStream = try Enigma256V3PurposeStream(
            ikm: masterIKM,
            salt: nonce,
            profile: profile,
            purpose: "message/lfsr-seed"
        )
        var lfsrSeed: UInt64 = 0
        repeat {
            lfsrSeed = try lfsrStream.readUInt64LE()
        } while lfsrSeed == 0

        let centerMaskKey = try deriveFixedKey(
            ikm: masterIKM,
            salt: nonce,
            profile: profile,
            purpose: "message/center-mask-key",
            length: Enigma256V3Profile.centerMaskKeyLength
        )

        return try Enigma256V3MessageKey(
            profile: profile,
            rotorIndices: selected,
            positions: positions,
            lfsrSeed: lfsrSeed,
            centerMaskKey: centerMaskKey
        )
    }

    package static func deriveFixedKey(
        ikm: Data,
        salt: Data,
        profile: Enigma256V3Profile,
        purpose: String,
        length: Int
    ) throws -> Data {
        let info = try profile.domain(purpose)
        return HKDF<SHA512>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: ikm),
            salt: salt,
            info: info,
            outputByteCount: length
        ).withUnsafeBytes { Data($0) }
    }

    package static func firstNonzeroDerivedLFSR(candidates: [UInt64]) throws -> UInt64 {
        guard let candidate = candidates.first(where: { $0 != 0 }) else {
            throw Enigma256V3Error.insufficientDerivedState
        }
        return candidate
    }

    package static func fisherYatesOrder(
        count: Int,
        stream: inout Enigma256V3PurposeStream
    ) throws -> [Int] {
        guard count > 0, count <= 65_536 else {
            throw Enigma256V3Error.invalidBound(count)
        }
        var items = Array(0 ..< count)
        guard count > 1 else { return items }
        for index in stride(from: count - 1, through: 1, by: -1) {
            let other = try Enigma256V3RejectionSampler.sample(
                upperBound: index + 1,
                from: &stream
            )
            items.swapAt(index, other)
        }
        return items
    }
}

// MARK: - Profile-bound v3 byte machine

package struct Enigma256V3ByteTrace: Sendable, Equatable {
    package let profileHash: String
    package let input: UInt8
    package let output: UInt8
    package let lfsrBefore: UInt64
    package let lfsrAfter: UInt64
    package let offsetsBefore: [UInt8]
    package let offsetsAfter: [UInt8]
    package let stepMaskBits: UInt8
    package let absoluteByteCounterBefore: UInt64
    package let absoluteByteCounterAfter: UInt64
    package let centerMask: UInt8
    package let centerInput: UInt8
    package let centerOutput: UInt8
}

package struct Enigma256V3Machine: Sendable {
    package let profile: Enigma256V3Profile
    package let wiring: Enigma256V3Wiring
    package let centerMaskKey: Data
    package private(set) var lfsr: UInt64
    package private(set) var positions: [UInt8]
    package private(set) var absoluteByteCounter: UInt64
    private var cachedMaskBlockCounter: UInt64?
    private var cachedMaskBlock: [UInt8]

    package init(
        state: Enigma256V3ValidatedState,
        absoluteByteCounter: UInt64 = 0
    ) throws {
        try state.message.validate(profile: state.profile)
        try state.wiring.validate(profile: state.profile)
        guard state.message.lfsrSeed != 0 else { throw Enigma256V3Error.zeroLFSRState }
        self.profile = state.profile
        self.wiring = state.wiring
        self.centerMaskKey = state.message.centerMaskKey
        self.lfsr = state.message.lfsrSeed
        self.positions = state.message.positions
        self.absoluteByteCounter = absoluteByteCounter
        self.cachedMaskBlockCounter = nil
        self.cachedMaskBlock = []
    }

    package mutating func process(_ input: UInt8) throws -> UInt8 {
        try processTraced(input).output
    }

    package mutating func process(_ input: [UInt8]) throws -> [UInt8] {
        var output: [UInt8] = []
        output.reserveCapacity(input.count)
        for byte in input { output.append(try process(byte)) }
        return output
    }

    package mutating func processTraced(_ input: UInt8) throws -> Enigma256V3ByteTrace {
        guard absoluteByteCounter != UInt64.max else {
            throw Enigma256V3Error.counterExhausted
        }
        let counterBefore = absoluteByteCounter
        let lfsrBefore = lfsr
        let offsetsBefore = positions
        let mask = try centerMask(counter: counterBefore)
        let result = scramble(input, centerMask: mask)
        let step = profile.stepMask(state: lfsr)
        let maskBits = UInt8(step.0 ? 1 : 0)
            | UInt8(step.1 ? 2 : 0)
            | UInt8(step.2 ? 4 : 0)
            | UInt8(step.3 ? 8 : 0)
        if step.0 { positions[0] &+= 1 }
        if step.1 { positions[1] &+= 1 }
        if step.2 { positions[2] &+= 1 }
        if step.3 { positions[3] &+= 1 }
        lfsr = Enigma256LFSR(seed: lfsr).next
        absoluteByteCounter += 1
        return Enigma256V3ByteTrace(
            profileHash: profile.profileHashHex,
            input: input,
            output: result.output,
            lfsrBefore: lfsrBefore,
            lfsrAfter: lfsr,
            offsetsBefore: offsetsBefore,
            offsetsAfter: positions,
            stepMaskBits: maskBits,
            absoluteByteCounterBefore: counterBefore,
            absoluteByteCounterAfter: absoluteByteCounter,
            centerMask: mask,
            centerInput: result.centerInput,
            centerOutput: result.centerOutput
        )
    }

    package func scramble(
        _ input: UInt8,
        centerMask: UInt8
    ) -> (output: UInt8, centerInput: UInt8, centerOutput: UInt8) {
        let pbIn = wiring.plugboard[Int(input)]
        let r1 = wiring.r1Fwd[Int(pbIn &+ positions[0])] &- positions[0]
        let r2 = wiring.r2Fwd[Int(r1 &+ positions[1])] &- positions[1]
        let r3 = wiring.r3Fwd[Int(r2 &+ positions[2])] &- positions[2]
        let r4 = wiring.r4Fwd[Int(r3 &+ positions[3])] &- positions[3]
        let centerOutput = r4 ^ centerMask
        let rr4 = wiring.r4Rev[Int(centerOutput &+ positions[3])] &- positions[3]
        let rr3 = wiring.r3Rev[Int(rr4 &+ positions[2])] &- positions[2]
        let rr2 = wiring.r2Rev[Int(rr3 &+ positions[1])] &- positions[1]
        let rr1 = wiring.r1Rev[Int(rr2 &+ positions[0])] &- positions[0]
        return (wiring.plugboard[Int(rr1)], centerInput: r4, centerOutput: centerOutput)
    }

    private mutating func centerMask(counter: UInt64) throws -> UInt8 {
        let blockCounter = counter / UInt64(Enigma256V3Profile.centerMaskBlockLength)
        if cachedMaskBlockCounter != blockCounter {
            var message = try profile.domain("center-mask/block")
            message.append(0)
            var counterBE = blockCounter.bigEndian
            withUnsafeBytes(of: &counterBE) { message.append(contentsOf: $0) }
            cachedMaskBlock = Array(HMAC<SHA256>.authenticationCode(
                for: message,
                using: SymmetricKey(data: centerMaskKey)
            ))
            cachedMaskBlockCounter = blockCounter
        }
        return cachedMaskBlock[Int(counter % UInt64(Enigma256V3Profile.centerMaskBlockLength))]
    }
}
