import CryptoKit
import Foundation

// MARK: - Enigma 256 ↔ FPGA bridge (hex BRAMs + golden session JSON)
//
// Load order into `enigma_256_core` matches Verilog `wr_sel`:
//   0 plugboard, 1 r1_fwd, 2 r1_rev, 3 r2_fwd, 4 r2_rev,
//   5 r3_fwd, 6 r3_rev, 7 r4_fwd, 8 r4_rev, 9 reflector

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
    case reflector = 9

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
        case .reflector: return "reflector.hex"
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

    /// Deterministic non-secret input stream for the long-form schema-3 KAT.
    package static var deterministicGoldenPlaintext: [UInt8] {
        var state: UInt64 = 0xE256_0003_CE17_7ACE
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
        let plaintext = suppliedPlaintext ?? branchCoveringGoldenPlaintext(
            wiring: wiring,
            message: message,
            profile: profile
        )
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

    private static func branchCoveringGoldenPlaintext(
        wiring: Enigma256Wiring,
        message: Enigma256MessageKey,
        profile: Enigma256Generation
    ) -> [UInt8] {
        var machine = Enigma256Machine(
            wiring: wiring,
            lfsrSeed: message.lfsrSeed,
            positions: message.positions,
            generation: profile
        )
        var pending = Set(["0:0", "0:1", "1:0", "1:1"])
        var plaintext: [UInt8] = []
        plaintext.reserveCapacity(goldenTraceLength)

        for fallback in deterministicGoldenPlaintext {
            let mode = machine.centerMode ? 1 : 0
            let target = [0, 1].first { pending.contains("\(mode):\($0)") }
            var selected = fallback
            if let target {
                for candidate in 0 ... 255 {
                    var probe = machine
                    if probe.processTraced(UInt8(candidate)).centerInput == UInt8(target) {
                        selected = UInt8(candidate)
                        break
                    }
                }
            }
            let trace = machine.processTraced(selected)
            if trace.centerInput < 2 {
                pending.remove("\(trace.centerMode ? 1 : 0):\(trace.centerInput)")
            }
            plaintext.append(selected)
        }
        precondition(pending.isEmpty, "schema-3 golden failed to cover all reserved center branches")
        return plaintext
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
        case .reflector: return wiring.reflector
        }
    }

    /// Reconstruct wiring from ten 256-byte tables (load-order).
    package static func wiring(fromTables tables: [[UInt8]]) -> Enigma256Wiring {
        precondition(tables.count == 10)
        for t in tables { precondition(t.count == 256) }
        return Enigma256Wiring(
            plugboard: tables[0],
            r1Fwd: tables[1], r1Rev: tables[2],
            r2Fwd: tables[3], r2Rev: tables[4],
            r3Fwd: tables[5], r3Rev: tables[6],
            r4Fwd: tables[7], r4Rev: tables[8],
            reflector: tables[9]
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
            guard let v = UInt8(line, radix: 16) else {
                preconditionFailure("bad hex byte '\(line)'")
            }
            return v
        }
    }

    /// Transactionally write and validate the complete schema-3 KAT suite, then
    /// promote the staged directory as one filesystem replacement.
    @discardableResult
    package static func writeGoldenBundle(session: Enigma256Session, to directory: URL) throws -> URL {
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
        let tablesDir = directory.appendingPathComponent("tables", isDirectory: true)
        let traceDir = directory.appendingPathComponent("trace", isDirectory: true)
        try fm.createDirectory(at: tablesDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: traceDir, withIntermediateDirectories: true)

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

        let json = sessionJSON(session)
        let jsonData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try jsonData.write(to: directory.appendingPathComponent("session.json"))
        artifactPaths.append("session.json")

        try writeByteHex(session.plaintext, to: directory.appendingPathComponent("plaintext.hex"))
        try writeByteHex(session.ciphertext, to: directory.appendingPathComponent("ciphertext.hex"))
        artifactPaths += ["plaintext.hex", "ciphertext.hex"]

        let m = session.message
        let lfsrHex = String(m.lfsrSeed, radix: 16)
        let lfsrPad = String(repeating: "0", count: max(0, 16 - lfsrHex.count)) + lfsrHex
        let vh = """
        // Auto-generated by Enigma256Bridge — include at module scope (not inside initial).
        // Compatibility: \(session.profile.compatibilityKey)
        // Receipt SHA-256: \(session.profile.receiptSHA256)
        localparam int ENIGMA256_N = \(session.plaintext.count);
        localparam [63:0] ENIGMA256_LFSR = 64'h\(lfsrPad);
        localparam [7:0] ENIGMA256_R1 = 8'h\(String(format: "%02x", m.positions.0));
        localparam [7:0] ENIGMA256_R2 = 8'h\(String(format: "%02x", m.positions.1));
        localparam [7:0] ENIGMA256_R3 = 8'h\(String(format: "%02x", m.positions.2));
        localparam [7:0] ENIGMA256_R4 = 8'h\(String(format: "%02x", m.positions.3));
        """
        try vh.write(to: directory.appendingPathComponent("tb_params.vh"), atomically: true, encoding: .utf8)
        artifactPaths.append("tb_params.vh")

        let traceFiles = try traceArtifacts(session)
        for (name, data) in traceFiles {
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
            "schema": "E256-KAT-MANIFEST-3",
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

    /// Reload tables + session and verify ciphertext, trace, and manifest.
    package static func loadAndVerify(
        bundle directory: URL,
        profile: Enigma256Generation = .v2Gen0
    ) throws -> Enigma256Session {
        var tables: [[UInt8]] = []
        for sel in Enigma256TableSel.allCases {
            let text = try String(contentsOf: directory.appendingPathComponent("tables/\(sel.fileName)"), encoding: .utf8)
            tables.append(parseHexMEM(text))
        }
        let wiring = wiring(fromTables: tables)

        let jsonData = try Data(contentsOf: directory.appendingPathComponent("session.json"))
        guard let obj = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              (obj["version"] as? NSNumber)?.intValue == 3,
              let compatibility = obj["compatibility"] as? [String: Any],
              let family = compatibility["family"] as? String,
              let suiteVersion = (compatibility["suite_version"] as? NSNumber)?.intValue,
              let generation = (compatibility["generation"] as? NSNumber)?.intValue,
              let fixtureSchemaVersion = (compatibility["fixture_schema_version"] as? NSNumber)?.intValue,
              let profileSHA256 = compatibility["profile_sha256"] as? String,
              let profileCanonicalHex = compatibility["profile_canonical_hex"] as? String,
              let lfsrTransition = compatibility["lfsr_transition"] as? String,
              let updateOrder = compatibility["update_order"] as? String,
              let reflectorDerivation = compatibility["reflector_derivation"] as? String,
              let centerReservedPairRule = compatibility["center_reserved_pair_rule"] as? String,
              let centerMode = compatibility["center_mode"] as? String,
              let centerMapOrder = compatibility["center_map_order"] as? String,
              let formula = compatibility["formula"] as? String,
              let receiptSHA256 = compatibility["receipt_sha256"] as? String,
              let msg = obj["message"] as? [String: Any],
              let indices = msg["rotor_indices"] as? [Int], indices.count == 4,
              let positions = msg["positions"] as? [Int], positions.count == 4,
              let lfsrHex = msg["lfsr_seed_hex"] as? String,
              let lfsrSeed = UInt64(lfsrHex.hasPrefix("0x") ? String(lfsrHex.dropFirst(2)) : lfsrHex, radix: 16),
              let ptHex = obj["plaintext_hex"] as? String,
              let ctHex = obj["ciphertext_hex"] as? String
        else {
            throw BridgeError.badSessionJSON
        }

        guard (try? profile.validate()) != nil,
              family == profile.family,
              suiteVersion == profile.suiteVersion,
              generation == profile.id,
              fixtureSchemaVersion == profile.fixtureSchemaVersion,
              profileSHA256 == profile.profileHashHex,
              profileCanonicalHex == hexBytes([UInt8](profile.canonicalProfile)),
              lfsrTransition == profile.lfsrTransition,
              updateOrder == profile.updateOrder,
              reflectorDerivation == profile.reflectorDerivation,
              centerReservedPairRule == profile.centerReservedPairRule,
              centerMode == profile.centerMode,
              centerMapOrder == profile.centerMapOrder,
              formula == profile.formula.rawValue,
              receiptSHA256 == profile.receiptSHA256 else {
            throw BridgeError.profileMismatch
        }

        let plaintext = parseHexBytes(ptHex)
        let ciphertext = parseHexBytes(ctHex)
        let message = Enigma256MessageKey(
            rotorIndices: (indices[0], indices[1], indices[2], indices[3]),
            positions: (UInt8(positions[0]), UInt8(positions[1]), UInt8(positions[2]), UInt8(positions[3])),
            lfsrSeed: lfsrSeed == 0 ? 1 : lfsrSeed
        )

        var enc = Enigma256Machine(
            wiring: wiring,
            lfsrSeed: message.lfsrSeed,
            positions: message.positions,
            generation: profile
        )
        let recomputed = enc.process(plaintext)
        guard recomputed == ciphertext else {
            throw BridgeError.ciphertextMismatch
        }

        let ikm = parseHexBytes((obj["ikm_hex"] as? String) ?? "")
        let salt = parseHexBytes((obj["salt_hex"] as? String) ?? "")
        let nonce = parseHexBytes((obj["nonce_hex"] as? String) ?? "")
        let loaded = Enigma256Session(
            profile: profile,
            ikm: Data(ikm),
            salt: Data(salt),
            nonce: Data(nonce),
            message: message,
            plaintext: plaintext,
            ciphertext: ciphertext,
            wiring: wiring
        )

        guard try Data(contentsOf: directory.appendingPathComponent("plaintext.bin")) == Data(plaintext),
              try Data(contentsOf: directory.appendingPathComponent("ciphertext.bin")) == Data(ciphertext),
              parseHexMEMStream(try String(
                contentsOf: directory.appendingPathComponent("plaintext.hex"),
                encoding: .utf8
              )) == plaintext,
              parseHexMEMStream(try String(
                contentsOf: directory.appendingPathComponent("ciphertext.hex"),
                encoding: .utf8
              )) == ciphertext else {
            throw BridgeError.artifactMismatch("plaintext/ciphertext duplicate")
        }

        for (name, expected) in try traceArtifacts(loaded) {
            let actual = try Data(contentsOf: directory.appendingPathComponent("trace/\(name)"))
            guard actual == expected else { throw BridgeError.artifactMismatch("trace/\(name)") }
        }
        try verifyManifest(bundle: directory, profile: profile)
        return loaded
    }

    package enum BridgeError: Error {
        case badSessionJSON
        case profileMismatch
        case ciphertextMismatch
        case artifactMismatch(String)
        case traceCoverage
        case manifestMismatch
    }

    // MARK: - Private

    private static let traceFileNames = [
        "lfsr_before.hex", "lfsr_after.hex",
        "offsets_before.hex", "offsets_after.hex",
        "step_mask.hex", "center_mode.hex",
        "center_input.hex", "center_output.hex"
    ]

    private static func traceArtifacts(_ session: Enigma256Session) throws -> [String: Data] {
        var machine = Enigma256Machine(
            wiring: session.wiring,
            lfsrSeed: session.message.lfsrSeed,
            positions: session.message.positions,
            generation: session.profile
        )
        let traces = session.plaintext.map { machine.processTraced($0) }
        guard traces.map(\.output) == session.ciphertext else {
            throw BridgeError.ciphertextMismatch
        }
        let coveredReservedBranches = Set(
            traces.filter { $0.centerInput < 2 }.map {
                "\($0.centerMode ? 1 : 0):\($0.centerInput)"
            }
        )
        guard coveredReservedBranches == Set(["0:0", "0:1", "1:0", "1:1"]) else {
            throw BridgeError.traceCoverage
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
            "center_mode.hex": rows { $0.centerMode ? "1" : "0" },
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
        profile: Enigma256Generation
    ) throws {
        let data = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["schema"] as? String == "E256-KAT-MANIFEST-3",
              object["compatibility_key"] as? String == profile.compatibilityKey,
              object["profile_sha256"] as? String == profile.profileHashHex,
              object["profile_canonical_hex"] as? String == hexBytes([UInt8](profile.canonicalProfile)),
              let artifacts = object["artifacts"] as? [String: String],
              Set(artifacts.keys) == expectedManifestPaths() else {
            throw BridgeError.manifestMismatch
        }
        for (relative, expectedHash) in artifacts {
            let artifact = try Data(contentsOf: directory.appendingPathComponent(relative))
            guard sha256Hex(artifact) == expectedHash else {
                throw BridgeError.artifactMismatch(relative)
            }
        }
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func parseHexMEMStream(_ text: String) -> [UInt8] {
        text.split(whereSeparator: \.isNewline).compactMap {
            UInt8($0.trimmingCharacters(in: .whitespaces), radix: 16)
        }
    }

    private static func writeByteHex(_ bytes: [UInt8], to url: URL) throws {
        let body = bytes.map { String(format: "%02x", $0) }.joined(separator: "\n") + "\n"
        try body.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func sessionJSON(_ session: Enigma256Session) -> [String: Any] {
        let m = session.message
        return [
            "version": 3,
            "core": "enigma_256_core",
            "compatibility": [
                "family": session.profile.family,
                "suite_version": session.profile.suiteVersion,
                "generation": session.profile.id,
                "fixture_schema_version": session.profile.fixtureSchemaVersion,
                "profile_sha256": session.profile.profileHashHex,
                "profile_canonical_hex": hexBytes([UInt8](session.profile.canonicalProfile)),
                "lfsr_transition": session.profile.lfsrTransition,
                "update_order": session.profile.updateOrder,
                "reflector_derivation": session.profile.reflectorDerivation,
                "center_reserved_pair_rule": session.profile.centerReservedPairRule,
                "center_mode": session.profile.centerMode,
                "center_map_order": session.profile.centerMapOrder,
                "formula": session.profile.formula.rawValue,
                "receipt_sha256": session.profile.receiptSHA256
            ],
            "ikm_hex": hexBytes([UInt8](session.ikm)),
            "salt_hex": hexBytes([UInt8](session.salt)),
            "nonce_hex": hexBytes([UInt8](session.nonce)),
            "message": [
                "rotor_indices": [m.rotorIndices.0, m.rotorIndices.1, m.rotorIndices.2, m.rotorIndices.3],
                "positions": [Int(m.positions.0), Int(m.positions.1), Int(m.positions.2), Int(m.positions.3)],
                "lfsr_seed_hex": String(format: "0x%016llx", m.lfsrSeed)
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

    private static func parseHexBytes(_ hex: String) -> [UInt8] {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count % 2 == 0 else { return [] }
        var out: [UInt8] = []
        out.reserveCapacity(cleaned.count / 2)
        var i = cleaned.startIndex
        while i < cleaned.endIndex {
            let j = cleaned.index(i, offsetBy: 2)
            out.append(UInt8(cleaned[i..<j], radix: 16) ?? 0)
            i = j
        }
        return out
    }
}
