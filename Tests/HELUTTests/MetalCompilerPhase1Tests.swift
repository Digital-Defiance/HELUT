import XCTest
import Metal
@testable import HELUTCore

/// Phase 1 Metal torus compiler battery.
///
/// Bars from `directives/metal-compiler-phases.md`:
/// kernel ≡ CPU schoolbook, tiled BR ≡ CPU (and fused at small N), tile-width
/// invariance, telemetry / PSO cache, both identity bits (no all-zero false PASS).
/// *N*=1024 wall-clock stays a microbench, not this suite.
final class MetalCompilerPhase1Tests: XCTestCase {
    private var device: MTLDevice!
    private var queue: MTLCommandQueue!

    override func setUpWithError() throws {
        try super.setUpWithError()
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device")
        }
        guard let queue = device.makeCommandQueue() else {
            throw XCTSkip("No MTLCommandQueue")
        }
        self.device = device
        self.queue = queue
        MetalBRControl.progress = nil
        MetalBRControl.overrideLowering = nil
        MetalBRControl.defaultTileWidth = 64
    }

    override func tearDown() {
        MetalBRControl.progress = nil
        MetalBRControl.overrideLowering = nil
        super.tearDown()
    }

    // MARK: - 2.1 kernel ≡ CPU schoolbook

    func testKernelPolyMulEdgeVectors() throws {
        for n in [8, 16, 32, 64, 128, 256] {
            let zero = [UInt32](repeating: 0, count: n)
            var one = zero
            one[0] = 1
            var x = zero
            x[1] = 1
            let allOnes = [UInt32](repeating: 1, count: n)
            let allMax = [UInt32](repeating: UInt32.max, count: n)
            var rng = LCG32(state: UInt32(0x5EED ^ (n &* 0x9E37)))
            let randomA = (0..<n).map { _ in rng.next() }
            let randomB = (0..<n).map { _ in rng.next() }
            let cases: [(String, [UInt32], [UInt32])] = [
                ("0*0", zero, zero),
                ("0*r", zero, randomB),
                ("1*b", one, randomB),
                ("a*1", randomA, one),
                ("X*a", x, randomA),
                ("ones", allOnes, allOnes),
                ("max", allMax, randomB),
                ("rand", randomA, randomB)
            ]
            for (label, a, b) in cases {
                let cpu = negacyclicPolynomialMultiply(a, b)
                let metal = try MetalGGSW.negacyclicPolyMulMetal(
                    a, b, device: device, commandQueue: queue
                )
                XCTAssertEqual(metal, cpu, "kernel \(label) N=\(n)")
                XCTAssertEqual(
                    NegacyclicNTT.multiply(a, b), cpu, "CPU NTT \(label) N=\(n)"
                )
            }
        }
    }

    func testKernelPolyMulManyRandomSeeds() throws {
        for n in [8, 32, 64] {
            for seed in 0..<16 {
                var rng = LCG32(state: UInt32(0xC0FFEE &+ UInt32(n &* 17) &+ UInt32(seed)))
                let a = (0..<n).map { _ in rng.next() }
                let b = (0..<n).map { _ in rng.next() }
                let cpu = negacyclicPolynomialMultiply(a, b)
                let metal = try MetalGGSW.negacyclicPolyMulMetal(
                    a, b, device: device, commandQueue: queue
                )
                XCTAssertEqual(metal, cpu, "kernel seed=\(seed) N=\(n)")
            }
        }
    }

    func testKernelNTTPolyMulN1024Spot() throws {
        let n = 1024
        var rng = LCG32(state: 0x1024_4E77)
        let a = (0..<n).map { _ in rng.next() }
        let b = (0..<n).map { _ in rng.next() }
        let cpu = negacyclicPolynomialMultiply(a, b)
        let metal = try MetalGGSW.negacyclicPolyMulMetal(
            a, b, device: device, commandQueue: queue
        )
        XCTAssertEqual(metal, cpu, "Metal NTT N=1024")
        XCTAssertEqual(NegacyclicNTT.multiply(a, b), cpu)
    }

    // MARK: - External product kernel ≡ CPU (Phase 2.2 fused launch)

    func testExternalProductKernelMatchesCPUBooleanAndCrypto() throws {
        for (degree, params, seed) in [
            (8, GGSWParams.booleanTrivial(degree: 8), UInt32(0xE001)),
            (16, GGSWParams.booleanTrivial(degree: 16), UInt32(0xE002)),
            (32, GGSWParams.booleanTrivial(degree: 32), UInt32(0xE004)),
            (8, GGSWParams.crypto(degree: 8), UInt32(0xE003)),
            (16, GGSWParams.cryptoPublicMS(degree: 16), UInt32(0xE005))
        ] as [(Int, GGSWParams, UInt32)] {
            let secret = TFHESecretKey.random(params: params.tfhe, seed: seed)
            var rng = LCG32(state: seed &+ 1)
            var msg = [UInt32](repeating: 0, count: degree)
            msg[0] = 1
            msg[degree / 2] = 3
            let ct = encryptGLWE(message: msg, secret: secret, rng: &rng)
            for bit in [UInt32(0), 1] {
                let ggsw = encryptGGSW(bit: bit, secret: secret, params: params, rng: &rng)
                let cpu = externalProduct(ggsw, ct)
                let metal = try MetalGGSW.externalProductKernel(
                    ggsw: ggsw,
                    ciphertext: ct,
                    device: device,
                    commandQueue: queue
                )
                XCTAssertEqual(metal, cpu, "EP kernel bit=\(bit) N=\(degree) g=\(params.baseLog)×\(params.levelCount)")
                XCTAssertEqual(
                    decryptGLWE(metal, secret: secret),
                    decryptGLWE(cpu, secret: secret)
                )
            }
        }
    }

    // MARK: - Tiled BR ≡ CPU, both bits, several N and W

    func testIdentityLUTBothBitsAcrossDegreesAndTileWidths() throws {
        let truth: [UInt32] = [0, 1]
        for degree in [8, 16, 32, 64] {
            let widths: [Int]
            switch degree {
            case 8: widths = [1, 3, 8, 64]
            case 16: widths = [4, 16]
            case 32: widths = [8, 32]
            default: widths = [16, 64]
            }
            let params = GGSWParams.booleanTrivial(degree: degree)
            let secret = TFHESecretKey.random(params: params.tfhe, seed: 0x1D00 &+ UInt32(degree))
            var rng = LCG32(state: 0x1D01 &+ UInt32(degree))
            let bk = bootstrapKey(secret: secret, params: params, rng: &rng)
            let twoN = 2 * degree
            let scale = rotationScale(polynomialDegree: degree)
            for w in widths {
                var ciphertexts: [UInt32: LWECiphertext] = [:]
                for bit in [UInt32(0), 1] {
                    let ct = encryptLWERotationNative(
                        message: bit, secret: secret.lweSecret, twoN: twoN, rng: &rng
                    )
                    let cpu = evaluateLUTBlindRotate(
                        truthTable: truth, inputs: [ct], bootstrapKey: bk, scale: scale
                    )
                    let metal = try MetalGGSW.evaluateLUTBlindRotate(
                        truthTable: truth,
                        inputs: [ct],
                        bootstrapKey: bk,
                        scale: scale,
                        device: device,
                        commandQueue: queue,
                        lowering: .tiledKernel,
                        tileWidth: w
                    )
                    let gotCPU = decodeRotationBoolean(decryptLWE(cpu, secret: secret), scale: scale)
                    let gotMetal = decodeRotationBoolean(decryptLWE(metal, secret: secret), scale: scale)
                    XCTAssertEqual(gotCPU, bit, "CPU identity N=\(degree) W=\(w) bit=\(bit)")
                    XCTAssertEqual(gotMetal, bit, "Metal identity N=\(degree) W=\(w) bit=\(bit)")
                    XCTAssertEqual(cpu, metal, "ctext identity N=\(degree) W=\(w) bit=\(bit)")
                    ciphertexts[bit] = metal
                    let tel = MetalBRControl.lastTelemetry
                    XCTAssertEqual(tel.lowering, MetalBRLowering.tiledKernel.rawValue)
                    XCTAssertEqual(tel.ring, "ntt", "persist BR must use inlined NTT EP N=\(degree)")
                    XCTAssertEqual(tel.tileWidth, w)
                    XCTAssertEqual(tel.tileCount, (degree + w - 1) / w, "tiles N=\(degree) W=\(w)")
                    XCTAssertGreaterThanOrEqual(tel.gpuRunSeconds, 0)
                }
                XCTAssertNotEqual(
                    ciphertexts[0], ciphertexts[1],
                    "bit0/bit1 must not collapse (false-PASS guard) N=\(degree) W=\(w)"
                )
            }
        }
    }

    func testXORAllStimuliFusedAndTiled() throws {
        let truth: [UInt32] = [0, 1, 1, 0]
        for degree in [8, 16] {
            let params = GGSWParams.booleanTrivial(degree: degree)
            let secret = TFHESecretKey.random(params: params.tfhe, seed: 0xA0B0 &+ UInt32(degree))
            var rng = LCG32(state: 0xA0B1 &+ UInt32(degree))
            let bk = bootstrapKey(secret: secret, params: params, rng: &rng)
            let twoN = 2 * degree
            let scale = rotationScale(polynomialDegree: degree)
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
                    let fused = try MetalGGSW.evaluateLUTBlindRotate(
                        truthTable: truth, inputs: [lx, ly], bootstrapKey: bk, scale: scale,
                        device: device, commandQueue: queue, lowering: .fused
                    )
                    let tiled = try MetalGGSW.evaluateLUTBlindRotate(
                        truthTable: truth, inputs: [lx, ly], bootstrapKey: bk, scale: scale,
                        device: device, commandQueue: queue, lowering: .tiledKernel, tileWidth: 4
                    )
                    let want = UInt32(x ^ y)
                    XCTAssertEqual(decodeRotationBoolean(decryptLWE(cpu, secret: secret), scale: scale), want)
                    XCTAssertEqual(decodeRotationBoolean(decryptLWE(fused, secret: secret), scale: scale), want)
                    XCTAssertEqual(decodeRotationBoolean(decryptLWE(tiled, secret: secret), scale: scale), want)
                    XCTAssertEqual(fused, cpu, "fused≡CPU XOR N=\(degree) x=\(x) y=\(y)")
                    XCTAssertEqual(tiled, cpu, "tiled≡CPU XOR N=\(degree) x=\(x) y=\(y)")
                    XCTAssertEqual(fused, tiled, "fused≡tiled XOR N=\(degree) x=\(x) y=\(y)")
                }
            }
        }
    }

    func testCarryLUTTiledMatchesCPU() throws {
        let lutTruth = "11101000"
        var table = [UInt32](repeating: 0, count: 8)
        for mask in 0..<8 {
            let ch = lutTruth[lutTruth.index(lutTruth.startIndex, offsetBy: lutTruth.count - 1 - mask)]
            table[mask] = ch == "1" ? 1 : 0
        }
        for degree in [8, 16] {
            let params = GGSWParams.booleanTrivial(degree: degree)
            let secret = TFHESecretKey.random(params: params.tfhe, seed: 0xCA11 &+ UInt32(degree))
            var rng = LCG32(state: 0xCA12 &+ UInt32(degree))
            let bk = bootstrapKey(secret: secret, params: params, rng: &rng)
            let twoN = 2 * degree
            let scale = rotationScale(polynomialDegree: degree)
            for a in 0...1 {
                for b in 0...1 {
                    for cin in 0...1 {
                        let bits = [UInt32(a), UInt32(b), UInt32(cin)]
                        let inputs = bits.map {
                            encryptLWERotationNative(
                                message: $0, secret: secret.lweSecret, twoN: twoN, rng: &rng
                            )
                        }
                        let cpu = evaluateLUTBlindRotate(
                            truthTable: table, inputs: inputs, bootstrapKey: bk, scale: scale
                        )
                        let metal = try MetalGGSW.evaluateLUTBlindRotate(
                            truthTable: table, inputs: inputs, bootstrapKey: bk, scale: scale,
                            device: device, commandQueue: queue,
                            lowering: .tiledKernel, tileWidth: 4
                        )
                        let want = table[a | (b << 1) | (cin << 2)]
                        XCTAssertEqual(
                            decodeRotationBoolean(decryptLWE(cpu, secret: secret), scale: scale),
                            want
                        )
                        XCTAssertEqual(
                            decodeRotationBoolean(decryptLWE(metal, secret: secret), scale: scale),
                            want,
                            "carry N=\(degree) a=\(a) b=\(b) cin=\(cin)"
                        )
                        XCTAssertEqual(cpu, metal, "carry ctext N=\(degree) a=\(a) b=\(b) cin=\(cin)")
                    }
                }
            }
        }
    }

    func testAutomaticLoweringSelectsFusedThenTiled() {
        XCTAssertEqual(MetalBRLowering.automatic(degree: 8), .fused)
        XCTAssertEqual(MetalBRLowering.automatic(degree: 64), .fused)
        XCTAssertEqual(MetalBRLowering.automatic(degree: 128), .tiledKernel)
        XCTAssertEqual(MetalBRLowering.automatic(degree: 1024), .tiledKernel)
    }

    func testTiledProgressAndTelemetry() throws {
        var lines: [String] = []
        MetalBRControl.progress = { lines.append($0) }
        let degree = 16
        let w = 4
        let params = GGSWParams.booleanTrivial(degree: degree)
        let secret = TFHESecretKey.random(params: params.tfhe, seed: 0x7E1E)
        var rng = LCG32(state: 0x7E1F)
        let bk = bootstrapKey(secret: secret, params: params, rng: &rng)
        let scale = rotationScale(polynomialDegree: degree)
        let ct = encryptLWERotationNative(
            message: 1, secret: secret.lweSecret, twoN: 2 * degree, rng: &rng
        )
        let out = try MetalGGSW.evaluateLUTBlindRotate(
            truthTable: [0, 1], inputs: [ct], bootstrapKey: bk, scale: scale,
            device: device, commandQueue: queue, lowering: .tiledKernel, tileWidth: w
        )
        XCTAssertEqual(decodeRotationBoolean(decryptLWE(out, secret: secret), scale: scale), 1)
        let expectTiles = (degree + w - 1) / w
        XCTAssertEqual(lines.count, expectTiles)
        for (i, line) in lines.enumerated() {
            XCTAssertTrue(line.contains("BR tile=\(i + 1)/\(expectTiles)"), line)
        }
        let tel = MetalBRControl.lastTelemetry
        XCTAssertEqual(tel.tileCount, expectTiles)
        XCTAssertEqual(tel.lowering, "tiled-kernel")
        XCTAssertEqual(tel.ring, "ntt")
        XCTAssertGreaterThan(tel.gpuRunSeconds, 0)
    }

    func testIdentityLUTCryptoNTTMatchesCPU() throws {
        let truth: [UInt32] = [0, 1]
        let degree = 8
        let params = GGSWParams.crypto(degree: degree)
        let secret = TFHESecretKey.random(params: params.tfhe, seed: 0xC18A)
        var rng = LCG32(state: 0xC18B)
        let bk = bootstrapKey(secret: secret, params: params, rng: &rng)
        let twoN = 2 * degree
        let scale = rotationScale(polynomialDegree: degree)
        let job = MetalGGSW.NetlistLUTJob(
            name: "identity",
            truthTable: truth,
            inputWireIds: [1],
            outputWireId: 2
        )
        var sawRoundUp = false
        for bit in [UInt32(0), 1] {
            let ct = encryptLWERotationNative(
                message: bit, secret: secret.lweSecret, twoN: twoN, rng: &rng
            )
            let cpu = evaluateLUTBlindRotate(
                truthTable: truth, inputs: [ct], bootstrapKey: bk, scale: scale
            )
            let metal = try MetalGGSW.evaluateLUTBlindRotate(
                truthTable: truth,
                inputs: [ct],
                bootstrapKey: bk,
                scale: scale,
                device: device,
                commandQueue: queue,
                lowering: .tiledKernel,
                tileWidth: 8
            )
            XCTAssertEqual(cpu, metal, "crypto NTT identity ctext bit=\(bit)")
            XCTAssertEqual(
                decodeRotationBoolean(decryptLWE(metal, secret: secret), scale: scale),
                bit
            )
            XCTAssertEqual(MetalBRControl.lastTelemetry.ring, "ntt")

            sawRoundUp = sawRoundUp || (cpu.a + [cpu.b]).contains {
                ($0 % scale) >= (scale >> 1)
            }
            let expectedRefresh = publicRefreshBit(cpu, twoN: twoN, scale: scale)
            MetalBRControl.overrideLowering = .tiledKernel
            let hostNetlist = try MetalGGSW.evaluateTopoNetlistSingleGraph(
                jobs: [job], primaryWires: [1: ct], bootstrapKey: bk, scale: scale,
                device: device, commandQueue: queue, inputPacking: .rotationNative
            )
            MetalBRControl.overrideLowering = .fused
            let graphNetlist = try MetalGGSW.evaluateTopoNetlistSingleGraph(
                jobs: [job], primaryWires: [1: ct], bootstrapKey: bk, scale: scale,
                device: device, commandQueue: queue, inputPacking: .rotationNative
            )
            MetalBRControl.overrideLowering = nil
            XCTAssertEqual(hostNetlist[2], expectedRefresh)
            XCTAssertEqual(graphNetlist[2], expectedRefresh)
        }
        XCTAssertTrue(sawRoundUp, "regression vector must exercise half-step rounding")
    }

    func testSecondBlindRotateHitsPolyMulCache() throws {
        let degree = 16
        let params = GGSWParams.booleanTrivial(degree: degree)
        let secret = TFHESecretKey.random(params: params.tfhe, seed: 0xCA5E)
        var rng = LCG32(state: 0xCA5F)
        let bk = bootstrapKey(secret: secret, params: params, rng: &rng)
        let scale = rotationScale(polynomialDegree: degree)
        let twoN = 2 * degree

        func run(_ bit: UInt32) throws -> (LWECiphertext, MetalBRTelemetry) {
            let ct = encryptLWERotationNative(
                message: bit, secret: secret.lweSecret, twoN: twoN, rng: &rng
            )
            let out = try MetalGGSW.evaluateLUTBlindRotate(
                truthTable: [0, 1], inputs: [ct], bootstrapKey: bk, scale: scale,
                device: device, commandQueue: queue, lowering: .tiledKernel, tileWidth: 8
            )
            return (out, MetalBRControl.lastTelemetry)
        }

        let (out0, tel0) = try run(0)
        let (out1, tel1) = try run(1)
        XCTAssertEqual(decodeRotationBoolean(decryptLWE(out0, secret: secret), scale: scale), 0)
        XCTAssertEqual(decodeRotationBoolean(decryptLWE(out1, secret: secret), scale: scale), 1)
        XCTAssertEqual(tel0.lowering, tel1.lowering)
        XCTAssertEqual(tel0.tileCount, tel1.tileCount)
        // Cold PSO compile is charged to the first engine create; later BRs must not
        // re-encode the shader (Phase 1.3).
        XCTAssertEqual(tel1.encodeSeconds, 0, accuracy: 1e-9, "second BR must hit PSO cache")
        XCTAssertGreaterThan(tel1.gpuRunSeconds, 0)
    }

    func testTiledKernelNetlistFullAdderMatchesClear() throws {
        guard let path = metalP1RepoFile("netlist.json") else {
            return XCTFail("netlist.json not found")
        }
        let netlist = loadYosysNetlist(from: path)
        guard let (moduleName, module) = netlist.modules.first else {
            return XCTFail("Empty netlist")
        }
        MetalBRControl.overrideLowering = .tiledKernel
        for degree in [8, 16] {
            let params = GGSWParams.booleanPublicMS(degree: degree)
            let secret = TFHESecretKey.random(params: params.tfhe, seed: 0x10D1 &+ UInt32(degree))
            let enc = EncryptedNetlistSimulator(
                moduleName: moduleName,
                module: module,
                secret: secret,
                params: params,
                backend: .blindRotateMetalNetlist,
                wireRefresh: .publicMS,
                seed: 0x10D2 &+ UInt32(degree),
                device: device,
                commandQueue: queue
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
                        XCTAssertEqual(
                            got["sum"], want["sum"],
                            "tiled-netlist sum N=\(degree) a=\(a) b=\(b) cin=\(cin)"
                        )
                        XCTAssertEqual(
                            got["cout"], want["cout"],
                            "tiled-netlist cout N=\(degree) a=\(a) b=\(b) cin=\(cin)"
                        )
                    }
                }
            }
        }
    }
}

private func metalP1RepoFile(_ name: String) -> String? {
    let fileManager = FileManager.default
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 {
        url.deleteLastPathComponent()
        let candidate = url.appendingPathComponent(name).path
        if fileManager.fileExists(atPath: candidate) { return candidate }
    }
    return nil
}
