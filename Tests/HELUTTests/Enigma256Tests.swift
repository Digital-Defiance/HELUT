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
        // Reconfigure and decrypt (reciprocal).
        handle.configure(context: ctx, nonce: nonce)
        XCTAssertEqual(handle.transfer(box.ciphertext), plain)
        XCTAssertTrue(handle.transactionLog.contains(.loadState))
        XCTAssertGreaterThan(handle.transactionLog.count, 10 * 256)
    }
}
