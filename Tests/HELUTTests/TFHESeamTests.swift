import XCTest
import Metal
import MetalPerformanceShadersGraph
@testable import HELUTCore

final class TFHESeamTests: XCTestCase {
    func testTrivialEncodingsRoundTrip() {
        for kind in TrivialBitEncodingKind.allCases {
            let enc = kind.makeEncoding(degree: 8)
            for bit: UInt32 in [0, 1] {
                XCTAssertEqual(enc.decodeBit(enc.encodeBit(bit)), bit, "kind=\(kind)")
            }
        }
        let phase = TrivialPhaseEncoding(degree: 4).encodeBit(1)
        XCTAssertEqual(phase, [1, 0, 0, 0])
        let fill = TrivialConstantFillEncoding(degree: 4).encodeBit(1)
        XCTAssertEqual(fill, [1, 1, 1, 1])
        let glwe = TrivialGLWEEncoding(degree: 4).encodeBit(1)
        XCTAssertEqual(glwe, phase)
    }

    func testGLWESampleEncryptExtractDecrypt() {
        let params = TFHEParams(polynomialDegree: 8, glweDimension: 1, delta: 1)
        let enc = TrivialGLWEEncoding(params: params)
        for bit: UInt32 in [0, 1] {
            let ct = enc.encryptBit(bit)
            XCTAssertEqual(ct.mask.count, 1)
            XCTAssertTrue(ct.mask[0].allSatisfy { $0 == 0 })
            XCTAssertEqual(ct.body[0], bit)
            XCTAssertEqual(enc.decryptBit(ct), bit)
            XCTAssertEqual(enc.decodeBit(enc.encodeBit(bit)), bit)

            let lwe = sampleExtractLWE(ct, params: params)
            XCTAssertEqual(lwe.a.count, params.lweDimension)
            XCTAssertTrue(lwe.a.allSatisfy { $0 == 0 })
            XCTAssertEqual(lwe.b, bit)
        }

        // k=2 trivial: mask still zero, extract doubles a length.
        let params2 = TFHEParams(polynomialDegree: 4, glweDimension: 2, delta: 1)
        let ct2 = GLWECiphertext.trivial(bit: 1, params: params2)
        let lwe2 = sampleExtractLWE(ct2, params: params2)
        XCTAssertEqual(lwe2.a.count, 8)
        XCTAssertEqual(lwe2.b, 1)
    }

    func testDatapathConfigs() {
        XCTAssertEqual(HELUTDatapathConfig.booleanSafeTrivial.encodingKind, .constantFill)
        XCTAssertEqual(HELUTDatapathConfig.booleanSafePhase.encodingKind, .phase)
        XCTAssertEqual(HELUTDatapathConfig.booleanSafeGLWE.encodingKind, .glweTrivial)
        XCTAssertEqual(HELUTDatapathConfig.booleanSafeGLWEPacked.encodingKind, .glwePacked)
        XCTAssertEqual(HELUTDatapathConfig.clearShapeBoolean.encodingDegree, 1)
        XCTAssertTrue(LUTEvaluationBackend.multilinear.isBooleanSafeUnderTrivialEncoding)
        XCTAssertTrue(LUTEvaluationBackend.programmableBootstrap.isImplemented)
        XCTAssertTrue(LUTEvaluationBackend.programmableBootstrap.isBooleanSafeUnderTrivialEncoding)
        HELUTDatapathConfig.booleanSafeTrivial.assertRunnable()
        HELUTDatapathConfig.booleanSafePhase.assertRunnable()
        HELUTDatapathConfig.booleanSafeGLWE.assertRunnable()
        HELUTDatapathConfig.booleanSafeGLWEPacked.assertRunnable()
        HELUTDatapathConfig.clearShapeBoolean.assertRunnable()
        XCTAssertTrue(LUTEvaluationBackend.programmableBootstrapGGSW.isImplemented)
        XCTAssertTrue(LUTEvaluationBackend.programmableBootstrapGGSW.usesPBSMetalSubgraph)
        HELUTDatapathConfig(
            encodingDegree: 64,
            encodingKind: .glweTrivial,
            lutBackend: .programmableBootstrapGGSW
        ).assertRunnable()
    }

    func testPBSStubTestPolynomial() {
        let poly = ProgrammableBootstrapStub.testPolynomial(
            truthTable: [0, 1, 1, 0],
            degree: 8,
            delta: 7
        )
        XCTAssertEqual(poly, [0, 7, 7, 0, 0, 0, 0, 0])
    }

    func testNegacyclicMultiplyByXPower() {
        // X * (1 + 2X + 3X^2) in N=3 → (-3, 1, 2)
        let p: [UInt32] = [1, 2, 3]
        XCTAssertEqual(negacyclicMultiplyByXPower(p, power: 1), [UInt32(0) &- 3, 1, 2])
        // X^{-1} ≡ -X^{2}: (-X²)(1+2X+3X²) = 2 + 3X − X²
        XCTAssertEqual(
            negacyclicMultiplyByXPower(p, power: -1),
            [2, 3, UInt32(0) &- 1]
        )
        XCTAssertEqual(negacyclicMultiplyByXPower(p, power: 0), p)
    }

    func testGLWEEncryptDecryptNonZeroSecret() {
        let params = TFHEParams(polynomialDegree: 16, glweDimension: 1, delta: 1)
        let secret = TFHESecretKey.random(params: params, seed: 0x5EED)
        var rng = LCG32(state: 42)
        for bit: UInt32 in [0, 1] {
            var message = [UInt32](repeating: 0, count: 16)
            message[0] = bit
            let ct = encryptGLWE(message: message, secret: secret, rng: &rng)
            XCTAssertFalse(ct.mask[0].allSatisfy { $0 == 0 }, "expected non-zero mask")
            let plain = decryptGLWE(ct, secret: secret)
            XCTAssertEqual(plain[0], bit)
            for i in 1..<16 {
                XCTAssertEqual(plain[i], 0)
            }
        }
    }

    func testPBSGGSWNonZeroSecretCryptoGadget() {
        let degree = 8
        let table: [UInt32] = [0, 1, 1, 0]
        var msg = [UInt32](repeating: 0, count: degree)
        msg[0] = 1
        msg[2] = 1

        for params in [GGSWParams.booleanTrivial(degree: degree), .crypto(degree: degree)] {
            let secret = TFHESecretKey.random(params: params.tfhe, seed: 0xB0B)
            var rng = LCG32(state: 99)
            let ggsw1 = encryptGGSW(bit: 1, secret: secret, params: params, rng: &rng)
            let ggsw0 = encryptGGSW(bit: 0, secret: secret, params: params, rng: &rng)

            let ctFlat = encryptGLWETrivialMask(message: msg, secret: secret)
            XCTAssertEqual(decryptGLWE(externalProduct(ggsw1, ctFlat), secret: secret), msg)
            XCTAssertEqual(
                decryptGLWE(externalProduct(ggsw0, ctFlat), secret: secret),
                [UInt32](repeating: 0, count: degree)
            )

            let ctMasked = encryptGLWE(message: msg, secret: secret, rng: &rng)
            XCTAssertEqual(decryptGLWE(externalProduct(ggsw1, ctMasked), secret: secret), msg)

            for mask in 0..<4 {
                let inputs: [UInt32] = [UInt32(mask & 1), UInt32((mask >> 1) & 1)]
                let want = evaluateMultilinearLUT(truthTable: table, inputs: inputs)
                let got = evaluatePBSGGSW(
                    truthTable: table,
                    inputs: inputs,
                    secret: secret,
                    params: params,
                    rng: &rng
                )
                XCTAssertEqual(got, want, "\(params.baseLog)/\(params.levelCount) inputs=\(inputs)")
            }
        }
    }

    func testTrivialPBSOracleMatchesMultilinear() {
        let tables: [[UInt32]] = [
            [0, 1],           // identity / NOT depends on inputs
            [0, 1, 1, 0],     // XOR
            [0, 0, 0, 1],     // AND
            [0, 1, 1, 1],     // OR
            [0, 0, 0, 1, 0, 1, 1, 1] // majority-ish
        ]
        for table in tables {
            let width = table.count.trailingZeroBitCount
            let degree = max(8, table.count)
            let ggswParams = GGSWParams.booleanTrivial(degree: degree)
            for mask in 0..<table.count {
                var inputs: [UInt32] = []
                for i in 0..<width {
                    inputs.append(UInt32((mask >> i) & 1))
                }
                let want = evaluateMultilinearLUT(truthTable: table, inputs: inputs)
                let got = evaluateTrivialPBS(
                    truthTable: table,
                    inputs: inputs,
                    degree: degree
                )
                XCTAssertEqual(got, want, "pbs table=\(table) inputs=\(inputs)")
                let gotGGSW = evaluateTrivialPBSGGSW(
                    truthTable: table,
                    inputs: inputs,
                    params: ggswParams
                )
                XCTAssertEqual(gotGGSW, want, "pbs-ggsw table=\(table) inputs=\(inputs)")
            }
        }
    }

    func testGGSWExternalProductAndCMux() {
        let params = GGSWParams.booleanTrivial(degree: 8)
        let one = trivialEncryptGGSW(bit: 1, params: params)
        let zero = trivialEncryptGGSW(bit: 0, params: params)
        var msg = [UInt32](repeating: 0, count: 8)
        msg[0] = 1
        msg[3] = 1
        let ct = GLWECiphertext(
            mask: [[UInt32](repeating: 0, count: 8)],
            body: msg
        )
        let timesOne = externalProduct(one, ct)
        XCTAssertEqual(timesOne.body, msg)
        let timesZero = externalProduct(zero, ct)
        XCTAssertTrue(timesZero.body.allSatisfy { $0 == 0 })

        let d0 = zeroGLWE(params: params.tfhe)
        var d1Body = [UInt32](repeating: 0, count: 8)
        d1Body[0] = 1
        let d1 = GLWECiphertext(mask: d0.mask, body: d1Body)
        XCTAssertEqual(cmuxGGSW(one, d1: d1, d0: d0).body[0], 1)
        XCTAssertEqual(cmuxGGSW(zero, d1: d1, d0: d0).body[0], 0)
    }

