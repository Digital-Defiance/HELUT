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
            (--enigma256-ikm <path|hex|string> | --enigma256-passphrase <text>) \\
            --enigma256-in <file> --enigma256-out <file> \\
            [--enigma256-salt <path|hex|string>] [--enigma256-nonce <hex>] \\
            [--enigma256-pbkdf2-iters N]

        Encrypt writes an E256 container (magic|ver|nonce|ciphertext).
        Decrypt reads that container. Reciprocal cipher — same IKM/salt for both.

        """, stderr)
        exit(2)
    }

    let salt = enigma256Material(stringFlag("--enigma256-salt"), label: "salt", allowNil: true) ?? Data()
    let ctx: Enigma256Context
    do {
        ctx = try enigma256ResolveContext(salt: salt)
    } catch {
        fputs("Enigma256 key material failed: \(error)\n", stderr)
        exit(2)
    }

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

/// Prefer `--enigma256-passphrase` (PBKDF2) over raw `--enigma256-ikm`.
func enigma256ResolveContext(salt: Data) throws -> Enigma256Context {
    if let pass = stringFlag("--enigma256-passphrase") {
        let iters = intFlag("--enigma256-pbkdf2-iters") ?? Enigma256Passphrase.defaultIterations
        let effectiveSalt = salt.isEmpty ? Data("helut-pbkdf2".utf8) : salt
        return try Enigma256Passphrase.openContext(
            passphrase: pass,
            salt: effectiveSalt,
            iterations: iters
        )
    }
    guard let ikm = enigma256Material(stringFlag("--enigma256-ikm"), label: "ikm") else {
        fputs("Provide --enigma256-ikm or --enigma256-passphrase\n", stderr)
        exit(2)
    }
    return Enigma256Context(ikm: ikm, salt: salt)
}

func enigma256UsesPSK() -> Bool {
    stringFlag("--enigma256-passphrase") != nil
}

// MARK: - Enigma 256 ECDH demo (`--enigma256-ecdh-demo`)

func runEnigma256ECDHDemo() {
    let salt = enigma256Material(stringFlag("--enigma256-salt"), label: "salt", allowNil: true) ?? Data("helut".utf8)
    let plain: [UInt8]
    if let path = stringFlag("--enigma256-plain-file") ?? stringFlag("--enigma256-in") {
        do { plain = [UInt8](try Data(contentsOf: URL(fileURLWithPath: path))) }
        catch {
            fputs("Failed reading plaintext: \(error)\n", stderr)
            exit(1)
        }
    } else if let text = stringFlag("--enigma256-plain") {
        plain = Array(text.utf8)
    } else {
        plain = Array("Enigma256 X25519 handshake demo".utf8)
    }

    do {
        let (alice, bob) = try Enigma256Handshake.paired(salt: salt)
        print("Enigma256 ECDH (X25519) — software control plane only (no Verilog)")
        print("  alice pub: \(alice.local.publicKeyRaw.map { String(format: "%02x", $0) }.joined().prefix(32))…")
        print("  bob   pub: \(bob.local.publicKeyRaw.map { String(format: "%02x", $0) }.joined().prefix(32))…")
        print("  ikm match: \(alice.context?.ikm == bob.context?.ikm)")

        let box = try alice.seal(plain)
        let recovered = try bob.open(box)
        precondition(recovered == plain, "ECDH seal/open mismatch")
        print("  seal/open: \(plain.count) B OK (nonce \(box.nonce.count) B)")

        // Day-key tables could now be pushed over AXI from bob.context.
        if let ctx = bob.context {
            let bus = Enigma256SoftBus()
            let drv = Enigma256AXIDriver(bus: bus)
            drv.configure(context: ctx, nonce: box.nonce)
            let axiPT = drv.transfer(box.ciphertext)
            precondition(axiPT == plain, "ECDH→AXI soft decrypt failed")
            print("  ecdh→axi softbus decrypt: OK")
        }

        alice.burn()
        bob.burn()
        print("  burned ephemeral keys + contexts")
    } catch {
        fputs("Enigma256 ECDH demo failed: \(error)\n", stderr)
        exit(1)
    }
}

// MARK: - Enigma 256 wire-session demo (`--enigma256-wire-demo`)

func runEnigma256WireDemo() {
    let salt = enigma256Material(stringFlag("--enigma256-salt"), label: "salt", allowNil: true)
        ?? Data("helut-wire".utf8)
    let messages: [[UInt8]]
    if let path = stringFlag("--enigma256-plain-file") ?? stringFlag("--enigma256-in") {
        do { messages = [[UInt8](try Data(contentsOf: URL(fileURLWithPath: path)))] }
        catch {
            fputs("Failed reading plaintext: \(error)\n", stderr)
            exit(1)
        }
    } else if let text = stringFlag("--enigma256-plain") {
        messages = [Array(text.utf8)]
    } else {
        messages = [
            Array("HELLO from HELUT wire framing".utf8),
            Array("second datagram on Apple Silicon".utf8)
        ]
    }

    do {
        print("Enigma256 wire session (in-process duplex, SoftBus decrypt)")
        print("  frames: HELLO → ACK → DATA×\(messages.count) → BYE")
        let got = try Enigma256WireSession.runInProcess(
            messages: messages,
            salt: salt,
            decryptViaSoftBus: true
        )
        precondition(got == messages)
        for (i, m) in got.enumerated() {
            let preview = String(bytes: m.prefix(48), encoding: .utf8) ?? "(\(m.count) B)"
            print("  rx[\(i)]: \(preview)")
        }
        print("  OK")
    } catch {
        fputs("Enigma256 wire demo failed: \(error)\n", stderr)
        exit(1)
    }
}

// MARK: - Enigma 256 TCP listen / connect (Network.framework)

func enigma256Port() -> UInt16 {
    if let n = intFlag("--enigma256-port"), n > 0, n <= 65535 {
        return UInt16(n)
    }
    return 25600
}

func runEnigma256TCPListen() {
    let port = enigma256Port()
    let psk = enigma256UsesPSK()
    print("Enigma256 TCP listen on 0.0.0.0:\(port) (responder, SoftBus decrypt, \(psk ? "PSK" : "ECDH"))")
    do {
        let transport = try Enigma256TCPTransport.accept(port: port, timeout: 120)
        defer { transport.close() }
        let peer = Enigma256WirePeer(transport: transport, decryptViaSoftBus: true)
        if psk {
            let pass = stringFlag("--enigma256-passphrase")!
            let iters = intFlag("--enigma256-pbkdf2-iters") ?? Enigma256Passphrase.defaultIterations
            try peer.handshakeAsPSKResponder(passphrase: pass, iterations: iters)
        } else {
            try peer.handshakeAsResponder()
        }
        print("  handshake OK — waiting for DATA…")
        while true {
            do {
                let plain = try peer.receivePlaintext()
                let preview = String(bytes: plain.prefix(80), encoding: .utf8) ?? "(\(plain.count) B)"
                print("  rx: \(preview)")
            } catch Enigma256WireError.closed {
                print("  peer BYE / closed")
                break
            }
        }
    } catch {
        fputs("Enigma256 listen failed: \(error)\n", stderr)
        exit(1)
    }
}

func runEnigma256TCPConnect() {
    let host = stringFlag("--enigma256-host") ?? "127.0.0.1"
    let port = enigma256Port()
    let psk = enigma256UsesPSK()
    let salt = enigma256Material(stringFlag("--enigma256-salt"), label: "salt", allowNil: true)
        ?? (psk ? Enigma256Passphrase.randomSalt() : Data("helut-wire".utf8))
    let messages: [[UInt8]]
    if let path = stringFlag("--enigma256-plain-file") ?? stringFlag("--enigma256-in") {
        do { messages = [[UInt8](try Data(contentsOf: URL(fileURLWithPath: path)))] }
        catch {
            fputs("Failed reading plaintext: \(error)\n", stderr)
            exit(1)
        }
    } else if let text = stringFlag("--enigma256-plain") {
        messages = [Array(text.utf8)]
    } else {
        messages = [Array("helut tcp datagram on Apple Silicon".utf8)]
    }

    print("Enigma256 TCP connect \(host):\(port) (initiator, \(psk ? "PSK" : "ECDH"))")
    do {
        let transport = try Enigma256TCPTransport.connect(host: host, port: port, timeout: 15)
        defer { transport.close() }
        let peer = Enigma256WirePeer(transport: transport, decryptViaSoftBus: true)
        if psk {
            let pass = stringFlag("--enigma256-passphrase")!
            let iters = intFlag("--enigma256-pbkdf2-iters") ?? Enigma256Passphrase.defaultIterations
            try peer.handshakeAsPSKInitiator(passphrase: pass, salt: salt, iterations: iters)
        } else {
            try peer.handshakeAsInitiator(salt: salt)
        }
        for (i, msg) in messages.enumerated() {
            try peer.sendPlaintext(msg)
            print("  tx[\(i)]: \(msg.count) B")
        }
        try peer.close()
        print("  BYE sent — done")
    } catch {
        fputs("Enigma256 connect failed: \(error)\n", stderr)
        exit(1)
    }
}
