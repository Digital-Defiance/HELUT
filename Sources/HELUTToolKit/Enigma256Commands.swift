import Foundation
import HELUTCore
import HELUTCLI

// MARK: - Enigma 256 golden dump (`--enigma256-golden`)

enum Enigma256GoldenPublicationError: Error, Equatable, CustomStringConvertible {
    case canonicalBundleProfileMismatch(expected: String, supplied: String)

    var description: String {
        switch self {
        case let .canonicalBundleProfileMismatch(expected, supplied):
            return "refusing canonical E256 KAT publication: canonical profile is \(expected), supplied profile is \(supplied)"
        }
    }
}

func enigma256ValidateGoldenPublication(
    suppliedCompatibilityKey: String,
    outputURL: URL,
    canonicalCompatibilityKey: String,
    canonicalOutputURL: URL
) throws {
    let outputPath = outputURL.standardizedFileURL.resolvingSymlinksInPath().path
    let canonicalPath = canonicalOutputURL.standardizedFileURL.resolvingSymlinksInPath().path
    guard outputPath == canonicalPath else { return }
    guard suppliedCompatibilityKey == canonicalCompatibilityKey else {
        throw Enigma256GoldenPublicationError.canonicalBundleProfileMismatch(
            expected: canonicalCompatibilityKey,
            supplied: suppliedCompatibilityKey
        )
    }
}

