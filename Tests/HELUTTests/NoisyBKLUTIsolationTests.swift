import Foundation
import Metal
import XCTest
@testable import HELUTCore

final class NoisyBKLUTIsolationTests: XCTestCase {
    private struct Observation: Equatable {
        var extracted: LWECiphertext
        var rawPhase: UInt32
        var rawBit: UInt32
        var rawResidual: UInt32
        var refreshedPhase: UInt32
        var refreshedBit: UInt32
        var refreshedResidual: UInt32
    }

    func testStrideKTestPolynomialUsesJitterTolerantBands() {
        let degree = 128
        let booleanK = 14
        let twoN = 2 * degree
        let scale = rotationBooleanScale(polynomialDegree: degree, mul: booleanK)
        let table: [UInt32] = [0, 0, 0, 0, 1, 0, 0, 1]
        let poly = TFHETestPolyCache.shared.testPolynomial(
            truthTable: table,
            degree: degree,
            scale: scale
        )

        // Address 4 is centered at 56. The lower tie at 49 belongs to address
        // 3, while 50...63 form address 4's nearest-center plateau.
        XCTAssertEqual(poly[49], 0)
        XCTAssertEqual(poly[50], scale)
        XCTAssertEqual(poly[52], scale, "C60's packed -4 jitter must stay in address 4")
        XCTAssertEqual(poly[56], scale)
        XCTAssertEqual(poly[63], scale)
        XCTAssertEqual(poly[64], 0)

        let params = GGSWParams.booleanTrivial(degree: degree)
        let secret = TFHESecretKey.zero(params: params.tfhe)
        let bootstrap = trivialBootstrapKey(
            lweDimension: params.tfhe.lweDimension,
            params: params
        )
        var rng = LCG32(state: 0xC600)
        let jitteredInputs = [UInt32(0), 0, 13].map { native in
            encryptLWERotationNative(
                message: native,
                secret: secret.lweSecret,
                twoN: twoN,
                rng: &rng
            )
        }
        let extracted = evaluateLUTBlindRotate(
            truthTable: table,
            inputs: jitteredInputs,
            bootstrapKey: bootstrap,
            scale: scale
        )
        XCTAssertEqual(
            decodeRotationBoolean(decryptLWE(extracted, secret: secret), scale: scale),
            1
        )
        let refreshed = publicRefreshBit(extracted, twoN: twoN, scale: scale)
        XCTAssertEqual(
            decodeRotationNativeBit(
                decryptLWE(refreshed, secret: secret),
                twoN: twoN,
                k: booleanK
            ),
            1
        )

        // Native -1 is still logically zero. Negacyclic tail fill must preserve
        // a table whose address-zero output is one across that wrap boundary.
        let wrappedZero = encryptLWERotationNative(
            message: UInt32(twoN - 1),
            secret: secret.lweSecret,
            twoN: twoN,
            rng: &rng
        )
        let wrappedExtracted = evaluateLUTBlindRotate(
            truthTable: [1, 0],
            inputs: [wrappedZero],
            bootstrapKey: bootstrap,
            scale: scale
        )
        XCTAssertEqual(
            decodeRotationBoolean(
                decryptLWE(wrappedExtracted, secret: secret),
                scale: scale
            ),
            1
        )
    }

    func testAggregateFirstPackingPreventsWeightedPublicMSAlias() {
        let degree = 1024
        let twoN = 2 * degree
        let booleanK = 14
        let delta = rotationScale(polynomialDegree: degree)
        let scale = rotationBooleanScale(polynomialDegree: degree, mul: booleanK)
        let half = delta >> 1
        let phase: (LWECiphertext) -> UInt32 = { ciphertext in
            precondition(ciphertext.a.count == 1)
            return ciphertext.b &- ciphertext.a[0]
        }

        let exactZero = LWECiphertext(a: [0], b: 0)
        // Its torus phase is only +2, so it is logically zero. Rounding this
        // ciphertext alone sends a→0 and b→1, creating the historical native +1.
        let roundedFalse = LWECiphertext(a: [half &- 1], b: half &+ 1)
        let exactTrue = LWECiphertext(a: [0], b: scale)
        let fullTorusInputs = [
            exactZero, exactZero, exactZero, exactZero, roundedFalse, exactTrue,
        ]
        XCTAssertEqual(phase(roundedFalse), 2)
        XCTAssertEqual(
            decodeRotationBoolean(phase(roundedFalse), scale: scale),
            0
        )

        let roundedInputs = fullTorusInputs.map {
            publicRefreshBit($0, twoN: twoN, scale: scale)
        }
        let oldPacked = packLWEBits(roundedInputs, twoN: twoN)
        let repairedPacked = packLWEBitsAggregateFirst(
            fullTorusInputs,
            twoN: twoN,
            scale: scale
        )
        XCTAssertEqual(phase(oldPacked) % UInt32(twoN), 464)
        XCTAssertEqual(phase(repairedPacked) % UInt32(twoN), 448)
    }

