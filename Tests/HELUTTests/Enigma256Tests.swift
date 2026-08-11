import XCTest
@testable import HELUTCore

final class Enigma256Tests: XCTestCase {

    func testLFSRMatchesVerilogFeedback() {
        var lfsr = Enigma256LFSR(seed: 1)
        // Manual Galois step: shift-left, XOR 0xD8… if former MSB set.
        XCTAssertEqual(lfsr.next, 2)
        lfsr.clock()
        XCTAssertEqual(lfsr.state, 2)

        // Seed with MSB set → feedback engages.
        lfsr = Enigma256LFSR(seed: 1 << 63)
        XCTAssertEqual(lfsr.next, 0xD800_0000_0000_0000)
    }

    func testIdentityWiringIsReciprocalAndSteps() {
        var enc = Enigma256Machine(
            wiring: .identity,
            lfsrSeed: 0x0123_4567_89AB_CDEF,
            positions: (1, 2, 3, 4)
        )
        var dec = enc
        let plain: [UInt8] = Array(0 ... 255) + [0xA5, 0x5A, 0x00, 0xFF]
        let cipher = enc.process(plain)
        let recovered = dec.process(cipher)
        XCTAssertEqual(recovered, plain)
        // Identity tables cancel entry/exit offsets, so the stream is plaintext;
        // reciprocity still holds and LFSR/offsets still advance.
        XCTAssertEqual(cipher, plain)
        XCTAssertNotEqual(enc.lfsr.state, 0x0123_4567_89AB_CDEF)
    }

    func testScrambleBeforeStepParity() {
        var m = Enigma256Machine(
            wiring: .identity,
            lfsrSeed: 0x8000_0000_0000_0001,
            positions: (0, 0, 0, 0)
        )
        // With identity tables and zero offsets, scramble is identity before step.
        XCTAssertEqual(m.scramble(0x42), 0x42)
        let steps = m.lfsr.stepMask
        m.step()
        XCTAssertEqual(m.lfsr.state, Enigma256LFSR(seed: 0x8000_0000_0000_0001).next)
        if steps.0 { XCTAssertEqual(m.offsetR1, 1) } else { XCTAssertEqual(m.offsetR1, 0) }
    }

    func testHKDFDayAndMessageRoundTrip() {
        let master = Data("helut-enigma256-test-ikm-32bytes!!".utf8)
        let day = Enigma256KDF.deriveDayKey(ikm: master, salt: Data("salt".utf8))
        XCTAssertEqual(day.rotorPoolFwd.count, 16)
        XCTAssertTrue(isInvolution(day.plugboard))
        XCTAssertTrue(isInvolution(day.reflector))
        for i in 0 ..< 16 {
            XCTAssertTrue(isInverse(day.rotorPoolFwd[i], day.rotorPoolRev[i]))
        }

        let nonce = Data((0 ..< 16).map { UInt8($0) ^ 0xA5 })
        let msg = Enigma256KDF.deriveMessageKey(masterIKM: master, nonce: nonce)
        XCTAssertNotEqual(msg.lfsrSeed, 0)

        var enc = Enigma256Machine(day: day, message: msg)
        var dec = Enigma256Machine(day: day, message: msg)
        let plain = Array("ENIGMA256 polymorphic stream cipher golden".utf8)
        let cipher = enc.process(plain)
        XCTAssertNotEqual(cipher, plain)
        XCTAssertEqual(dec.process(cipher), plain)
    }

    func testDistinctNoncesYieldDistinctCiphertext() {
        let master = Data(repeating: 0x11, count: 32)
        let day = Enigma256KDF.deriveDayKey(ikm: master)
        let plain = Array(repeating: UInt8(0x55), count: 64)

        let m0 = Enigma256KDF.deriveMessageKey(masterIKM: master, nonce: Data(repeating: 0, count: 12))
        let m1 = Enigma256KDF.deriveMessageKey(masterIKM: master, nonce: Data(repeating: 1, count: 12))
        XCTAssertNotEqual(m0.lfsrSeed, m1.lfsrSeed)

        var a = Enigma256Machine(day: day, message: m0)
        var b = Enigma256Machine(day: day, message: m1)
        XCTAssertNotEqual(a.process(plain), b.process(plain))
    }