func runEnigma256Golden() {
    let canonicalProfilePath = "Fixtures/enigma256_generation.json"
    let canonicalOutputPath = "Fixtures/enigma256_golden"
    let profilePath = stringFlag("--enigma256-genes") ?? canonicalProfilePath
    let outDir = stringFlag("--enigma256-out")
        ?? "build/hardware/Enigma256/enigma256_golden"
    let profile: Enigma256Generation
    do {
        profile = try Enigma256Generation.load(from: URL(fileURLWithPath: profilePath))
        let canonicalProfile = try Enigma256Generation.load(
            from: URL(fileURLWithPath: canonicalProfilePath)
        )
        try enigma256ValidateGoldenPublication(
            suppliedCompatibilityKey: profile.compatibilityKey,
            outputURL: URL(fileURLWithPath: outDir, isDirectory: true),
            canonicalCompatibilityKey: canonicalProfile.compatibilityKey,
            canonicalOutputURL: URL(fileURLWithPath: canonicalOutputPath, isDirectory: true)
        )
        profile.activate()
    } catch {
        fatalError("Enigma256 profile/publication validation failed at \(profilePath): \(error)")
    }
    let plainArg = stringFlag("--enigma256-plain")
    let plaintext = plainArg.map { Array($0.utf8) }

    let session = Enigma256Bridge.makeGoldenSession(plaintext: plaintext)
    let url = URL(fileURLWithPath: outDir, isDirectory: true)
    do {
        _ = try Enigma256Bridge.writeGoldenBundle(session: session, to: url)
        _ = try Enigma256Bridge.loadAndVerify(bundle: url, profile: profile)
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
    print("  files: manifest.json tables/*.hex trace/*.hex session.json plaintext.* ciphertext.* tb_params.vh")
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
        if enigma256PreferHybrid(), #available(macOS 26.0, *) {
            print("  frames: hybrid HELLO/ACK (Ed25519) → DATA×\(messages.count) AEAD → BYE")
            let got = try Enigma256WireSession.runInProcessHybrid(
                messages: messages,
                salt: salt,
                decryptViaSoftBus: true,
                requireTrust: true
            )
            precondition(got == messages)
            for (i, m) in got.enumerated() {
                let preview = String(bytes: m.prefix(48), encoding: .utf8) ?? "(\(m.count) B)"
                print("  rx[\(i)]: \(preview)")
            }
        } else {
            print("  frames: HELLO → ACK → DATA×\(messages.count) AEAD → BYE")
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

/// Default wire mode: hybrid PQ + Ed25519 (macOS 26+). Opt out with `--enigma256-classical`.
func enigma256PreferHybrid() -> Bool {
    if enigma256UsesPSK() { return false }
    if CommandLine.arguments.contains("--enigma256-classical")
        || CommandLine.arguments.contains("--enigma256-x25519")
    {
        return false
    }
    if CommandLine.arguments.contains("--enigma256-hybrid") { return true }
    if #available(macOS 26.0, *) { return true }
    return false
}

func enigma256LoadOrMakeIdentity() -> Enigma256Identity {
    if let path = stringFlag("--enigma256-identity") {
        do {
            let raw = try Data(contentsOf: URL(fileURLWithPath: path))
            return try Enigma256Identity(privateKeyRaw: raw)
        } catch {
            fputs("Failed loading --enigma256-identity: \(error)\n", stderr)
            exit(2)
        }
    }
    let id = Enigma256Identity()
    if let out = stringFlag("--enigma256-identity-out") {
        if let sk = id.privateKeyRaw {
            try? sk.write(to: URL(fileURLWithPath: out))
            try? id.publicKeyRaw.write(to: URL(fileURLWithPath: out + ".pub"))
            print("  wrote identity → \(out) (+ .pub)")
        }
    }
    return id
}

func enigma256TrustedSet() -> Set<Data> {
    var trusted = Set<Data>()
    if let hex = stringFlag("--enigma256-trust") {
        trusted.insert(Data(enigma256ParseHex(hex, label: "trust")))
    }
    if let path = stringFlag("--enigma256-trust-file") {
        if let raw = try? Data(contentsOf: URL(fileURLWithPath: path)), raw.count == 32 {
            trusted.insert(raw)
        }
    }
    return trusted
}

func runEnigma256TCPListen() {
    let port = enigma256Port()
    let psk = enigma256UsesPSK()
    let hybrid = !psk && enigma256PreferHybrid()
    let mode = psk ? "PSK" : (hybrid ? "hybrid+AEAD" : "X25519+AEAD")
    print("Enigma256 TCP listen on 0.0.0.0:\(port) (responder, SoftBus decrypt, \(mode))")
    do {
        let transport = try Enigma256TCPTransport.accept(port: port, timeout: 120)
        defer { transport.close() }
        let identity = hybrid ? enigma256LoadOrMakeIdentity() : nil
        let peer = Enigma256WirePeer(
            transport: transport,
            decryptViaSoftBus: true,
            identity: identity
        )
        peer.trustedIdentities = enigma256TrustedSet()
        if psk {
            let pass = stringFlag("--enigma256-passphrase")!
            let iters = intFlag("--enigma256-pbkdf2-iters") ?? Enigma256Passphrase.defaultIterations
            try peer.handshakeAsPSKResponder(passphrase: pass, iterations: iters)
        } else if hybrid {
            guard #available(macOS 26.0, *) else {
                fputs("Hybrid handshake requires macOS 26+\n", stderr)
                exit(2)
            }
            try peer.handshakeAsHybridResponder()
            if let pub = peer.peerIdentityPublicKey {
                let hex = pub.map { String(format: "%02x", $0) }.joined()
                print("  peer identity: \(hex.prefix(32))…")
            }
        } else {
            try peer.handshakeAsResponder()
        }
        print("  handshake OK — DATA carries AEAD (HMAC-SHA512); waiting…")
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
    let hybrid = !psk && enigma256PreferHybrid()
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

    let mode = psk ? "PSK" : (hybrid ? "hybrid+AEAD" : "X25519+AEAD")
    print("Enigma256 TCP connect \(host):\(port) (initiator, \(mode))")
    do {
        let transport = try Enigma256TCPTransport.connect(host: host, port: port, timeout: 15)
        defer { transport.close() }
        let identity = hybrid ? enigma256LoadOrMakeIdentity() : nil
        let peer = Enigma256WirePeer(
            transport: transport,
            decryptViaSoftBus: true,
            identity: identity
        )
        peer.trustedIdentities = enigma256TrustedSet()
        if psk {
            let pass = stringFlag("--enigma256-passphrase")!
            let iters = intFlag("--enigma256-pbkdf2-iters") ?? Enigma256Passphrase.defaultIterations
            try peer.handshakeAsPSKInitiator(passphrase: pass, salt: salt, iterations: iters)
        } else if hybrid {
            guard #available(macOS 26.0, *) else {
                fputs("Hybrid handshake requires macOS 26+\n", stderr)
                exit(2)
            }
            try peer.handshakeAsHybridInitiator(salt: salt)
            if let pub = peer.peerIdentityPublicKey {
                let hex = pub.map { String(format: "%02x", $0) }.joined()
                print("  peer identity: \(hex.prefix(32))…")
            }
        } else {
            try peer.handshakeAsInitiator(salt: salt)
        }
        for (i, msg) in messages.enumerated() {
            try peer.sendPlaintext(msg)
            print("  tx[\(i)]: \(msg.count) B (AEAD)")
        }
        try peer.close()
        print("  BYE sent — done")
    } catch {
        fputs("Enigma256 connect failed: \(error)\n", stderr)
        exit(1)
    }
}

// MARK: - NLFF step-enable quality (`--enigma256-nlff-stats`)

func runEnigma256NLFFStats() {
    let profile = Enigma256Generation.bootstrapFromFixture()
    if CommandLine.arguments.contains("--enigma256-nlff-breed")
        || CommandLine.arguments.contains("--enigma256-nlff-breed-apply") {
        fputs("""
        In-process NLFF breeding/apply is disabled for E256-v2.
        Generate candidates offline with Scripts/e256_nlff_v2_search.py, then validate and
        promote an accepted receipt with Scripts/e256_nlff_emit.py. Canonical artifacts are
        never mutated by this command.

        """, stderr)
        exit(2)
    }

    let steps = intFlag("--enigma256-nlff-stats-steps") ?? 200_000
    let stats = profile.stepEnableStats(steps: steps)
    let rateText = stats.rates.map { String(format: "%.4f", $0) }.joined(separator: " ")
    print("Enigma 256 native NLFF step-enable diagnostics (\(steps) LFSR clocks)")
    print("  compatibility: \(profile.compatibilityKey)")
    print("  status: \(profile.researchStatus) — bounded diagnostics, not a security proof")
    print("  receipt: \(profile.receipt) sha256=\(profile.receiptSHA256)")
    print("  rates: \(rateText) mean=\(String(format: "%.4f", stats.meanRate)) \(stats.meanRateOK ? "OK" : "BIAS") \(stats.rateFloorOK ? "FLOOR_OK" : "DEAD_ROTORS")")
    print("  max|φ| off-diag=\(String(format: "%.4f", stats.maxAbsOffDiagPhi)) \(stats.independenceOK ? "OK" : "CORRELATED")")
    print(String(format: "  P(all four on)=%.6f", stats.allFourOnRate))
    for row in stats.phi {
        print("  φ " + row.map { String(format: "%+.3f", $0) }.joined(separator: " "))
    }
}


// MARK: - Enigma 256 Red/Blue campaign (`--enigma256-campaign`)
//
// Field = Apple Silicon SoftBus + HELUT TensorLUT. No Zynq required.
// The profile is immutable at runtime; these runs record bounded evidence only.

struct Enigma256TensorLUTScore: Sendable {
    var family: String?
    var suiteVersion: Int?
    var generation: Int?
    var fixtureSchemaVersion: Int?
    var profileSHA256: String?
    var finalCrypto: Double?
    var squeezeSurvived: Bool?
    var formula: String?
    var verdict: String?
    var path: String

    var redPressure: Bool {
        guard let c = finalCrypto, let s = squeezeSurvived else { return false }
        return s && c <= 1e-6
    }

    var blueHold: Bool {
        squeezeSurvived == false
    }
}

func enigma256ParseTensorLUTLog(at path: String) -> Enigma256TensorLUTScore {
    var score = Enigma256TensorLUTScore(
        family: nil,
        suiteVersion: nil,
        generation: nil,
        fixtureSchemaVersion: nil,
        profileSHA256: nil,
        finalCrypto: nil,
        squeezeSurvived: nil,
        formula: nil,
        verdict: nil,
        path: path
    )
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return score }
    for line in text.split(whereSeparator: \.isNewline) {
        let s = String(line)
        if s.hasPrefix("family:") {
            score.family = s.dropFirst("family:".count).trimmingCharacters(in: .whitespaces)
        } else if s.hasPrefix("suite_version:") {
            let t = s.dropFirst("suite_version:".count).trimmingCharacters(in: .whitespaces)
            score.suiteVersion = Int(t)
        } else if s.hasPrefix("generation:") {
            let t = s.dropFirst("generation:".count).trimmingCharacters(in: .whitespaces)
            score.generation = Int(t)
        } else if s.hasPrefix("fixture_schema_version:") {
            let t = s.dropFirst("fixture_schema_version:".count).trimmingCharacters(in: .whitespaces)
            score.fixtureSchemaVersion = Int(t)
        } else if s.hasPrefix("profile_sha256:") {
            score.profileSHA256 = s.dropFirst("profile_sha256:".count).trimmingCharacters(in: .whitespaces)
        } else if s.hasPrefix("final_crypto:") {
            let t = s.dropFirst("final_crypto:".count).trimmingCharacters(in: .whitespaces)
            score.finalCrypto = Double(t)
        } else if s.hasPrefix("squeeze_survived:") {
            let t = s.dropFirst("squeeze_survived:".count).trimmingCharacters(in: .whitespaces).lowercased()
            score.squeezeSurvived = (t == "true" || t == "1" || t == "yes")
        } else if s.hasPrefix("formula:") {
            score.formula = s.dropFirst("formula:".count).trimmingCharacters(in: .whitespaces)
        } else if s.hasPrefix("verdict:") {
            score.verdict = s.dropFirst("verdict:".count).trimmingCharacters(in: .whitespaces)
        }
    }
    return score
}