    func testAggregateFirstArity6Address32UsesLogicalTableCell() {
        let degree = 1024
        let twoN = 2 * degree
        let booleanK = 14
        let delta = rotationScale(polynomialDegree: degree)
        let scale = rotationBooleanScale(polynomialDegree: degree, mul: booleanK)
        let half = delta >> 1
        let params = GGSWParams.booleanTrivial(degree: degree).withLWEDimension(1)
        var secretPolynomial = [UInt32](repeating: 0, count: degree)
        secretPolynomial[0] = 1
        let secret = TFHESecretKey(params: params.tfhe, polynomials: [secretPolynomial])
        var rng = LCG32(state: 0x29072)
        let bootstrap = bootstrapKey(secret: secret, params: params, rng: &rng)

        let directBits = "0000000000000000000000000000000001000100110101000000000000000000"
        let table = directBits.map { $0 == "1" ? UInt32(1) : UInt32(0) }
        XCTAssertEqual(table.count, 64)
        XCTAssertEqual(table[32], 0)
        XCTAssertEqual(table[33], 1)

        let exactZero = LWECiphertext(a: [0], b: 0)
        let roundedFalse = LWECiphertext(a: [half &- 1], b: half &+ 1)
        let exactTrue = LWECiphertext(a: [0], b: scale)
        let fullTorusInputs = [
            exactZero, exactZero, exactZero, exactZero, roundedFalse, exactTrue,
        ]
        let roundedInputs = fullTorusInputs.map {
            publicRefreshBit($0, twoN: twoN, scale: scale)
        }

        let aliased = evaluateLUTBlindRotate(
            truthTable: table,
            inputs: roundedInputs,
            bootstrapKey: bootstrap,
            scale: scale,
            inputPacking: .rotationNative
        )
        let repaired = evaluateLUTBlindRotate(
            truthTable: table,
            inputs: fullTorusInputs,
            bootstrapKey: bootstrap,
            scale: scale,
            inputPacking: .fullTorusPublicMS
        )
        XCTAssertEqual(
            decodeRotationBoolean(decryptLWE(aliased, secret: secret), scale: scale),
            1,
            "round-each-then-pack control must reproduce address-33 alias"
        )
        XCTAssertEqual(
            decodeRotationBoolean(decryptLWE(repaired, secret: secret), scale: scale),
            0,
            "aggregate-first must retain logical address 32"
        )
    }

    /// Opt-in, release-oriented probe for C60's first locally corrupt LUT.
    ///
    /// Run with `HELUT_RUN_C60_LUT_PROBE=1`; optional controls are:
    /// - `HELUT_C60_LUT_PROBE_BASE_LOG=1|2` (default 2)
    /// - `HELUT_C60_LUT_PROBE_K=1...16` (default 7)
    /// - `HELUT_C60_LUT_PROBE_SIGMA=<Double>` (default 0)
    /// - `HELUT_C60_LUT_PROBE_BACKEND=cpu|metal|both` (default both)
    ///
    /// The probe is parameter-exact but not ciphertext-identical to the archived
    /// full-netlist failure: that run did not retain the three input LWEs. Fixed,
    /// independent seeds make this differential experiment reproducible.
    func testC60FirstCorruptLUTCPUAndMetal() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["HELUT_RUN_C60_LUT_PROBE"] == "1" else {
            throw XCTSkip("set HELUT_RUN_C60_LUT_PROBE=1 for the N=1024 C60 isolation probe")
        }

