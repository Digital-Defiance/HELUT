import Foundation

// MARK: - Enigma 256 session wire framing (Apple Silicon / HELUT host)
//
// Length-prefixed records over any byte pipe. No Verilog — runs entirely in
// HELUTCore on the control plane, then SoftBus/AXI programs day keys locally.

package enum Enigma256WireError: Error, Equatable {
    case badMagic
    case truncated
    case unexpectedType(UInt8)
    case badHello
    case notConnected
    case closed
    case oversized(Int)
    case badAuth
    case hybridUnavailable
}

package enum Enigma256FrameType: UInt8, Sendable {
    case hello = 1
    case ack = 2
    case data = 3
    case bye = 4
    /// Passphrase mode: payload = salt only (no ECDH pubs).
    case pskHello = 5
    /// Hybrid X25519‖ML-KEM HELLO (signed when identity present).
    case hybridHello = 6
    /// Hybrid ACK carrying peer X25519 pub + ML-KEM ciphertext.
    case hybridAck = 7
}

/// On-wire unit: `E2W1` | type | u32be length | payload.
package struct Enigma256Frame: Sendable, Equatable {
    package static let magic = Data("E2W1".utf8)
    package static let maxPayload = 16 * 1024 * 1024

    package var type: Enigma256FrameType
    package var payload: Data

    package init(type: Enigma256FrameType, payload: Data = Data()) {
        self.type = type
        self.payload = payload
    }

    package func encode() -> Data {
        precondition(payload.count <= Self.maxPayload)
        var out = Self.magic
        out.append(type.rawValue)
        var len = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &len) { out.append(contentsOf: $0) }
        out.append(payload)
        return out
    }

    /// Parse one frame from the front of `buffer`, consuming it. Returns nil if incomplete.
    package static func parse(from buffer: inout Data) throws -> Enigma256Frame? {
        guard buffer.count >= 9 else { return nil }
        let magic = buffer.prefix(4)
        guard magic == Self.magic else { throw Enigma256WireError.badMagic }
        guard let type = Enigma256FrameType(rawValue: buffer[4]) else {
            throw Enigma256WireError.unexpectedType(buffer[4])
        }
        let len = buffer.subdata(in: 5 ..< 9).withUnsafeBytes { raw -> UInt32 in
            UInt32(bigEndian: raw.load(as: UInt32.self))
        }
        let payloadLen = Int(len)
        guard payloadLen <= Self.maxPayload else { throw Enigma256WireError.oversized(payloadLen) }
        guard buffer.count >= 9 + payloadLen else { return nil }
        let payload = buffer.subdata(in: 9..<(9 + payloadLen))
        buffer.removeSubrange(0..<(9 + payloadLen))
        return Enigma256Frame(type: type, payload: payload)
    }

    package static func hello(publicKey: Data, salt: Data) -> Enigma256Frame {
        precondition(publicKey.count == 32)
        precondition(salt.count <= 255)
        var payload = publicKey
        payload.append(UInt8(salt.count))
        payload.append(salt)
        return Enigma256Frame(type: .hello, payload: payload)
    }

    package static func parseHello(_ frame: Enigma256Frame) throws -> (pub: Data, salt: Data) {
        guard frame.type == .hello else { throw Enigma256WireError.unexpectedType(frame.type.rawValue) }
        guard frame.payload.count >= 33 else { throw Enigma256WireError.badHello }
        let pub = frame.payload.prefix(32)
        let saltLen = Int(frame.payload[32])
        guard frame.payload.count == 33 + saltLen else { throw Enigma256WireError.badHello }
        let salt = frame.payload.suffix(saltLen)
        return (Data(pub), Data(salt))
    }

    package static func ack(publicKey: Data) -> Enigma256Frame {
        precondition(publicKey.count == 32)
        return Enigma256Frame(type: .ack, payload: publicKey)
    }

    package static func pskHello(salt: Data) -> Enigma256Frame {
        precondition(salt.count <= 255)
        var payload = Data([UInt8(salt.count)])
        payload.append(salt)
        return Enigma256Frame(type: .pskHello, payload: payload)
    }

    package static func parsePSKHello(_ frame: Enigma256Frame) throws -> Data {
        guard frame.type == .pskHello else { throw Enigma256WireError.unexpectedType(frame.type.rawValue) }
        guard frame.payload.count >= 1 else { throw Enigma256WireError.badHello }
        let saltLen = Int(frame.payload[0])
        guard frame.payload.count == 1 + saltLen else { throw Enigma256WireError.badHello }
        return Data(frame.payload.suffix(saltLen))
    }

    /// ML-KEM-768 sizes (CryptoKit / FIPS 203).
    package static let mlkemPublicKeyLength = 1184
    package static let mlkemCiphertextLength = 1088
    package static let identityPublicKeyLength = 32
    package static let signatureLength = 64

    /// Hybrid HELLO: suite | x25519(32) | mlkem_pk(1184) | salt_len | salt | id(32) | sig(64)
    package static func hybridHello(
        suite: Enigma256KEMSuite = .x25519MLKEM768,
        x25519Public: Data,
        mlkemPublic: Data,
        salt: Data,
        identityPublic: Data,
        signature: Data
    ) -> Enigma256Frame {
        precondition(x25519Public.count == 32)
        precondition(mlkemPublic.count == mlkemPublicKeyLength)
        precondition(identityPublic.count == identityPublicKeyLength)
        precondition(signature.count == signatureLength)
        precondition(salt.count <= 255)
        var payload = Data([suite.rawValue])
        payload.append(x25519Public)
        payload.append(mlkemPublic)
        payload.append(UInt8(salt.count))
        payload.append(salt)
        payload.append(identityPublic)
        payload.append(signature)
        return Enigma256Frame(type: .hybridHello, payload: payload)
    }

    package static func parseHybridHello(_ frame: Enigma256Frame) throws -> (
        suite: Enigma256KEMSuite,
        x25519: Data,
        mlkemPublic: Data,
        salt: Data,
        identity: Data,
        signature: Data
    ) {
        guard frame.type == .hybridHello else {
            throw Enigma256WireError.unexpectedType(frame.type.rawValue)
        }
        let minLen = 1 + 32 + mlkemPublicKeyLength + 1 + identityPublicKeyLength + signatureLength
        guard frame.payload.count >= minLen else { throw Enigma256WireError.badHello }
        guard let suite = Enigma256KEMSuite(rawValue: frame.payload[0]),
              suite == .x25519MLKEM768
        else { throw Enigma256WireError.badHello }
        var i = 1
        let x25519 = frame.payload.subdata(in: i ..< (i + 32)); i += 32
        let mlkem = frame.payload.subdata(in: i ..< (i + mlkemPublicKeyLength)); i += mlkemPublicKeyLength
        let saltLen = Int(frame.payload[i]); i += 1
        guard frame.payload.count == i + saltLen + identityPublicKeyLength + signatureLength else {
            throw Enigma256WireError.badHello
        }
        let salt = frame.payload.subdata(in: i ..< (i + saltLen)); i += saltLen
        let identity = frame.payload.subdata(in: i ..< (i + identityPublicKeyLength)); i += identityPublicKeyLength
        let signature = frame.payload.subdata(in: i ..< (i + signatureLength))
        return (suite, x25519, mlkem, salt, identity, signature)
    }

    /// Hybrid ACK: suite | x25519(32) | mlkem_ct(1088) | id(32) | sig(64)
    package static func hybridAck(
        suite: Enigma256KEMSuite = .x25519MLKEM768,
        x25519Public: Data,
        mlkemCiphertext: Data,
        identityPublic: Data,
        signature: Data
    ) -> Enigma256Frame {
        precondition(x25519Public.count == 32)
        precondition(mlkemCiphertext.count == mlkemCiphertextLength)
        precondition(identityPublic.count == identityPublicKeyLength)
        precondition(signature.count == signatureLength)
        var payload = Data([suite.rawValue])
        payload.append(x25519Public)
        payload.append(mlkemCiphertext)
        payload.append(identityPublic)
        payload.append(signature)
        return Enigma256Frame(type: .hybridAck, payload: payload)
    }

    package static func parseHybridAck(_ frame: Enigma256Frame) throws -> (
        suite: Enigma256KEMSuite,
        x25519: Data,
        ciphertext: Data,
        identity: Data,
        signature: Data
    ) {
        guard frame.type == .hybridAck else {
            throw Enigma256WireError.unexpectedType(frame.type.rawValue)
        }
        let expect = 1 + 32 + mlkemCiphertextLength + identityPublicKeyLength + signatureLength
        guard frame.payload.count == expect else { throw Enigma256WireError.badHello }
        guard let suite = Enigma256KEMSuite(rawValue: frame.payload[0]),
              suite == .x25519MLKEM768
        else { throw Enigma256WireError.badHello }
        var i = 1
        let x25519 = frame.payload.subdata(in: i ..< (i + 32)); i += 32
        let ct = frame.payload.subdata(in: i ..< (i + mlkemCiphertextLength)); i += mlkemCiphertextLength
        let identity = frame.payload.subdata(in: i ..< (i + identityPublicKeyLength)); i += identityPublicKeyLength
        let signature = frame.payload.subdata(in: i ..< (i + signatureLength))
        return (suite, x25519, ct, identity, signature)
    }
}