/// Soft Red: day key known; random-search message keys against SoftBus CT (stochastic KPA).
func enigma256SoftBusKPA(
    day: Enigma256DayKey,
    plaintext: [UInt8],
    ciphertext: [UInt8],
    trials: Int,
    rng: inout some RandomNumberGenerator
) -> (bestMatches: Int, trials: Int, elapsedMs: Double) {
    let t0 = DispatchTime.now().uptimeNanoseconds
    var best = 0
    for _ in 0 ..< trials {
        var available = Array(0 ..< 16)
        available.shuffle(using: &rng)
        let rotors = (available[0], available[1], available[2], available[3])
        let positions = (
            UInt8.random(in: .min ... .max, using: &rng),
            UInt8.random(in: .min ... .max, using: &rng),
            UInt8.random(in: .min ... .max, using: &rng),
            UInt8.random(in: .min ... .max, using: &rng)
        )
        var seed = UInt64.random(in: 1 ... .max, using: &rng)
        if seed == 0 { seed = 1 }
        let centerMaskKey = Data((0 ..< Enigma256CenterMask.keyLength).map { _ in
            UInt8.random(in: .min ... .max, using: &rng)
        })
        let msg = Enigma256MessageKey(
            rotorIndices: rotors,
            positions: positions,
            lfsrSeed: seed,
            centerMaskKey: centerMaskKey
        )
        let bus = Enigma256SoftBus()
        let driver = Enigma256AXIDriver(bus: bus)
        driver.configure(day: day, message: msg)
        let guess = driver.transfer(plaintext)
        var matches = 0
        for i in 0 ..< min(guess.count, ciphertext.count) where guess[i] == ciphertext[i] {
            matches += 1
        }
        if matches > best { best = matches }
        if best == plaintext.count { break }
    }
    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
    return (best, trials, elapsed)
}