        let degree = 1024
        let twoN = 2 * degree
        let baseLog = try requiredInt(
            environment["HELUT_C60_LUT_PROBE_BASE_LOG"] ?? "2",
            name: "HELUT_C60_LUT_PROBE_BASE_LOG",
            allowed: [1, 2]
        )
        let booleanK = try requiredInt(
            environment["HELUT_C60_LUT_PROBE_K"] ?? "7",
            name: "HELUT_C60_LUT_PROBE_K",
            range: 1...16
        )
        let sigmaText = environment["HELUT_C60_LUT_PROBE_SIGMA"] ?? "0"
        guard let sigma = Double(sigmaText), sigma >= 0, sigma.isFinite else {
            throw ProbeConfigurationError.invalid(
                "HELUT_C60_LUT_PROBE_SIGMA must be a finite nonnegative Double"
            )
        }
        let backend = environment["HELUT_C60_LUT_PROBE_BACKEND"] ?? "both"
        guard ["cpu", "metal", "both"].contains(backend) else {
            throw ProbeConfigurationError.invalid(
                "HELUT_C60_LUT_PROBE_BACKEND must be cpu, metal, or both"
            )
        }

        let params = GGSWParams.covering(degree: degree, baseLog: baseLog)
        XCTAssertEqual(params.tfhe.lweDimension, degree)
        XCTAssertEqual(params.levelCount, 32 / baseLog)

        // Yosys INIT=10010000 is stored MSB-first. Direct address order is the
        // reversed table below; A[0] is the least-significant address bit.
        let truthTable: [UInt32] = [0, 0, 0, 0, 1, 0, 0, 1]
        let clearBits: [UInt32] = [0, 0, 1]
        let clearAddress = 4
        let expectedBit = truthTable[clearAddress]
        XCTAssertEqual(expectedBit, 1)
        XCTAssertLessThan(booleanK * (truthTable.count - 1), degree)

        let scale = rotationBooleanScale(polynomialDegree: degree, mul: booleanK)
        let nativeDelta = rotationScale(polynomialDegree: degree)
        let secretSeed: UInt32 = 0xE135
        let bkSeed: UInt32 = 0xE235
        let inputSeed: UInt32 = 0xE335
        let secret = TFHESecretKey.random(params: params.tfhe, seed: secretSeed)
        var bkRNG = LCG32(state: bkSeed)
        let noise: TFHENoiseParams = sigma == 0 ? .none : .gaussian(sigma: sigma)

        print(
            "C60_LUT_PROBE start N=\(degree) n=\(params.tfhe.lweDimension) "
                + "baseLog=\(baseLog) levels=\(params.levelCount) k=\(booleanK) "
                + "sigma=\(sigma) backend=\(backend) secretSeed=0xE135 "
                + "bkSeed=0xE235 inputSeed=0xE335"
        )
        let bkStarted = Date()
        let bootstrap = bootstrapKey(
            secret: secret,
            params: params,
            rng: &bkRNG,
            publicRefreshCompatible: true,
            noise: noise
        )
        print(String(format: "C60_LUT_PROBE bk-seconds=%.6f", -bkStarted.timeIntervalSinceNow))

        var inputRNG = LCG32(state: inputSeed)
        let inputs = clearBits.map { bit in
            encryptLWERotationNative(
                message: encodeRotationNativeBit(bit, k: booleanK),
                secret: secret.lweSecret,
                twoN: twoN,
                rng: &inputRNG
            )
        }
        let decodedInputs = inputs.map {
            decodeRotationNativeBit(
                decryptLWE($0, secret: secret),
                twoN: twoN,
                k: booleanK
            )
        }
        XCTAssertEqual(decodedInputs, clearBits)
        let packed = packLWEBits(inputs, twoN: twoN)
        let packedPhase = decryptLWE(packed, secret: secret) % UInt32(twoN)
        XCTAssertEqual(packedPhase, UInt32(booleanK * clearAddress))
        print(
            "C60_LUT_PROBE input address=\(clearAddress) packed-native=\(packedPhase) "
                + "expected-packed=\(booleanK * clearAddress) expected-bit=\(expectedBit)"
        )