// MARK: - Transport

package protocol Enigma256FrameTransport: AnyObject {
    func send(_ frame: Enigma256Frame) throws
    func receive() throws -> Enigma256Frame
}

/// Thread-safe in-process duplex (two peers on Apple Silicon, no sockets required).
package final class Enigma256InProcessPipe: Enigma256FrameTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var inbox = Data()
    private weak var peer: Enigma256InProcessPipe?
    private var closed = false

    package init() {}

    package static func paired() -> (Enigma256InProcessPipe, Enigma256InProcessPipe) {
        let a = Enigma256InProcessPipe()
        let b = Enigma256InProcessPipe()
        a.peer = b
        b.peer = a
        return (a, b)
    }

    package func send(_ frame: Enigma256Frame) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !closed, let peer else { throw Enigma256WireError.closed }
        peer.enqueue(frame.encode())
    }

    package func receive() throws -> Enigma256Frame {
        // Spin with short sleeps — fine for HELUT demos/tests (same process).
        for _ in 0 ..< 10_000 {
            lock.lock()
            if closed {
                lock.unlock()
                throw Enigma256WireError.closed
            }
            do {
                if let frame = try Enigma256Frame.parse(from: &inbox) {
                    lock.unlock()
                    return frame
                }
            } catch {
                lock.unlock()
                throw error
            }
            lock.unlock()
            Thread.sleep(forTimeInterval: 0.0005)
        }
        throw Enigma256WireError.truncated
    }

    private func enqueue(_ data: Data) {
        lock.lock()
        inbox.append(data)
        lock.unlock()
    }

    package func hangup() {
        lock.lock()
        closed = true
        lock.unlock()
        peer?.lock.lock()
        peer?.closed = true
        peer?.lock.unlock()
    }
}