func runEnigma256Campaign() {
    let genesPath = stringFlag("--enigma256-genes") ?? "Fixtures/enigma256_generation.json"
    let ledgerPath = stringFlag("--enigma256-campaign-log") ?? "logs/enigma256-rb-campaign.jsonl"
    let tensorLog = stringFlag("--enigma256-tensorlut-log") ?? "logs/tensorlut-enigma256-nlff.log"
    let trials = intFlag("--enigma256-campaign-trials") ?? 4_096
    let allowMutate = CommandLine.arguments.contains("--enigma256-campaign-mutate")
    let forceMutate = CommandLine.arguments.contains("--enigma256-campaign-force-mutate")
    if allowMutate || forceMutate {
        fputs("""
        Runtime campaign mutation is disabled for the immutable E256-v2 profile.
        Run Scripts/e256_nlff_v2_search.py offline, independently validate its holdout receipt,
        then promote only an accepted receipt with Scripts/e256_nlff_emit.py.

        """, stderr)
        exit(2)
    }
    let crib = Array((stringFlag("--enigma256-plain") ?? "HELUT Enigma256 SoftBus Red/Blue crib").utf8)

    let genesURL = URL(fileURLWithPath: genesPath)
    guard FileManager.default.fileExists(atPath: genesPath) else {
        fputs("Missing required E256-v2 profile fixture: \(genesPath)\n", stderr)
        exit(2)
    }
    let generation: Enigma256Generation
    do {
        generation = try Enigma256Generation.load(from: genesURL)
    } catch {
        fputs("Failed to load E256-v2 profile \(genesPath): \(error)\n", stderr)
        exit(2)
    }
    generation.activate()

    let tensor = enigma256ParseTensorLUTLog(at: tensorLog)
    if FileManager.default.fileExists(atPath: tensorLog) {
        let compatible = tensor.family == generation.family
            && tensor.suiteVersion == generation.suiteVersion
            && tensor.generation == generation.id
            && tensor.fixtureSchemaVersion == generation.fixtureSchemaVersion
            && tensor.profileSHA256 == generation.profileHashHex
        guard compatible else {
            let foundSuite = tensor.suiteVersion.map { String($0) } ?? "missing"
            let foundGeneration = tensor.generation.map { String($0) } ?? "missing"
            let foundSchema = tensor.fixtureSchemaVersion.map { String($0) } ?? "missing"
            fputs("""
            Refusing incompatible TensorLUT report: \(tensorLog)
              expected: \(generation.compatibilityKey)
              found: family=\(tensor.family ?? "missing") suite_version=\(foundSuite) generation=\(foundGeneration) fixture_schema_version=\(foundSchema) profile_sha256=\(tensor.profileSHA256 ?? "missing")
            Re-run TensorLUT for the active profile and pass that report with --enigma256-tensorlut-log.

            """, stderr)
            exit(2)
        }
    }

    let ikm = Data("enigma256-rb-campaign-ikm-v1".utf8)
    let ctx = Enigma256Context(ikm: ikm)
    let nonce = Data("campaign-nonce-01".utf8)
    let box = ctx.seal(crib, nonce: nonce)
    let trueKey = Enigma256KDF.deriveMessageKey(masterIKM: ikm, nonce: nonce)
    let bus = Enigma256SoftBus()
    let driver = Enigma256AXIDriver(bus: bus)
    driver.configure(day: ctx.day, message: trueKey)
    let softCT = driver.transfer(crib)
    precondition(softCT == box.ciphertext, "SoftBus body must match Context seal body")

    var rng = SystemRandomNumberGenerator()
    let soft = enigma256SoftBusKPA(
        day: ctx.day,
        plaintext: crib,
        ciphertext: softCT,
        trials: trials,
        rng: &rng
    )
    let softPressure = soft.bestMatches == crib.count
    let redPressure = softPressure || tensor.redPressure

    print("Enigma 256 Red/Blue campaign (Apple Silicon SoftBus field)")
    print("  compatibility: \(generation.compatibilityKey)")
    print("  formula: \(generation.formula.rawValue)")
    let foldDesc = generation.folds.map { fold -> String in
        "(\(fold.taps.map(String.init).joined(separator: ",")))"
    }.joined(separator: " ")
    print("  folds: \(foldDesc)")
    print("  SoftBus KPA: best \(soft.bestMatches)/\(crib.count) over \(soft.trials) trials in \(String(format: "%.1f", soft.elapsedMs)) ms")
    if let c = tensor.finalCrypto, let s = tensor.squeezeSurvived {
        let side = s
            ? "RED pressure (squeeze recovered a binary elite)"
            : "bounded negative (no binary elite recovered)"
        print("  TensorLUT: final_crypto=\(String(format: "%.6f", c)) squeeze_survived=\(s) → \(side)")
        print("  TensorLUT log: \(tensor.path)")
    } else {
        print("  TensorLUT: no score in \(tensor.path) (run Scripts/enigma256_tensorlut.sh)")
    }
    if redPressure {
        print("  red_pressure: true — immutable profile; runtime mutation is disabled")
    } else if tensor.blueHold {
        print("  red_pressure: false — no recovery in these bounded SoftBus/TensorLUT runs")
    } else {
        print("  red_pressure: false (soft=\(softPressure) tensor=\(tensor.redPressure)); bounded evidence only")
    }

    let mutated = false
    let nextGen = generation
    if redPressure {
        print("  Immutable profile — red pressure recorded as bounded evidence")
        print("  Next: run offline search and holdout grading; promote only an independently validated receipt")
    } else if tensor.blueHold {
        print("  No binary elite was recovered in this bounded TensorLUT run; this is not a security claim")
    } else {
        print("  SoftBus KPA found no recovery in the bounded trial budget; TensorLUT unscored")
    }

    // JSONL ledger row
    let row: [String: Any] = [
        "ts": ISO8601DateFormatter().string(from: Date()),
        "family": generation.family,
        "suite_version": generation.suiteVersion,
        "generation": generation.id,
        "next_generation": nextGen.id,
        "fixture_schema_version": generation.fixtureSchemaVersion,
        "profile_sha256": generation.profileHashHex,
        "compatibility_key": generation.compatibilityKey,
        "formula": generation.formula.rawValue,
        "lfsr_transition": generation.lfsrTransition,
        "update_order": generation.updateOrder,
        "research_status": generation.researchStatus,
        "receipt": generation.receipt,
        "receipt_sha256": generation.receiptSHA256,
        "mutated": mutated,
        "soft_best_matches": soft.bestMatches,
        "soft_length": crib.count,
        "soft_trials": soft.trials,
        "soft_ms": soft.elapsedMs,
        "soft_pressure": softPressure,
        "tensor_final_crypto": tensor.finalCrypto.map { $0 as Any } ?? NSNull(),
        "tensor_squeeze_survived": tensor.squeezeSurvived.map { $0 as Any } ?? NSNull(),
        "tensor_pressure": tensor.redPressure,
        "red_pressure": redPressure,
        "components": generation.components.map { ["truth_hex": $0.truthHex] },
        "folds": generation.folds.map {
            [
                "taps": $0.taps,
                "left_component": $0.leftComponent,
                "right_component": $0.rightComponent
            ] as [String: Any]
        }
    ]
    if let data = try? JSONSerialization.data(withJSONObject: row),
       let line = String(data: data, encoding: .utf8) {
        let url = URL(fileURLWithPath: ledgerPath)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            if let payload = (line + "\n").data(using: .utf8) {
                try? handle.write(contentsOf: payload)
            }
        } else {
            try? (line + "\n").write(toFile: ledgerPath, atomically: true, encoding: .utf8)
        }
        print("  ledger: \(ledgerPath)")
    }
}