        func observe(_ extracted: LWECiphertext) -> Observation {
            let rawPhase = decryptLWE(extracted, secret: secret)
            let rawBit = decodeRotationBoolean(rawPhase, scale: scale)
            let rawResidual = torusCenteredMagnitude(
                rawPhase &- (expectedBit &* scale)
            )
            let refreshed = publicRefreshBit(extracted, twoN: twoN, scale: scale)
            let refreshedPhase = decryptLWE(refreshed, secret: secret) % UInt32(twoN)
            let refreshedBit = decodeRotationNativeBit(
                refreshedPhase,
                twoN: twoN,
                k: booleanK
            )
            let normalized = refreshedPhase &* nativeDelta
            let refreshedResidual = torusCenteredMagnitude(
                normalized &- (expectedBit &* scale)
            )
            return Observation(
                extracted: extracted,
                rawPhase: rawPhase,
                rawBit: rawBit,
                rawResidual: rawResidual,
                refreshedPhase: refreshedPhase,
                refreshedBit: refreshedBit,
                refreshedResidual: refreshedResidual
            )
        }

        func report(_ label: String, _ observation: Observation, seconds: TimeInterval) {
            print(
                String(
                    format: "C60_LUT_PROBE backend=%@ seconds=%.6f raw=%u raw-bit=%u raw-|e|=%u refreshed-native=%u refreshed-bit=%u refreshed-|e|=%u half-gap=%u",
                    label,
                    seconds,
                    observation.rawPhase,
                    observation.rawBit,
                    observation.rawResidual,
                    observation.refreshedPhase,
                    observation.refreshedBit,
                    observation.refreshedResidual,
                    scale >> 1
                )
            )
        }

        var cpu: Observation?
        if backend == "cpu" || backend == "both" {
            let started = Date()
            let extracted = evaluateLUTBlindRotate(
                truthTable: truthTable,
                inputs: inputs,
                bootstrapKey: bootstrap,
                scale: scale
            )
            let observation = observe(extracted)
            report("cpu", observation, seconds: -started.timeIntervalSinceNow)
            cpu = observation
        }

        var metal: Observation?
        if backend == "metal" || backend == "both" {
            guard let device = MTLCreateSystemDefaultDevice() else {
                throw XCTSkip("No Metal device")
            }
            guard let commandQueue = device.makeCommandQueue() else {
                throw XCTSkip("No MTLCommandQueue")
            }
            let started = Date()
            let extracted = try MetalGGSW.evaluateLUTBlindRotate(
                truthTable: truthTable,
                inputs: inputs,
                bootstrapKey: bootstrap,
                scale: scale,
                device: device,
                commandQueue: commandQueue,
                lowering: .tiledKernel,
                tileWidth: 64
            )
            let observation = observe(extracted)
            report("metal", observation, seconds: -started.timeIntervalSinceNow)
            metal = observation
        }

        if let cpu, let metal {
            XCTAssertEqual(cpu, metal, "CPU and tiled Metal must produce the same extracted LWE")
        }
        if sigma == 0 {
            for observation in [cpu, metal].compactMap({ $0 }) {
                XCTAssertEqual(observation.rawBit, expectedBit)
                XCTAssertEqual(observation.refreshedBit, expectedBit)
                XCTAssertLessThan(observation.rawResidual, scale >> 1)
            }
        }
        print("C60_LUT_PROBE result COMPLETE diagnostic-only=\(sigma > 0)")
    }

    private func requiredInt(
        _ text: String,
        name: String,
        range: ClosedRange<Int>
    ) throws -> Int {
        guard let value = Int(text), range.contains(value) else {
            throw ProbeConfigurationError.invalid("\(name) must be in \(range)")
        }
        return value
    }

    private func requiredInt(
        _ text: String,
        name: String,
        allowed: Set<Int>
    ) throws -> Int {
        guard let value = Int(text), allowed.contains(value) else {
            throw ProbeConfigurationError.invalid(
                "\(name) must be one of \(allowed.sorted())"
            )
        }
        return value
    }
}

private enum ProbeConfigurationError: Error, CustomStringConvertible {
    case invalid(String)

    var description: String {
        switch self {
        case .invalid(let message): return message
        }
    }
}
