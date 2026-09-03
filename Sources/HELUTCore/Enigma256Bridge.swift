import CryptoKit
import Foundation

// MARK: - Enigma 256 ↔ FPGA bridge (hex BRAMs + golden session JSON)
//
// Load order into `enigma_256_core` matches Verilog `wr_sel`:
//   0 plugboard, 1 r1_fwd, 2 r1_rev, 3 r2_fwd, 4 r2_rev,
//   5 r3_fwd, 6 r3_rev, 7 r4_fwd, 8 r4_rev

package enum Enigma256TableSel: Int, CaseIterable, Sendable {
    case plugboard = 0
    case r1Fwd = 1
    case r1Rev = 2
    case r2Fwd = 3
    case r2Rev = 4
    case r3Fwd = 5
    case r3Rev = 6
    case r4Fwd = 7
    case r4Rev = 8

    package var fileName: String {
        switch self {
        case .plugboard: return "plugboard.hex"
        case .r1Fwd: return "r1_fwd.hex"
        case .r1Rev: return "r1_rev.hex"
        case .r2Fwd: return "r2_fwd.hex"
        case .r2Rev: return "r2_rev.hex"
        case .r3Fwd: return "r3_fwd.hex"
        case .r3Rev: return "r3_rev.hex"
        case .r4Fwd: return "r4_fwd.hex"
        case .r4Rev: return "r4_rev.hex"
        }
    }
}

package struct Enigma256Session: Sendable {
    package var profile: Enigma256Generation
    package var ikm: Data
    package var salt: Data
    package var nonce: Data
    package var message: Enigma256MessageKey
    package var plaintext: [UInt8]
    package var ciphertext: [UInt8]
    package var wiring: Enigma256Wiring

    package init(
        profile: Enigma256Generation,
        ikm: Data,
        salt: Data,
        nonce: Data,
        message: Enigma256MessageKey,
        plaintext: [UInt8],
        ciphertext: [UInt8],
        wiring: Enigma256Wiring
    ) {
        self.profile = profile
        self.ikm = ikm
        self.salt = salt
        self.nonce = nonce
        self.message = message
        self.plaintext = plaintext
        self.ciphertext = ciphertext
        self.wiring = wiring
    }
}