// MARK: - SoftBus keystream entropy (`--enigma256-ent`)

struct Enigma256EntReport: Sendable {
    var bytes: Int
    var entropyPerByte: Double?
    var mean: Double?
    var serialCorr: Double?
    var chiPercent: Double?
    var path: String
    var raw: String

    /// Smoke thresholds for ≥1MiB samples (not a cryptanalytic bar).
    var pass: Bool {
        guard let e = entropyPerByte, let m = mean, let c = serialCorr else { return false }
        return e >= 7.9 && abs(m - 127.5) < 2.0 && abs(c) < 0.05
    }
}

func enigma256ParseEntOutput(_ text: String, bytes: Int, path: String) -> Enigma256EntReport {
    var report = Enigma256EntReport(
        bytes: bytes, entropyPerByte: nil, mean: nil, serialCorr: nil, chiPercent: nil, path: path, raw: text
    )
    for line in text.split(whereSeparator: \.isNewline).map(String.init) {
        if line.hasPrefix("Entropy ="), line.contains("bits per byte") {
            let part = line.dropFirst("Entropy =".count)
                .trimmingCharacters(in: .whitespaces)
                .split(separator: " ").first
            report.entropyPerByte = part.flatMap { Double($0) }
        } else if line.contains("Arithmetic mean value of data bytes is") {
            // "Arithmetic mean value of data bytes is 127.9123 (127.5 = random)."
            if let range = line.range(of: "bytes is ") {
                let rest = line[range.upperBound...]
                let num = rest.split(separator: " ").first.map(String.init)
                report.mean = num.flatMap(Double.init)
            }
        } else if line.hasPrefix("Serial correlation coefficient is") {
            if let range = line.range(of: "coefficient is ") {
                let rest = line[range.upperBound...]
                let num = rest.split(separator: " ").first.map(String.init)
                report.serialCorr = num.flatMap(Double.init)
            }
        } else if line.contains("would exceed this value") {
            if let range = line.range(of: "value ") {
                let rest = line[range.upperBound...]
                let num = rest.split(separator: " ").first.map(String.init)
                report.chiPercent = num.flatMap(Double.init)
            }
        }
    }
    return report
}