    func testBlindRotateAndKeySwitchTrivial() {
        let params = GGSWParams.booleanTrivial(degree: 8)
        let test = ProgrammableBootstrapStub.testPolynomial(
            truthTable: [0, 1],
            degree: 8,
            delta: 1
        )
        let bk = trivialBootstrapKey(lweDimension: params.tfhe.lweDimension, params: params)
        for bit: UInt32 in [0, 1] {
            let lwe = LWECiphertext.trivial(bit: bit, params: params.tfhe)
            let rotated = blindRotateTrivial(testPolynomial: test, lwe: lwe, bootstrapKey: bk)
            let extracted = sampleExtractLWE(rotated, params: params.tfhe)
            let switched = keySwitch(extracted, key: .trivialIdentity(dimension: params.tfhe.lweDimension))
            XCTAssertEqual(switched.b, bit)
        }
    }

    func testMetalGGSWExternalProductAndCMux() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device")
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw XCTSkip("No MTLCommandQueue")
        }

        let degree = 8
        let params = GGSWParams.booleanTrivial(degree: degree)
        let secret = TFHESecretKey.random(params: params.tfhe, seed: 0x507A1)
        var rng = LCG32(state: 1234)

        var msg = [UInt32](repeating: 0, count: degree)
        msg[0] = 1
        msg[3] = 1

        let ggsw1 = encryptGGSW(bit: 1, secret: secret, params: params, rng: &rng)
        let ggsw0 = encryptGGSW(bit: 0, secret: secret, params: params, rng: &rng)

        let ctFlat = encryptGLWETrivialMask(message: msg, secret: secret)
        let metalFlat1 = try MetalGGSW.externalProduct(
            ggsw: ggsw1,
            ciphertext: ctFlat,
            device: device,
            commandQueue: commandQueue
        )
        XCTAssertEqual(decryptGLWE(metalFlat1, secret: secret), msg)

        let metalFlat0 = try MetalGGSW.externalProduct(
            ggsw: ggsw0,
            ciphertext: ctFlat,
            device: device,
            commandQueue: commandQueue
        )
        XCTAssertEqual(
            decryptGLWE(metalFlat0, secret: secret),
            [UInt32](repeating: 0, count: degree)
        )

        let ctMasked = encryptGLWE(message: msg, secret: secret, rng: &rng)
        let metalMasked = try MetalGGSW.externalProduct(
            ggsw: ggsw1,
            ciphertext: ctMasked,
            device: device,
            commandQueue: commandQueue
        )
        XCTAssertEqual(decryptGLWE(metalMasked, secret: secret), msg)

        var d0msg = [UInt32](repeating: 0, count: degree)
        d0msg[0] = 1
        var d1msg = [UInt32](repeating: 0, count: degree)
        d1msg[1] = 1
        let d0 = encryptGLWETrivialMask(message: d0msg, secret: secret)
        let d1 = encryptGLWETrivialMask(message: d1msg, secret: secret)
        let metalCmux1 = try MetalGGSW.cmux(
            control: ggsw1,
            d1: d1,
            d0: d0,
            device: device,
            commandQueue: commandQueue
        )
        let metalCmux0 = try MetalGGSW.cmux(
            control: ggsw0,
            d1: d1,
            d0: d0,
            device: device,
            commandQueue: commandQueue
        )
        XCTAssertEqual(decryptGLWE(metalCmux1, secret: secret), d1msg)
        XCTAssertEqual(decryptGLWE(metalCmux0, secret: secret), d0msg)

        let packed = GLWEPack.pack(ctMasked)
        let unpacked = GLWEPack.unpack(packed, polynomialDegree: degree, glweDimension: 1)
        XCTAssertEqual(unpacked, ctMasked)
    }

    func testMetalGGSWMatchesCPUExternalProduct() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device")
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw XCTSkip("No MTLCommandQueue")
        }
        let degree = 16
        let params = GGSWParams.booleanTrivial(degree: degree)
        let secret = TFHESecretKey.random(params: params.tfhe, seed: 0xC0DE)
        var rng = LCG32(state: 7)
        var msg = [UInt32](repeating: 0, count: degree)
        for i in 0..<degree where i % 3 == 0 {
            msg[i] = 1
        }
        let ct = encryptGLWE(message: msg, secret: secret, rng: &rng)
        let ggsw = encryptGGSW(bit: 1, secret: secret, params: params, rng: &rng)
        let cpu = externalProduct(ggsw, ct)
        let metal = try MetalGGSW.externalProduct(
            ggsw: ggsw,
            ciphertext: ct,
            device: device,
            commandQueue: commandQueue
        )
        XCTAssertEqual(cpu, metal, "Metal packed GGSW ⋉ must match CPU ciphertext")
        XCTAssertEqual(decryptGLWE(metal, secret: secret), msg)
    }

    func testMetalGGSWCryptoGadgetMatchesCPU() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device")
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw XCTSkip("No MTLCommandQueue")
        }
        let degree = 8
        let params = GGSWParams.crypto(degree: degree)
        let secret = TFHESecretKey.random(params: params.tfhe, seed: 0xC4E1)
        var rng = LCG32(state: 11)
        var msg = [UInt32](repeating: 0, count: degree)
        msg[0] = 1
        msg[2] = 1
        let ct = encryptGLWE(message: msg, secret: secret, rng: &rng)
        let ggsw = encryptGGSW(bit: 1, secret: secret, params: params, rng: &rng)
        let cpu = externalProduct(ggsw, ct)
        let metal = try MetalGGSW.externalProduct(
            ggsw: ggsw,
            ciphertext: ct,
            device: device,
            commandQueue: commandQueue
        )
        XCTAssertEqual(cpu, metal)
        XCTAssertEqual(decryptGLWE(metal, secret: secret), msg)
    }

    func testRealKeySwitchBetweenSecrets() {
        let n = 16
        var rng = LCG32(state: 42)
        let from = (0..<n).map { _ in rng.next() & 1 }
        let to = (0..<n).map { _ in rng.next() & 1 }
        let ksk = makeKeySwitchKey(from: from, to: to, baseLog: 8, levelCount: 4, rng: &rng)
        for message: UInt32 in [0, 1, 7, 100, 0xFFFF_0001] {
            let ct = encryptLWE(message: message, secret: from, rng: &rng)
            let switched = keySwitch(ct, key: ksk)
            var phase = switched.b
            for i in 0..<to.count {
                phase &-= switched.a[i] &* to[i]
            }
            XCTAssertEqual(phase, message, "KS failed for message \(message)")
        }
    }

    func testExtractKeySwitchClosesPBSWhenNLessThanKN() {
        let degree = 32
        let lweN = 8
        let params = GGSWParams.booleanPublicMS(degree: degree).withLWEDimension(lweN)
        let secret = TFHESecretKey.random(params: params.tfhe, seed: 0xE5E5)
        var rng = LCG32(state: 0x51)
        let bk = bootstrapKey(
            secret: secret,
            params: params,
            rng: &rng,
            publicRefreshCompatible: true
        )
        let ksk = extractToLWEKeySwitchKey(secret: secret, rng: &rng)
        XCTAssertFalse(ksk.isIdentity)
        XCTAssertEqual(ksk.inputDimension, degree)
        XCTAssertEqual(ksk.outputDimension, lweN)
        let twoN = 2 * degree
        let scale = rotationScale(polynomialDegree: degree)
        for bit: UInt32 in [0, 1] {
            let ct = encryptLWERotationNative(
                message: bit,
                secret: secret.lweSecret,
                twoN: twoN,
                rng: &rng
            )
            XCTAssertEqual(ct.lweDimension, lweN)
            let out = evaluateLUTBlindRotate(
                truthTable: [0, 1],
                inputs: [ct],
                bootstrapKey: bk,
                scale: scale,
                keySwitchKey: ksk
            )
            XCTAssertEqual(out.lweDimension, lweN)
            let torusPhase = decryptLWE(out, secret: secret)
            XCTAssertEqual(
                decodeRotationBoolean(torusPhase, scale: scale),
                bit,
                "torus decrypt after KS failed for bit \(bit) phase=\(torusPhase)"
            )
            let refreshed = publicRefreshBit(out, twoN: twoN, scale: scale)
            XCTAssertEqual(refreshed.lweDimension, lweN)
            let phase = decryptLWE(refreshed, secret: secret)
            XCTAssertEqual(decodeRotationNativeBit(phase, twoN: twoN, k: 1), bit)
            let chained = evaluateLUTBlindRotate(
                truthTable: [0, 1],
                inputs: [refreshed],
                bootstrapKey: bk,
                scale: scale,
                keySwitchKey: ksk
            )
            let chainedPhase = decryptLWE(
                publicRefreshBit(chained, twoN: twoN, scale: scale),
                secret: secret
            )
            XCTAssertEqual(decodeRotationNativeBit(chainedPhase, twoN: twoN, k: 1), bit)
        }
    }

    func testPackedGLWEEncodingRoundTrip() {
        let enc = PackedGLWEEncoding(polynomialDegree: 8)
        XCTAssertEqual(enc.degree, 16)
        for bit: UInt32 in [0, 1] {
            XCTAssertEqual(enc.decodeBit(enc.encodeBit(bit)), bit)
        }
        XCTAssertEqual(TrivialBitEncodingKind.glwePacked.wireWidth(polynomialDegree: 32), 64)
    }

    func testDiscreteNoiseGLWERoundTrip() {
        let params = TFHEParams.noisyBoolean(degree: 8, deltaLog: 20)
        let secret = TFHESecretKey.random(params: params, seed: 0xA015)
        var rng = LCG32(state: 99)
        for bit: UInt32 in [0, 1] {
            var msg = [UInt32](repeating: 0, count: params.polynomialDegree)
            msg[0] = bit &* params.delta
            let ct = encryptGLWE(
                message: msg,
                secret: secret,
                rng: &rng,
                noise: .demo
            )
            XCTAssertFalse(ct.mask[0].allSatisfy { $0 == 0 }, "mask should be non-trivial")
            let phase = decryptGLWE(ct, secret: secret)[0]
            let err = phase &- (bit &* params.delta)
            // Centered residual magnitude < Δ/4.
            let mag = min(err, UInt32(0) &- err)
            XCTAssertLessThan(mag, params.delta / 4)
            XCTAssertEqual(decodeBooleanPhase(phase, delta: params.delta), bit)
        }
        let noise = TFHENoise.sample(count: 32, params: .demo, rng: &rng)
        XCTAssertEqual(noise.count, 32)
        for e in noise {
            let mag = min(e, UInt32(0) &- e)
            XCTAssertLessThanOrEqual(mag, TFHENoiseParams.demo.bound)
        }
    }

    func testEncryptedPackedGLWERoundTrip() {
        let params = TFHEParams.noisyBoolean(degree: 8, deltaLog: 20)
        let secret = TFHESecretKey.random(params: params, seed: 0xA61C)
        let state = EncryptedPackedGLWEState(secret: secret, noise: .demo, seed: 0xE11C)
        let enc = EncryptedPackedGLWEEncoding(state: state)
        XCTAssertEqual(enc.degree, 16)
        for bit: UInt32 in [0, 1] {
            let packed = enc.encodeBit(bit)
            XCTAssertEqual(packed.count, 16)
            XCTAssertFalse(packed.prefix(8).allSatisfy { $0 == 0 })
            XCTAssertEqual(enc.decodeBit(packed), bit)
            let ct = enc.encryptBit(bit)
            XCTAssertEqual(enc.decryptBit(ct), bit)
        }
    }

    func testMetalGGSWEvaluatePBSMatchesCPU() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device")
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw XCTSkip("No MTLCommandQueue")
        }
        let degree = 8
        let params = GGSWParams.crypto(degree: degree)
        let secret = TFHESecretKey.random(params: params.tfhe, seed: 0xB551)
        let truth: [UInt32] = [0, 1, 1, 0] // XOR
        for x in 0...1 {
            for y in 0...1 {
                var rngCPU = LCG32(state: UInt32(0xC000 &+ x &* 3 &+ y))
                var rngMetal = LCG32(state: UInt32(0xC000 &+ x &* 3 &+ y))
                let inputs: [UInt32] = [UInt32(x), UInt32(y)]
                let cpu = evaluatePBSGGSW(
                    truthTable: truth,
                    inputs: inputs,
                    secret: secret,
                    params: params,
                    rng: &rngCPU
                )
                let metal = try MetalGGSW.evaluatePBS(
                    truthTable: truth,
                    inputs: inputs,
                    secret: secret,
                    params: params,
                    device: device,
                    commandQueue: commandQueue,
                    rng: &rngMetal
                )
                let clear = evaluateMultilinearLUT(truthTable: truth, inputs: inputs)
                XCTAssertEqual(cpu, clear, "cpu XOR x=\(x) y=\(y)")
                XCTAssertEqual(metal, clear, "metal XOR x=\(x) y=\(y)")
                XCTAssertEqual(metal, cpu)
            }
        }
    }

    func testMultilinearOracleXOR() {
        XCTAssertEqual(
            evaluateMultilinearLUT(truthTable: [0, 1, 1, 0], inputs: [1, 1]),
            0
        )
        XCTAssertEqual(
            evaluateMultilinearLUT(truthTable: [0, 1, 1, 0], inputs: [0, 1]),
            1
        )
    }

    /// Metal trivial PBS full adder ≡ cleartext under all trivial encodings.
    func testTrivialPBSFullAdderMatchesCleartext() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device")
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw XCTSkip("No MTLCommandQueue")
        }
        guard let path = resolvePBSRepoFile("netlist.json") else {
            return XCTFail("netlist.json not found")
        }

        let netlist = loadYosysNetlist(from: path)
        guard let (moduleName, module) = netlist.modules.first else {
            return XCTFail("Empty netlist")
        }

        for encoding in TrivialBitEncodingKind.allCases {
            for backend in [LUTEvaluationBackend.programmableBootstrap, .programmableBootstrapGGSW] {
            let degree = 32
            let compiler = YosysGraphCompiler(
                degree: degree,
                batch: 1,
                encodingKind: encoding,
                lutBackend: backend
            )
            compiler.compile(moduleName: moduleName, module: module)
            let clear = CleartextNetlistSimulator(moduleName: moduleName, module: module)

            for a in 0...1 {
                for b in 0...1 {
                    for cin in 0...1 {
                        let clearOut = clear.tick(inputs: [
                            "a": [UInt8(a)],
                            "b": [UInt8(b)],
                            "cin": [UInt8(cin)]
                        ])
                        let metal = try evaluatePBSCombinational(
                            compiler: compiler,
                            device: device,
                            commandQueue: commandQueue,
                            inputs: [
                                "a": [UInt32(a)],
                                "b": [UInt32(b)],
                                "cin": [UInt32(cin)]
                            ]
                        )
                        XCTAssertEqual(
                            metal["sum"],
                            [UInt32(clearOut["sum"]?[0] ?? 255)],
                            "sum encoding=\(encoding) backend=\(backend) a=\(a) b=\(b) cin=\(cin)"
                        )
                        XCTAssertEqual(
                            metal["cout"],
                            [UInt32(clearOut["cout"]?[0] ?? 255)],
                            "cout encoding=\(encoding) backend=\(backend) a=\(a) b=\(b) cin=\(cin)"
                        )
                    }
                }
            }
            }
        }
    }

    func testPublicModulusSwitchAfterBlindRotate() {
        // publicRefreshBit folds PBS-extracted LWE into Z_{2N} for the next BR.
        let degree = 8
        let params = GGSWParams.booleanTrivial(degree: degree)
        let secret = TFHESecretKey.random(params: params.tfhe, seed: 0xA501)
        var rng = LCG32(state: 0xA502)
        let bk = bootstrapKey(secret: secret, params: params, rng: &rng)
        let twoN = 2 * degree
        let scale = rotationScale(polynomialDegree: degree)
        let lx = encryptLWERotationNative(
            message: 1, secret: secret.lweSecret, twoN: twoN, rng: &rng
        )
        let ly = encryptLWERotationNative(
            message: 0, secret: secret.lweSecret, twoN: twoN, rng: &rng
        )
        let extracted = evaluateLUTBlindRotate(
            truthTable: [0, 1, 1, 0], inputs: [lx, ly], bootstrapKey: bk, scale: scale
        )
        XCTAssertEqual(decodeRotationBoolean(decryptLWE(extracted, secret: secret), scale: scale), 1)
        let refreshed = publicRefreshBit(extracted, twoN: twoN, scale: scale)
        XCTAssertEqual(refreshed.lweDimension, extracted.lweDimension)
        let id = evaluateLUTBlindRotate(
            truthTable: [0, 1], inputs: [refreshed], bootstrapKey: bk, scale: scale
        )
        XCTAssertEqual(decodeRotationBoolean(decryptLWE(id, secret: secret), scale: scale), 1)
    }

    func testNoiseBudgetTracksBlindRotate() {
        var budget = TFHENoiseBudget(capacity: 10)
        budget.consume(.encrypt)
        budget.consume(.blindRotateLevel)
        budget.consume(.blindRotateLevel)
        budget.consume(.sampleExtract)
        XCTAssertEqual(budget.remaining, 6)
        XCTAssertTrue(budget.isSafe)
        XCTAssertEqual(HELUTDatapathConfig.encryptedBlindRotate.lutBackend, .encryptedBlindRotate)
    }

    func testNoiseGrowthBoundedAccounting() {
        var g = TFHENoiseGrowth(bound: 0, delta: 1 << 20)
        XCTAssertTrue(g.isDecodable)
        g.setEncrypt(noise: .demo) // bound 64
        XCTAssertEqual(g.bound, 64)
        XCTAssertTrue(g.isDecodable)

        // Homomorphic adds without PBS eventually exceed Δ/2.
        var acc = g
        for _ in 0..<10_000 {
            acc.afterAdd(g)
        }
        XCTAssertFalse(acc.isDecodable)
        XCTAssertEqual(acc.remainingMargin, 0)

        // PBS refreshes to the BK noise floor.
        acc.afterBlindRotate(outputNoiseBound: 0)
        XCTAssertTrue(acc.isDecodable)
        XCTAssertEqual(acc.bound, 0)

        var ms = TFHENoiseGrowth(bound: 10, delta: 1 << 20)
        ms.afterExactModulusSwitch()
        XCTAssertEqual(ms.bound, 10)
        ms.afterApproxModulusSwitch(lweDimension: 8)
        // +4 * delta — far above half-gap
        XCTAssertFalse(ms.isDecodable)
    }

    func testNoiseProofCoreLemmas() {
        XCTAssertTrue(
            TFHENoiseProof.verifyCoreLemmas(degree: 8, seed: 0xF001),
            "bounded noise lemmas must hold under HELUT hypotheses"
        )
    }

    func testNoiseCertificateFullAdder() throws {
        guard let path = resolvePBSRepoFile("netlist.json") else {
            return XCTFail("netlist.json not found")
        }
        let netlist = loadYosysNetlist(from: path)
        guard let (moduleName, module) = netlist.modules.first else {
            return XCTFail("Empty netlist")
        }
        let degree = 8
        let params = GGSWParams.crypto(degree: degree)
        let secret = TFHESecretKey.random(params: params.tfhe, seed: 0xC001)
        let enc = EncryptedNetlistSimulator(
            moduleName: moduleName,
            module: module,
            secret: secret,
            params: params,
            backend: .blindRotate,
            wireRefresh: .publicMS,
            inputNoise: .demo,
            scaledPrimaryInputs: true,
            seed: 0xC002
        )
        let cert = enc.issueNoiseCertificate()
        XCTAssertEqual(cert.inputNoiseBound, TFHENoiseParams.demo.bound)
        XCTAssertEqual(clearLUTCount(enc), 3)
        XCTAssertGreaterThanOrEqual(cert.steps.count, 5)
        XCTAssertTrue(cert.isDecodable)
        cert.assertValid()
        XCTAssertTrue(
            cert.hypotheses.contains(where: { $0.contains("inputNoiseBound") })
        )

        let clear = CleartextNetlistSimulator(moduleName: moduleName, module: module)
        let inputs: [String: [UInt8]] = ["a": [1], "b": [1], "cin": [0]]
        let want = clear.tick(inputs: inputs)
        let got = try enc.tick(inputs: inputs)
        XCTAssertEqual(got["sum"], want["sum"])
        XCTAssertEqual(got["cout"], want["cout"])
        XCTAssertNotNil(enc.noiseCertificate)
        XCTAssertNotNil(enc.asymptoticCertificate)
        XCTAssertTrue(enc.asymptoticCertificate!.isSecure)
        XCTAssertEqual(enc.noiseGrowth.bound, 0)
        XCTAssertTrue(enc.noiseGrowth.isDecodable)
    }

    func testGaussianAsymptoticProductionCertificate() {
        let prod = TFHEGaussianParams.productionBoolean64(polynomialDegree: 1024)
        let cert = TFHEAsymptoticSecurityCertificate.forEncryptedNetlist(
            params: prod,
            inputWireCount: 3,
            lutCount: 3
        )
        XCTAssertTrue(cert.isSecure, "P≈2^\(cert.failureLog2) should be ≤ 2^{-64}")
        XCTAssertLessThanOrEqual(cert.failureLog2, -64)
        cert.assertSecure()

        let demo = TFHEGaussianParams.demoBoolean64(polynomialDegree: 8)
        let demoCert = TFHEAsymptoticSecurityCertificate.forEncryptedNetlist(
            params: demo,
            inputWireCount: 3,
            lutCount: 3
        )
        XCTAssertTrue(demoCert.isSecure)

        // Tail sanity: σ = half-gap ⇒ P(|e|≥half) is O(1), not production-secure.
        let loose = TFHEGaussianParams(
            sigma: Double(demo.delta) / 2,
            delta: demo.delta,
            lweDimension: 8,
            polynomialDegree: 8,
            targetFailureLog2: -64
        )
        let bad = TFHEAsymptoticSecurityCertificate.forEncryptedNetlist(
            params: loose,
            inputWireCount: 3,
            lutCount: 3
        )
        XCTAssertFalse(bad.isSecure)
    }

    func testDynamicRotateCostBinaryBeatsMux() {
        let twoN = 2048 // N=1024
        let n = 1024
        let mux = MetalGGSW.DynamicRotateCost.muxRotates(twoN: twoN, lweDimension: n)
        let bin = MetalGGSW.DynamicRotateCost.binaryRotates(twoN: twoN, lweDimension: n)
        XCTAssertEqual(mux, (n + 1) * twoN)
        XCTAssertEqual(bin, (n + 1) * 11) // log2(2048)=11
        XCTAssertLessThan(bin * 100, mux) // >100× fewer static rotates
    }

    func testLWEHardnessCertificate128() {
        let cert = TFHELWEProduction.certificate128()
        XCTAssertGreaterThanOrEqual(cert.estimatedClassicalBits, 128)
        XCTAssertTrue(cert.meetsTarget)
        cert.assertMeetsTarget()
        XCTAssertTrue(cert.hypotheses.contains(where: { $0.contains("Decision-LWE") }))

        // Tiny demo params are not 128-bit hard — certificate must report that.
        let demo = TFHELWEHardnessCertificate.forHELUTEncrypt(
            gaussian: .demoBoolean64(polynomialDegree: 8),
            targetSecurityBits: 128
        )
        XCTAssertFalse(demo.meetsTarget)
    }

    func testLWEHardnessCalibrationTable() {
        XCTAssertTrue(
            TFHELWECalibration.isCalibrated(),
            "HELUT estimate drifted from calibration anchors:\n\(TFHELWECalibration.markdownTable())"
        )
        let prod = TFHELWECalibration.anchors.first { $0.label == "prod-n1024-s16" }
        XCTAssertNotNil(prod)
        XCTAssertGreaterThanOrEqual(prod!.helutEstimateBits, 128)
        let demo = TFHELWECalibration.anchors.first { $0.label == "demo-N8" }
        XCTAssertNotNil(demo)
        XCTAssertLessThan(demo!.helutEstimateBits, 128)
        // Export / markdown stay non-empty for docs / canvas sync.
        XCTAssertFalse(TFHELWECalibration.markdownTable().isEmpty)
        XCTAssertEqual(TFHELWECalibration.exportRows().count, TFHELWECalibration.anchors.count)
    }

    func testNoisyBKDepthCertificate() {
        let quiet = TFHENoisyBKCertificate.forNetlist(
            params: .noiseless(polynomialDegree: 1024, lutCount: 64)
        )
        XCTAssertTrue(quiet.meetsHELUTNoiselessHypothesis)
        XCTAssertTrue(quiet.eachLUTDecodable)
        XCTAssertTrue(quiet.unboundedDepthUnderPublicMS)
        quiet.assertDecodable()

        let noisyOK = TFHENoisyBKCertificate.forNetlist(
            params: .bounded(outputNoiseBound: 1 << 18, polynomialDegree: 1024, lutCount: 8)
        )
        // δ(N=1024)=2^20, half=2^19; B=2^18 < half
        XCTAssertTrue(noisyOK.eachLUTDecodable)

        let noisyBad = TFHENoisyBKCertificate.forNetlist(
            params: .bounded(outputNoiseBound: 1 << 20, polynomialDegree: 1024, lutCount: 8)
        )
        XCTAssertFalse(noisyBad.eachLUTDecodable)

        let g0 = TFHENoisyBKGaussianCertificate.forDepth(
            sigmaBK: 0,
            polynomialDegree: 1024,
            lutCount: 100
        )
        XCTAssertTrue(g0.isSecure)

        let gLoud = TFHENoisyBKGaussianCertificate.forDepth(
            sigmaBK: Double(1 << 19),
            polynomialDegree: 1024,
            lutCount: 100
        )
        XCTAssertFalse(gLoud.isSecure)
    }

    func testNoisyBKIdentityMeasurement() {
        let degree = 8
        // Covering gadget (baseLog·ℓ = 32, g₀ = δ). ℓ=1 booleanPublicMS is a
        // noiseless-lattice vehicle — BK noise leaves the δ lattice and later
        // CMUXes mis-decompose.
        let params = GGSWParams.cryptoPublicMS(degree: degree)
        XCTAssertEqual(params.baseLog * params.levelCount, 32)
        let secret = TFHESecretKey.random(params: params.tfhe, seed: 0xB401)
        let quiet = TFHENoisyBKMeasurement.identity(
            secret: secret,
            params: params,
            noise: .none,
            trials: 8,
            seed: 0xB402
        )
        XCTAssertEqual(quiet.maxAbsError, 0)
        XCTAssertEqual(quiet.sigmaHat, 0)
        XCTAssertEqual(quiet.decodeFailures, 0)
        XCTAssertTrue(quiet.eachLUTDecodable)
        let quietCert = quiet.certificate(lutCount: 3)
        XCTAssertTrue(quietCert.meetsHELUTNoiselessHypothesis)
        XCTAssertTrue(quietCert.hypotheses.contains(where: { $0.contains("measured") }))
        XCTAssertTrue(quiet.gaussianCertificate(lutCount: 8).isSecure)

        let noisy = TFHENoisyBKMeasurement.identity(
            secret: secret,
            params: params,
            noise: .demo,
            trials: 8,
            seed: 0xB403
        )
        XCTAssertGreaterThan(noisy.maxAbsError, 0)
        XCTAssertGreaterThan(noisy.sigmaHat, 0)
        XCTAssertEqual(noisy.decodeFailures, 0)
        XCTAssertTrue(noisy.eachLUTDecodable)
        XCTAssertLessThan(noisy.maxAbsError, noisy.decodingHalfGap)
        let noisyCert = noisy.certificate(lutCount: 3)
        XCTAssertFalse(noisyCert.meetsHELUTNoiselessHypothesis)
        XCTAssertTrue(noisyCert.eachLUTDecodable)
        XCTAssertTrue(noisy.gaussianCertificate(lutCount: 8).isSecure)
    }

    func testEncryptedNetlistFullAdderWithNoisyBK() throws {
        guard let path = resolvePBSRepoFile("netlist.json") else {
            return XCTFail("netlist.json not found")
        }
        let netlist = loadYosysNetlist(from: path)
        guard let (moduleName, module) = netlist.modules.first else {
            return XCTFail("Empty netlist")
        }
        let degree = 8
        let params = GGSWParams.cryptoPublicMS(degree: degree)
        let secret = TFHESecretKey.random(params: params.tfhe, seed: 0xB411)
        let enc = EncryptedNetlistSimulator(
            moduleName: moduleName,
            module: module,
            secret: secret,
            params: params,
            backend: .blindRotate,
            wireRefresh: .publicMS,
            bkNoise: .demo,
            seed: 0xB412
        )
        let clear = CleartextNetlistSimulator(moduleName: moduleName, module: module)
        for a in 0...1 {
            for b in 0...1 {
                for cin in 0...1 {
                    let inputs: [String: [UInt8]] = [
                        "a": [UInt8(a)],
                        "b": [UInt8(b)],
                        "cin": [UInt8(cin)]
                    ]
                    let want = clear.tick(inputs: inputs)
                    let got = try enc.tick(inputs: inputs)
                    XCTAssertEqual(got["sum"], want["sum"], "sum a=\(a) b=\(b) cin=\(cin)")
                    XCTAssertEqual(got["cout"], want["cout"], "cout a=\(a) b=\(b) cin=\(cin)")
                }
            }
        }
        XCTAssertNotNil(enc.noisyBKMeasurement)
        XCTAssertGreaterThan(enc.noisyBKMeasurement!.maxAbsError, 0)
        XCTAssertEqual(enc.noisyBKMeasurement!.decodeFailures, 0)
        XCTAssertNotNil(enc.noisyBKCertificate)
        XCTAssertEqual(
            enc.noisyBKCertificate!.params.outputNoiseBound,
            enc.noisyBKMeasurement!.maxAbsError
        )
        XCTAssertTrue(enc.noisyBKCertificate!.eachLUTDecodable)
        XCTAssertFalse(enc.noisyBKCertificate!.meetsHELUTNoiselessHypothesis)
        XCTAssertNotNil(enc.noisyBKGaussianCertificate)
        XCTAssertTrue(enc.noisyBKGaussianCertificate!.isSecure)
    }

    func testLWEEstimatorProtocolPending() {
        let rows = TFHELWEEstimatorProtocol.pendingTable()
        XCTAssertEqual(rows.count, TFHELWECalibration.anchors.count)
        XCTAssertTrue(rows.allSatisfy { !$0.verified })
        XCTAssertFalse(TFHELWEEstimatorProtocol.allVerifiedWithinTolerance(rows))
        let merged = TFHELWEEstimatorProtocol.mergeExternal(
            Dictionary(uniqueKeysWithValues: rows.map { ($0.label, $0.helutBits) })
        )
        XCTAssertTrue(merged.allSatisfy(\.verified))
        XCTAssertTrue(TFHELWEEstimatorProtocol.allVerifiedWithinTolerance(merged))
        XCTAssertTrue(TFHELWEEstimatorProtocol.exportPendingJSON().contains("helut_bits"))
    }

    func testCoreSVPModelFillsEstimatorColumn() {
        let filled = TFHELWECoreSVPModel.fillEstimatorRows()
        XCTAssertTrue(filled.allSatisfy(\.verified))
        XCTAssertTrue(TFHELWECoreSVPModel.agreesWithHELUT())
        let prod = filled.first { $0.label == "prod-n1024-s16" }!
        XCTAssertGreaterThanOrEqual(prod.externalBits!, 128)
        let merged = TFHELWEEstimatorProtocol.mergeExternal(
            TFHELWECoreSVPModel.exportBitsByLabel()
        )
        XCTAssertTrue(TFHELWEEstimatorProtocol.allVerifiedWithinTolerance(merged))
        XCTAssertFalse(TFHELWECoreSVPModel.markdownTable().isEmpty)
    }

    func testTensorLUTFormalCertificate() {
        let cert = TensorLUTFormal.certificate()
        XCTAssertTrue(cert.allHold, "\(cert.steps.filter { !$0.holds }.map(\.lemma))")
        cert.assertValid()
        XCTAssertTrue(cert.hypotheses.contains(where: { $0.contains("multilinear") }))
    }

    func testTensorLUTFormalCorollaryCertificate() {
        let cert = TensorLUTFormal.corollaryCertificate()
        XCTAssertTrue(cert.allHold, "\(cert.steps.filter { !$0.holds }.map(\.lemma))")
        cert.assertValid()
        XCTAssertEqual(cert.steps.count, 2)
        XCTAssertTrue(cert.steps.contains { $0.lemma == .emitterDiscreteAgreement && $0.holds })
        XCTAssertTrue(cert.steps.contains { $0.lemma == .involutionUnderFreeze && $0.holds })
    }

    func testTensorLUTMeltFreezeSnapCertificate() {
        let cert = TensorLUTFormal.meltFreezeSnapCertificate()
        XCTAssertTrue(cert.allHold, "\(cert.steps.filter { !$0.holds }.map(\.lemma))")
        cert.assertValid()
        XCTAssertEqual(cert.steps.count, 3)
        XCTAssertTrue(cert.steps.contains { $0.lemma == .separableMeltUniqueMaximizer && $0.holds })
        XCTAssertTrue(cert.steps.contains { $0.lemma == .snapBasinCompleteness && $0.holds })
        XCTAssertTrue(cert.steps.contains { $0.lemma == .freezePreservesMaximizer && $0.holds })
        XCTAssertTrue(cert.hypotheses.contains(where: { $0.contains("separable") || $0.contains("1-LUT") }))
    }

    func testEnigma256FormalCertificate() {
        let cert = Enigma256Formal.certificate()
        XCTAssertTrue(cert.allHold, "\(cert.steps.filter { !$0.holds }.map(\.lemma))")
        cert.assertValid()
        XCTAssertEqual(cert.steps.count, 5)
        XCTAssertTrue(cert.hypotheses.contains(where: { $0.contains("Fail-closed") || $0.contains("fail-closed") || $0.contains("coupledCubic6") }))
    }

    func testGGSWIncompleteCoveringCertificate() {
        let cert = GGSWIncompleteCovering.certificate()
        XCTAssertTrue(cert.allHold, "\(cert.steps.filter { !$0.holds }.map(\.lemma))")
        cert.assertValid()
        XCTAssertEqual(cert.productionUncoveredBits, 10)
        XCTAssertEqual(GGSWIncompleteCovering.uncoveredBits(degree: 128), 0)
        XCTAssertEqual(GGSWIncompleteCovering.uncoveredBits(degree: 1024), 10)
        XCTAssertEqual(GGSWIncompleteCovering.closestCoveringBaseLog(degree: 1024), 8)
    }

    func testGGSWPublicMSCoveringCertificate() {
        let cert = GGSWPublicMSCovering.certificate()
        XCTAssertTrue(cert.allHold, "\(cert.steps.filter { !$0.holds }.map(\.lemma))")
        cert.assertValid()
        XCTAssertEqual(cert.exactDegrees, [8, 128])
        XCTAssertEqual(cert.steps.count, 5) // includes C29 power-of-two word obstruction
        XCTAssertFalse(GGSWPublicMSCovering.isExactPublicMSCovering(degree: 1024))
        XCTAssertTrue(GGSWPublicMSCovering.isExactPublicMSCovering(degree: 128))
        let incomplete = GGSWParams.cryptoPublicMS(degree: 1024)
        XCTAssertEqual(incomplete.baseLog * incomplete.levelCount, 22)
        // C29: widening limb to UInt64 / 128-bit still forbids N=1024 exact public-MS covering.
        for w in GGSWPublicMSCovering.powerOfTwoWordBits {
            XCTAssertFalse(GGSWPublicMSCovering.isExactPublicMSCovering(degree: 1024, wordBits: w))
            XCTAssertEqual(
                GGSWPublicMSCovering.practicalDegrees.filter {
                    GGSWPublicMSCovering.isExactPublicMSCovering(degree: $0, wordBits: w)
                },
                [8, 128]
            )
        }
    }

    func testTestPolyInitCacheHits() {
        TFHETestPolyCache.shared.clear()
        let table: [UInt32] = [0, 1, 1, 0]
        let a = TFHETestPolyCache.shared.testPolynomial(truthTable: table, degree: 8, scale: 1 << 28)
        let b = TFHETestPolyCache.shared.testPolynomial(truthTable: table, degree: 8, scale: 1 << 28)
        XCTAssertEqual(a, b)
        let (hits, misses, entries) = TFHETestPolyCache.shared.stats
        XCTAssertEqual(misses, 1)
        XCTAssertEqual(hits, 1)
        XCTAssertEqual(entries, 1)
        // Same INIT bits, different degree → miss
        _ = TFHETestPolyCache.shared.testPolynomial(truthTable: table, degree: 16, scale: 1 << 28)
        XCTAssertEqual(TFHETestPolyCache.shared.stats.misses, 2)
    }

    func testLUTNodeEncryptedMetalLowering() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device")
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw XCTSkip("No MTLCommandQueue")
        }
        let degree = 8
        let params = GGSWParams.crypto(degree: degree)
        let secret = TFHESecretKey.random(params: params.tfhe, seed: 0xA101)
        var rng = LCG32(state: 0xA102)
        let bk = bootstrapKey(
            secret: secret, params: params, rng: &rng, publicRefreshCompatible: true
        )
        let twoN = 2 * degree
        let scale = rotationScale(polynomialDegree: degree)
        let truth: [UInt32] = [0, 1, 1, 0]
        let node = LUTNode(
            name: "xor",
            truthTable: truth,
            degree: degree,
            batch: 1,
            backend: .encryptedBlindRotate,
            encodingKind: .glwePacked
        )
        let context = EncryptedLUTMetalContext(
            bootKey: bk,
            scale: scale,
            device: device,
            commandQueue: commandQueue
        )
        for x in 0...1 {
            for y in 0...1 {
                let lx = encryptLWERotationNative(
                    message: UInt32(x), secret: secret.lweSecret, twoN: twoN, rng: &rng
                )
                let ly = encryptLWERotationNative(
                    message: UInt32(y), secret: secret.lweSecret, twoN: twoN, rng: &rng
                )
                let cpu = evaluateLUTBlindRotate(
                    truthTable: truth, inputs: [lx, ly], bootstrapKey: bk, scale: scale
                )
                let metal = try node.evaluateEncrypted(inputs: [lx, ly], context: context)
                let want = UInt32(x ^ y)
                XCTAssertEqual(
                    decodeRotationBoolean(decryptLWE(cpu, secret: secret), scale: scale),
                    want
                )
                XCTAssertEqual(
                    decodeRotationBoolean(decryptLWE(metal, secret: secret), scale: scale),
                    want
                )
                XCTAssertEqual(cpu, metal, "LUTNode Metal lowering must match CPU")
            }
        }
    }

    func testEncryptedNetlistMetalSingleGraphFullAdder() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device")
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw XCTSkip("No MTLCommandQueue")
        }
        guard let path = resolvePBSRepoFile("netlist.json") else {
            return XCTFail("netlist.json not found")
        }
        let netlist = loadYosysNetlist(from: path)
        guard let (moduleName, module) = netlist.modules.first else {
            return XCTFail("Empty netlist")
        }
        let degree = 8
        let params = GGSWParams.booleanTrivial(degree: degree)
        let secret = TFHESecretKey.random(params: params.tfhe, seed: 0xA201)
        let enc = EncryptedNetlistSimulator(
            moduleName: moduleName,
            module: module,
            secret: secret,
            params: params,
            backend: .blindRotateMetalNetlist,
            wireRefresh: .publicMS,
            seed: 0xA202,
            device: device,
            commandQueue: commandQueue
        )
        let clear = CleartextNetlistSimulator(moduleName: moduleName, module: module)
        for a in 0...1 {
            for b in 0...1 {
                for cin in 0...1 {
                    let inputs: [String: [UInt8]] = [
                        "a": [UInt8(a)],
                        "b": [UInt8(b)],
                        "cin": [UInt8(cin)]
                    ]
                    let want = clear.tick(inputs: inputs)
                    let got = try enc.tick(inputs: inputs)
                    XCTAssertEqual(got["sum"], want["sum"], "sum a=\(a) b=\(b) cin=\(cin)")
                    XCTAssertEqual(got["cout"], want["cout"], "cout a=\(a) b=\(b) cin=\(cin)")
                }
            }
        }
    }

    func testEncryptedTreeNetlistCPU() throws {
        guard let path = resolvePBSRepoFile("tree_netlist.json") else {
            return XCTFail("tree_netlist.json not found")
        }
        let netlist = loadYosysNetlist(from: path)
        guard let (moduleName, module) = netlist.modules.first else {
            return XCTFail("Empty netlist")
        }
        let degree = 8
        let params = GGSWParams.crypto(degree: degree)
        let secret = TFHESecretKey.random(params: params.tfhe, seed: 0xA301)
        let enc = EncryptedNetlistSimulator(
            moduleName: moduleName,
            module: module,
            secret: secret,
            params: params,
            backend: .blindRotate,
            wireRefresh: .publicMS,
            seed: 0xA302
        )
        let clear = CleartextNetlistSimulator(moduleName: moduleName, module: module)
        XCTAssertTrue(clear.dffs.isEmpty)
        for mask in 0..<256 {
            var remaining = mask
            var fa = [UInt8](repeating: 0, count: 4)
            var fb = [UInt8](repeating: 0, count: 4)
            for i in 0..<4 {
                fa[i] = UInt8(remaining & 1)
                remaining >>= 1
            }
            for i in 0..<4 {
                fb[i] = UInt8(remaining & 1)
                remaining >>= 1
            }
            let inputs: [String: [UInt8]] = ["feature_a": fa, "feature_b": fb]
            let want = clear.tick(inputs: inputs)
            let got = try enc.tick(inputs: inputs)
            XCTAssertEqual(got["is_high_risk"], want["is_high_risk"], "mask=\(mask)")
        }
        XCTAssertNotNil(enc.noisyBKCertificate)
        XCTAssertTrue(enc.noisyBKCertificate!.eachLUTDecodable)
    }

    private func clearLUTCount(_ enc: EncryptedNetlistSimulator) -> Int {
        enc.clear.luts.count
    }

    func testEncryptedNetlistFullAdderWithInputNoise() throws {
        guard let path = resolvePBSRepoFile("netlist.json") else {
            return XCTFail("netlist.json not found")
        }
        let netlist = loadYosysNetlist(from: path)
        guard let (moduleName, module) = netlist.modules.first else {
            return XCTFail("Empty netlist")
        }
        let degree = 8
        let clear = CleartextNetlistSimulator(moduleName: moduleName, module: module)
        for (label, params, noise) in [
            ("boolean-demo", GGSWParams.booleanTrivial(degree: degree), TFHENoiseParams.demo),
            ("crypto-demo", GGSWParams.crypto(degree: degree), TFHENoiseParams.demo),
            ("crypto-scaled0", GGSWParams.crypto(degree: degree), TFHENoiseParams.none)
        ] as [(String, GGSWParams, TFHENoiseParams)] {
            let secret = TFHESecretKey.random(params: params.tfhe, seed: 0xA015)
            let enc = EncryptedNetlistSimulator(
                moduleName: moduleName,
                module: module,
                secret: secret,
                params: params,
                backend: .blindRotate,
                wireRefresh: .publicMS,
                inputNoise: noise,
                scaledPrimaryInputs: true,
                seed: 0xA016
            )
            for a in 0...1 {
                for b in 0...1 {
                    for cin in 0...1 {
                        let inputs: [String: [UInt8]] = [
                            "a": [UInt8(a)],
                            "b": [UInt8(b)],
                            "cin": [UInt8(cin)]
                        ]
                        let want = clear.tick(inputs: inputs)
                        let got = try enc.tick(inputs: inputs)
                        XCTAssertEqual(
                            got["sum"], want["sum"],
                            "\(label) sum a=\(a) b=\(b) cin=\(cin)"
                        )
                        XCTAssertEqual(
                            got["cout"], want["cout"],
                            "\(label) cout a=\(a) b=\(b) cin=\(cin)"
                        )
                        XCTAssertTrue(enc.noiseGrowth.isDecodable, label)
                    }
                }
            }
        }
    }

    func testFusedMetalBlindRotateMatchesCPU() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device")
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw XCTSkip("No MTLCommandQueue")
        }
        let degree = 8
        let params = GGSWParams.booleanTrivial(degree: degree)
        let secret = TFHESecretKey.random(params: params.tfhe, seed: 0xF05E)
        var rng = LCG32(state: 0xF05F)
        let bk = bootstrapKey(secret: secret, params: params, rng: &rng)
        let twoN = 2 * degree
        let scale = rotationScale(polynomialDegree: degree)
        let truth: [UInt32] = [0, 1, 1, 0]
        for x in 0...1 {
            for y in 0...1 {
                let lx = encryptLWERotationNative(
                    message: UInt32(x), secret: secret.lweSecret, twoN: twoN, rng: &rng
                )
                let ly = encryptLWERotationNative(
                    message: UInt32(y), secret: secret.lweSecret, twoN: twoN, rng: &rng
                )
                let cpu = evaluateLUTBlindRotate(
                    truthTable: truth, inputs: [lx, ly], bootstrapKey: bk, scale: scale
                )
                let metal = try MetalGGSW.evaluateLUTBlindRotate(
                    truthTable: truth,
                    inputs: [lx, ly],
                    bootstrapKey: bk,
                    scale: scale,
                    device: device,
                    commandQueue: commandQueue,
                    lowering: .fused
                )
                let want = UInt32(x ^ y)
                XCTAssertEqual(decodeRotationBoolean(decryptLWE(cpu, secret: secret), scale: scale), want)
                XCTAssertEqual(decodeRotationBoolean(decryptLWE(metal, secret: secret), scale: scale), want)
                XCTAssertEqual(cpu, metal, "fused Metal BR must match CPU ciphertext x=\(x) y=\(y)")
            }
        }
    }

    func testMetalKernelPolyMulMatchesCPU() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device")
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw XCTSkip("No MTLCommandQueue")
        }
        for n in [8, 32, 64] {
            var rng = LCG32(state: UInt32(0xA11 * n))
            let a = (0..<n).map { _ in rng.next() }
            let b = (0..<n).map { _ in rng.next() }
            let cpu = negacyclicPolynomialMultiply(a, b)
            let metal = try MetalGGSW.negacyclicPolyMulMetal(
                a, b, device: device, commandQueue: commandQueue
            )
            XCTAssertEqual(metal, cpu, "kernel poly-mul N=\(n)")
        }
    }

    func testTiledKernelBlindRotateMatchesCPU() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device")
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw XCTSkip("No MTLCommandQueue")
        }
        let degree = 8
        let params = GGSWParams.booleanTrivial(degree: degree)
        let secret = TFHESecretKey.random(params: params.tfhe, seed: 0x71ED)
        var rng = LCG32(state: 0x71EE)
        let bk = bootstrapKey(secret: secret, params: params, rng: &rng)
        let twoN = 2 * degree
        let scale = rotationScale(polynomialDegree: degree)
        let truth: [UInt32] = [0, 1, 1, 0]
        for x in 0...1 {
            for y in 0...1 {
                let lx = encryptLWERotationNative(
                    message: UInt32(x), secret: secret.lweSecret, twoN: twoN, rng: &rng
                )
                let ly = encryptLWERotationNative(
                    message: UInt32(y), secret: secret.lweSecret, twoN: twoN, rng: &rng
                )
                let cpu = evaluateLUTBlindRotate(
                    truthTable: truth, inputs: [lx, ly], bootstrapKey: bk, scale: scale
                )
                let metal = try MetalGGSW.evaluateLUTBlindRotate(
                    truthTable: truth,
                    inputs: [lx, ly],
                    bootstrapKey: bk,
                    scale: scale,
                    device: device,
                    commandQueue: commandQueue,
                    lowering: .tiledKernel,
                    tileWidth: 4
                )
                let want = UInt32(x ^ y)
                XCTAssertEqual(decodeRotationBoolean(decryptLWE(cpu, secret: secret), scale: scale), want)
                XCTAssertEqual(decodeRotationBoolean(decryptLWE(metal, secret: secret), scale: scale), want)
                XCTAssertEqual(cpu, metal, "tiled-kernel Metal BR must match CPU x=\(x) y=\(y)")
            }
        }
    }

    func testChainedExtractedLWEWithSecretRefresh() {
        let degree = 8
        let params = GGSWParams.booleanTrivial(degree: degree)
        let secret = TFHESecretKey.random(params: params.tfhe, seed: 0xC4A1)
        var rng = LCG32(state: 0xC4A2)
        let bk = bootstrapKey(secret: secret, params: params, rng: &rng)
        let twoN = 2 * degree
        let scale = rotationScale(polynomialDegree: degree)
        let xorTable: [UInt32] = [0, 1, 1, 0]
        for x in 0...1 {
            for y in 0...1 {
                for z in 0...1 {
                    let lx = encryptLWERotationNative(
                        message: UInt32(x), secret: secret.lweSecret, twoN: twoN, rng: &rng
                    )
                    let ly = encryptLWERotationNative(
                        message: UInt32(y), secret: secret.lweSecret, twoN: twoN, rng: &rng
                    )
                    let mid = evaluateLUTBlindRotate(
                        truthTable: xorTable, inputs: [lx, ly], bootstrapKey: bk, scale: scale
                    )
                    let midBit = decodeRotationBoolean(decryptLWE(mid, secret: secret), scale: scale)
                    let midNative = encryptLWERotationNative(
                        message: midBit, secret: secret.lweSecret, twoN: twoN, rng: &rng
                    )
                    let lz = encryptLWERotationNative(
                        message: UInt32(z), secret: secret.lweSecret, twoN: twoN, rng: &rng
                    )
                    let out = evaluateLUTBlindRotate(
                        truthTable: xorTable, inputs: [midNative, lz], bootstrapKey: bk, scale: scale
                    )
                    let phase = decryptLWE(out, secret: secret)
                    XCTAssertEqual(
                        decodeRotationBoolean(phase, scale: scale),
                        UInt32(x ^ y ^ z),
                        "chained XOR x=\(x) y=\(y) z=\(z) phase=\(phase)"
                    )
                }
            }
        }
    }

    /// Public MS refresh: extracted mid → Z_{2N}, then chain with rotation-native.
    func testChainedExtractedLWEWithPublicMS() {
        let degree = 8
        let params = GGSWParams.booleanTrivial(degree: degree)
        let secret = TFHESecretKey.random(params: params.tfhe, seed: 0xC4B1)
        var rng = LCG32(state: 0xC4B2)
        let bk = bootstrapKey(secret: secret, params: params, rng: &rng)
        let twoN = 2 * degree
        let scale = rotationScale(polynomialDegree: degree)
        let xorTable: [UInt32] = [0, 1, 1, 0]
        for x in 0...1 {
            for y in 0...1 {
                for z in 0...1 {
                    let lx = encryptLWERotationNative(
                        message: UInt32(x), secret: secret.lweSecret, twoN: twoN, rng: &rng
                    )
                    let ly = encryptLWERotationNative(
                        message: UInt32(y), secret: secret.lweSecret, twoN: twoN, rng: &rng
                    )
                    let mid = evaluateLUTBlindRotate(
                        truthTable: xorTable, inputs: [lx, ly], bootstrapKey: bk, scale: scale
                    )
                    let midNative = publicRefreshBit(mid, twoN: twoN, scale: scale)
                    let lz = encryptLWERotationNative(
                        message: UInt32(z), secret: secret.lweSecret, twoN: twoN, rng: &rng
                    )
                    let out = evaluateLUTBlindRotate(
                        truthTable: xorTable, inputs: [midNative, lz], bootstrapKey: bk, scale: scale
                    )
                    let phase = decryptLWE(out, secret: secret)
                    XCTAssertEqual(
                        decodeRotationBoolean(phase, scale: scale),
                        UInt32(x ^ y ^ z),
                        "public-MS chained XOR x=\(x) y=\(y) z=\(z) phase=\(phase)"
                    )
                }
            }
        }
    }

    /// kδ wires live in `{0,k}`; native-δ public MS + stride-k test poly chains XOR.
    func testStrideKPublicMSChainedXOR() {
        let degree = 32
        let k = 3
        let params = GGSWParams.booleanTrivial(degree: degree)
        let secret = TFHESecretKey.random(params: params.tfhe, seed: 0xC4C1)
        var rng = LCG32(state: 0xC4C2)
        let bk = bootstrapKey(secret: secret, params: params, rng: &rng)
        let twoN = 2 * degree
        let scale = rotationBooleanScale(polynomialDegree: degree, mul: k)
        let xorTable: [UInt32] = [0, 1, 1, 0]
        for x in 0...1 {
            for y in 0...1 {
                for z in 0...1 {
                    let lx = encryptLWERotationNative(
                        message: encodeRotationNativeBit(UInt32(x), k: k),
                        secret: secret.lweSecret, twoN: twoN, rng: &rng
                    )
                    let ly = encryptLWERotationNative(
                        message: encodeRotationNativeBit(UInt32(y), k: k),
                        secret: secret.lweSecret, twoN: twoN, rng: &rng
                    )
                    let mid = evaluateLUTBlindRotate(
                        truthTable: xorTable, inputs: [lx, ly], bootstrapKey: bk, scale: scale
                    )
                    XCTAssertEqual(
                        decodeRotationBoolean(decryptLWE(mid, secret: secret), scale: scale),
                        UInt32(x ^ y)
                    )
                    let midNative = publicRefreshBit(mid, twoN: twoN, scale: scale)
                    XCTAssertEqual(
                        decodeRotationNativeBit(
                            decryptLWE(midNative, secret: secret), twoN: twoN, k: k
                        ),
                        UInt32(x ^ y)
                    )
                    let lz = encryptLWERotationNative(
                        message: encodeRotationNativeBit(UInt32(z), k: k),
                        secret: secret.lweSecret, twoN: twoN, rng: &rng
                    )
                    let out = evaluateLUTBlindRotate(
                        truthTable: xorTable, inputs: [midNative, lz], bootstrapKey: bk, scale: scale
                    )
                    XCTAssertEqual(
                        decodeRotationBoolean(decryptLWE(out, secret: secret), scale: scale),
                        UInt32(x ^ y ^ z),
                        "stride-k public-MS chained XOR x=\(x) y=\(y) z=\(z)"
                    )
                }
            }
        }
    }

    func testRotationNativePackStaysInZ2N() {
        // Regression: arity-3 packing at N≥256 used to overflow rotationPower's
        // 256·2N headroom and modulus-switch by mistake (full_adder cout failures).
        for degree in [64, 128, 256, 1024] {
            let twoN = 2 * degree
            let mod = UInt32(twoN)
            var rng = LCG32(state: UInt32(0xA07A) &+ UInt32(degree))
            let secret = (0..<degree).map { _ in rng.next() & 1 }
            let bits = (0..<3).map { _ in
                encryptLWERotationNative(message: 1, secret: secret, twoN: twoN, rng: &rng)
            }
            for ct in bits {
                XCTAssertTrue(ct.a.allSatisfy { $0 < mod }, "encrypt a in Z_{2N} N=\(degree)")
                XCTAssertLessThan(ct.b, mod, "encrypt b in Z_{2N} N=\(degree)")
            }
            let packed = packLWEBits(bits)
            XCTAssertTrue(packed.a.allSatisfy { $0 < mod }, "pack a in Z_{2N} N=\(degree)")
            XCTAssertLessThan(packed.b, mod, "pack b in Z_{2N} N=\(degree)")
            XCTAssertEqual(rotationPower(packed.b, twoN: twoN), Int(packed.b))
            for a in packed.a {
                XCTAssertEqual(rotationPower(a, twoN: twoN), Int(a))
            }
        }
    }

    func testPublicMSCryptoGadgetDiagnostics() {
        let degree = 8
        let scale = rotationScale(polynomialDegree: degree)
        let twoN = 2 * degree
        let xorTable: [UInt32] = [0, 1, 1, 0]
        for (label, params, pub) in [
            ("boolean", GGSWParams.booleanTrivial(degree: degree), false),
            ("crypto", GGSWParams.crypto(degree: degree), false),
            ("crypto+stride", GGSWParams.crypto(degree: degree), true)
        ] as [(String, GGSWParams, Bool)] {
            let secret = TFHESecretKey.random(params: params.tfhe, seed: 0xD001)
            var rng = LCG32(state: 0xD002)
            let bk = bootstrapKey(
                secret: secret,
                params: params,
                rng: &rng,
                publicRefreshCompatible: pub
            )
            var okMSBit = 0
            var okChain = 0
            var onLattice = 0
            var totalCoeffs = 0
            for x in 0...1 {
                for y in 0...1 {
                    let lx = encryptLWERotationNative(
                        message: UInt32(x), secret: secret.lweSecret, twoN: twoN, rng: &rng
                    )
                    let ly = encryptLWERotationNative(
                        message: UInt32(y), secret: secret.lweSecret, twoN: twoN, rng: &rng
                    )
                    let mid = evaluateLUTBlindRotate(
                        truthTable: xorTable, inputs: [lx, ly], bootstrapKey: bk, scale: scale
                    )
                    let want = UInt32(x ^ y)
                    totalCoeffs += mid.a.count + 1
                    onLattice += mid.a.filter { $0 % scale == 0 }.count
                    if mid.b % scale == 0 { onLattice += 1 }

                    let midMS = publicRefreshBit(mid, twoN: twoN, scale: scale)
                    let msPhase = decryptLWE(midMS, secret: secret) & 1
                    if msPhase == want { okMSBit += 1 }

                    let lz = encryptLWERotationNative(
                        message: 0, secret: secret.lweSecret, twoN: twoN, rng: &rng
                    )
                    let out = evaluateLUTBlindRotate(
                        truthTable: xorTable, inputs: [midMS, lz], bootstrapKey: bk, scale: scale
                    )
                    if decodeRotationBoolean(decryptLWE(out, secret: secret), scale: scale) == want {
                        okChain += 1
                    }
                }
            }
            print(
                "DIAG \(label): lattice=\(onLattice)/\(totalCoeffs) msBit=\(okMSBit)/4 chain=\(okChain)/4"
            )
            if label != "crypto" {
                XCTAssertEqual(onLattice, totalCoeffs, "\(label) lattice")
                XCTAssertEqual(okMSBit, 4, "\(label) msBit")
                XCTAssertEqual(okChain, 4, "\(label) chain")
            }
        }
    }

    func testEncryptedNetlistWireRefreshPublicMSFullAdder() throws {
        guard let path = resolvePBSRepoFile("netlist.json") else {
            return XCTFail("netlist.json not found")
        }
        let netlist = loadYosysNetlist(from: path)
        guard let (moduleName, module) = netlist.modules.first else {
            return XCTFail("Empty netlist")
        }
        let clear = CleartextNetlistSimulator(moduleName: moduleName, module: module)
        // N=8 (fast) + N=256 (δ≠classic g₀) — rounded MS fails at n≳256 without g₀=δ.
        for degree in [8, 256] {
            for (label, params, seed) in [
                ("booleanPublicMS", GGSWParams.booleanPublicMS(degree: degree), UInt32(0xADDF)),
                ("cryptoPublicMS", GGSWParams.cryptoPublicMS(degree: degree), UInt32(0xAE01))
            ] as [(String, GGSWParams, UInt32)] {
                let secret = TFHESecretKey.random(params: params.tfhe, seed: seed)
                let enc = EncryptedNetlistSimulator(
                    moduleName: moduleName,
                    module: module,
                    secret: secret,
                    params: params,
                    backend: .blindRotate,
                    wireRefresh: .publicMS,
                    seed: seed &+ 1
                )
                for a in 0...1 {
                    for b in 0...1 {
                        for cin in 0...1 {
                            let inputs: [String: [UInt8]] = [
                                "a": [UInt8(a)],
                                "b": [UInt8(b)],
                                "cin": [UInt8(cin)]
                            ]
                            let want = clear.tick(inputs: inputs)
                            let got = try enc.tick(inputs: inputs)
                            XCTAssertEqual(
                                got["sum"], want["sum"],
                                "\(label) N=\(degree) sum a=\(a) b=\(b) cin=\(cin)"
                            )
                            XCTAssertEqual(
                                got["cout"], want["cout"],
                                "\(label) N=\(degree) cout a=\(a) b=\(b) cin=\(cin)"
                            )
                        }
                    }
                }
            }
        }
    }

    func testBlindRotateIdentityAndXOR() {
        let degree = 8
        let params = GGSWParams.booleanTrivial(degree: degree)
        let secret = TFHESecretKey.random(params: params.tfhe, seed: 0xB107)
        var rng = LCG32(state: 0xB108)
        let bk = bootstrapKey(secret: secret, params: params, rng: &rng)
        let twoN = 2 * degree
        let scale = rotationScale(polynomialDegree: degree)

        // Zero-secret control: BR reduces to X^{-b}·v.
        let zero = TFHESecretKey.zero(params: params.tfhe)
        var rngZ = LCG32(state: 1)
        let bkZ = bootstrapKey(secret: zero, params: params, rng: &rngZ)
        let lwe1 = encryptLWERotationNative(
            message: 1,
            secret: zero.lweSecret,
            twoN: twoN,
            rng: &rngZ
        )
        XCTAssertEqual(decryptLWE(lwe1, secret: zero), 1)
        var idPoly = [UInt32](repeating: 0, count: degree)
        idPoly[1] = scale
        let accZ = blindRotate(testPolynomial: idPoly, lwe: lwe1, bootstrapKey: bkZ)
        let phaseZ = decryptGLWE(accZ, secret: zero)[0]
        XCTAssertEqual(phaseZ, scale, "zero-secret BR body[0] should be scale, got \(phaseZ)")
        XCTAssertEqual(decodeRotationBoolean(phaseZ, scale: scale), 1)

        for bit: UInt32 in [0, 1] {
            let lwe = encryptLWERotationNative(
                message: bit,
                secret: secret.lweSecret,
                twoN: twoN,
                rng: &rng
            )
            XCTAssertEqual(decryptLWE(lwe, secret: secret), bit)
            var poly = [UInt32](repeating: 0, count: degree)
            poly[0] = 0
            poly[1] = scale
            let acc = blindRotate(testPolynomial: poly, lwe: lwe, bootstrapKey: bk)
            let phase = decryptGLWE(acc, secret: secret)[0]
            XCTAssertEqual(
                decodeRotationBoolean(phase, scale: scale),
                bit,
                "identity BR bit=\(bit) phase=\(phase)"
            )
        }

        let truth: [UInt32] = [0, 1, 1, 0]
        for x in 0...1 {
            for y in 0...1 {
                let lx = encryptLWERotationNative(
                    message: UInt32(x),
                    secret: secret.lweSecret,
                    twoN: twoN,
                    rng: &rng
                )
                let ly = encryptLWERotationNative(
                    message: UInt32(y),
                    secret: secret.lweSecret,
                    twoN: twoN,
                    rng: &rng
                )
                let out = evaluateLUTBlindRotate(
                    truthTable: truth,
                    inputs: [lx, ly],
                    bootstrapKey: bk,
                    scale: scale
                )
                let phase = decryptLWE(out, secret: secret)
                XCTAssertEqual(
                    decodeRotationBoolean(phase, scale: scale),
                    UInt32(x ^ y),
                    "XOR BR x=\(x) y=\(y) phase=\(phase)"
                )
            }
        }
    }

    func testEncryptedNetlistFullAdderCPU() throws {
        guard let path = resolvePBSRepoFile("netlist.json") else {
            return XCTFail("netlist.json not found")
        }
        let netlist = loadYosysNetlist(from: path)
        guard let (moduleName, module) = netlist.modules.first else {
            return XCTFail("Empty netlist")
        }
        let degree = 8
        let params = GGSWParams.booleanTrivial(degree: degree)
        let secret = TFHESecretKey.random(params: params.tfhe, seed: 0xADDE)
        let enc = EncryptedNetlistSimulator(
            moduleName: moduleName,
            module: module,
            secret: secret,
            params: params,
            backend: .blindRotate,
            seed: 0xC001
        )
        let clear = CleartextNetlistSimulator(moduleName: moduleName, module: module)
        for a in 0...1 {
            for b in 0...1 {
                for cin in 0...1 {
                    let inputs: [String: [UInt8]] = [
                        "a": [UInt8(a)],
                        "b": [UInt8(b)],
                        "cin": [UInt8(cin)]
                    ]
                    let want = clear.tick(inputs: inputs)
                    let got = try enc.tick(inputs: inputs)
                    XCTAssertEqual(got["sum"], want["sum"], "sum a=\(a) b=\(b) cin=\(cin)")
                    XCTAssertEqual(got["cout"], want["cout"], "cout a=\(a) b=\(b) cin=\(cin)")
                }
            }
        }
    }

    func testEncryptedNetlistFullAdderMetal() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device")
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw XCTSkip("No MTLCommandQueue")
        }
        guard let path = resolvePBSRepoFile("netlist.json") else {
            return XCTFail("netlist.json not found")
        }
        let netlist = loadYosysNetlist(from: path)
        guard let (moduleName, module) = netlist.modules.first else {
            return XCTFail("Empty netlist")
        }
        let degree = 8
        let params = GGSWParams.booleanTrivial(degree: degree)
        let secret = TFHESecretKey.random(params: params.tfhe, seed: 0xAE7A)
        let enc = EncryptedNetlistSimulator(
            moduleName: moduleName,
            module: module,
            secret: secret,
            params: params,
            backend: .blindRotateMetal,
            seed: 0xC002,
            device: device,
            commandQueue: commandQueue
        )
        let clear = CleartextNetlistSimulator(moduleName: moduleName, module: module)
        for a in 0...1 {
            for b in 0...1 {
                for cin in 0...1 {
                    let inputs: [String: [UInt8]] = [
                        "a": [UInt8(a)],
                        "b": [UInt8(b)],
                        "cin": [UInt8(cin)]
                    ]
                    let want = clear.tick(inputs: inputs)
                    let got = try enc.tick(inputs: inputs)
                    XCTAssertEqual(got["sum"], want["sum"], "metal sum a=\(a) b=\(b) cin=\(cin)")
                    XCTAssertEqual(got["cout"], want["cout"], "metal cout a=\(a) b=\(b) cin=\(cin)")
                }
            }
        }
    }

    func testEncryptedNetlistFullAdderClearSelectorCPU() throws {
        guard let path = resolvePBSRepoFile("netlist.json") else {
            return XCTFail("netlist.json not found")
        }
        let netlist = loadYosysNetlist(from: path)
        guard let (moduleName, module) = netlist.modules.first else {
            return XCTFail("Empty netlist")
        }
        let degree = 8
        let params = GGSWParams.crypto(degree: degree)
        let secret = TFHESecretKey.random(params: params.tfhe, seed: 0xC10C)
        let enc = EncryptedNetlistSimulator(
            moduleName: moduleName,
            module: module,
            secret: secret,
            params: params,
            backend: .cpuGGSW,
            seed: 0xC003
        )
        let clear = CleartextNetlistSimulator(moduleName: moduleName, module: module)
        let inputs: [String: [UInt8]] = ["a": [1], "b": [1], "cin": [0]]
        let want = clear.tick(inputs: inputs)
        let got = try enc.tick(inputs: inputs)
        XCTAssertEqual(got["sum"], want["sum"])
        XCTAssertEqual(got["cout"], want["cout"])
    }
}

