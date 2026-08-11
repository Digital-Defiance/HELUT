import Foundation
import HELUTCore

// MARK: - Enigma 256 golden dump (`--enigma256-golden`)

func runEnigma256Golden() {
    let outDir = stringFlag("--enigma256-out") ?? "Fixtures/enigma256_golden"
    let plainArg = stringFlag("--enigma256-plain")
    let plaintext: [UInt8]
    if let plainArg {
        plaintext = Array(plainArg.utf8)
    } else {
        plaintext = Array("HELUT Enigma256 golden vector stream".utf8)
    }

    let session = Enigma256Bridge.makeGoldenSession(plaintext: plaintext)
    let url = URL(fileURLWithPath: outDir, isDirectory: true)
    do {
        _ = try Enigma256Bridge.writeGoldenBundle(session: session, to: url)
        _ = try Enigma256Bridge.loadAndVerify(bundle: url)
    } catch {
        fatalError("Enigma256 golden dump failed: \(error)")
    }

    let m = session.message
    print("Enigma 256 golden bundle → \(outDir)")
    print("  bytes: \(session.plaintext.count)")
    print("  rotors: \(m.rotorIndices.0),\(m.rotorIndices.1),\(m.rotorIndices.2),\(m.rotorIndices.3)")
    print("  positions: \(String(format: "%02x %02x %02x %02x", m.positions.0, m.positions.1, m.positions.2, m.positions.3))")
    print("  lfsr: \(String(format: "0x%016llx", m.lfsrSeed))")
    print("  ct[0..7]: \(session.ciphertext.prefix(8).map { String(format: "%02x", $0) }.joined())")
    print("  files: tables/*.hex session.json plaintext.hex ciphertext.hex tb_params.vh")
}

// MARK: - Enigma 256 file crypt (`--enigma256-crypt`)

func runEnigma256Crypt() {
    let mode = (stringFlag("--enigma256-mode") ?? "encrypt").lowercased()
    let inPath = stringFlag("--enigma256-in")
    let outPath = stringFlag("--enigma256-out")
    guard let inPath, let outPath else {
        fputs("""
        Usage:
          helut --enigma256-crypt --enigma256-mode encrypt|decrypt \\
            --enigma256-ikm <path|hex|string> --enigma256-in <file> --enigma256-out <file> \\
            [--enigma256-salt <path|hex|string>] [--enigma256-nonce <hex>]

        Encrypt writes an E256 container (magic|ver|nonce|ciphertext).
        Decrypt reads that container. Reciprocal cipher — same IKM/salt for both.

        """, stderr)
        exit(2)
    }

    let ikm = enigma256Material(stringFlag("--enigma256-ikm"), label: "ikm")!
    let salt = enigma256Material(stringFlag("--enigma256-salt"), label: "salt", allowNil: true) ?? Data()
    let ctx = Enigma256Context(ikm: ikm, salt: salt)

    do {
        let input = try Data(contentsOf: URL(fileURLWithPath: inPath))
        let output: Data
        switch mode {
        case "encrypt", "seal", "enc":
            let nonce: Data
            if let nonceHex = stringFlag("--enigma256-nonce") {
                nonce = Data(enigma256ParseHex(nonceHex, label: "nonce"))
            } else {
                var bytes = [UInt8](repeating: 0, count: 16)
                var rng = SystemRandomNumberGenerator()
                for i in 0 ..< 16 { bytes[i] = UInt8.random(in: .min ... .max, using: &rng) }
                nonce = Data(bytes)
            }
            let box = ctx.seal([UInt8](input), nonce: nonce)
            output = box.encode()
            print("Enigma256 seal: \(input.count) B → \(output.count) B container (nonce \(nonce.count) B)")
        case "decrypt", "open", "dec":
            let box = try Enigma256SealedBox.decode(input)
            let plain = ctx.open(box)
            output = Data(plain)
            print("Enigma256 open: \(input.count) B container → \(plain.count) B")
        default:
            fputs("Unknown --enigma256-mode \(mode) (use encrypt|decrypt)\n", stderr)
            exit(2)
        }
        try output.write(to: URL(fileURLWithPath: outPath))
        print("Wrote \(outPath)")
    } catch {
        fputs("Enigma256 crypt failed: \(error)\n", stderr)
        exit(1)
    }
}

/// Resolve IKM/salt from a file path, hex string, or literal UTF-8.
func enigma256Material(_ raw: String?, label: String, allowNil: Bool = false) -> Data? {
    guard let raw else {
        if allowNil { return nil }
        fputs("Missing --enigma256-\(label)\n", stderr)
        exit(2)
    }
    if FileManager.default.fileExists(atPath: raw) {
        do { return try Data(contentsOf: URL(fileURLWithPath: raw)) }
        catch {
            fputs("Failed reading \(label) file: \(error)\n", stderr)
            exit(1)
        }
    }
    let hexish = raw.allSatisfy { $0.isHexDigit } && raw.count >= 16 && raw.count.isMultiple(of: 2)
    if hexish {
        return Data(enigma256ParseHex(raw, label: label))
    }
    return Data(raw.utf8)
}

func enigma256ParseHex(_ hex: String, label: String) -> [UInt8] {
    let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
    guard cleaned.count.isMultiple(of: 2), !cleaned.isEmpty else {
        fputs("Bad \(label) hex\n", stderr)
        exit(2)
    }
    var out: [UInt8] = []
    var i = cleaned.startIndex
    while i < cleaned.endIndex {
        let j = cleaned.index(i, offsetBy: 2)
        guard let b = UInt8(cleaned[i..<j], radix: 16) else {
            fputs("Bad \(label) hex\n", stderr)
            exit(2)
        }
        out.append(b)
        i = j
    }
    return out
}