package enum Enigma256Bridge {
    package static let goldenTraceLength = 1_024

    private static let initialByteCounter: UInt64 = 0
    private static let sessionVersion = 4
    private static let manifestSchema = "E256-KAT-MANIFEST-4"
    private static let traceSchema = "E256-KAT-TRACE-4"

    /// Deterministic non-secret input stream for the long-form fixture-v4 KAT.
    package static var deterministicGoldenPlaintext: [UInt8] {
        var state: UInt64 = 0xE256_0004_CE17_7ACE
        return (0 ..< goldenTraceLength).map { index in
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return UInt8(truncatingIfNeeded: state &+ UInt64(index &* 0x5D))
        }
    }

    /// Deterministic golden session used by CLI + RTL testbench.
    package static func makeGoldenSession(
        ikm: Data = Data("helut-enigma256-golden-ikm-v1!!!!".utf8),
        salt: Data = Data("helut-salt".utf8),
        nonce: Data = Data([0xE2, 0x56, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05,
                            0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D]),
        plaintext suppliedPlaintext: [UInt8]? = nil
    ) -> Enigma256Session {
        let profile = Enigma256Generation.current
        precondition((try? profile.validate()) != nil, "invalid active E256 profile")
        let ctx = Enigma256Context(ikm: ikm, salt: salt, profile: profile)
        let (message, wiring) = ctx.messageState(nonce: nonce)
        let plaintext = suppliedPlaintext ?? deterministicGoldenPlaintext
        let box = ctx.seal(plaintext, nonce: nonce)
        return Enigma256Session(
            profile: profile,
            ikm: ikm,
            salt: salt,
            nonce: nonce,
            message: message,
            plaintext: plaintext,
            ciphertext: box.ciphertext,
            wiring: wiring
        )
    }

    /// Bytes for `wr_sel` in core load order.
    package static func table(_ wiring: Enigma256Wiring, sel: Enigma256TableSel) -> [UInt8] {
        switch sel {
        case .plugboard: return wiring.plugboard
        case .r1Fwd: return wiring.r1Fwd
        case .r1Rev: return wiring.r1Rev
        case .r2Fwd: return wiring.r2Fwd
        case .r2Rev: return wiring.r2Rev
        case .r3Fwd: return wiring.r3Fwd
        case .r3Rev: return wiring.r3Rev
        case .r4Fwd: return wiring.r4Fwd
        case .r4Rev: return wiring.r4Rev
        }
    }

    /// Reconstruct wiring from nine 256-byte tables (load-order).
    package static func wiring(fromTables tables: [[UInt8]]) -> Enigma256Wiring {
        precondition(tables.count == 9)
        for table in tables { precondition(table.count == 256) }
        return Enigma256Wiring(
            plugboard: tables[0],
            r1Fwd: tables[1], r1Rev: tables[2],
            r2Fwd: tables[3], r2Rev: tables[4],
            r3Fwd: tables[5], r3Rev: tables[6],
            r4Fwd: tables[7], r4Rev: tables[8]
        )
    }

    /// `$readmemh`-compatible: 256 lines of two hex digits (addr = line index).
    package static func hexMEM(_ bytes: [UInt8]) -> String {
        precondition(bytes.count == 256)
        return bytes.map { String(format: "%02x", $0) }.joined(separator: "\n") + "\n"
    }

    package static func parseHexMEM(_ text: String) -> [UInt8] {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("//") && !$0.hasPrefix("@") }
        precondition(lines.count == 256, "hex mem must have 256 data lines, got \(lines.count)")
        return lines.map { line in
            guard let value = UInt8(line, radix: 16) else {
                preconditionFailure("bad hex byte '\(line)'")
            }
            return value
        }
    }

    /// Transactionally write and validate the complete fixture-v4 KAT suite, then
    /// promote the staged directory as one filesystem replacement.
    @discardableResult
    package static func writeGoldenBundle(session: Enigma256Session, to directory: URL) throws -> URL {
        try validateFixture4Profile(session.profile)

        let fm = FileManager.default
        let parent = directory.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(
            ".\(directory.lastPathComponent).staging-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fm.removeItem(at: staging) }

        try writeGoldenBundleContents(session: session, to: staging)
        _ = try loadAndVerify(bundle: staging, profile: session.profile)

        if fm.fileExists(atPath: directory.path) {
            _ = try fm.replaceItemAt(directory, withItemAt: staging)
        } else {
            try fm.moveItem(at: staging, to: directory)
        }
        return directory
    }

    private static func writeGoldenBundleContents(
        session: Enigma256Session,
        to directory: URL
    ) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let tablesDirectory = directory.appendingPathComponent("tables", isDirectory: true)
        let traceDirectory = directory.appendingPathComponent("trace", isDirectory: true)
        try fm.createDirectory(at: tablesDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: traceDirectory, withIntermediateDirectories: true)

        var artifactPaths: [String] = []
        for sel in Enigma256TableSel.allCases {
            let relative = "tables/\(sel.fileName)"
            try hexMEM(table(session.wiring, sel: sel)).write(
                to: directory.appendingPathComponent(relative),
                atomically: true,
                encoding: .utf8
            )
            artifactPaths.append(relative)
        }

        try Data(session.plaintext).write(to: directory.appendingPathComponent("plaintext.bin"))
        try Data(session.ciphertext).write(to: directory.appendingPathComponent("ciphertext.bin"))
        artifactPaths += ["plaintext.bin", "ciphertext.bin"]

        let jsonData = try JSONSerialization.data(
            withJSONObject: sessionJSON(session),
            options: [.prettyPrinted, .sortedKeys]
        )
        try jsonData.write(to: directory.appendingPathComponent("session.json"))
        artifactPaths.append("session.json")

        try writeByteHex(session.plaintext, to: directory.appendingPathComponent("plaintext.hex"))
        try writeByteHex(session.ciphertext, to: directory.appendingPathComponent("ciphertext.hex"))
        artifactPaths += ["plaintext.hex", "ciphertext.hex"]

        try testbenchParameters(session).write(
            to: directory.appendingPathComponent("tb_params.vh"),
            atomically: true,
            encoding: .utf8
        )
        artifactPaths.append("tb_params.vh")

        let traceFiles = try traceArtifacts(session)
        for name in traceFileNames {
            guard let data = traceFiles[name] else {
                throw BridgeError.traceInvariant("missing generated trace \(name)")
            }
            let relative = "trace/\(name)"
            try data.write(to: directory.appendingPathComponent(relative), options: .atomic)
            artifactPaths.append(relative)
        }

        var hashes: [String: String] = [:]
        for relative in artifactPaths.sorted() {
            let data = try Data(contentsOf: directory.appendingPathComponent(relative))
            hashes[relative] = sha256Hex(data)
        }
        let manifest: [String: Any] = [
            "schema": manifestSchema,
            "trace_schema": traceSchema,
            "compatibility_key": session.profile.compatibilityKey,
            "profile_sha256": session.profile.profileHashHex,
            "profile_canonical_hex": hexBytes([UInt8](session.profile.canonicalProfile)),
            "stream_bytes": session.plaintext.count,
            "artifacts": hashes
        ]
        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        try manifestData.write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
    }

    /// Independently rederive the message and nine tables, then verify ciphertext,
    /// trace, duplicate payloads, testbench parameters, and manifest.
    package static func loadAndVerify(
        bundle directory: URL,
        profile: Enigma256Generation = .v2Gen0
    ) throws -> Enigma256Session {
        try validateFixture4Profile(profile)

        let jsonData = try Data(contentsOf: directory.appendingPathComponent("session.json"))
        guard let object = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw BridgeError.badSessionJSON
        }

        let serializedVersion = (object["version"] as? NSNumber)?.intValue
        if serializedVersion == 3 {
            throw BridgeError.legacyFixtureIdentity
        }
        guard serializedVersion == sessionVersion,
              object["core"] as? String == "enigma_256_core",
              let compatibility = object["compatibility"] as? [String: Any],
              let ikmHex = object["ikm_hex"] as? String,
              let saltHex = object["salt_hex"] as? String,
              let nonceHex = object["nonce_hex"] as? String,
              let messageObject = object["message"] as? [String: Any]
        else {
            throw BridgeError.badSessionJSON
        }

        try verifyCompatibility(compatibility, profile: profile)

        // These are the only serialized inputs trusted to derive message state.
        let ikm = try parseHexBytes(ikmHex, field: "ikm_hex")
        let salt = try parseHexBytes(saltHex, field: "salt_hex")
        let nonce = try parseHexBytes(nonceHex, field: "nonce_hex")
        guard !ikm.isEmpty else { throw BridgeError.badSessionJSON }

        let context = Enigma256Context(ikm: Data(ikm), salt: Data(salt), profile: profile)
        let (derivedMessage, derivedWiring) = context.messageState(nonce: Data(nonce))

        let expectedMessageKeys: Set<String> = [
            "rotor_indices", "positions", "lfsr_seed_hex", "initial_byte_counter_hex"
        ]
        guard Set(messageObject.keys) == expectedMessageKeys,
              let indices = messageObject["rotor_indices"] as? [Int], indices.count == 4,
              indices.allSatisfy({ (0 ..< 16).contains($0) }),
              let positions = messageObject["positions"] as? [Int], positions.count == 4,
              positions.allSatisfy({ (0 ... 255).contains($0) }),
              let lfsrHex = messageObject["lfsr_seed_hex"] as? String,
              let counterHex = messageObject["initial_byte_counter_hex"] as? String
        else {
            throw BridgeError.badSessionJSON
        }
        let serializedLFSR = try parseUInt64Hex(lfsrHex, field: "message.lfsr_seed_hex")
        let serializedCounter = try parseUInt64Hex(
            counterHex,
            field: "message.initial_byte_counter_hex"
        )
        let expectedIndices = [
            derivedMessage.rotorIndices.0, derivedMessage.rotorIndices.1,
            derivedMessage.rotorIndices.2, derivedMessage.rotorIndices.3
        ]
        let expectedPositions = [
            Int(derivedMessage.positions.0), Int(derivedMessage.positions.1),
            Int(derivedMessage.positions.2), Int(derivedMessage.positions.3)
        ]
        guard indices == expectedIndices,
              positions == expectedPositions,
              serializedLFSR == derivedMessage.lfsrSeed,
              serializedCounter == initialByteCounter
        else {
            throw BridgeError.messageDerivationMismatch
        }

        guard let serializedOrder = object["wr_sel_order"] as? [String],
              serializedOrder == Enigma256TableSel.allCases.map(\.fileName)
        else {
            throw BridgeError.badSessionJSON
        }

        var serializedTables: [[UInt8]] = []
        serializedTables.reserveCapacity(Enigma256TableSel.allCases.count)
        for sel in Enigma256TableSel.allCases {
            let relative = "tables/\(sel.fileName)"
            let text = try String(
                contentsOf: directory.appendingPathComponent(relative),
                encoding: .utf8
            )
            let bytes = try parseHexMEMArtifact(text, field: relative)
            guard bytes == table(derivedWiring, sel: sel) else {
                throw BridgeError.artifactMismatch(relative)
            }
            serializedTables.append(bytes)
        }
        let serializedWiring = wiring(fromTables: serializedTables)
        guard serializedWiring == derivedWiring else {
            throw BridgeError.wiringDerivationMismatch
        }

        guard let plaintextHex = object["plaintext_hex"] as? String,
              let ciphertextHex = object["ciphertext_hex"] as? String,
              let length = (object["length"] as? NSNumber)?.intValue
        else {
            throw BridgeError.badSessionJSON
        }
        let plaintext = try parseHexBytes(plaintextHex, field: "plaintext_hex")
        let ciphertext = try parseHexBytes(ciphertextHex, field: "ciphertext_hex")
        guard length == goldenTraceLength,
              plaintext.count == length,
              ciphertext.count == length
        else {
            throw BridgeError.artifactMismatch("stream length")
        }

        guard try Data(contentsOf: directory.appendingPathComponent("plaintext.bin")) == Data(plaintext),
              try Data(contentsOf: directory.appendingPathComponent("ciphertext.bin")) == Data(ciphertext),
              try parseHexMEMStream(
                  String(
                      contentsOf: directory.appendingPathComponent("plaintext.hex"),
                      encoding: .utf8
                  ),
                  field: "plaintext.hex"
              ) == plaintext,
              try parseHexMEMStream(
                  String(
                      contentsOf: directory.appendingPathComponent("ciphertext.hex"),
                      encoding: .utf8
                  ),
                  field: "ciphertext.hex"
              ) == ciphertext
        else {
            throw BridgeError.artifactMismatch("plaintext/ciphertext duplicate")
        }

        var machine = Enigma256Machine(
            wiring: derivedWiring,
            lfsrSeed: derivedMessage.lfsrSeed,
            positions: derivedMessage.positions,
            centerMaskKey: derivedMessage.centerMaskKey,
            absoluteByteCounter: initialByteCounter,
            generation: profile
        )
        guard machine.process(plaintext) == ciphertext else {
            throw BridgeError.ciphertextMismatch
        }

        let loaded = Enigma256Session(
            profile: profile,
            ikm: Data(ikm),
            salt: Data(salt),
            nonce: Data(nonce),
            message: derivedMessage,
            plaintext: plaintext,
            ciphertext: ciphertext,
            wiring: derivedWiring
        )

        let actualParameters = try String(
            contentsOf: directory.appendingPathComponent("tb_params.vh"),
            encoding: .utf8
        )
        guard actualParameters == testbenchParameters(loaded) else {
            throw BridgeError.artifactMismatch("tb_params.vh")
        }

        let expectedTraces = try traceArtifacts(loaded)
        for name in traceFileNames {
            guard let expected = expectedTraces[name] else {
                throw BridgeError.traceInvariant("missing expected trace \(name)")
            }
            let actual = try Data(contentsOf: directory.appendingPathComponent("trace/\(name)"))
            guard actual == expected else { throw BridgeError.artifactMismatch("trace/\(name)") }
        }
        try verifyManifest(bundle: directory, profile: profile, streamBytes: plaintext.count)
        return loaded
    }

    package enum BridgeError: Error {
        case badSessionJSON
        case invalidHex(String)
        case legacyFixtureIdentity
        case profileMismatch
        case messageDerivationMismatch
        case wiringDerivationMismatch
        case ciphertextMismatch
        case artifactMismatch(String)
        case traceInvariant(String)
        case manifestMismatch
    }

    // MARK: - Private

    private static let traceFileNames = [
        "lfsr_before.hex", "lfsr_after.hex",
        "offsets_before.hex", "offsets_after.hex",
        "step_mask.hex", "byte_counter_before.hex", "byte_counter_after.hex",
        "center_mask.hex", "center_input.hex", "center_output.hex"
    ]

    private static func traceArtifacts(_ session: Enigma256Session) throws -> [String: Data] {
        guard session.plaintext.count == goldenTraceLength,
              session.ciphertext.count == goldenTraceLength
        else {
            throw BridgeError.traceInvariant("fixture-v4 trace must contain 1024 bytes")
        }

        var machine = Enigma256Machine(
            wiring: session.wiring,
            lfsrSeed: session.message.lfsrSeed,
            positions: session.message.positions,
            centerMaskKey: session.message.centerMaskKey,
            absoluteByteCounter: initialByteCounter,
            generation: session.profile
        )
        let traces = session.plaintext.map { machine.processTraced($0) }
        guard traces.map(\.output) == session.ciphertext else {
            throw BridgeError.ciphertextMismatch
        }

        for (index, trace) in traces.enumerated() {
            let before = UInt64(index)
            let after = before + 1
            guard trace.absoluteByteCounterBefore == before,
                  trace.absoluteByteCounterAfter == after,
                  trace.centerOutput == trace.centerInput ^ trace.centerMask
            else {
                throw BridgeError.traceInvariant("byte \(index)")
            }
        }
        guard traces.first?.absoluteByteCounterBefore == initialByteCounter,
              traces.last?.absoluteByteCounterAfter == UInt64(goldenTraceLength)
        else {
            throw BridgeError.traceInvariant("counter range")
        }

        func rows(_ render: (Enigma256ByteTrace) -> String) -> Data {
            Data((traces.map(render).joined(separator: "\n") + "\n").utf8)
        }
        func packedOffsets(
            _ r1: UInt8, _ r2: UInt8, _ r3: UInt8, _ r4: UInt8
        ) -> UInt32 {
            (UInt32(r1) << 24) | (UInt32(r2) << 16) | (UInt32(r3) << 8) | UInt32(r4)
        }

        return [
            "lfsr_before.hex": rows { String(format: "%016llx", $0.lfsrBefore) },
            "lfsr_after.hex": rows { String(format: "%016llx", $0.lfsrAfter) },
            "offsets_before.hex": rows {
                String(format: "%08x", packedOffsets(
                    $0.offsetR1Before, $0.offsetR2Before, $0.offsetR3Before, $0.offsetR4Before
                ))
            },
            "offsets_after.hex": rows {
                String(format: "%08x", packedOffsets(
                    $0.offsetR1After, $0.offsetR2After, $0.offsetR3After, $0.offsetR4After
                ))
            },
            "step_mask.hex": rows { String(format: "%01x", $0.stepMaskBits) },
            "byte_counter_before.hex": rows {
                String(format: "%016llx", $0.absoluteByteCounterBefore)
            },
            "byte_counter_after.hex": rows {
                String(format: "%016llx", $0.absoluteByteCounterAfter)
            },
            "center_mask.hex": rows { String(format: "%02x", $0.centerMask) },
            "center_input.hex": rows { String(format: "%02x", $0.centerInput) },
            "center_output.hex": rows { String(format: "%02x", $0.centerOutput) }
        ]
    }

    private static func expectedManifestPaths() -> Set<String> {
        var paths = Set(Enigma256TableSel.allCases.map { "tables/\($0.fileName)" })
        paths.formUnion([
            "plaintext.bin", "ciphertext.bin", "session.json",
            "plaintext.hex", "ciphertext.hex", "tb_params.vh"
        ])
        paths.formUnion(traceFileNames.map { "trace/\($0)" })
        return paths
    }

    private static func verifyManifest(
        bundle directory: URL,
        profile: Enigma256Generation,
        streamBytes: Int
    ) throws {
        let data = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BridgeError.manifestMismatch
        }
        if object["schema"] as? String == "E256-KAT-MANIFEST-3"
            || object["compatibility_key"] as? String
                == Enigma256Generation.historicalSchema3CompatibilityKey
            || object["profile_sha256"] as? String
                == Enigma256Generation.historicalSchema3ProfileSHA256
        {
            throw BridgeError.legacyFixtureIdentity
        }
        guard object["schema"] as? String == manifestSchema,
              object["trace_schema"] as? String == traceSchema,
              object["compatibility_key"] as? String == profile.compatibilityKey,
              object["profile_sha256"] as? String == profile.profileHashHex,
              object["profile_canonical_hex"] as? String
                == hexBytes([UInt8](profile.canonicalProfile)),
              (object["stream_bytes"] as? NSNumber)?.intValue == streamBytes,
              let artifacts = object["artifacts"] as? [String: String],
              Set(artifacts.keys) == expectedManifestPaths()
        else {
            throw BridgeError.manifestMismatch
        }
        for (relative, expectedHash) in artifacts {
            let artifact = try Data(contentsOf: directory.appendingPathComponent(relative))
            guard sha256Hex(artifact) == expectedHash else {
                throw BridgeError.artifactMismatch(relative)
            }
        }
    }

    private static func validateFixture4Profile(_ profile: Enigma256Generation) throws {
        guard (try? profile.validate()) != nil else { throw BridgeError.profileMismatch }
        guard profile.fixtureSchemaVersion == sessionVersion,
              profile.profileHashHex != Enigma256Generation.historicalSchema3ProfileSHA256,
              profile.compatibilityKey != Enigma256Generation.historicalSchema3CompatibilityKey
        else {
            throw BridgeError.legacyFixtureIdentity
        }
    }

    private static func verifyCompatibility(
        _ compatibility: [String: Any],
        profile: Enigma256Generation
    ) throws {
        if compatibility["profile_sha256"] as? String
            == Enigma256Generation.historicalSchema3ProfileSHA256
            || (compatibility["fixture_schema_version"] as? NSNumber)?.intValue == 3
        {
            throw BridgeError.legacyFixtureIdentity
        }
        let actual = try JSONSerialization.data(
            withJSONObject: compatibility,
            options: [.sortedKeys]
        )
        let expected = try JSONSerialization.data(
            withJSONObject: compatibilityJSON(profile),
            options: [.sortedKeys]
        )
        guard actual == expected else { throw BridgeError.profileMismatch }
    }

    private static func compatibilityJSON(_ profile: Enigma256Generation) -> [String: Any] {
        [
            "family": profile.family,
            "suite_version": profile.suiteVersion,
            "generation": profile.id,
            "fixture_schema_version": profile.fixtureSchemaVersion,
            "profile_sha256": profile.profileHashHex,
            "profile_canonical_hex": hexBytes([UInt8](profile.canonicalProfile)),
            "lfsr_transition": profile.lfsrTransition,
            "update_order": profile.updateOrder,
            "center_construction": profile.centerConstruction,
            "center_mask_key_kdf": profile.centerMaskKeyKDF,
            "center_mask_prf": profile.centerMaskPRF,
            "center_mask_key_domain": profile.centerMaskKeyDomain,
            "center_mask_block_domain": profile.centerMaskBlockDomain,
            "center_mask_counter": profile.centerMaskCounter,
            "center_mask_extraction": profile.centerMaskExtraction,
            "center_map_order": profile.centerMapOrder,
            "formula": profile.formula.rawValue,
            "receipt_sha256": profile.receiptSHA256
        ]
    }

    private static func testbenchParameters(_ session: Enigma256Session) -> String {
        let message = session.message
        return """
        // Auto-generated by Enigma256Bridge — include at module scope (not inside initial).
        // Compatibility: \(session.profile.compatibilityKey)
        // Receipt SHA-256: \(session.profile.receiptSHA256)
        localparam int ENIGMA256_N = \(session.plaintext.count);
        localparam [63:0] ENIGMA256_LFSR = 64'h\(hexUInt64(message.lfsrSeed));
        localparam [63:0] ENIGMA256_COUNTER = 64'h\(hexUInt64(initialByteCounter));
        localparam [7:0] ENIGMA256_R1 = 8'h\(String(format: "%02x", message.positions.0));
        localparam [7:0] ENIGMA256_R2 = 8'h\(String(format: "%02x", message.positions.1));
        localparam [7:0] ENIGMA256_R3 = 8'h\(String(format: "%02x", message.positions.2));
        localparam [7:0] ENIGMA256_R4 = 8'h\(String(format: "%02x", message.positions.3));
        """
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func parseHexMEMArtifact(_ text: String, field: String) throws -> [UInt8] {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("//") && !$0.hasPrefix("@") }
        guard lines.count == 256 else { throw BridgeError.invalidHex(field) }
        return try lines.map { line in
            guard line.count == 2, let value = UInt8(line, radix: 16) else {
                throw BridgeError.invalidHex(field)
            }
            return value
        }
    }

    private static func parseHexMEMStream(_ text: String, field: String) throws -> [UInt8] {
        try text.split(whereSeparator: \.isNewline).map { line in
            let cleaned = line.trimmingCharacters(in: .whitespaces)
            guard cleaned.count == 2, let value = UInt8(cleaned, radix: 16) else {
                throw BridgeError.invalidHex(field)
            }
            return value
        }
    }

    private static func writeByteHex(_ bytes: [UInt8], to url: URL) throws {
        let body = bytes.map { String(format: "%02x", $0) }.joined(separator: "\n") + "\n"
        try body.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func sessionJSON(_ session: Enigma256Session) -> [String: Any] {
        let message = session.message
        return [
            "version": sessionVersion,
            "core": "enigma_256_core",
            "compatibility": compatibilityJSON(session.profile),
            "ikm_hex": hexBytes([UInt8](session.ikm)),
            "salt_hex": hexBytes([UInt8](session.salt)),
            "nonce_hex": hexBytes([UInt8](session.nonce)),
            "message": [
                "rotor_indices": [
                    message.rotorIndices.0, message.rotorIndices.1,
                    message.rotorIndices.2, message.rotorIndices.3
                ],
                "positions": [
                    Int(message.positions.0), Int(message.positions.1),
                    Int(message.positions.2), Int(message.positions.3)
                ],
                "lfsr_seed_hex": "0x\(hexUInt64(message.lfsrSeed))",
                "initial_byte_counter_hex": "0x\(hexUInt64(initialByteCounter))"
            ],
            "plaintext_hex": hexBytes(session.plaintext),
            "ciphertext_hex": hexBytes(session.ciphertext),
            "length": session.plaintext.count,
            "wr_sel_order": Enigma256TableSel.allCases.map(\.fileName)
        ]
    }

    private static func hexBytes(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func hexUInt64(_ value: UInt64) -> String {
        String(format: "%016llx", value)
    }

    private static func parseUInt64Hex(_ value: String, field: String) throws -> UInt64 {
        guard value.hasPrefix("0x") else { throw BridgeError.invalidHex(field) }
        let digits = String(value.dropFirst(2))
        guard digits.count == 16,
              digits.allSatisfy(\.isHexDigit),
              let parsed = UInt64(digits, radix: 16)
        else {
            throw BridgeError.invalidHex(field)
        }
        return parsed
    }

    private static func parseHexBytes(_ hex: String, field: String) throws -> [UInt8] {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count % 2 == 0, cleaned.allSatisfy(\.isHexDigit) else {
            throw BridgeError.invalidHex(field)
        }
        var output: [UInt8] = []
        output.reserveCapacity(cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let end = cleaned.index(index, offsetBy: 2)
            guard let value = UInt8(cleaned[index ..< end], radix: 16) else {
                throw BridgeError.invalidHex(field)
            }
            output.append(value)
            index = end
        }
        return output
    }
}