// MARK: - Helpers

private func resolvePBSRepoFile(_ name: String) -> String? {
    let fileManager = FileManager.default
    let cwd = fileManager.currentDirectoryPath
    for relative in [name, "../\(name)", "../../\(name)", "../../../\(name)"] {
        let path = URL(fileURLWithPath: cwd).appendingPathComponent(relative).path
        if fileManager.fileExists(atPath: path) { return path }
    }
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 {
        url.deleteLastPathComponent()
        let candidate = url.appendingPathComponent(name).path
        if fileManager.fileExists(atPath: candidate) { return candidate }
    }
    return nil
}

private func evaluatePBSCombinational(
    compiler: YosysGraphCompiler,
    device: MTLDevice,
    commandQueue: MTLCommandQueue,
    inputs: [String: [UInt32]]
) throws -> [String: [UInt32]] {
    let degree = compiler.degree
    let batch = compiler.batch
    let encoding = compiler.bitEncoding
    let elementCount = batch * degree
    let vectorShape: [NSNumber] = [NSNumber(value: batch), NSNumber(value: degree)]

    var feeds: [MPSGraphTensor: MPSGraphTensorData] = [:]
    for entry in compiler.inputNodes {
        guard let placeholder = entry.node.placeholder else {
            throw NSError(domain: "TFHESeamTests", code: 1)
        }
        let bits = inputs[entry.port] ?? [0]
        precondition(entry.bitIndex < bits.count)
        let values = encoding.encodeBit(bits[entry.bitIndex])
        var host = values
        if batch > 1 {
            host = []
            for _ in 0..<batch { host.append(contentsOf: values) }
        }
        let buffer = device.makeBuffer(
            bytes: host,
            length: host.count * MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        )!
        feeds[placeholder] = MPSGraphTensorData(buffer, shape: vectorShape, dataType: .uInt32)
    }

    var results: [MPSGraphTensor: MPSGraphTensorData] = [:]
    var outputBuffers: [(port: String, bit: Int, buffer: MTLBuffer)] = []
    for entry in compiler.outputTensors {
        let buffer = device.makeBuffer(
            length: elementCount * MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        )!
        results[entry.tensor] = MPSGraphTensorData(buffer, shape: vectorShape, dataType: .uInt32)
        outputBuffers.append((entry.port, entry.bitIndex, buffer))
    }

    compiler.graph.run(
        with: commandQueue,
        feeds: feeds,
        targetOperations: nil,
        resultsDictionary: results
    )

    var decoded: [String: [UInt32]] = [:]
    for (port, bit, buffer) in outputBuffers {
        let ptr = buffer.contents().bindMemory(to: UInt32.self, capacity: elementCount)
        let lane = Array(UnsafeBufferPointer(start: ptr, count: degree))
        let value = encoding.decodeBit(lane)
        var bits = decoded[port] ?? []
        while bits.count <= bit { bits.append(0) }
        bits[bit] = value
        decoded[port] = bits
    }
    return decoded
}