// MARK: - Session peer (HELLO → ACK → DATA* → BYE)

package final class Enigma256WirePeer: @unchecked Sendable {
    package enum Role: Sendable {
        case initiator
        case responder
    }

    package private(set) var channel: Enigma256SecureChannel?
    /// Set by passphrase (PSK) handshake when ECDH is not used.
    package private(set) var pskContext: Enigma256Context?
    package private(set) var role: Role?
    /// Peer long-term identity observed during authenticated hybrid handshake.
    package private(set) var peerIdentityPublicKey: Data?
    private let local: Enigma256EphemeralIdentity
    private let transport: Enigma256FrameTransport
    /// Optional durable Ed25519 identity for MitM binding (hybrid path).
    package var identity: Enigma256Identity?
    /// When non-empty, peer identity must be in this set (otherwise TOFU / any).
    package var trustedIdentities: Set<Data> = []
    /// When true, DATA decrypt goes through SoftBus/AXI driver (HELUT local fabric model).
    package var decryptViaSoftBus: Bool

    package var activeContext: Enigma256Context? {
        pskContext ?? channel?.context
    }

    package init(
        transport: Enigma256FrameTransport,
        decryptViaSoftBus: Bool = true,
        identity: Enigma256Identity? = nil
    ) {
        self.transport = transport
        self.local = Enigma256EphemeralIdentity()
        self.decryptViaSoftBus = decryptViaSoftBus
        self.identity = identity
    }

    /// Initiator: HELLO(pub,salt) → wait ACK → open channel.
    package func handshakeAsInitiator(salt: Data = Data()) throws {
        role = .initiator
        try transport.send(.hello(publicKey: local.publicKeyRaw, salt: salt))
        let frame = try transport.receive()
        guard frame.type == .ack, frame.payload.count == 32 else {
            throw Enigma256WireError.unexpectedType(frame.type.rawValue)
        }
        channel = try Enigma256SecureChannel(local: local, peerPublicKeyRaw: frame.payload, salt: salt)
        pskContext = nil
    }

    /// Responder: wait HELLO → ACK(pub) → open channel with HELLO salt.
    package func handshakeAsResponder() throws {
        role = .responder
        let frame = try transport.receive()
        let hello = try Enigma256Frame.parseHello(frame)
        try transport.send(.ack(publicKey: local.publicKeyRaw))
        channel = try Enigma256SecureChannel(
            local: local,
            peerPublicKeyRaw: hello.pub,
            salt: hello.salt
        )
        pskContext = nil
    }

    /// Authenticated hybrid initiator: X25519 ‖ ML-KEM + Ed25519 (macOS 26+).
    /// Initiator publishes ML-KEM pub; responder encapsulates; initiator decapsulates.
    package func handshakeAsHybridInitiator(salt: Data = Data()) throws {
        guard #available(macOS 26.0, *) else { throw Enigma256WireError.hybridUnavailable }
        guard let identity else { throw Enigma256WireError.badAuth }
        role = .initiator

        let hybrid = try Enigma256HybridEphemeral()
        var ephBlob = hybrid.x25519.publicKeyRaw
        ephBlob.append(hybrid.mlkemPublicRaw)
        let transcript = Enigma256Transcript.handshake(
            role: "initiator",
            suite: Enigma256KEMSuite.x25519MLKEM768.rawValue,
            ephemeralBlob: ephBlob,
            salt: salt
        )
        let sig = try identity.sign(transcript)
        try transport.send(.hybridHello(
            x25519Public: hybrid.x25519.publicKeyRaw,
            mlkemPublic: hybrid.mlkemPublicRaw,
            salt: salt,
            identityPublic: identity.publicKeyRaw,
            signature: sig
        ))

        let ackFrame = try transport.receive()
        let ack = try Enigma256Frame.parseHybridAck(ackFrame)
        try enforceTrust(ack.identity)
        var ackBlob = ack.x25519
        ackBlob.append(ack.ciphertext)
        let ackTranscript = Enigma256Transcript.handshake(
            role: "responder",
            suite: ack.suite.rawValue,
            ephemeralBlob: ackBlob,
            salt: salt
        )
        do {
            try Enigma256Identity.verify(
                publicKeyRaw: ack.identity,
                message: ackTranscript,
                signature: ack.signature
            )
        } catch {
            throw Enigma256WireError.badAuth
        }
        peerIdentityPublicKey = ack.identity

        let ikm = try hybrid.respond(
            peerX25519Public: ack.x25519,
            ciphertext: ack.ciphertext,
            salt: salt
        )
        let ctx = Enigma256Context(ikm: ikm, salt: salt)
        channel = Enigma256SecureChannel(
            context: ctx,
            local: hybrid.x25519,
            peerPublicKeyRaw: ack.x25519,
            salt: salt
        )
        pskContext = nil
        hybrid.burn()
    }

    /// Authenticated hybrid responder (macOS 26+).
    package func handshakeAsHybridResponder() throws {
        guard #available(macOS 26.0, *) else { throw Enigma256WireError.hybridUnavailable }
        guard let identity else { throw Enigma256WireError.badAuth }
        role = .responder

        let helloFrame = try transport.receive()
        let hello = try Enigma256Frame.parseHybridHello(helloFrame)
        try enforceTrust(hello.identity)
        var helloBlob = hello.x25519
        helloBlob.append(hello.mlkemPublic)
        let helloTranscript = Enigma256Transcript.handshake(
            role: "initiator",
            suite: hello.suite.rawValue,
            ephemeralBlob: helloBlob,
            salt: hello.salt
        )
        do {
            try Enigma256Identity.verify(
                publicKeyRaw: hello.identity,
                message: helloTranscript,
                signature: hello.signature
            )
        } catch {
            throw Enigma256WireError.badAuth
        }
        peerIdentityPublicKey = hello.identity

        let hybrid = try Enigma256HybridEphemeral()
        let (ikm, ct) = try hybrid.initiate(
            peerX25519Public: hello.x25519,
            peerMLKEMPublic: hello.mlkemPublic,
            salt: hello.salt
        )
        var ackBlob = hybrid.x25519.publicKeyRaw
        ackBlob.append(ct)
        let ackTranscript = Enigma256Transcript.handshake(
            role: "responder",
            suite: Enigma256KEMSuite.x25519MLKEM768.rawValue,
            ephemeralBlob: ackBlob,
            salt: hello.salt
        )
        let sig = try identity.sign(ackTranscript)
        try transport.send(.hybridAck(
            x25519Public: hybrid.x25519.publicKeyRaw,
            mlkemCiphertext: ct,
            identityPublic: identity.publicKeyRaw,
            signature: sig
        ))

        let ctx = Enigma256Context(ikm: ikm, salt: hello.salt)
        channel = Enigma256SecureChannel(
            context: ctx,
            local: hybrid.x25519,
            peerPublicKeyRaw: hello.x25519,
            salt: hello.salt
        )
        pskContext = nil
        hybrid.burn()
    }

    private func enforceTrust(_ peerIdentity: Data) throws {
        guard !trustedIdentities.isEmpty else { return }
        guard trustedIdentities.contains(peerIdentity) else {
            throw Enigma256WireError.badAuth
        }
    }

    /// Passphrase initiator: PSK_HELLO(salt) → ACK → shared PBKDF2 context.
    package func handshakeAsPSKInitiator(
        passphrase: String,
        salt: Data = Enigma256Passphrase.randomSalt(),
        iterations: Int = Enigma256Passphrase.defaultIterations
    ) throws {
        role = .initiator
        try transport.send(.pskHello(salt: salt))
        let frame = try transport.receive()
        guard frame.type == .ack else {
            throw Enigma256WireError.unexpectedType(frame.type.rawValue)
        }
        pskContext = try Enigma256Passphrase.openContext(
            passphrase: passphrase,
            salt: salt,
            iterations: iterations
        )
        channel = nil
    }

    /// Passphrase responder: wait PSK_HELLO → ACK → PBKDF2 with announced salt.
    package func handshakeAsPSKResponder(
        passphrase: String,
        iterations: Int = Enigma256Passphrase.defaultIterations
    ) throws {
        role = .responder
        let frame = try transport.receive()
        let salt = try Enigma256Frame.parsePSKHello(frame)
        try transport.send(Enigma256Frame(type: .ack, payload: Data()))
        pskContext = try Enigma256Passphrase.openContext(
            passphrase: passphrase,
            salt: salt,
            iterations: iterations
        )
        channel = nil
    }

    package func sendPlaintext(_ plain: [UInt8], nonce: Data? = nil) throws {
        guard let ctx = activeContext else { throw Enigma256WireError.notConnected }
        let box: Enigma256SealedBox
        if let nonce {
            box = ctx.sealAEAD(plain, nonce: nonce)
        } else {
            box = ctx.seal(plain) // random nonce + AEAD
        }
        try transport.send(Enigma256Frame(type: .data, payload: box.encode()))
    }

    package func receivePlaintext() throws -> [UInt8] {
        guard let ctx = activeContext else { throw Enigma256WireError.notConnected }
        let frame = try transport.receive()
        switch frame.type {
        case .data:
            let box = try Enigma256SealedBox.decode(frame.payload)
            // Verify MAC before any FPGA / SoftBus stream (malleability defense).
            let plain = try ctx.openAEAD(box)
            if decryptViaSoftBus {
                let bus = Enigma256SoftBus()
                let drv = Enigma256AXIDriver(bus: bus)
                drv.setStreamJitter(true)
                drv.configure(context: ctx, nonce: box.nonce)
                let body = drv.transfer(box.ciphertext)
                // SoftBus body must match AEAD-opened plaintext.
                guard body == plain else { throw Enigma256WireError.badAuth }
                return body
            }
            return plain
        case .bye:
            burnSession()
            throw Enigma256WireError.closed
        default:
            throw Enigma256WireError.unexpectedType(frame.type.rawValue)
        }
    }

    package func close() throws {
        try transport.send(Enigma256Frame(type: .bye))
        burnSession()
    }

    private func burnSession() {
        channel?.burn()
        channel = nil
        pskContext = nil
    }
}

