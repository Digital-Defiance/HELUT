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
    package var ikm: Data
    package var salt: Data
    package var nonce: Data
    package var message: Enigma256MessageKey
    package var plaintext: [UInt8]
    package var ciphertext: [UInt8]
    package var wiring: Enigma256Wiring

    package init(
        ikm: Data,
        salt: Data,
        nonce: Data,
        message: Enigma256MessageKey,
        plaintext: [UInt8],
        ciphertext: [UInt8],
        wiring: Enigma256Wiring
    ) {
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
    /// Deterministic golden session used by CLI + RTL testbench.
    package static func makeGoldenSession(
        ikm: Data = Data("helut-enigma256-golden-ikm-v1!!!!".utf8),
        salt: Data = Data("helut-salt".utf8),
        nonce: Data = Data([0xE2, 0x56, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05,
                            0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D]),
        plaintext: [UInt8] = Array("HELUT Enigma256 golden vector stream".utf8)
    ) -> Enigma256Session {
        let ctx = Enigma256Context(ikm: ikm, salt: salt)
        let box = ctx.seal(plaintext, nonce: nonce)
        let (message, wiring) = ctx.messageState(nonce: nonce)
        return Enigma256Session(
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

    /// Write `tables/*.hex` + `session.json` + `plaintext.bin` / `ciphertext.bin` under `directory`.
    @discardableResult
    package static func writeGoldenBundle(session: Enigma256Session, to directory: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let tablesDir = directory.appendingPathComponent("tables", isDirectory: true)
        try fm.createDirectory(at: tablesDir, withIntermediateDirectories: true)

        for sel in Enigma256TableSel.allCases {
            let path = tablesDir.appendingPathComponent(sel.fileName)
            try hexMEM(table(session.wiring, sel: sel)).write(to: path, atomically: true, encoding: .utf8)
        }

        try Data(session.plaintext).write(to: directory.appendingPathComponent("plaintext.bin"))
        try Data(session.ciphertext).write(to: directory.appendingPathComponent("ciphertext.bin"))

        let json = sessionJSON(session)
        let jsonData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try jsonData.write(to: directory.appendingPathComponent("session.json"))

        // Flat vectors for Verilog `$readmemh` of streaming I/O (one byte per line).
        try writeByteHex(session.plaintext, to: directory.appendingPathComponent("plaintext.hex"))
        try writeByteHex(session.ciphertext, to: directory.appendingPathComponent("ciphertext.hex"))

        let m = session.message
        let lfsrHex = String(m.lfsrSeed, radix: 16)
        let lfsrPad = String(repeating: "0", count: max(0, 16 - lfsrHex.count)) + lfsrHex
        let vh = """
        // Auto-generated by Enigma256Bridge — include at module scope (not inside initial).
        localparam int ENIGMA256_N = \(session.plaintext.count);
        localparam [63:0] ENIGMA256_LFSR = 64'h\(lfsrPad);
        localparam [7:0] ENIGMA256_R1 = 8'h\(String(format: "%02x", m.positions.0));
        localparam [7:0] ENIGMA256_R2 = 8'h\(String(format: "%02x", m.positions.1));
        localparam [7:0] ENIGMA256_R3 = 8'h\(String(format: "%02x", m.positions.2));
        localparam [7:0] ENIGMA256_R4 = 8'h\(String(format: "%02x", m.positions.3));
        """
        try vh.write(to: directory.appendingPathComponent("tb_params.vh"), atomically: true, encoding: .utf8)

        return directory
    }

    /// Reload tables + session and verify ciphertext matches a fresh encrypt.
    package static func loadAndVerify(bundle directory: URL) throws -> Enigma256Session {
        var tables: [[UInt8]] = []
        for sel in Enigma256TableSel.allCases {
            let text = try String(contentsOf: directory.appendingPathComponent("tables/\(sel.fileName)"), encoding: .utf8)
            tables.append(parseHexMEM(text))
        }
        let wiring = wiring(fromTables: tables)

        let jsonData = try Data(contentsOf: directory.appendingPathComponent("session.json"))
        guard let obj = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
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

        let plaintext = parseHexBytes(ptHex)
        let ciphertext = parseHexBytes(ctHex)
        let message = Enigma256MessageKey(
            rotorIndices: (indices[0], indices[1], indices[2], indices[3]),
            positions: (UInt8(positions[0]), UInt8(positions[1]), UInt8(positions[2]), UInt8(positions[3])),
            lfsrSeed: lfsrSeed == 0 ? 1 : lfsrSeed
        )

        var enc = Enigma256Machine(wiring: wiring, lfsrSeed: message.lfsrSeed, positions: message.positions)
        let recomputed = enc.process(plaintext)
        guard recomputed == ciphertext else {
            throw BridgeError.ciphertextMismatch
        }

        let ikm = parseHexBytes((obj["ikm_hex"] as? String) ?? "")
        let salt = parseHexBytes((obj["salt_hex"] as? String) ?? "")
        let nonce = parseHexBytes((obj["nonce_hex"] as? String) ?? "")
        return Enigma256Session(
            ikm: Data(ikm),
            salt: Data(salt),
            nonce: Data(nonce),
            message: message,
            plaintext: plaintext,
            ciphertext: ciphertext,
            wiring: wiring
        )
    }

    package enum BridgeError: Error {
        case badSessionJSON
        case ciphertextMismatch
    }

    // MARK: - Private

    private static func writeByteHex(_ bytes: [UInt8], to url: URL) throws {
        let body = bytes.map { String(format: "%02x", $0) }.joined(separator: "\n") + "\n"
        try body.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func sessionJSON(_ session: Enigma256Session) -> [String: Any] {
        let m = session.message
        return [
            "version": 1,
            "core": "enigma_256_core",
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