    func testPlugboardInvolutionProperty() {
        let entropy = Data((0 ..< 512).map { UInt8(truncatingIfNeeded: $0 &* 17 &+ 3) })
        let pb = Enigma256KDF.involution(from: entropy, allowFixedPoints: false)
        XCTAssertTrue(isInvolution(pb))
        // No fixed points when allowFixedPoints is false (perfect matching).
        for i in 0 ..< 256 {
            XCTAssertNotEqual(Int(pb[i]), i)
        }
    }

    // MARK: - Helpers

    private func isInvolution(_ t: [UInt8]) -> Bool {
        guard t.count == 256 else { return false }
        for i in 0 ..< 256 {
            if Int(t[Int(t[i])]) != i { return false }
        }
        return true
    }

    private func isInverse(_ fwd: [UInt8], _ rev: [UInt8]) -> Bool {
        guard fwd.count == 256, rev.count == 256 else { return false }
        for i in 0 ..< 256 {
            if Int(rev[Int(fwd[i])]) != i { return false }
            if Int(fwd[Int(rev[i])]) != i { return false }
        }
        return true
    }

    func testGoldenBundleRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("enigma256-golden-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let session = Enigma256Bridge.makeGoldenSession()
        _ = try Enigma256Bridge.writeGoldenBundle(session: session, to: dir)
        let loaded = try Enigma256Bridge.loadAndVerify(bundle: dir)
        XCTAssertEqual(loaded.ciphertext, session.ciphertext)
        XCTAssertEqual(loaded.plaintext, session.plaintext)
        XCTAssertEqual(loaded.wiring.plugboard, session.wiring.plugboard)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("tb_params.vh").path))
        let vh = try String(contentsOf: dir.appendingPathComponent("tb_params.vh"), encoding: .utf8)
        XCTAssertTrue(
            vh.contains(String(format: "%016llx", session.message.lfsrSeed)),
            "tb_params.vh must embed the full 64-bit LFSR seed"
        )
    }

    func testTableSelCoversTenBRAMs() {
        XCTAssertEqual(Enigma256TableSel.allCases.count, 10)
        let w = Enigma256Wiring.identity
        for sel in Enigma256TableSel.allCases {
            XCTAssertEqual(Enigma256Bridge.table(w, sel: sel).count, 256)
        }
    }

    func testSessionSealOpenRoundTrip() throws {
        let ctx = Enigma256Context(ikm: Data("session-api-ikm-32-bytes!!!!!!".utf8), salt: Data("s".utf8))
        let plain = Array("control-plane seal/open".utf8)
        let box = ctx.seal(plain, nonce: Data(repeating: 0x42, count: 16))
        XCTAssertNotEqual(box.ciphertext, plain)
        XCTAssertEqual(ctx.open(box), plain)

        let encoded = box.encode()
        let decoded = try Enigma256SealedBox.decode(encoded)
        XCTAssertEqual(decoded.nonce, box.nonce)
        XCTAssertEqual(ctx.open(decoded), plain)
    }

    func testCoreHandleMatchesContextSeal() {
        let ctx = Enigma256Context(ikm: Data(repeating: 0xAB, count: 32))
        let nonce = Data((0 ..< 12).map { UInt8($0) })
        let plain = Array("AXI bitbang parity".utf8)
        let box = ctx.seal(plain, nonce: nonce)

        let handle = Enigma256CoreHandle()
        handle.configure(context: ctx, nonce: nonce)
        XCTAssertEqual(handle.transfer(plain), box.ciphertext)
        handle.configure(context: ctx, nonce: nonce)
        XCTAssertEqual(handle.transfer(box.ciphertext), plain)
        XCTAssertTrue(handle.transactionLog.contains(.loadState))
        XCTAssertTrue(handle.transactionLog.contains(.tableBurst(byteCount: 10 * 256)))
    }

    func testAXISoftBusMatchesContextSeal() {
        let ctx = Enigma256Context(ikm: Data("axi-softbus-ikm-32-bytes!!!!!!!".utf8))
        let nonce = Data(repeating: 0x7E, count: 16)
        let plain = Array("register-map bring-up vector".utf8)
        let want = ctx.seal(plain, nonce: nonce).ciphertext

        let bus = Enigma256SoftBus()
        let drv = Enigma256AXIDriver(bus: bus)
        drv.configure(context: ctx, nonce: nonce)
        XCTAssertEqual(drv.transfer(plain), want)

        // Reciprocal via same MMIO path.
        drv.configure(context: ctx, nonce: nonce)
        XCTAssertEqual(drv.transfer(want), plain)
        XCTAssertEqual(bus.lastBurstBytes, 10 * 256)
    }

    func testAXIRegOffsetsMatchDoc() {
        XCTAssertEqual(Enigma256Reg.ctrl.offset, 0x00)
        XCTAssertEqual(Enigma256Reg.wrData.offset, 0x0C)
        XCTAssertEqual(Enigma256Reg.dataIn.offset, 0x28)
        XCTAssertEqual(Enigma256Reg.status.offset, 0x30)
        XCTAssertEqual(Enigma256Reg.scaCtrl.offset, 0x34)
        XCTAssertEqual(Enigma256Reg.burstStatus.offset, 0x38)
    }

    func testECDHPairedChannelsSealOpenAndBurn() throws {
        let (alice, bob) = try Enigma256Handshake.paired(salt: Data("session-salt".utf8))
        XCTAssertEqual(alice.context?.ikm, bob.context?.ikm)
        XCTAssertEqual(alice.local.publicKeyRaw.count, 32)

        let plain = Array("ecdh control-plane plaintext".utf8)
        let box = try alice.seal(plain, nonce: Data(repeating: 0x11, count: 16))
        XCTAssertEqual(try bob.open(box), plain)
        XCTAssertEqual(try alice.open(box), plain)

        // Distinct peer keys → distinct IKM.
        let (carol, _) = try Enigma256Handshake.paired()
        XCTAssertNotEqual(alice.context?.ikm, carol.context?.ikm)

        alice.burn()
        bob.burn()
        XCTAssertTrue(alice.isBurned)
        XCTAssertThrowsError(try alice.seal(plain)) { err in
            XCTAssertEqual(err as? Enigma256ECDHError, .burned)
        }
    }

    func testECDHFeedsAXISoftBus() throws {
        let (alice, bob) = try Enigma256Handshake.paired()
        let nonce = Data(repeating: 0x5A, count: 12)
        let plain = Array("ecdh→axi day-key".utf8)
        let box = try alice.seal(plain, nonce: nonce)

        let bus = Enigma256SoftBus()
        let drv = Enigma256AXIDriver(bus: bus)
        drv.configure(context: bob.context!, nonce: nonce)
        XCTAssertEqual(drv.transfer(box.ciphertext), plain)
    }

    func testWireFrameRoundTrip() throws {
        var buf = Data()
        let frame = Enigma256Frame.hello(publicKey: Data(repeating: 0xAB, count: 32), salt: Data("xy".utf8))
        buf.append(frame.encode())
        let parsed = try Enigma256Frame.parse(from: &buf)
        XCTAssertTrue(buf.isEmpty)
        let hello = try Enigma256Frame.parseHello(parsed!)
        XCTAssertEqual(hello.pub.count, 32)
        XCTAssertEqual(hello.salt, Data("xy".utf8))
    }

    func testWireInProcessSessionSoftBus() throws {
        let messages: [[UInt8]] = [
            Array("first wire datagram".utf8),
            Array("second".utf8),
            Array(repeating: 0x7F, count: 64)
        ]
        let got = try Enigma256WireSession.runInProcess(messages: messages, decryptViaSoftBus: true)
        XCTAssertEqual(got, messages)
    }

    func testWireInProcessSessionChannelOnly() throws {
        let messages = [Array("no softbus path".utf8)]
        let got = try Enigma256WireSession.runInProcess(messages: messages, decryptViaSoftBus: false)
        XCTAssertEqual(got, messages)
    }

    func testTCPLocalhostSession() throws {
        let port = UInt16.random(in: 26000 ... 26999)
        let plain = Array("tcp localhost softbus".utf8)
        let gate = DispatchGroup()
        var serverError: Error?
        var clientError: Error?
        var received: [UInt8]?

        gate.enter()
        DispatchQueue.global().async {
            defer { gate.leave() }
            do {
                let transport = try Enigma256TCPTransport.accept(port: port, timeout: 20)
                defer { transport.close() }
                let peer = Enigma256WirePeer(transport: transport, decryptViaSoftBus: true)
                try peer.handshakeAsResponder()
                received = try peer.receivePlaintext()
                do { _ = try peer.receivePlaintext() }
                catch Enigma256WireError.closed {}
            } catch {
                serverError = error
            }
        }

        Thread.sleep(forTimeInterval: 0.3)

        gate.enter()
        DispatchQueue.global().async {
            defer { gate.leave() }
            do {
                let transport = try Enigma256TCPTransport.connect(host: "127.0.0.1", port: port, timeout: 10)
                defer { transport.close() }
                let peer = Enigma256WirePeer(transport: transport, decryptViaSoftBus: true)
                try peer.handshakeAsInitiator(salt: Data("tcp-test".utf8))
                try peer.sendPlaintext(plain)
                try peer.close()
            } catch {
                clientError = error
            }
        }

        let ok = gate.wait(timeout: .now() + 30)
        XCTAssertEqual(ok, .success)
        XCTAssertNil(serverError, "server: \(String(describing: serverError))")
        XCTAssertNil(clientError, "client: \(String(describing: clientError))")
        XCTAssertEqual(received, plain)
    }

    func testPassphrasePBKDF2DeterministicAndDistinct() throws {
        let salt = Data("fixed-salt-16b!!".utf8)
        let a = try Enigma256Passphrase.deriveIKM(passphrase: "correct horse", salt: salt, iterations: 10_000)
        let b = try Enigma256Passphrase.deriveIKM(passphrase: "correct horse", salt: salt, iterations: 10_000)
        let c = try Enigma256Passphrase.deriveIKM(passphrase: "wrong battery", salt: salt, iterations: 10_000)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 64)
        XCTAssertNotEqual(a, c)
    }

    func testPassphraseContextSealOpen() throws {
        let salt = Data("ctx-salt".utf8)
        let ctx = try Enigma256Passphrase.openContext(
            passphrase: "helut-demo-pass",
            salt: salt,
            iterations: 8_000
        )
        let plain = Array("pbkdf2 sealed".utf8)
        let box = ctx.seal(plain, nonce: Data(repeating: 9, count: 16))
        XCTAssertEqual(ctx.open(box), plain)
    }

    func testWireInProcessPSKSession() throws {
        let messages = [Array("psk wire datagram".utf8)]
        let got = try Enigma256WireSession.runInProcessPSK(
            passphrase: "shared-secret-phrase",
            messages: messages,
            salt: Data("psk-salt-bytes!!".utf8),
            iterations: 5_000,
            decryptViaSoftBus: true
        )
        XCTAssertEqual(got, messages)
    }

    func testHKDFUsesSHA512Chunking() {
        let okm = Enigma256KDF.hkdf(
            ikm: Data("ikm".utf8),
            salt: Data("salt".utf8),
            info: Data("info".utf8),
            length: 256 * 64
        )
        XCTAssertEqual(okm.count, 256 * 64)
        XCTAssertNotEqual(Data(okm.prefix(64)), Data(okm.suffix(64)))
    }

    func testHybridX25519MLKEMPaired() throws {
        guard #available(macOS 26.0, *) else { return }
        let salt = Data("hybrid-salt".utf8)
        let (alice, bob) = try Enigma256HybridHandshake.paired(salt: salt)
        XCTAssertEqual(alice.context?.ikm, bob.context?.ikm)
        XCTAssertEqual(alice.context?.ikm.count, 64)
        let plain = Array("hybrid pq seal".utf8)
        let box = try alice.seal(plain, nonce: Data(repeating: 3, count: 16))
        XCTAssertEqual(try bob.open(box), plain)
        alice.burn()
        bob.burn()
    }

    func testXWingPairedIKM() throws {
        guard #available(macOS 26.0, *) else { return }
        let (a, b) = try Enigma256XWingHandshake.paired(salt: Data("xwing".utf8))
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 64)
    }

    func testEd25519IdentityBindsTranscript() throws {
        let id = Enigma256Identity()
        let msg = Enigma256Transcript.handshake(
            role: "initiator",
            suite: 2,
            ephemeralBlob: Data(repeating: 1, count: 64),
            salt: Data("s".utf8)
        )
        let sig = try id.sign(msg)
        try Enigma256Identity.verify(publicKeyRaw: id.publicKeyRaw, message: msg, signature: sig)
        XCTAssertThrowsError(
            try Enigma256Identity.verify(
                publicKeyRaw: id.publicKeyRaw,
                message: Data("tampered".utf8),
                signature: sig
            )
        )
    }

    func testWireInProcessHybridAuthenticated() throws {
        guard #available(macOS 26.0, *) else { return }
        let messages = [Array("hybrid wire datagram".utf8), Array("two".utf8)]
        let got = try Enigma256WireSession.runInProcessHybrid(
            messages: messages,
            decryptViaSoftBus: true,
            requireTrust: true
        )
        XCTAssertEqual(got, messages)
    }

    func testNLFFStepMaskNotRawBits() {
        // Known state where raw bit0=1 but NLFF (bit0 & bit7) ^ bit12 may differ.
        let lfsr = Enigma256LFSR(seed: 0b1) // only bit 0 set
        let rawBit0 = true
        let nlff = (true && false) != false // (0&7)^12 = 0
        XCTAssertEqual(lfsr.stepMask.0, nlff)
        XCTAssertNotEqual(lfsr.stepMask.0, rawBit0)
    }

    func testAEADRejectsBitFlip() throws {
        let ctx = Enigma256Context(ikm: Data(repeating: 0x5A, count: 32), salt: Data("mac".utf8))
        let plain = Array("authenticated payload".utf8)
        var box = ctx.sealAEAD(plain, nonce: Data(repeating: 1, count: 16))
        XCTAssertEqual(try ctx.openAEAD(box), plain)
        box.ciphertext[0] ^= 0x01
        XCTAssertThrowsError(try ctx.openAEAD(box)) { err in
            XCTAssertEqual(err as? Enigma256AEADError, .authenticationFailed)
        }
    }

    func testProtectedSessionNonceReuseRejected() throws {
        let session = Enigma256ProtectedSession(ikm: Data(repeating: 0x11, count: 32))
        let nonce = Data(repeating: 0x22, count: 16)
        _ = try session.seal(Array("a".utf8), nonce: nonce)
        XCTAssertThrowsError(try session.seal(Array("b".utf8), nonce: nonce)) { err in
            XCTAssertEqual(err as? Enigma256AEADError, .nonceReused)
        }
        let box = try session.seal(Array("c".utf8))
        XCTAssertEqual(box.tag?.count, 32)
        XCTAssertEqual(try session.open(box), Array("c".utf8))
    }

    func testAEADContainerRoundTrip() throws {
        let ctx = Enigma256Context(ikm: Data("aead-container-ikm-32-bytes!!!!".utf8))
        let box = ctx.seal(Array("v2".utf8))
        let decoded = try Enigma256SealedBox.decode(box.encode())
        XCTAssertEqual(decoded.tag?.count, 32)
        XCTAssertEqual(try ctx.openAEAD(decoded), Array("v2".utf8))
    }
}