func runEnigma256Ent() {
    _ = Enigma256Generation.bootstrapFromFixture()
    let bytes = intFlag("--enigma256-ent-bytes") ?? (1 << 20)
    let outPath = stringFlag("--enigma256-ent-out") ?? "build/enigma256_keystream.bin"
    let logPath = stringFlag("--enigma256-ent-log") ?? "logs/enigma256-ent.log"
    let failClosed = CommandLine.arguments.contains("--enigma256-ent-fail-closed")

    guard bytes >= 4096 else {
        fputs("ent sample too small (\(bytes)); use ≥4096 (prefer ≥1MiB)\n", stderr)
        exit(2)
    }

    // Seeded PRNG plaintext → SoftBus ciphertext under the active profile.
    // `ent` remains a smoke test only; the separate zero-plaintext probe checks
    // the schema-3 equality null near 1/256 and cannot establish security.
    // Prefer PRNG PT over a counter for the unrelated entropy smoke sample.
    let plainMode = (stringFlag("--enigma256-ent-plain") ?? "prng").lowercased()
    let ikm = Data("enigma256-ent-ikm-v1-32-bytes!!!!!!".utf8)
    let ctx = Enigma256Context(ikm: ikm)
    let nonce = Data("ent-nonce-16b!!!!".utf8)
    let key = Enigma256KDF.deriveMessageKey(masterIKM: ikm, nonce: nonce)
    let bus = Enigma256SoftBus()
    let driver = Enigma256AXIDriver(bus: bus)
    driver.configure(day: ctx.day, message: key)

    // Chosen-plaintext structural probe. A balanced center mode with two
    // frozen points in mode one has null p = 1/256 after conjugation.
    var fpProbe = 0
    let fpN = min(100_000, bytes)
    for _ in 0 ..< fpN {
        if driver.transfer(0) == 0 { fpProbe += 1 }
    }
    let fpRate = Double(fpProbe) / Double(fpN)
    let fpNull = 1.0 / 256.0
    let fpSigma = sqrt(fpNull * (1 - fpNull) / Double(fpN))
    let fpCalibrated = abs(fpRate - fpNull) <= 6 * fpSigma
    // Re-arm for the actual entropy sample.
    driver.configure(day: ctx.day, message: key)

    let chunk = 64 * 1024
    var plain = [UInt8](repeating: 0, count: min(chunk, bytes))
    var produced = 0
    // xorshift64* — deterministic, not crypto; only to feed a non-structured PT.
    var prng: UInt64 = 0xE256_E470_51ED_0001
    func nextPlainByte() -> UInt8 {
        switch plainMode {
        case "zeros", "zero":
            return 0
        case "counter":
            return UInt8(truncatingIfNeeded: produced) // filled per index below
        default:
            prng ^= prng << 13
            prng ^= prng >> 7
            prng ^= prng << 17
            return UInt8(truncatingIfNeeded: prng &* 0x2545_F491_4F6C_DD1D)
        }
    }
    let url = URL(fileURLWithPath: outPath)
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    FileManager.default.createFile(atPath: outPath, contents: nil)
    guard let handle = try? FileHandle(forWritingTo: url) else {
        fputs("cannot write \(outPath)\n", stderr)
        exit(1)
    }
    defer { try? handle.close() }

    let t0 = DispatchTime.now().uptimeNanoseconds
    while produced < bytes {
        let n = min(plain.count, bytes - produced)
        if n != plain.count { plain = [UInt8](repeating: 0, count: n) }
        for i in 0 ..< n {
            if plainMode == "counter" {
                plain[i] = UInt8(truncatingIfNeeded: produced &+ i)
            } else {
                plain[i] = nextPlainByte()
            }
        }
        let ct = driver.transfer(plain)
        try? handle.write(contentsOf: Data(ct))
        produced += n
    }
    let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000

    let entPath = ProcessInfo.processInfo.environment["ENT"] ?? "ent"
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    proc.arguments = [entPath, outPath]
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = pipe
    do {
        try proc.run()
        proc.waitUntilExit()
    } catch {
        fputs("failed to run ent (\(entPath)): \(error)\n", stderr)
        exit(2)
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let text = String(data: data, encoding: .utf8) ?? ""
    let report = enigma256ParseEntOutput(text, bytes: bytes, path: outPath)

    let summary = """
    # Enigma 256 SoftBus ent gate
    generation: \(Enigma256Generation.current.id)
    formula: \(Enigma256Generation.current.formula.rawValue)
    bytes: \(bytes)
    plaintext: \(plainMode)
    sample: \(outPath)
    softbus_ms: \(String(format: "%.1f", ms))
    zero_pt_equality_rate: \(String(format: "%.6f", fpRate))
    zero_pt_null: 0.00390625
    zero_pt_six_sigma_pass: \(fpCalibrated)
    entropy_bits_per_byte: \(report.entropyPerByte.map { String(format: "%.6f", $0) } ?? "n/a")
    mean: \(report.mean.map { String(format: "%.4f", $0) } ?? "n/a")
    serial_corr: \(report.serialCorr.map { String(format: "%.6f", $0) } ?? "n/a")
    chi_percent: \(report.chiPercent.map { String(format: "%.2f", $0) } ?? "n/a")
    pass: \(report.pass)
    thresholds: entropy>=7.9 mean∈[125.5,129.5] |corr|<0.05

    \(text)
    """
    try? FileManager.default.createDirectory(
        at: URL(fileURLWithPath: logPath).deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try? summary.write(toFile: logPath, atomically: true, encoding: .utf8)

    print("Enigma 256 SoftBus ent gate (gen \(Enigma256Generation.current.id))")
    print("  bytes: \(bytes) plain=\(plainMode) → \(outPath) in \(String(format: "%.1f", ms)) ms")
    print(String(format: "  zero-PT equality rate=%.4f%% (null 1/256; six-sigma %@)", fpRate * 100, fpCalibrated ? "PASS" : "FAIL"))
    if let e = report.entropyPerByte, let m = report.mean, let c = report.serialCorr {
        print(String(format: "  entropy=%.6f  mean=%.4f  corr=%+.6f  → %@", e, m, c, report.pass ? "PASS" : "FAIL"))
    } else {
        print("  failed to parse ent output")
        print(text)
        exit(2)
    }
    print("  log → \(logPath)")
    if failClosed && (!report.pass || !fpCalibrated) { exit(1) }
}

// MARK: - Structured SoftBus KPA (widen Red beyond random search)

func enigma256MatchCount(_ a: [UInt8], _ b: [UInt8]) -> Int {
    zip(a, b).reduce(0) { $0 + ($1.0 == $1.1 ? 1 : 0) }
}

func enigma256SoftBusCrypt(
    day: Enigma256DayKey,
    message: Enigma256MessageKey,
    plaintext: [UInt8]
) -> [UInt8] {
    let bus = Enigma256SoftBus()
    let driver = Enigma256AXIDriver(bus: bus)
    driver.configure(day: day, message: message)
    return driver.transfer(plaintext)
}

/// SoftBus scorer that burst-loads day tables once, then only reloads message keys.
final class Enigma256SoftBusScorer {
    private let day: Enigma256DayKey
    private let bus = Enigma256SoftBus()
    private let driver: Enigma256AXIDriver
    private var tablesLoaded = false

    init(day: Enigma256DayKey) {
        self.day = day
        self.driver = Enigma256AXIDriver(bus: bus)
    }

    func crypt(message: Enigma256MessageKey, plaintext: [UInt8]) -> [UInt8] {
        if !tablesLoaded {
            driver.configure(day: day, message: message)
            tablesLoaded = true
        } else {
            // Re-burst active-slot wiring (cheap SoftBus assign) + reload stream state.
            driver.programTablesBurst(message.wiring(from: day))
            driver.writeMessageKey(message)
            driver.pulseLoadState()
        }
        return driver.transfer(plaintext)
    }

    func matchCount(message: Enigma256MessageKey, plaintext: [UInt8], ciphertext: [UInt8]) -> Int {
        enigma256MatchCount(crypt(message: message, plaintext: plaintext), ciphertext)
    }
}

/// Hill-climb LFSR seed with Walzenlage, Grundstellung, and center schedule key known.
func enigma256HillClimbLFSR(
    day: Enigma256DayKey,
    rotors: (Int, Int, Int, Int),
    positions: (UInt8, UInt8, UInt8, UInt8),
    centerMaskKey: Data,
    plaintext: [UInt8],
    ciphertext: [UInt8],
    rounds: Int,
    rng: inout some RandomNumberGenerator
) -> (bestMatches: Int, seed: UInt64, elapsedMs: Double) {
    let t0 = DispatchTime.now().uptimeNanoseconds
    let scorer = Enigma256SoftBusScorer(day: day)
    var seed = UInt64.random(in: 1 ... .max, using: &rng)
    if seed == 0 { seed = 1 }
    var bestSeed = seed
    var best = scorer.matchCount(
        message: Enigma256MessageKey(
            rotorIndices: rotors,
            positions: positions,
            lfsrSeed: seed,
            centerMaskKey: centerMaskKey
        ),
        plaintext: plaintext,
        ciphertext: ciphertext
    )
    for _ in 0 ..< rounds {
        let bit = Int.random(in: 0 ..< 64, using: &rng)
        let trial = seed ^ (UInt64(1) << bit)
        let s = trial == 0 ? 1 : trial
        let matches = scorer.matchCount(
            message: Enigma256MessageKey(
                rotorIndices: rotors,
                positions: positions,
                lfsrSeed: s,
                centerMaskKey: centerMaskKey
            ),
            plaintext: plaintext,
            ciphertext: ciphertext
        )
        if matches >= best {
            best = matches
            seed = s
            bestSeed = s
            if best == plaintext.count { break }
        }
    }
    let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
    return (best, bestSeed, ms)
}

/// Hill-climb Grundstellung with rotors, LFSR, and center schedule key known.
func enigma256HillClimbPositions(
    day: Enigma256DayKey,
    rotors: (Int, Int, Int, Int),
    lfsrSeed: UInt64,
    centerMaskKey: Data,
    plaintext: [UInt8],
    ciphertext: [UInt8],
    rounds: Int,
    rng: inout some RandomNumberGenerator
) -> (bestMatches: Int, positions: (UInt8, UInt8, UInt8, UInt8), elapsedMs: Double) {
    let t0 = DispatchTime.now().uptimeNanoseconds
    let scorer = Enigma256SoftBusScorer(day: day)
    var pos: (UInt8, UInt8, UInt8, UInt8) = (
        UInt8.random(in: .min ... .max, using: &rng),
        UInt8.random(in: .min ... .max, using: &rng),
        UInt8.random(in: .min ... .max, using: &rng),
        UInt8.random(in: .min ... .max, using: &rng)
    )
    var bestPos = pos
    var best = scorer.matchCount(
        message: Enigma256MessageKey(
            rotorIndices: rotors,
            positions: pos,
            lfsrSeed: lfsrSeed,
            centerMaskKey: centerMaskKey
        ),
        plaintext: plaintext,
        ciphertext: ciphertext
    )
    for _ in 0 ..< rounds {
        var trial = pos
        switch Int.random(in: 0 ..< 4, using: &rng) {
        case 0: trial.0 &+= UInt8.random(in: 1 ... 7, using: &rng)
        case 1: trial.1 &+= UInt8.random(in: 1 ... 7, using: &rng)
        case 2: trial.2 &+= UInt8.random(in: 1 ... 7, using: &rng)
        default: trial.3 &+= UInt8.random(in: 1 ... 7, using: &rng)
        }
        let matches = scorer.matchCount(
            message: Enigma256MessageKey(
                rotorIndices: rotors,
                positions: trial,
                lfsrSeed: lfsrSeed,
                centerMaskKey: centerMaskKey
            ),
            plaintext: plaintext,
            ciphertext: ciphertext
        )
        if matches >= best {
            best = matches
            pos = trial
            bestPos = trial
            if best == plaintext.count { break }
        }
    }
    let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
    return (best, bestPos, ms)
}

/// Hill-climb rotor order, positions, and LFSR with the center schedule key leaked.
/// This is not a day-key-only attack under fixture-v4.
func enigma256HillClimbJoint(
    day: Enigma256DayKey,
    centerMaskKey: Data,
    plaintext: [UInt8],
    ciphertext: [UInt8],
    rounds: Int,
    rng: inout some RandomNumberGenerator
) -> (bestMatches: Int, elapsedMs: Double) {
    let t0 = DispatchTime.now().uptimeNanoseconds
    let scorer = Enigma256SoftBusScorer(day: day)
    var available = Array(0 ..< 16)
    available.shuffle(using: &rng)
    var rotors = (available[0], available[1], available[2], available[3])
    var positions = (
        UInt8.random(in: .min ... .max, using: &rng),
        UInt8.random(in: .min ... .max, using: &rng),
        UInt8.random(in: .min ... .max, using: &rng),
        UInt8.random(in: .min ... .max, using: &rng)
    )
    var seed = UInt64.random(in: 1 ... .max, using: &rng)
    if seed == 0 { seed = 1 }

    func score(_ r: (Int, Int, Int, Int), _ p: (UInt8, UInt8, UInt8, UInt8), _ s: UInt64) -> Int {
        scorer.matchCount(
            message: Enigma256MessageKey(
                rotorIndices: r,
                positions: p,
                lfsrSeed: s,
                centerMaskKey: centerMaskKey
            ),
            plaintext: plaintext,
            ciphertext: ciphertext
        )
    }

    var best = score(rotors, positions, seed)
    for _ in 0 ..< rounds {
        var trialR = rotors
        var trialP = positions
        var trialS = seed
        switch Int.random(in: 0 ..< 3, using: &rng) {
        case 0:
            let bit = Int.random(in: 0 ..< 64, using: &rng)
            trialS ^= (UInt64(1) << bit)
            if trialS == 0 { trialS = 1 }
        case 1:
            switch Int.random(in: 0 ..< 4, using: &rng) {
            case 0: trialP.0 &+= UInt8.random(in: 1 ... 7, using: &rng)
            case 1: trialP.1 &+= UInt8.random(in: 1 ... 7, using: &rng)
            case 2: trialP.2 &+= UInt8.random(in: 1 ... 7, using: &rng)
            default: trialP.3 &+= UInt8.random(in: 1 ... 7, using: &rng)
            }
        default:
            let pool = Array(0 ..< 16).filter {
                $0 != trialR.0 && $0 != trialR.1 && $0 != trialR.2 && $0 != trialR.3
            }
            guard let pick = pool.randomElement(using: &rng) else { continue }
            switch Int.random(in: 0 ..< 4, using: &rng) {
            case 0: trialR.0 = pick
            case 1: trialR.1 = pick
            case 2: trialR.2 = pick
            default: trialR.3 = pick
            }
        }
        let matches = score(trialR, trialP, trialS)
        if matches >= best {
            best = matches
            rotors = trialR
            positions = trialP
            seed = trialS
            if best == plaintext.count { break }
        }
    }
    let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
    return (best, ms)
}

// MARK: - Scramble bijection sweep (`--enigma256-bijection`)

func runEnigma256BijectionSweep() {
    _ = Enigma256Generation.bootstrapFromFixture()
    let states = intFlag("--enigma256-bijection-states") ?? 1_000_000
    let streamBytes = intFlag("--enigma256-bijection-stream", allowZero: true) ?? 64
    let seedRaw = intFlag("--enigma256-bijection-seed") ?? 0xE256_B13E
    let seed = UInt64(bitPattern: Int64(seedRaw))
    let ikm = Data((stringFlag("--enigma256-ikm") ?? "enigma256-bijection-gate-ikm-v1!!!!").utf8)
    let day = Enigma256KDF.deriveDayKey(ikm: ikm, salt: Data("bijection-gate".utf8))

    print("Enigma 256 bijection sweep (gen \(Enigma256Generation.current.id))")
    print("  states: \(states)  stream_bytes/state: \(streamBytes)  seed: \(String(format: "0x%016llx", seed))")
    fflush(stdout)
    let report = Enigma256Bijection.sweep(
        day: day,
        states: states,
        streamBytes: streamBytes,
        seed: seed
    ) { n in
        print("  … \(n) states")
        fflush(stdout)
    }

    let rate = report.elapsedSeconds > 0
        ? Double(report.statesChecked) / report.elapsedSeconds
        : 0
    if let fail = report.failure, let st = report.failedState {
        fputs("""
        FAIL after \(report.statesChecked) states (\(String(format: "%.2f", report.elapsedSeconds)) s): \(fail)
          rotors: \(st.rotorIndices.0),\(st.rotorIndices.1),\(st.rotorIndices.2),\(st.rotorIndices.3)
          positions: \(String(format: "%02x %02x %02x %02x", st.positions.0, st.positions.1, st.positions.2, st.positions.3))

        """, stderr)
        exit(2)
    }
    print(
        "  PASS: \(report.statesChecked) states — scramble bijection + reciprocity"
            + (streamBytes > 0 ? " + \(streamBytes) B stream round-trip" : "")
            + " in \(String(format: "%.2f", report.elapsedSeconds)) s"
            + " (\(String(format: "%.0f", rate)) states/s)"
    )
}

func runEnigma256StructuredKPA() {
    let profile = Enigma256Generation.bootstrapFromFixture()
    let rounds = intFlag("--enigma256-kpa-rounds") ?? 16_384
    let defaultCrib =
        "HELUT Enigma256 structured SoftBus KPA long crib — bounded leaked-center-key hill-climb pressure vector."
    let crib = Array((stringFlag("--enigma256-plain") ?? defaultCrib).utf8)
    let ikm = Data("enigma256-struct-kpa-ikm-v1!!!!".utf8)
    let ctx = Enigma256Context(ikm: ikm)
    let nonce = Data("struct-kpa-nonce!".utf8)
    let trueKey = Enigma256KDF.deriveMessageKey(masterIKM: ikm, nonce: nonce)
    let ct = enigma256SoftBusCrypt(day: ctx.day, message: trueKey, plaintext: crib)
    let runHard = CommandLine.arguments.contains("--enigma256-structured-kpa-hard")
        || !CommandLine.arguments.contains("--enigma256-structured-kpa-partial-only")

    var rng = SystemRandomNumberGenerator()
    let climbLFSR = enigma256HillClimbLFSR(
        day: ctx.day,
        rotors: trueKey.rotorIndices,
        positions: trueKey.positions,
        centerMaskKey: trueKey.centerMaskKey,
        plaintext: crib,
        ciphertext: ct,
        rounds: rounds,
        rng: &rng
    )
    let climbPos = enigma256HillClimbPositions(
        day: ctx.day,
        rotors: trueKey.rotorIndices,
        lfsrSeed: trueKey.lfsrSeed,
        centerMaskKey: trueKey.centerMaskKey,
        plaintext: crib,
        ciphertext: ct,
        rounds: rounds,
        rng: &rng
    )
    let climbJoint: (bestMatches: Int, elapsedMs: Double)? = runHard
        ? enigma256HillClimbJoint(
            day: ctx.day,
            centerMaskKey: trueKey.centerMaskKey,
            plaintext: crib,
            ciphertext: ct,
            rounds: rounds,
            rng: &rng
        )
        : nil

    let lfsrPressure = climbLFSR.bestMatches == crib.count
    let posPressure = climbPos.bestMatches == crib.count
    let jointPressure = climbJoint.map { $0.bestMatches == crib.count } ?? false
    print("Enigma 256 structured SoftBus KPA")
    print("  compatibility: \(profile.compatibilityKey)")
    print("  scope: bounded attack run with the 32-byte center schedule key leaked; not a security claim")
    print("  crib: \(crib.count) B  rounds: \(rounds)")
    print("  hill-climb LFSR (pos+Walzenlage+center key known): \(climbLFSR.bestMatches)/\(crib.count) in \(String(format: "%.1f", climbLFSR.elapsedMs)) ms \(lfsrPressure ? "RECOVERY" : "no recovery")")
    print("  hill-climb positions (LFSR+Walzenlage+center key known): \(climbPos.bestMatches)/\(crib.count) in \(String(format: "%.1f", climbPos.elapsedMs)) ms \(posPressure ? "RECOVERY" : "no recovery")")
    if let joint = climbJoint {
        print("  hill-climb joint (day+center key known): \(joint.bestMatches)/\(crib.count) in \(String(format: "%.1f", joint.elapsedMs)) ms \(jointPressure ? "RECOVERY" : "no recovery")")
    }
    if lfsrPressure || posPressure || jointPressure {
        print("  red_pressure: true — full crib recovery in this bounded leak/search model; keep AEAD/control-plane tight")
        exit(2)
    } else {
        print("  red_pressure: false — no full recovery in this bounded structured-KPA run; not a security claim")
    }
}