/// Run a full in-process session on Apple Silicon (initiator + responder).
package enum Enigma256WireSession {
    package static func runInProcess(
        messages: [[UInt8]],
        salt: Data = Data("helut-wire".utf8),
        decryptViaSoftBus: Bool = true
    ) throws -> [[UInt8]] {
        let (pipeA, pipeB) = Enigma256InProcessPipe.paired()
        let initiator = Enigma256WirePeer(transport: pipeA, decryptViaSoftBus: decryptViaSoftBus)
        let responder = Enigma256WirePeer(transport: pipeB, decryptViaSoftBus: decryptViaSoftBus)

        var received: [[UInt8]] = []
        let group = DispatchGroup()
        var responderError: Error?
        var initiatorError: Error?

        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            do {
                try responder.handshakeAsResponder()
                for _ in messages {
                    received.append(try responder.receivePlaintext())
                }
                do { _ = try responder.receivePlaintext() }
                catch Enigma256WireError.closed { /* ok */ }
            } catch {
                responderError = error
            }
        }

        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            do {
                try initiator.handshakeAsInitiator(salt: salt)
                for msg in messages {
                    try initiator.sendPlaintext(msg)
                }
                try initiator.close()
            } catch {
                initiatorError = error
            }
        }

        group.wait()
        if let initiatorError { throw initiatorError }
        if let responderError { throw responderError }
        pipeA.hangup()
        return received
    }

    /// In-process passphrase (PSK) session — no X25519.
    package static func runInProcessPSK(
        passphrase: String,
        messages: [[UInt8]],
        salt: Data = Enigma256Passphrase.randomSalt(),
        iterations: Int = Enigma256Passphrase.defaultIterations,
        decryptViaSoftBus: Bool = true
    ) throws -> [[UInt8]] {
        let (pipeA, pipeB) = Enigma256InProcessPipe.paired()
        let initiator = Enigma256WirePeer(transport: pipeA, decryptViaSoftBus: decryptViaSoftBus)
        let responder = Enigma256WirePeer(transport: pipeB, decryptViaSoftBus: decryptViaSoftBus)

        var received: [[UInt8]] = []
        let group = DispatchGroup()
        var responderError: Error?
        var initiatorError: Error?

        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            do {
                try responder.handshakeAsPSKResponder(passphrase: passphrase, iterations: iterations)
                for _ in messages {
                    received.append(try responder.receivePlaintext())
                }
                do { _ = try responder.receivePlaintext() }
                catch Enigma256WireError.closed {}
            } catch {
                responderError = error
            }
        }

        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            do {
                try initiator.handshakeAsPSKInitiator(
                    passphrase: passphrase,
                    salt: salt,
                    iterations: iterations
                )
                for msg in messages {
                    try initiator.sendPlaintext(msg)
                }
                try initiator.close()
            } catch {
                initiatorError = error
            }
        }

        group.wait()
        if let initiatorError { throw initiatorError }
        if let responderError { throw responderError }
        pipeA.hangup()
        return received
    }

    /// In-process authenticated hybrid session (X25519‖ML-KEM + Ed25519).
    @available(macOS 26.0, *)
    package static func runInProcessHybrid(
        messages: [[UInt8]],
        salt: Data = Data("helut-hybrid".utf8),
        decryptViaSoftBus: Bool = true,
        requireTrust: Bool = true
    ) throws -> [[UInt8]] {
        let (pipeA, pipeB) = Enigma256InProcessPipe.paired()
        let idA = Enigma256Identity()
        let idB = Enigma256Identity()
        let initiator = Enigma256WirePeer(transport: pipeA, decryptViaSoftBus: decryptViaSoftBus, identity: idA)
        let responder = Enigma256WirePeer(transport: pipeB, decryptViaSoftBus: decryptViaSoftBus, identity: idB)
        if requireTrust {
            initiator.trustedIdentities = [idB.publicKeyRaw]
            responder.trustedIdentities = [idA.publicKeyRaw]
        }

        var received: [[UInt8]] = []
        let group = DispatchGroup()
        var responderError: Error?
        var initiatorError: Error?

        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            do {
                try responder.handshakeAsHybridResponder()
                for _ in messages {
                    received.append(try responder.receivePlaintext())
                }
                do { _ = try responder.receivePlaintext() }
                catch Enigma256WireError.closed {}
            } catch {
                responderError = error
            }
        }

        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            do {
                try initiator.handshakeAsHybridInitiator(salt: salt)
                for msg in messages {
                    try initiator.sendPlaintext(msg)
                }
                try initiator.close()
            } catch {
                initiatorError = error
            }
        }

        group.wait()
        if let initiatorError { throw initiatorError }
        if let responderError { throw responderError }
        pipeA.hangup()
        return received
    }
}
