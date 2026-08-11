import Foundation
import HELUTCore

// MARK: - Enigma 256 golden dump (`--enigma256-golden`)

func runEnigma256Golden() {
    _ = Enigma256Generation.bootstrapFromFixture()
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

// MARK: - Enigma 256 Red/Blue campaign (`--enigma256-campaign`)
//
// Field = Apple Silicon SoftBus + HELUT TensorLUT. No Zynq required.

struct Enigma256TensorLUTScore: Sendable {
    var finalCrypto: Double?
    var squeezeSurvived: Bool?
    var path: String

    var redPressure: Bool {
        guard let c = finalCrypto, let s = squeezeSurvived else { return false }
        return s && c <= 1e-6
    }
}

func enigma256ParseTensorLUTLog(at path: String) -> Enigma256TensorLUTScore {
    var score = Enigma256TensorLUTScore(finalCrypto: nil, squeezeSurvived: nil, path: path)
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return score }
    for line in text.split(whereSeparator: \.isNewline) {
        let s = String(line)
        if s.hasPrefix("final_crypto:") {
            let t = s.dropFirst("final_crypto:".count).trimmingCharacters(in: .whitespaces)
            score.finalCrypto = Double(t)
        } else if s.hasPrefix("squeeze_survived:") {
            let t = s.dropFirst("squeeze_survived:".count).trimmingCharacters(in: .whitespaces).lowercased()
            score.squeezeSurvived = (t == "true" || t == "1" || t == "yes")
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
        let msg = Enigma256MessageKey(rotorIndices: rotors, positions: positions, lfsrSeed: seed)
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
    let crib = Array((stringFlag("--enigma256-plain") ?? "HELUT Enigma256 SoftBus Red/Blue crib").utf8)

    let genesURL = URL(fileURLWithPath: genesPath)
    var generation: Enigma256Generation
    if FileManager.default.fileExists(atPath: genesPath) {
        do {
            generation = try Enigma256Generation.load(from: genesURL)
        } catch {
            fputs("Failed to load genes \(genesPath): \(error)\n", stderr)
            exit(2)
        }
    } else {
        generation = .gen0
    }
    generation.activate()

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

    let tensor = enigma256ParseTensorLUTLog(at: tensorLog)
    let redPressure = softPressure || tensor.redPressure

    print("Enigma 256 Red/Blue campaign (Apple Silicon SoftBus field)")
    print("  generation: \(generation.id) formula=\(generation.formula.rawValue)")
    let foldDesc = generation.folds.map { fold -> String in
        let taps = fold.taps(for: generation.formula).map(String.init).joined(separator: ",")
        return "(\(taps))"
    }.joined(separator: " ")
    print("  folds: \(foldDesc)")
    print("  SoftBus KPA: best \(soft.bestMatches)/\(crib.count) over \(soft.trials) trials in \(String(format: "%.1f", soft.elapsedMs)) ms")
    if let c = tensor.finalCrypto, let s = tensor.squeezeSurvived {
        print("  TensorLUT: final_crypto=\(String(format: "%.6f", c)) squeeze_survived=\(s) (\(tensor.path))")
        if generation.id != 0 {
            print("  note: TensorLUT log may predate generation \(generation.id) — re-run Scripts/enigma256_tensorlut.sh")
        }
    } else {
        print("  TensorLUT: no score in \(tensor.path) (run Scripts/enigma256_tensorlut.sh)")
    }
    print("  red_pressure: \(redPressure) (soft=\(softPressure) tensor=\(tensor.redPressure))")

    var mutated = false
    var nextGen = generation
    // Explicit --mutate on quadratic3 always structural-hardens to cubic6.
    if forceMutate || (allowMutate && (redPressure || generation.formula == .quadratic3)) {
        if generation.formula == .quadratic3 {
            nextGen = generation.hardenedCubic()
        } else {
            nextGen = generation.mutated(rng: &rng)
        }
        nextGen.activate()
        do {
            try FileManager.default.createDirectory(
                at: genesURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try nextGen.save(to: genesURL)
            let combo = nextGen.emitNLFFComboVerilog()
            try combo.write(toFile: "enigma_256_nlff_combo.v", atomically: true, encoding: .utf8)
            for path in ["enigma_256_core.v", "enigma_256_step_cone.v"] {
                let src = try String(contentsOfFile: path, encoding: .utf8)
                try nextGen.rewritingNLFF(in: src).write(toFile: path, atomically: true, encoding: .utf8)
            }
            mutated = true
            print("  Blue mutate → generation \(nextGen.id) (genes + NLFF Verilog rewritten)")
            do {
                let session = Enigma256Bridge.makeGoldenSession()
                _ = try Enigma256Bridge.writeGoldenBundle(
                    session: session,
                    to: URL(fileURLWithPath: "Fixtures/enigma256_golden", isDirectory: true)
                )
                print("  golden fixtures regenerated under generation \(nextGen.id)")
            } catch {
                fputs("  warning: golden regenerate failed: \(error)\n", stderr)
            }
            print("  Next: ./Scripts/enigma256_sim.sh && ./Scripts/enigma256_tensorlut.sh")
        } catch {
            fputs("Blue mutate failed: \(error)\n", stderr)
            exit(1)
        }
    } else if redPressure {
        print("  Blue hold — red pressure present; re-run with --enigma256-campaign-mutate to roll genes")
    } else {
        print("  Blue hold — SoftBus KPA did not recover; TensorLUT pressure absent or unscored")
    }

    // JSONL ledger row
    let row: [String: Any] = [
        "ts": ISO8601DateFormatter().string(from: Date()),
        "generation": generation.id,
        "next_generation": nextGen.id,
        "mutated": mutated,
        "soft_best_matches": soft.bestMatches,
        "soft_length": crib.count,
        "soft_trials": soft.trials,
        "soft_ms": soft.elapsedMs,
        "soft_pressure": softPressure,
        "tensor_final_crypto": tensor.finalCrypto as Any,
        "tensor_squeeze_survived": tensor.squeezeSurvived as Any,
        "tensor_pressure": tensor.redPressure,
        "red_pressure": redPressure,
        "folds": generation.folds.map { ["a": $0.a, "b": $0.b, "c": $0.c] }
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
