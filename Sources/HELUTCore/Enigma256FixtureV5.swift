import CryptoKit
import Foundation

// MARK: - Strict fixture-v5 typed contract

package struct Enigma256FixtureV5: Codable, Equatable, Sendable {
    package struct Schema: Codable, Equatable, Sendable {
        package let name: String
        package let version: Int
    }

    package struct Identity: Codable, Equatable, Sendable {
        package let family: String
        package let suiteVersion: Int
        package let generation: Int
        package let fixtureSchemaVersion: Int
        package let profileSHA256: String
        package let compatibilityKey: String

        enum CodingKeys: String, CodingKey {
            case family
            case suiteVersion = "suite_version"
            case generation
            case fixtureSchemaVersion = "fixture_schema_version"
            case profileSHA256 = "profile_sha256"
            case compatibilityKey = "compatibility_key"
        }
    }

    package struct NamedValue: Codable, Equatable, Sendable {
        package let name: String
        package let value: String
    }

    package struct NamedDigest: Codable, Equatable, Sendable {
        package let name: String
        package let sha256: String
    }

    package struct ProfileBinding: Codable, Equatable, Sendable {
        package let canonicalEncoding: String
        package let canonicalProfileBytes: Int
        package let canonicalProfileHex: String
        package let canonicalProfileSHA256: String
        package let domains: [NamedValue]

        enum CodingKeys: String, CodingKey {
            case canonicalEncoding = "canonical_encoding"
            case canonicalProfileBytes = "canonical_profile_bytes"
            case canonicalProfileHex = "canonical_profile_hex"
            case canonicalProfileSHA256 = "canonical_profile_sha256"
            case domains
        }
    }

    package struct Semantics: Codable, Equatable, Sendable {
        package let lfsrTransition: String
        package let updateOrder: String
        package let centerConstruction: String
        package let centerMaskPRF: String
        package let centerMaskCounter: String
        package let centerMaskExtraction: String
        package let centerMapOrder: String
        package let domainEncoding: String
        package let kdf: String
        package let purposeStream: String
        package let boundedSampler: String
        package let zeroPolicy: String
        package let plugboardPolicy: String
        package let rotorPolicy: String
        package let rotorSelection: String
        package let rawSecurityTarget: String
        package let envelopeTarget: String
        package let realDataPolicy: String

        enum CodingKeys: String, CodingKey {
            case lfsrTransition = "lfsr_transition"
            case updateOrder = "update_order"
            case centerConstruction = "center_construction"
            case centerMaskPRF = "center_mask_prf"
            case centerMaskCounter = "center_mask_counter"
            case centerMaskExtraction = "center_mask_extraction"
            case centerMapOrder = "center_map_order"
            case domainEncoding = "domain_encoding"
            case kdf
            case purposeStream = "purpose_stream"
            case boundedSampler = "bounded_sampler"
            case zeroPolicy = "zero_policy"
            case plugboardPolicy = "plugboard_policy"
            case rotorPolicy = "rotor_policy"
            case rotorSelection = "rotor_selection"
            case rawSecurityTarget = "raw_security_target"
            case envelopeTarget = "envelope_target"
            case realDataPolicy = "real_data_policy"
        }
    }

    package struct Inputs: Codable, Equatable, Sendable {
        package let dayIKMHex: String
        package let daySaltHex: String
        package let messageIKMHex: String
        package let nonceHex: String
        package let plaintextGenerator: String

        enum CodingKeys: String, CodingKey {
            case dayIKMHex = "day_ikm_hex"
            case daySaltHex = "day_salt_hex"
            case messageIKMHex = "message_ikm_hex"
            case nonceHex = "nonce_hex"
            case plaintextGenerator = "plaintext_generator"
        }
    }

    package struct PurposeVector: Codable, Equatable, Sendable {
        package let purpose: String
        package let first64Hex: String

        enum CodingKeys: String, CodingKey {
            case purpose
            case first64Hex = "first_64_hex"
        }
    }

    package struct Derivation: Codable, Equatable, Sendable {
        package let purposeVectors: [PurposeVector]
        package let dayTableDigests: [NamedDigest]
        package let activeTableDigests: [NamedDigest]
        package let rotorIndices: [Int]
        package let positionsHex: String
        package let lfsrSeedHex: String
        package let centerMaskKeyHex: String

        enum CodingKeys: String, CodingKey {
            case purposeVectors = "purpose_vectors"
            case dayTableDigests = "day_table_digests"
            case activeTableDigests = "active_table_digests"
            case rotorIndices = "rotor_indices"
            case positionsHex = "positions_hex"
            case lfsrSeedHex = "lfsr_seed_hex"
            case centerMaskKeyHex = "center_mask_key_hex"
        }
    }

    package struct RecurrenceCheckpoint: Codable, Equatable, Sendable {
        package let clock: Int
        package let stateHex: String

        enum CodingKeys: String, CodingKey {
            case clock
            case stateHex = "state_hex"
        }
    }

    package struct RecurrenceVectors: Codable, Equatable, Sendable {
        package let seedHex: String
        package let basisArtifact: String
        package let checkpoints: [RecurrenceCheckpoint]

        enum CodingKeys: String, CodingKey {
            case seedHex = "seed_hex"
            case basisArtifact = "basis_artifact"
            case checkpoints
        }
    }

    package struct StateCheckpoint: Codable, Equatable, Sendable {
        package let byte: Int
        package let absoluteByteCounter: UInt64
        package let lfsrHex: String
        package let positionsHex: String

        enum CodingKeys: String, CodingKey {
            case byte
            case absoluteByteCounter = "absolute_byte_counter"
            case lfsrHex = "lfsr_hex"
            case positionsHex = "positions_hex"
        }
    }

    package struct StreamKAT: Codable, Equatable, Sendable {
        package let byteCount: Int
        package let plaintextArtifact: String
        package let ciphertextArtifact: String
        package let traceArtifact: String
        package let reciprocalDecrypt: Bool
        package let stateCheckpoints: [StateCheckpoint]

        enum CodingKeys: String, CodingKey {
            case byteCount = "byte_count"
            case plaintextArtifact = "plaintext_artifact"
            case ciphertextArtifact = "ciphertext_artifact"
            case traceArtifact = "trace_artifact"
            case reciprocalDecrypt = "reciprocal_decrypt"
            case stateCheckpoints = "state_checkpoints"
        }
    }

    package struct NegativeVector: Codable, Equatable, Sendable {
        package let id: String
        package let mutation: String
        package let expectedError: String

        enum CodingKeys: String, CodingKey {
            case id
            case mutation
            case expectedError = "expected_error"
        }
    }

    package struct Artifact: Codable, Equatable, Sendable {
        package let path: String
        package let logicalID: String
        package let encoding: String
        package let fileBytes: Int
        package let decodedBytes: Int
        package let sha256: String

        enum CodingKeys: String, CodingKey {
            case path
            case logicalID = "logical_id"
            case encoding
            case fileBytes = "file_bytes"
            case decodedBytes = "decoded_bytes"
            case sha256
        }
    }

    package let schema: Schema
    package let identity: Identity
    package let profileBinding: ProfileBinding
    package let semantics: Semantics
    package let inputs: Inputs
    package let derivation: Derivation
    package let recurrenceVectors: RecurrenceVectors
    package let streamKAT: StreamKAT
    package let negativeVectors: [NegativeVector]
    package let artifacts: [Artifact]

    enum CodingKeys: String, CodingKey {
        case schema
        case identity
        case profileBinding = "profile_binding"
        case semantics
        case inputs
        case derivation
        case recurrenceVectors = "recurrence_vectors"
        case streamKAT = "stream_kat"
        case negativeVectors = "negative_vectors"
        case artifacts
    }
}

package struct Enigma256FixtureV5Bundle: Sendable {
    package let fixture: Enigma256FixtureV5
    package let artifactData: [String: Data]
}

package struct Enigma256FixtureV5Verification: Sendable, Equatable {
    package let compatibilityKey: String
    package let profileSHA256: String
    package let streamBytes: Int
    package let artifactCount: Int
    package let recurrenceBasisCount: Int
    package let negativeVectorDeclarationCount: Int
    package let reciprocalDecryptVerified: Bool
}

package enum Enigma256FixtureV5Codec {
    package static let manifestName = "fixture-v5.json"
    package static let manifestLimit = 2 * 1_024 * 1_024
    package static let artifactLimit = 16 * 1_024 * 1_024
    package static let totalArtifactLimit = 64 * 1_024 * 1_024
    package static let checkpointClocks = [0, 1, 2, 58, 59, 60, 64, 128, 1_024]

    private static let rawEncoding = "raw_v1"
    private static let hexEncoding = "lower_hex_lf_v1"
    private static let asciiEncoding = "ascii_lf_v1"

    private struct ArtifactBinding: Equatable {
        let path: String
        let logicalID: String
        let encoding: String

        init(path: String, logicalID: String, encoding: String) {
            self.path = path
            self.logicalID = logicalID
            self.encoding = encoding
        }

        init(_ artifact: Enigma256FixtureV5.Artifact) {
            self.init(
                path: artifact.path,
                logicalID: artifact.logicalID,
                encoding: artifact.encoding
            )
        }
    }

    /// The descriptor sequence is part of fixture-v5. Verifiers and RTL must
    /// consume the same canonical paths rather than a manifest-remapped alias.
    private static let requiredArtifactBindings: [ArtifactBinding] = {
        var bindings: [ArtifactBinding] = []
        func addRawAndHex(logicalID: String, stem: String) {
            bindings.append(.init(
                path: "artifacts/\(stem).bin",
                logicalID: logicalID,
                encoding: rawEncoding
            ))
            bindings.append(.init(
                path: "artifacts/\(stem).hex",
                logicalID: logicalID,
                encoding: hexEncoding
            ))
        }
        addRawAndHex(logicalID: "canonical_profile", stem: "canonical-profile")
        addRawAndHex(logicalID: "ciphertext", stem: "ciphertext")
        addRawAndHex(logicalID: "plaintext", stem: "plaintext")
        for table in [
            "plugboard", "r1_fwd", "r1_rev", "r2_fwd", "r2_rev",
            "r3_fwd", "r3_rev", "r4_fwd", "r4_rev"
        ] {
            addRawAndHex(logicalID: "table_\(table)", stem: "tables/\(table)")
        }
        bindings.append(.init(
            path: "artifacts/recurrence-basis.csv",
            logicalID: "recurrence_basis",
            encoding: asciiEncoding
        ))
        bindings.append(.init(
            path: "artifacts/stream-trace.csv",
            logicalID: "stream_trace",
            encoding: asciiEncoding
        ))
        return bindings.sorted { $0.path < $1.path }
    }()

    // MARK: Authoring into a fresh scratch directory only

    package static func makeBundle(
        profile: Enigma256V3Profile,
        dayIKM: Data,
        daySalt: Data,
        messageIKM: Data,
        nonce: Data,
        streamByteCount: Int = 1_024
    ) throws -> Enigma256FixtureV5Bundle {
        guard streamByteCount >= 1_024 else {
            throw Enigma256V3FixtureError.schemaMismatch("stream KAT must contain at least 1024 bytes")
        }
        try profile.validateFrozenIdentity()
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
        let state = try Enigma256V3ValidatedState(
            profile: profile,
            day: day,
            message: message
        )

        let plaintext = (0 ..< streamByteCount).map {
            UInt8(truncatingIfNeeded: ($0 * 73) ^ ($0 >> 2))
        }
        var machine = try Enigma256V3Machine(state: state)
        var ciphertext: [UInt8] = []
        var traceLines = [
            "byte,input,output,counter_before,lfsr_before,positions_before,step_mask,center_mask,center_input,center_output,counter_after,lfsr_after,positions_after"
        ]
        var stateCheckpoints: [Enigma256FixtureV5.StateCheckpoint] = []
        stateCheckpoints.append(checkpoint(byte: 0, machine: machine))
        for (index, byte) in plaintext.enumerated() {
            let trace = try machine.processTraced(byte)
            ciphertext.append(trace.output)
            traceLines.append(traceLine(byte: index, trace: trace))
            let completed = index + 1
            if checkpointClocks.dropFirst().contains(completed) {
                stateCheckpoints.append(checkpoint(byte: completed, machine: machine))
            }
        }
        var decryptor = try Enigma256V3Machine(state: state)
        let recovered = try decryptor.process(ciphertext)
        guard recovered == plaintext else {
            throw Enigma256V3FixtureError.streamMismatch("reciprocal decrypt")
        }

        let recurrenceSeed: UInt64 = 0x0123_4567_89AB_CDEF
        var recurrence = Enigma256LFSR(seed: recurrenceSeed)
        var recurrenceCheckpoints: [Enigma256FixtureV5.RecurrenceCheckpoint] = []
        for clock in 0 ... 1_024 {
            if checkpointClocks.contains(clock) {
                recurrenceCheckpoints.append(.init(
                    clock: clock,
                    stateHex: hex64(recurrence.state)
                ))
            }
            if clock != 1_024 { recurrence.clock() }
        }
        var basisLines = ["bit,start,next,previous_of_next"]
        for bit in 0 ..< 64 {
            let start = UInt64(1) << UInt64(bit)
            let next = Enigma256LFSR(seed: start).next
            let previous = Enigma256LFSR(seed: next).previous
            basisLines.append("\(bit),\(hex64(start)),\(hex64(next)),\(hex64(previous))")
        }

        var artifactData: [String: Data] = [:]
        var artifacts: [Enigma256FixtureV5.Artifact] = []
        func addRawAndHex(logicalID: String, stem: String, bytes: Data) {
            let rawPath = "artifacts/\(stem).bin"
            artifactData[rawPath] = bytes
            artifacts.append(artifact(
                path: rawPath,
                logicalID: logicalID,
                encoding: rawEncoding,
                data: bytes,
                decodedBytes: bytes.count
            ))
            let hexPath = "artifacts/\(stem).hex"
            let text = Data((hex(bytes) + "\n").utf8)
            artifactData[hexPath] = text
            artifacts.append(artifact(
                path: hexPath,
                logicalID: logicalID,
                encoding: hexEncoding,
                data: text,
                decodedBytes: bytes.count
            ))
        }
        func addASCII(logicalID: String, stem: String, lines: [String]) {
            let path = "artifacts/\(stem)"
            let data = Data((lines.joined(separator: "\n") + "\n").utf8)
            artifactData[path] = data
            artifacts.append(artifact(
                path: path,
                logicalID: logicalID,
                encoding: asciiEncoding,
                data: data,
                decodedBytes: data.count
            ))
        }

        addRawAndHex(
            logicalID: "canonical_profile",
            stem: "canonical-profile",
            bytes: profile.canonicalProfile
        )
        addRawAndHex(logicalID: "plaintext", stem: "plaintext", bytes: Data(plaintext))
        addRawAndHex(logicalID: "ciphertext", stem: "ciphertext", bytes: Data(ciphertext))
        let activeTables = activeTableValues(state.wiring)
        for entry in activeTables {
            addRawAndHex(
                logicalID: "table_\(entry.name)",
                stem: "tables/\(entry.name)",
                bytes: entry.data
            )
        }
        addASCII(logicalID: "stream_trace", stem: "stream-trace.csv", lines: traceLines)
        addASCII(logicalID: "recurrence_basis", stem: "recurrence-basis.csv", lines: basisLines)
        artifacts.sort { $0.path < $1.path }

        var domainValues: [Enigma256FixtureV5.NamedValue] = []
        for purpose in frozenPurposes {
            domainValues.append(.init(
                name: purpose,
                value: String(decoding: try profile.domain(purpose), as: UTF8.self)
            ))
        }

        var purposeVectors: [Enigma256FixtureV5.PurposeVector] = []
        for purpose in streamPurposes {
            let salt = purpose.hasPrefix("day/") ? daySalt : nonce
            let ikm = purpose.hasPrefix("day/") ? dayIKM : messageIKM
            var stream = try Enigma256V3PurposeStream(
                ikm: ikm,
                salt: salt,
                profile: profile,
                purpose: purpose
            )
            purposeVectors.append(.init(
                purpose: purpose,
                first64Hex: hex(Data(try stream.read(count: 64)))
            ))
        }

        let dayDigests = dayTableValues(day).map {
            Enigma256FixtureV5.NamedDigest(name: $0.name, sha256: sha256Hex($0.data))
        }
        let activeDigests = activeTables.map {
            Enigma256FixtureV5.NamedDigest(name: $0.name, sha256: sha256Hex($0.data))
        }

        let fixture = Enigma256FixtureV5(
            schema: .init(name: "E256-FIXTURE-5", version: 5),
            identity: .init(
                family: Enigma256V3Profile.family,
                suiteVersion: Enigma256V3Profile.suiteVersion,
                generation: Enigma256V3Profile.generation,
                fixtureSchemaVersion: Enigma256V3Profile.fixtureSchemaVersion,
                profileSHA256: profile.profileHashHex,
                compatibilityKey: profile.compatibilityKey
            ),
            profileBinding: .init(
                canonicalEncoding: Enigma256V3Profile.canonicalEncoding,
                canonicalProfileBytes: profile.canonicalProfile.count,
                canonicalProfileHex: hex(profile.canonicalProfile),
                canonicalProfileSHA256: profile.profileHashHex,
                domains: domainValues
            ),
            semantics: .init(
                lfsrTransition: Enigma256Generation.transitionIdentifier,
                updateOrder: Enigma256Generation.updateOrderIdentifier,
                centerConstruction: Enigma256Generation.centerConstructionIdentifier,
                centerMaskPRF: Enigma256Generation.centerMaskPRFIdentifier,
                centerMaskCounter: Enigma256Generation.centerMaskCounterIdentifier,
                centerMaskExtraction: Enigma256Generation.centerMaskExtractionIdentifier,
                centerMapOrder: Enigma256Generation.centerMapOrderIdentifier,
                domainEncoding: Enigma256V3Profile.domainEncoding,
                kdf: Enigma256V3Profile.KDF,
                purposeStream: Enigma256V3Profile.purposeStream,
                boundedSampler: Enigma256V3Profile.boundedSampler,
                zeroPolicy: Enigma256V3Profile.zeroPolicy,
                plugboardPolicy: "fixed_point_free_involution_v1",
                rotorPolicy: "permutation_inverse_pair_v1",
                rotorSelection: "four_distinct_without_replacement_v1",
                rawSecurityTarget: "nonce_respecting_ind_cpa_target_conditional_hkdf_hmac_prf",
                envelopeTarget: "encrypt_then_mac_hmac_sha256_independent_keys_v1",
                realDataPolicy: "standard_aead_required"
            ),
            inputs: .init(
                dayIKMHex: hex(dayIKM),
                daySaltHex: hex(daySalt),
                messageIKMHex: hex(messageIKM),
                nonceHex: hex(nonce),
                plaintextGenerator: "byte_i=(73*i xor (i>>2)) mod 256"
            ),
            derivation: .init(
                purposeVectors: purposeVectors,
                dayTableDigests: dayDigests,
                activeTableDigests: activeDigests,
                rotorIndices: message.rotorIndices,
                positionsHex: hex(Data(message.positions)),
                lfsrSeedHex: hex64(message.lfsrSeed),
                centerMaskKeyHex: hex(message.centerMaskKey)
            ),
            recurrenceVectors: .init(
                seedHex: hex64(recurrenceSeed),
                basisArtifact: "artifacts/recurrence-basis.csv",
                checkpoints: recurrenceCheckpoints
            ),
            streamKAT: .init(
                byteCount: streamByteCount,
                plaintextArtifact: "artifacts/plaintext.bin",
                ciphertextArtifact: "artifacts/ciphertext.bin",
                traceArtifact: "artifacts/stream-trace.csv",
                reciprocalDecrypt: true,
                stateCheckpoints: stateCheckpoints
            ),
            negativeVectors: requiredNegativeVectors,
            artifacts: artifacts
        )
        return Enigma256FixtureV5Bundle(fixture: fixture, artifactData: artifactData)
    }

    package static func write(
        _ bundle: Enigma256FixtureV5Bundle,
        to directory: URL
    ) throws {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: directory.path) else {
            throw Enigma256V3FixtureError.pathExists(directory.path)
        }
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let artifactDirectory = directory.appendingPathComponent("artifacts", isDirectory: true)
        try manager.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)
        for (relativePath, data) in bundle.artifactData.sorted(by: { $0.key < $1.key }) {
            let destination = directory.appendingPathComponent(relativePath)
            let parent = destination.deletingLastPathComponent()
            if !manager.fileExists(atPath: parent.path) {
                try manager.createDirectory(at: parent, withIntermediateDirectories: true)
            }
            try data.write(to: destination, options: [.atomic])
        }
        let manifest = try canonicalJSON(bundle.fixture)
        try manifest.write(
            to: directory.appendingPathComponent(manifestName),
            options: [.atomic]
        )
    }

    // MARK: Strict consumption and complete rederivation

    package static func verify(
        at directory: URL,
        profile: Enigma256V3Profile
    ) throws -> Enigma256FixtureV5Verification {
        try profile.validateFrozenIdentity()
        try requireDirectory(directory)
        let rootEntries = try Set(FileManager.default.contentsOfDirectory(atPath: directory.path))
        guard rootEntries == Set([manifestName, "artifacts"]) else {
            throw Enigma256V3FixtureError.unexpectedLayout(
                rootEntries.sorted().joined(separator: ",")
            )
        }
        let artifactDirectory = directory.appendingPathComponent("artifacts", isDirectory: true)
        try requireDirectory(artifactDirectory)
        let manifestURL = directory.appendingPathComponent(manifestName)
        let manifestData = try readRegularFile(manifestURL, limit: manifestLimit)
        try Enigma256StrictJSON.validate(manifestData, shape: manifestShape)
        let fixture: Enigma256FixtureV5
        do {
            fixture = try JSONDecoder().decode(Enigma256FixtureV5.self, from: manifestData)
        } catch {
            throw Enigma256V3FixtureError.invalidJSON(String(describing: error))
        }
        guard try canonicalJSON(fixture) == manifestData else {
            throw Enigma256V3FixtureError.nonCanonicalJSON
        }
        try validateIdentityAndSemantics(fixture, profile: profile)
        guard fixture.artifacts.map(ArtifactBinding.init) == requiredArtifactBindings else {
            throw Enigma256V3FixtureError.schemaMismatch("artifact bindings")
        }

        var expectedPaths = Set<String>()
        var seenLogicalEncodings = Set<String>()
        var decodedByLogical: [String: Data] = [:]
        var totalBytes = 0
        for descriptor in fixture.artifacts {
            try validateArtifactPath(descriptor.path)
            guard expectedPaths.insert(descriptor.path).inserted else {
                throw Enigma256V3FixtureError.duplicateArtifactPath(descriptor.path)
            }
            let logicalEncoding = "\(descriptor.logicalID)|\(descriptor.encoding)"
            guard seenLogicalEncodings.insert(logicalEncoding).inserted else {
                throw Enigma256V3FixtureError.duplicateLogicalEncoding(logicalEncoding)
            }
            let url = directory.appendingPathComponent(descriptor.path)
            let data = try readRegularFile(url, limit: artifactLimit)
            totalBytes += data.count
            guard totalBytes <= totalArtifactLimit else {
                throw Enigma256V3FixtureError.artifactTooLarge(
                    path: "aggregate",
                    size: totalBytes
                )
            }
            guard data.count == descriptor.fileBytes else {
                throw Enigma256V3FixtureError.artifactSize(
                    path: descriptor.path,
                    expected: descriptor.fileBytes,
                    actual: data.count
                )
            }
            let digest = sha256Hex(data)
            guard digest == descriptor.sha256 else {
                throw Enigma256V3FixtureError.artifactHash(
                    path: descriptor.path,
                    expected: descriptor.sha256,
                    actual: digest
                )
            }
            let decoded = try decodeArtifact(data, descriptor: descriptor)
            if let prior = decodedByLogical[descriptor.logicalID], prior != decoded {
                throw Enigma256V3FixtureError.duplicateArtifactMismatch(descriptor.logicalID)
            }
            decodedByLogical[descriptor.logicalID] = decoded
        }
        try verifyExactArtifactLayout(
            artifactDirectory: artifactDirectory,
            expectedRelativePaths: expectedPaths
        )

        guard decodedByLogical["canonical_profile"] == profile.canonicalProfile else {
            throw Enigma256V3FixtureError.identityMismatch("canonical profile artifact")
        }
        let dayIKM = try decodeHex(fixture.inputs.dayIKMHex, field: "inputs.day_ikm_hex")
        let daySalt = try decodeHex(fixture.inputs.daySaltHex, field: "inputs.day_salt_hex")
        let messageIKM = try decodeHex(fixture.inputs.messageIKMHex, field: "inputs.message_ikm_hex")
        let nonce = try decodeHex(
            fixture.inputs.nonceHex,
            expectedBytes: Enigma256V3Profile.nonceLength,
            field: "inputs.nonce_hex"
        )
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
        let state = try Enigma256V3ValidatedState(
            profile: profile,
            day: day,
            message: message
        )
        try verifyDerivation(
            fixture,
            profile: profile,
            dayIKM: dayIKM,
            daySalt: daySalt,
            messageIKM: messageIKM,
            nonce: nonce,
            day: day,
            message: message,
            state: state,
            decodedByLogical: decodedByLogical
        )
        try verifyRecurrence(fixture, decodedByLogical: decodedByLogical)
        try verifyStream(
            fixture,
            state: state,
            decodedByLogical: decodedByLogical
        )
        guard fixture.negativeVectors == requiredNegativeVectors else {
            throw Enigma256V3FixtureError.negativeVectorMismatch("required vector set")
        }
        try executeInMemoryNegativeControls(profile: profile, state: state)

        return Enigma256FixtureV5Verification(
            compatibilityKey: fixture.identity.compatibilityKey,
            profileSHA256: fixture.identity.profileSHA256,
            streamBytes: fixture.streamKAT.byteCount,
            artifactCount: fixture.artifacts.count,
            recurrenceBasisCount: 64,
            negativeVectorDeclarationCount: fixture.negativeVectors.count,
            reciprocalDecryptVerified: true
        )
    }

    // MARK: Validation internals

    private static func validateIdentityAndSemantics(
        _ fixture: Enigma256FixtureV5,
        profile: Enigma256V3Profile
    ) throws {
        guard fixture.schema == .init(name: "E256-FIXTURE-5", version: 5) else {
            throw Enigma256V3FixtureError.schemaMismatch("schema")
        }
        let expectedIdentity = Enigma256FixtureV5.Identity(
            family: "E256",
            suiteVersion: 3,
            generation: 0,
            fixtureSchemaVersion: 5,
            profileSHA256: profile.profileHashHex,
            compatibilityKey: profile.compatibilityKey
        )
        guard fixture.identity == expectedIdentity else {
            throw Enigma256V3FixtureError.identityMismatch("compatibility tuple")
        }
        guard fixture.profileBinding.canonicalEncoding == Enigma256V3Profile.canonicalEncoding,
              fixture.profileBinding.canonicalProfileBytes == profile.canonicalProfile.count,
              fixture.profileBinding.canonicalProfileSHA256 == profile.profileHashHex,
              try decodeHex(
                  fixture.profileBinding.canonicalProfileHex,
                  expectedBytes: profile.canonicalProfile.count,
                  field: "profile_binding.canonical_profile_hex"
              ) == profile.canonicalProfile else {
            throw Enigma256V3FixtureError.identityMismatch("canonical profile binding")
        }
        let expectedSemantics = Enigma256FixtureV5.Semantics(
            lfsrTransition: Enigma256Generation.transitionIdentifier,
            updateOrder: Enigma256Generation.updateOrderIdentifier,
            centerConstruction: Enigma256Generation.centerConstructionIdentifier,
            centerMaskPRF: Enigma256Generation.centerMaskPRFIdentifier,
            centerMaskCounter: Enigma256Generation.centerMaskCounterIdentifier,
            centerMaskExtraction: Enigma256Generation.centerMaskExtractionIdentifier,
            centerMapOrder: Enigma256Generation.centerMapOrderIdentifier,
            domainEncoding: Enigma256V3Profile.domainEncoding,
            kdf: Enigma256V3Profile.KDF,
            purposeStream: Enigma256V3Profile.purposeStream,
            boundedSampler: Enigma256V3Profile.boundedSampler,
            zeroPolicy: Enigma256V3Profile.zeroPolicy,
            plugboardPolicy: "fixed_point_free_involution_v1",
            rotorPolicy: "permutation_inverse_pair_v1",
            rotorSelection: "four_distinct_without_replacement_v1",
            rawSecurityTarget: "nonce_respecting_ind_cpa_target_conditional_hkdf_hmac_prf",
            envelopeTarget: "encrypt_then_mac_hmac_sha256_independent_keys_v1",
            realDataPolicy: "standard_aead_required"
        )
        guard fixture.semantics == expectedSemantics else {
            throw Enigma256V3FixtureError.schemaMismatch("semantic identifiers")
        }
        let expectedDomains = try frozenPurposes.map {
            Enigma256FixtureV5.NamedValue(
                name: $0,
                value: String(decoding: try profile.domain($0), as: UTF8.self)
            )
        }
        guard fixture.profileBinding.domains == expectedDomains else {
            throw Enigma256V3FixtureError.identityMismatch("domain registry")
        }
        guard fixture.inputs.plaintextGenerator == "byte_i=(73*i xor (i>>2)) mod 256" else {
            throw Enigma256V3FixtureError.schemaMismatch("plaintext generator")
        }
    }

    private static func verifyDerivation(
        _ fixture: Enigma256FixtureV5,
        profile: Enigma256V3Profile,
        dayIKM: Data,
        daySalt: Data,
        messageIKM: Data,
        nonce: Data,
        day: Enigma256V3DayKey,
        message: Enigma256V3MessageKey,
        state: Enigma256V3ValidatedState,
        decodedByLogical: [String: Data]
    ) throws {
        var vectors: [Enigma256FixtureV5.PurposeVector] = []
        for purpose in streamPurposes {
            let salt = purpose.hasPrefix("day/") ? daySalt : nonce
            let ikm = purpose.hasPrefix("day/") ? dayIKM : messageIKM
            var stream = try Enigma256V3PurposeStream(
                ikm: ikm,
                salt: salt,
                profile: profile,
                purpose: purpose
            )
            vectors.append(.init(
                purpose: purpose,
                first64Hex: hex(Data(try stream.read(count: 64)))
            ))
        }
        guard fixture.derivation.purposeVectors == vectors else {
            throw Enigma256V3FixtureError.derivationMismatch("purpose vectors")
        }
        let dayDigests = dayTableValues(day).map {
            Enigma256FixtureV5.NamedDigest(name: $0.name, sha256: sha256Hex($0.data))
        }
        guard fixture.derivation.dayTableDigests == dayDigests else {
            throw Enigma256V3FixtureError.derivationMismatch("day table digests")
        }
        let active = activeTableValues(state.wiring)
        let activeDigests = active.map {
            Enigma256FixtureV5.NamedDigest(name: $0.name, sha256: sha256Hex($0.data))
        }
        guard fixture.derivation.activeTableDigests == activeDigests else {
            throw Enigma256V3FixtureError.derivationMismatch("active table digests")
        }
        for entry in active {
            guard decodedByLogical["table_\(entry.name)"] == entry.data else {
                throw Enigma256V3FixtureError.derivationMismatch("active table \(entry.name)")
            }
        }
        guard fixture.derivation.rotorIndices == message.rotorIndices,
              try decodeHex(
                  fixture.derivation.positionsHex,
                  expectedBytes: 4,
                  field: "derivation.positions_hex"
              ) == Data(message.positions),
              fixture.derivation.lfsrSeedHex == hex64(message.lfsrSeed),
              try decodeHex(
                  fixture.derivation.centerMaskKeyHex,
                  expectedBytes: 32,
                  field: "derivation.center_mask_key_hex"
              ) == message.centerMaskKey else {
            throw Enigma256V3FixtureError.derivationMismatch("message state")
        }
    }

    private static func verifyRecurrence(
        _ fixture: Enigma256FixtureV5,
        decodedByLogical: [String: Data]
    ) throws {
        guard fixture.recurrenceVectors.basisArtifact == "artifacts/recurrence-basis.csv",
              let basis = decodedByLogical["recurrence_basis"],
              let basisText = String(data: basis, encoding: .ascii) else {
            throw Enigma256V3FixtureError.recurrenceMismatch("basis artifact")
        }
        var expectedLines = ["bit,start,next,previous_of_next"]
        for bit in 0 ..< 64 {
            let start = UInt64(1) << UInt64(bit)
            let next = Enigma256LFSR(seed: start).next
            let previous = Enigma256LFSR(seed: next).previous
            expectedLines.append("\(bit),\(hex64(start)),\(hex64(next)),\(hex64(previous))")
        }
        guard basisText == expectedLines.joined(separator: "\n") + "\n" else {
            throw Enigma256V3FixtureError.recurrenceMismatch("64-basis rows")
        }
        guard let seed = parseHex64(fixture.recurrenceVectors.seedHex) else {
            throw Enigma256V3FixtureError.invalidHex(field: "recurrence_vectors.seed_hex")
        }
        var lfsr = Enigma256LFSR(seed: seed)
        var checkpoints: [Enigma256FixtureV5.RecurrenceCheckpoint] = []
        for clock in 0 ... 1_024 {
            if checkpointClocks.contains(clock) {
                checkpoints.append(.init(clock: clock, stateHex: hex64(lfsr.state)))
            }
            if clock != 1_024 { lfsr.clock() }
        }
        guard fixture.recurrenceVectors.checkpoints == checkpoints else {
            throw Enigma256V3FixtureError.recurrenceMismatch("checkpoints")
        }
    }

    private static func verifyStream(
        _ fixture: Enigma256FixtureV5,
        state: Enigma256V3ValidatedState,
        decodedByLogical: [String: Data]
    ) throws {
        guard fixture.streamKAT.byteCount >= 1_024,
              fixture.streamKAT.plaintextArtifact == "artifacts/plaintext.bin",
              fixture.streamKAT.ciphertextArtifact == "artifacts/ciphertext.bin",
              fixture.streamKAT.traceArtifact == "artifacts/stream-trace.csv",
              fixture.streamKAT.reciprocalDecrypt,
              let plaintextData = decodedByLogical["plaintext"],
              let ciphertextData = decodedByLogical["ciphertext"],
              let traceData = decodedByLogical["stream_trace"],
              plaintextData.count == fixture.streamKAT.byteCount,
              ciphertextData.count == fixture.streamKAT.byteCount else {
            throw Enigma256V3FixtureError.streamMismatch("layout")
        }
        let expectedPlaintext = Data((0 ..< fixture.streamKAT.byteCount).map {
            UInt8(truncatingIfNeeded: ($0 * 73) ^ ($0 >> 2))
        })
        guard plaintextData == expectedPlaintext else {
            throw Enigma256V3FixtureError.streamMismatch("plaintext generator")
        }
        var machine = try Enigma256V3Machine(state: state)
        var ciphertext: [UInt8] = []
        var traceLines = [
            "byte,input,output,counter_before,lfsr_before,positions_before,step_mask,center_mask,center_input,center_output,counter_after,lfsr_after,positions_after"
        ]
        var checkpoints = [checkpoint(byte: 0, machine: machine)]
        for (index, byte) in plaintextData.enumerated() {
            let trace = try machine.processTraced(byte)
            ciphertext.append(trace.output)
            traceLines.append(traceLine(byte: index, trace: trace))
            if checkpointClocks.dropFirst().contains(index + 1) {
                checkpoints.append(checkpoint(byte: index + 1, machine: machine))
            }
        }
        guard Data(ciphertext) == ciphertextData else {
            throw Enigma256V3FixtureError.streamMismatch("ciphertext")
        }
        guard traceData == Data((traceLines.joined(separator: "\n") + "\n").utf8) else {
            throw Enigma256V3FixtureError.streamMismatch("full trace")
        }
        guard fixture.streamKAT.stateCheckpoints == checkpoints else {
            throw Enigma256V3FixtureError.streamMismatch("state checkpoints")
        }
        var decryptor = try Enigma256V3Machine(state: state)
        guard try decryptor.process(ciphertext) == Array(plaintextData) else {
            throw Enigma256V3FixtureError.streamMismatch("reciprocal decrypt")
        }
    }

    private static func executeInMemoryNegativeControls(
        profile: Enigma256V3Profile,
        state: Enigma256V3ValidatedState
    ) throws {
        do {
            _ = try Enigma256V3MessageKey(
                profile: profile,
                rotorIndices: [0, 1, 2, 3],
                positions: [0, 0, 0, 0],
                lfsrSeed: 0,
                centerMaskKey: Data(repeating: 0, count: 32)
            )
            throw Enigma256V3FixtureError.negativeVectorMismatch("external_zero_lfsr")
        } catch Enigma256V3Error.zeroLFSRState {}
        do {
            _ = try Enigma256V3MessageKey(
                profile: profile,
                rotorIndices: [0, 1, 1, 3],
                positions: [0, 0, 0, 0],
                lfsrSeed: 1,
                centerMaskKey: Data(repeating: 0, count: 32)
            )
            throw Enigma256V3FixtureError.negativeVectorMismatch("duplicate_rotor")
        } catch Enigma256V3Error.duplicateRotorIndex(1) {}
        do {
            _ = try Enigma256V3MessageKey(
                profile: profile,
                rotorIndices: [0, 1, 2, 16],
                positions: [0, 0, 0, 0],
                lfsrSeed: 1,
                centerMaskKey: Data(repeating: 0, count: 32)
            )
            throw Enigma256V3FixtureError.negativeVectorMismatch("rotor_out_of_range")
        } catch Enigma256V3Error.rotorIndexOutOfRange(16) {}
        let fixedPoint = (0 ... 255).map(UInt8.init)
        do {
            _ = try Enigma256V3Wiring(
                profile: profile,
                plugboard: fixedPoint,
                r1Fwd: state.wiring.r1Fwd, r1Rev: state.wiring.r1Rev,
                r2Fwd: state.wiring.r2Fwd, r2Rev: state.wiring.r2Rev,
                r3Fwd: state.wiring.r3Fwd, r3Rev: state.wiring.r3Rev,
                r4Fwd: state.wiring.r4Fwd, r4Rev: state.wiring.r4Rev
            )
            throw Enigma256V3FixtureError.negativeVectorMismatch("plugboard_fixed_point")
        } catch Enigma256V3Error.plugboardFixedPoint(index: 0) {}
    }

    // MARK: Artifact and format helpers

    private static func canonicalJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        if data.last != 0x0A { data.append(0x0A) }
        return data
    }

    private static func artifact(
        path: String,
        logicalID: String,
        encoding: String,
        data: Data,
        decodedBytes: Int
    ) -> Enigma256FixtureV5.Artifact {
        .init(
            path: path,
            logicalID: logicalID,
            encoding: encoding,
            fileBytes: data.count,
            decodedBytes: decodedBytes,
            sha256: sha256Hex(data)
        )
    }

    private static func validateArtifactPath(_ path: String) throws {
        guard path.hasPrefix("artifacts/"),
              !path.hasSuffix("/"),
              !path.contains("//"),
              !path.contains(".."),
              !path.contains("\\"),
              path.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value <= 0x7E }) else {
            throw Enigma256V3FixtureError.unsafeArtifactPath(path)
        }
    }

    private static func decodeArtifact(
        _ data: Data,
        descriptor: Enigma256FixtureV5.Artifact
    ) throws -> Data {
        switch descriptor.encoding {
        case rawEncoding:
            guard descriptor.decodedBytes == data.count else {
                throw Enigma256V3FixtureError.artifactEncoding(
                    path: descriptor.path,
                    encoding: descriptor.encoding
                )
            }
            return data
        case hexEncoding:
            guard data.last == 0x0A,
                  !data.dropLast().contains(0x0A),
                  !data.contains(0x0D),
                  let text = String(data: data.dropLast(), encoding: .ascii) else {
                throw Enigma256V3FixtureError.artifactEncoding(
                    path: descriptor.path,
                    encoding: descriptor.encoding
                )
            }
            let decoded = try decodeHex(
                text,
                expectedBytes: descriptor.decodedBytes,
                field: descriptor.path
            )
            return decoded
        case asciiEncoding:
            guard descriptor.decodedBytes == data.count,
                  data.last == 0x0A,
                  !data.contains(0x0D),
                  data.allSatisfy({ $0 == 0x0A || ($0 >= 0x20 && $0 <= 0x7E) }) else {
                throw Enigma256V3FixtureError.artifactEncoding(
                    path: descriptor.path,
                    encoding: descriptor.encoding
                )
            }
            return data
        default:
            throw Enigma256V3FixtureError.artifactEncoding(
                path: descriptor.path,
                encoding: descriptor.encoding
            )
        }
    }

    private static func readRegularFile(_ url: URL, limit: Int) throws -> Data {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            throw Enigma256V3FixtureError.missingPath(url.path)
        }
        let type = attributes[.type] as? FileAttributeType
        if type == .typeSymbolicLink { throw Enigma256V3FixtureError.symlink(url.path) }
        guard type == .typeRegular else {
            throw Enigma256V3FixtureError.notRegularFile(url.path)
        }
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size <= limit else {
            if url.lastPathComponent == manifestName {
                throw Enigma256V3FixtureError.manifestTooLarge(size)
            }
            throw Enigma256V3FixtureError.artifactTooLarge(path: url.path, size: size)
        }
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private static func requireDirectory(_ url: URL) throws {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            throw Enigma256V3FixtureError.missingPath(url.path)
        }
        let type = attributes[.type] as? FileAttributeType
        if type == .typeSymbolicLink { throw Enigma256V3FixtureError.symlink(url.path) }
        guard type == .typeDirectory else {
            throw Enigma256V3FixtureError.notDirectory(url.path)
        }
    }

    private static func verifyExactArtifactLayout(
        artifactDirectory: URL,
        expectedRelativePaths: Set<String>
    ) throws {
        let manager = FileManager.default
        let subpaths = try manager.subpathsOfDirectory(atPath: artifactDirectory.path)
        var actual = Set<String>()
        for subpath in subpaths {
            let url = artifactDirectory.appendingPathComponent(subpath)
            let attributes = try manager.attributesOfItem(atPath: url.path)
            let type = attributes[.type] as? FileAttributeType
            let relative = "artifacts/\(subpath)"
            if type == .typeSymbolicLink {
                throw Enigma256V3FixtureError.symlink(relative)
            }
            if type == .typeDirectory { continue }
            guard type == .typeRegular else {
                throw Enigma256V3FixtureError.notRegularFile(relative)
            }
            actual.insert(relative)
        }
        guard actual == expectedRelativePaths else {
            let extra = actual.subtracting(expectedRelativePaths)
            let missing = expectedRelativePaths.subtracting(actual)
            throw Enigma256V3FixtureError.unexpectedLayout(
                "extra=\(extra.sorted()) missing=\(missing.sorted())"
            )
        }
    }

    private static func decodeHex(
        _ text: String,
        expectedBytes: Int? = nil,
        field: String
    ) throws -> Data {
        guard text.count % 2 == 0,
              text == text.lowercased(),
              text.utf8.allSatisfy({
                  ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66)
              }),
              expectedBytes.map({ text.count == $0 * 2 }) ?? true else {
            throw Enigma256V3FixtureError.invalidHex(field: field)
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(text.count / 2)
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index ..< next], radix: 16) else {
                throw Enigma256V3FixtureError.invalidHex(field: field)
            }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }

    private static func parseHex64(_ text: String) -> UInt64? {
        guard text.count == 16,
              text == text.lowercased(),
              text.utf8.allSatisfy({
                  ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66)
              }) else { return nil }
        return UInt64(text, radix: 16)
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private static func hex64(_ value: UInt64) -> String {
        String(format: "%016llx", value)
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func checkpoint(
        byte: Int,
        machine: Enigma256V3Machine
    ) -> Enigma256FixtureV5.StateCheckpoint {
        .init(
            byte: byte,
            absoluteByteCounter: machine.absoluteByteCounter,
            lfsrHex: hex64(machine.lfsr),
            positionsHex: hex(Data(machine.positions))
        )
    }

    private static func traceLine(byte: Int, trace: Enigma256V3ByteTrace) -> String {
        [
            String(byte),
            String(format: "%02x", trace.input),
            String(format: "%02x", trace.output),
            hex64(trace.absoluteByteCounterBefore),
            hex64(trace.lfsrBefore),
            hex(Data(trace.offsetsBefore)),
            String(format: "%02x", trace.stepMaskBits),
            String(format: "%02x", trace.centerMask),
            String(format: "%02x", trace.centerInput),
            String(format: "%02x", trace.centerOutput),
            hex64(trace.absoluteByteCounterAfter),
            hex64(trace.lfsrAfter),
            hex(Data(trace.offsetsAfter))
        ].joined(separator: ",")
    }

    private static func dayTableValues(
        _ day: Enigma256V3DayKey
    ) -> [(name: String, data: Data)] {
        var values = [(name: "plugboard", data: Data(day.plugboard))]
        for rotor in 0 ..< 16 {
            values.append((
                name: String(format: "rotor_%02d_fwd", rotor),
                data: Data(day.rotorPoolFwd[rotor])
            ))
            values.append((
                name: String(format: "rotor_%02d_rev", rotor),
                data: Data(day.rotorPoolRev[rotor])
            ))
        }
        return values
    }

    private static func activeTableValues(
        _ wiring: Enigma256V3Wiring
    ) -> [(name: String, data: Data)] {
        [
            ("plugboard", Data(wiring.plugboard)),
            ("r1_fwd", Data(wiring.r1Fwd)), ("r1_rev", Data(wiring.r1Rev)),
            ("r2_fwd", Data(wiring.r2Fwd)), ("r2_rev", Data(wiring.r2Rev)),
            ("r3_fwd", Data(wiring.r3Fwd)), ("r3_rev", Data(wiring.r3Rev)),
            ("r4_fwd", Data(wiring.r4Fwd)), ("r4_rev", Data(wiring.r4Rev))
        ]
    }

    private static let frozenPurposes: [String] = [
        "day/plugboard"
    ] + (0 ..< 16).map { String(format: "day/rotor/%02d", $0) } + [
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

    private static let streamPurposes: [String] = [
        "day/plugboard"
    ] + (0 ..< 16).map { String(format: "day/rotor/%02d", $0) } + [
        "message/rotor-selection",
        "message/positions",
        "message/lfsr-seed"
    ]

    private static let requiredNegativeVectors: [Enigma256FixtureV5.NegativeVector] = [
        .init(id: "duplicate_json_key", mutation: "duplicate top-level schema key", expectedError: "duplicateJSONKey"),
        .init(id: "unknown_json_key", mutation: "add unknown top-level key", expectedError: "unknownJSONKey"),
        .init(id: "uppercase_hex", mutation: "uppercase one canonical hex nibble", expectedError: "invalidHex"),
        .init(id: "external_zero_lfsr", mutation: "set external lfsr_seed_hex to zero", expectedError: "zeroLFSRState"),
        .init(id: "duplicate_rotor", mutation: "repeat a message rotor index", expectedError: "duplicateRotorIndex"),
        .init(id: "rotor_out_of_range", mutation: "set a message rotor index to 16", expectedError: "rotorIndexOutOfRange"),
        .init(id: "plugboard_fixed_point", mutation: "set plugboard[0] to 0", expectedError: "plugboardFixedPoint"),
        .init(id: "table_not_permutation", mutation: "duplicate one rotor table value", expectedError: "notPermutation"),
        .init(id: "rotor_inverse_mismatch", mutation: "swap two reverse rotor entries", expectedError: "rotorPairNotInverse"),
        .init(id: "artifact_hash_mismatch", mutation: "flip one artifact byte", expectedError: "artifactHash"),
        .init(id: "duplicate_format_mismatch", mutation: "change hex duplicate only", expectedError: "duplicateArtifactMismatch"),
        .init(id: "extra_file", mutation: "add an unlisted regular file", expectedError: "unexpectedLayout"),
        .init(id: "symlink_artifact", mutation: "replace an artifact with a symlink", expectedError: "symlink")
    ]

    private static let manifestShape: Enigma256StrictJSONShape = .object([
        "schema": .object(["name": .scalar, "version": .scalar]),
        "identity": .object([
            "family": .scalar,
            "suite_version": .scalar,
            "generation": .scalar,
            "fixture_schema_version": .scalar,
            "profile_sha256": .scalar,
            "compatibility_key": .scalar
        ]),
        "profile_binding": .object([
            "canonical_encoding": .scalar,
            "canonical_profile_bytes": .scalar,
            "canonical_profile_hex": .scalar,
            "canonical_profile_sha256": .scalar,
            "domains": .array(.object(["name": .scalar, "value": .scalar]))
        ]),
        "semantics": .object([
            "lfsr_transition": .scalar,
            "update_order": .scalar,
            "center_construction": .scalar,
            "center_mask_prf": .scalar,
            "center_mask_counter": .scalar,
            "center_mask_extraction": .scalar,
            "center_map_order": .scalar,
            "domain_encoding": .scalar,
            "kdf": .scalar,
            "purpose_stream": .scalar,
            "bounded_sampler": .scalar,
            "zero_policy": .scalar,
            "plugboard_policy": .scalar,
            "rotor_policy": .scalar,
            "rotor_selection": .scalar,
            "raw_security_target": .scalar,
            "envelope_target": .scalar,
            "real_data_policy": .scalar
        ]),
        "inputs": .object([
            "day_ikm_hex": .scalar,
            "day_salt_hex": .scalar,
            "message_ikm_hex": .scalar,
            "nonce_hex": .scalar,
            "plaintext_generator": .scalar
        ]),
        "derivation": .object([
            "purpose_vectors": .array(.object([
                "purpose": .scalar,
                "first_64_hex": .scalar
            ])),
            "day_table_digests": .array(.object(["name": .scalar, "sha256": .scalar])),
            "active_table_digests": .array(.object(["name": .scalar, "sha256": .scalar])),
            "rotor_indices": .array(.scalar),
            "positions_hex": .scalar,
            "lfsr_seed_hex": .scalar,
            "center_mask_key_hex": .scalar
        ]),
        "recurrence_vectors": .object([
            "seed_hex": .scalar,
            "basis_artifact": .scalar,
            "checkpoints": .array(.object(["clock": .scalar, "state_hex": .scalar]))
        ]),
        "stream_kat": .object([
            "byte_count": .scalar,
            "plaintext_artifact": .scalar,
            "ciphertext_artifact": .scalar,
            "trace_artifact": .scalar,
            "reciprocal_decrypt": .scalar,
            "state_checkpoints": .array(.object([
                "byte": .scalar,
                "absolute_byte_counter": .scalar,
                "lfsr_hex": .scalar,
                "positions_hex": .scalar
            ]))
        ]),
        "negative_vectors": .array(.object([
            "id": .scalar,
            "mutation": .scalar,
            "expected_error": .scalar
        ])),
        "artifacts": .array(.object([
            "path": .scalar,
            "logical_id": .scalar,
            "encoding": .scalar,
            "file_bytes": .scalar,
            "decoded_bytes": .scalar,
            "sha256": .scalar
        ]))
    ])
}
