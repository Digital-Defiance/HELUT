import Foundation
import Metal

// MARK: - Encrypted Yosys netlist (graduation steps 10c–10d)
//
// Combinational `$lut` netlists under a binary secret + bootstrap key.
//
// Step 10d–10i (`.blindRotate`): wires are LWE; each `$lut` is pack + blind-rotate +
// sample-extract (no clear GGSW selectors). Inter-LUT refresh is configurable:
// `.publicMS` (default) folds extracted LWE into `Z_{2N}` via `publicRefreshBit`
// with a lattice-compatible BK (`maskStride = gadget[0]`); `.secret` re-encrypts;
// `.none` leaves extracted LWE (single-LUT only). Optional `inputNoise` uses
// scaled lattice LWE + `TFHENoiseGrowth` / `TFHENoiseCertificate` (bounded proof).
// Metal BR fuses the CMUX chain into one MPSGraph per LUT.
//
// Step 10c (`.cpuGGSW` / `.metalGGSW`): legacy clear-selector CMUX PBS on GLWE
// wires (decrypt → GGSW encrypt per LUT).

/// Inter-LUT wire refresh policy for `EncryptedNetlistSimulator`.
package enum EncryptedWireRefresh: String, Sendable {
    /// Re-encrypt rotation-native under the secret (always e=0-exact multi-LUT).
    case secret = "secret"
    /// Public fold of PBS-extracted LWE into `Z_{2N}` (`publicRefreshBit`); no mid-flight secret.
    case publicMS = "public-ms"
    /// Leave extracted LWE in place (single-LUT / same-domain only; not for mixed native+extracted).
    case none = "none"
}

/// Where `$lut` PBS bodies run.
package enum EncryptedLUTBackend: String, Sendable {
    /// Clear selectors + CPU GGSW CMUX tree (step 10c).
    case cpuGGSW = "cpu-ggsw"
    /// Clear selectors + Metal GGSW CMUX tree (step 10c).
    case metalGGSW = "metal-ggsw"
    /// Packed LWE + blind rotate + BK (step 10d; no clear selectors).
    case blindRotate = "blind-rotate"
    /// Blind rotate with Metal CMUX steps (step 10d); single-graph netlist when publicMS.
    case blindRotateMetal = "blind-rotate-metal"
    /// Whole-netlist one MPSGraph (dynamic X^p; publicMS rotation-native wires).
    case blindRotateMetalNetlist = "blind-rotate-metal-netlist"
}

package final class EncryptedNetlistSimulator {
    package let clear: CleartextNetlistSimulator
    package let secret: TFHESecretKey
    package let params: GGSWParams
    package let backend: EncryptedLUTBackend
    package let wireRefresh: EncryptedWireRefresh
    /// Discrete body noise on primary inputs (`0` → rotation-native noiseless encrypt).
    package let inputNoise: TFHENoiseParams
    /// Discrete body noise on GGSW BK rows (`0` → noiseless gadget encrypt).
    package let bkNoise: TFHENoiseParams
    /// Force scaled lattice primary encrypt (`bit·δ`, `maskStride=δ`) even when noiseless.
    package let scaledPrimaryInputs: Bool
    package private(set) var rng: LCG32
    package private(set) var bootstrappingKey: BootstrapKey?
    package private(set) var keySwitchKey: KeySwitchKey
    package private(set) var noiseBudget: TFHENoiseBudget
    /// Bounded ∞-norm tracker (step 10h); updated each `tick`.
    package private(set) var noiseGrowth: TFHENoiseGrowth
    /// Last bounded noise certificate issued by `tick` / `issueNoiseCertificate`.
    package private(set) var noiseCertificate: TFHENoiseCertificate?
    /// Gaussian asymptotic failure-probability certificate (step 10k).
    package private(set) var asymptoticCertificate: TFHEAsymptoticSecurityCertificate?
    /// Decision-LWE hardness binding certificate (step 10n).
    package private(set) var hardnessCertificate: TFHELWEHardnessCertificate?
    /// Noisy/noiseless BK depth certificate (step 10p).
    package private(set) var noisyBKCertificate: TFHENoisyBKCertificate?
    /// Identity-LUT residual when `bkNoise.bound > 0` (H4 measured σ_BK).
    package private(set) var noisyBKMeasurement: TFHENoisyBKMeasurement?
    /// Gaussian union-bound certificate from measured RMS (nil if BK noiseless / unmeasured).
    package private(set) var noisyBKGaussianCertificate: TFHENoisyBKGaussianCertificate?

    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private let twoN: Int
    private let scale: UInt32
    private let booleanK: Int
    /// Encrypted DFF Q (rotation-native / publicMS domain). Host clock; clk is not a torus wire.
    private var encryptedQ: [Int: LWECiphertext] = [:]

    package init(
        moduleName: String,
        module: YosysModule,
        secret: TFHESecretKey,
        params: GGSWParams,
        backend: EncryptedLUTBackend = .blindRotate,
        wireRefresh: EncryptedWireRefresh = .publicMS,
        inputNoise: TFHENoiseParams = .none,
        bkNoise: TFHENoiseParams = .none,
        scaledPrimaryInputs: Bool = false,
        seed: UInt32 = 0xE11C,
        device: MTLDevice? = nil,
        commandQueue: MTLCommandQueue? = nil,
        noiseBudget: TFHENoiseBudget? = nil,
        booleanScaleMul: Int = 1
    ) {
        precondition(secret.params == params.tfhe)
        precondition(params.tfhe.glweDimension == 1)
        if inputNoise.bound > 0 {
            precondition(
                wireRefresh != .none,
                "inputNoise requires .publicMS or .secret refresh (not .none)"
            )
        }
        self.clear = CleartextNetlistSimulator(moduleName: moduleName, module: module)
        let n = params.tfhe.polynomialDegree
        for lut in self.clear.luts {
            precondition(
                n >= lut.table.count,
                "degree \(n) < LUT \(lut.name) size \(lut.table.count)"
            )
        }
        let skippedBR = self.clear.luts.filter { $0.blindRotateSkip != nil }.count
        if skippedBR > 0 {
            print("  LUT BR skip     \(skippedBR)/\(self.clear.luts.count) identity/constant")
            fflush(stdout)
        }
        self.secret = secret
        self.params = params
        self.backend = backend
        self.wireRefresh = wireRefresh
        self.inputNoise = inputNoise
        self.bkNoise = bkNoise
        self.scaledPrimaryInputs = scaledPrimaryInputs || inputNoise.bound > 0
        self.rng = LCG32(state: seed == 0 ? 1 : seed)
        self.twoN = 2 * n
        self.scale = rotationBooleanScale(polynomialDegree: n, mul: booleanScaleMul)
        self.booleanK = booleanScaleMul
        if let noiseBudget {
            self.noiseBudget = noiseBudget
        } else {
            // Abstract units: 2 per BR input bit + MS/slack per LUT (see tickBlindRotate).
            var units = self.clear.luts.reduce(0) { partial, lut in
                partial + lut.aBits.count * TFHENoiseOp.blindRotateLevel.cost + 2
            }
            for dff in self.clear.dffs {
                if dff.enableBit != nil {
                    units += 3 * TFHENoiseOp.blindRotateLevel.cost + 2
                }
                if dff.resetBit != nil {
                    units += 2 * TFHENoiseOp.blindRotateLevel.cost + 2
                }
                if dff.enableBit == nil && dff.resetBit == nil {
                    units += 2
                }
            }
            self.noiseBudget = TFHENoiseBudget(capacity: max(64, units + 16))
        }
        self.noiseGrowth = .forRotationScale(polynomialDegree: n)
        self.noiseCertificate = nil
        self.asymptoticCertificate = nil
        self.hardnessCertificate = nil
        self.noisyBKCertificate = nil
        self.noisyBKMeasurement = nil
        self.noisyBKGaussianCertificate = nil
        self.keySwitchKey = .trivialIdentity(dimension: params.tfhe.glweDimension * n)
        if backend == .metalGGSW || backend == .blindRotateMetal || backend == .blindRotateMetalNetlist {
            precondition(device != nil && commandQueue != nil, "Metal backend needs device + queue")
        }
        self.device = device
        self.commandQueue = commandQueue
        if backend == .blindRotateMetalNetlist {
            precondition(
                self.clear.dffs.isEmpty,
                "blind-rotate-metal-netlist is combinational-only (M1 sequential uses per-LUT BR)"
            )
        }
        for dff in self.clear.dffs {
            encryptedQ[dff.qWire] = encryptLWERotationNative(
                message: 0,
                secret: secret.lweSecret,
                twoN: twoN,
                rng: &rng
            )
        }

        if backend == .blindRotate || backend == .blindRotateMetal || backend == .blindRotateMetalNetlist {
            self.bootstrappingKey = bootstrapKey(
                secret: secret,
                params: params,
                rng: &self.rng,
                publicRefreshCompatible: wireRefresh == .publicMS || self.scaledPrimaryInputs,
                noise: bkNoise
            )
            self.keySwitchKey = extractToLWEKeySwitchKey(secret: secret, rng: &self.rng)
            if !self.keySwitchKey.isIdentity {
                print(
                    "  extract→KS     kN=\(params.tfhe.glweDimension * n) → n=\(params.tfhe.lweDimension)  (δ-lattice GLev e=0)"
                )
                fflush(stdout)
            }
            if bkNoise.bound > 0 || bkNoise.usesGaussian, let bk = self.bootstrappingKey {
                // Covering identity at n≥256 × N=1024 SIGTRAPed (C67) after KS print;
                // e=0 covering SING at the same n PASSes. One trial is enough for B_bk.
                let lweN = params.tfhe.lweDimension
                let trials: Int
                if n <= 16 {
                    trials = 16
                } else if lweN >= 256 {
                    trials = 1
                } else {
                    trials = 4
                }
                print("  identity residual trials=\(trials)  (n=\(lweN))")
                fflush(stdout)
                let measured = TFHENoisyBKMeasurement.identity(
                    secret: secret,
                    params: params,
                    noise: bkNoise,
                    bootstrapKey: bk,
                    trials: trials,
                    seed: seed &+ 0xB10C,
                    publicRefreshCompatible: wireRefresh == .publicMS || self.scaledPrimaryInputs,
                    booleanScaleMul: booleanScaleMul
                )
                print("  identity B_bk    \(measured.maxAbsError)  (decodable \(measured.eachLUTDecodable))")
                fflush(stdout)
                self.noisyBKMeasurement = measured
                self.noisyBKGaussianCertificate = measured.gaussianCertificate(
                    lutCount: self.clear.luts.count
                )
            }
        } else {
            self.bootstrappingKey = nil
        }
    }

    /// Decrypt host-clocked Q (rotation-native / publicMS). SING diagnostic.
    package func decryptedRegisterBits() -> [Int: UInt8] {
        var out: [Int: UInt8] = [:]
        out.reserveCapacity(encryptedQ.count)
        for (wire, ct) in encryptedQ {
            let phase = decryptLWE(ct, secret: secret)
            out[wire] = UInt8(decodeRotationNativeBit(phase, twoN: twoN, k: booleanK))
        }
        return out
    }

    /// Issue (and store) the bounded noise certificate for this netlist under current noise params.
    @discardableResult
    package func issueNoiseCertificate() -> TFHENoiseCertificate {
        let cert = TFHENoiseProof.certificateEncryptedNetlist(
            polynomialDegree: params.tfhe.polynomialDegree,
            inputNoiseBound: inputNoise.bound,
            lutCount: clear.luts.count,
            wireRefresh: wireRefresh
        )
        noiseCertificate = cert
        return cert
    }

    /// Issue Gaussian asymptotic certificate (ε ≤ 2^{targetFailureLog2}).
    @discardableResult
    package func issueAsymptoticCertificate(
        gaussian: TFHEGaussianParams? = nil
    ) -> TFHEAsymptoticSecurityCertificate {
        let n = params.tfhe.polynomialDegree
        let g: TFHEGaussianParams
        if let gaussian {
            g = gaussian
        } else if inputNoise.bound > 0 {
            g = TFHEGaussianParams(
                sigma: gaussianSigmaProxy(uniformBound: inputNoise.bound),
                delta: scale,
                lweDimension: params.tfhe.lweDimension,
                polynomialDegree: n,
                targetFailureLog2: -64
            )
        } else {
            g = .demoBoolean64(polynomialDegree: n)
        }
        let inputWires = clear.inputPorts.values.reduce(0) { $0 + $1.count }
        let cert = TFHEAsymptoticSecurityCertificate.forEncryptedNetlist(
            params: g,
            inputWireCount: inputWires,
            lutCount: clear.luts.count
        )
        asymptoticCertificate = cert
        return cert
    }

    /// Issue Decision-LWE → IND-CPA hardness binding (+ concrete bit estimate).
    @discardableResult
    package func issueHardnessCertificate(
        targetSecurityBits: Int = 128
    ) -> TFHELWEHardnessCertificate {
        let n = params.tfhe.polynomialDegree
        let g: TFHEGaussianParams
        if n >= 1024 {
            g = .productionBoolean64(polynomialDegree: n)
        } else if inputNoise.bound > 0 {
            g = TFHEGaussianParams(
                sigma: gaussianSigmaProxy(uniformBound: inputNoise.bound),
                delta: scale,
                lweDimension: params.tfhe.lweDimension,
                polynomialDegree: n,
                targetFailureLog2: -64
            )
        } else {
            // Demo N: correctness-oriented; hardness estimate will be low — do not assert.
            g = .demoBoolean64(polynomialDegree: n)
        }
        let cert = TFHELWEHardnessCertificate.forHELUTEncrypt(
            gaussian: g,
            targetSecurityBits: targetSecurityBits
        )
        hardnessCertificate = cert
        return cert
    }

    /// Issue noisy/noiseless BK depth certificate.
    /// Default `B_bk` is the measured identity residual when BK was noisy, else 0.
    @discardableResult
    package func issueNoisyBKCertificate(
        outputNoiseBound: UInt32? = nil
    ) -> TFHENoisyBKCertificate {
        let bound = outputNoiseBound ?? noisyBKMeasurement?.maxAbsError ?? 0
        let params = TFHENoisyBKParams(
            outputNoiseBound: bound,
            delta: scale,
            lutCount: clear.luts.count
        )
        let cert = TFHENoisyBKCertificate.forNetlist(
            params: params,
            measurement: noisyBKMeasurement
        )
        noisyBKCertificate = cert
        return cert
    }

    /// Encrypt inputs, evaluate LUTs, decrypt outputs.
    package func tick(inputs: [String: [UInt8]]) throws -> [String: [UInt8]] {
        switch backend {
        case .blindRotate, .blindRotateMetal, .blindRotateMetalNetlist:
            return try tickBlindRotate(inputs: inputs)
        case .cpuGGSW, .metalGGSW:
            return try tickClearSelector(inputs: inputs)
        }
    }

    // MARK: - Step 10d (blind rotate)

    private func tickBlindRotate(inputs: [String: [UInt8]]) throws -> [String: [UInt8]] {
        let bk = bootstrappingKey!
        noiseBudget.reset()
        noiseGrowth = .forRotationScale(polynomialDegree: params.tfhe.polynomialDegree)
        let cert = issueNoiseCertificate()
        if inputNoise.bound > 0 || scaledPrimaryInputs {
            cert.assertValid()
        }
        let asym = issueAsymptoticCertificate()
        asym.assertSecure()
        let hard = issueHardnessCertificate()
        if params.tfhe.polynomialDegree >= 1024 {
            hard.assertMeetsTarget()
        }
        let bkCert = issueNoisyBKCertificate()
        bkCert.assertDecodable()
        var wires: [Int: LWECiphertext] = encryptedQ
        let useScaledInputs = scaledPrimaryInputs

        // Sorted, NOT raw dictionary order. This loop draws from the shared
        // serial `rng` to encrypt each primary input, and Swift randomises
        // Dictionary iteration order per process — so unsorted iteration hands a
        // different mask vector to a different wire on every run. That made the
        // whole encrypted path non-reproducible: with every seed fixed and an
        // identical measured B_bk, the n=512 covering adder SING alternated
        // between PASS and a `sum mismatch` fatalError, while running under
        // SWIFT_DETERMINISTIC_HASHING=1 passed 4/4. Found 2026-08-15.
        for (port, bits) in inputs.sorted(by: { $0.key < $1.key }) {
            guard let portBits = clear.inputPorts[port] else { continue }
            precondition(bits.count == portBits.count, "Width mismatch on \(port)")
            for (index, bit) in portBits.enumerated() {
                if case .net(let wire) = bit {
                    if useScaledInputs {
                        let scaled = encryptLWE(
                            message: UInt32(bits[index]) &* scale,
                            secret: secret.lweSecret,
                            rng: &rng,
                            noise: inputNoise,
                            maskStride: scale
                        )
                        noiseGrowth.setEncrypt(noise: inputNoise)
                        // Fold to Z_{2N} before packLWEBits: scaling lattice LWE by 2^i
                        // overflows UInt32 when mask coeffs sit near q. Exact when
                        // noiseless; rounded MS absorbs |e| < δ/2.
                        wires[wire] = publicRefreshBit(scaled, twoN: twoN, scale: scale)
                        noiseBudget.consume(.modulusSwitch)
                        if inputNoise.bound == 0 {
                            noiseGrowth.afterExactModulusSwitch()
                        } else {
                            // Noise eaten by δ-rounding into Z_{2N}.
                            noiseGrowth.afterBlindRotate(outputNoiseBound: 0)
                        }
                    } else {
                        wires[wire] = encryptLWERotationNative(
                            message: encodeRotationNativeBit(UInt32(bits[index]), k: booleanK),
                            secret: secret.lweSecret,
                            twoN: twoN,
                            rng: &rng
                        )
                    }
                }
            }
        }
        if useScaledInputs {
            noiseGrowth.assertDecodable()
        }

        if backend == .blindRotateMetalNetlist {
            precondition(
                wireRefresh == .publicMS,
                "blind-rotate-metal-netlist requires wireRefresh=.publicMS"
            )
            return try tickBlindRotateMetalNetlist(wires: &wires, bootstrapKey: bk)
        }

        var pending = clear.luts
        var guardCount = pending.count * pending.count + 1
        while !pending.isEmpty {
            guardCount -= 1
            precondition(guardCount > 0, "Combinational loop in encrypted sim")
            var still: [CleartextNetlistSimulator.LUTCell] = []
            var ready: [(CleartextNetlistSimulator.LUTCell, [LWECiphertext])] = []
            for lut in pending {
                if let aLWEs = resolveLWEBits(lut.aBits, wires: wires) {
                    ready.append((lut, aLWEs))
                } else {
                    still.append(lut)
                }
            }
            precondition(!ready.isEmpty, "Stuck encrypted LUT resolve")
            var extractedByWire: [Int: LWECiphertext] = [:]
            var brReady: [(CleartextNetlistSimulator.LUTCell, [LWECiphertext])] = []
            for (lut, aLWEs) in ready {
                if let skip = lut.blindRotateSkip {
                    switch skip {
                    case .copy(let i):
                        wires[lut.yWire] = aLWEs[i]
                    case .constant(let bit):
                        wires[lut.yWire] = encryptLWERotationNative(
                            message: encodeRotationNativeBit(UInt32(bit), k: booleanK),
                            secret: secret.lweSecret,
                            twoN: twoN,
                            rng: &rng
                        )
                        noiseBudget.consume(.encrypt)
                    }
                } else {
                    brReady.append((lut, aLWEs))
                }
            }
            // Set HELUT_SERIAL_WAVEFRONT=1 to evaluate ready LUTs serially.
            // Added 2026-08-15 to isolate a reproducible nondeterminism: with
            // every seed fixed and an identical measured B_bk, the n=512
            // covering adder SING alternates between PASS and a `sum mismatch`
            // fatalError across runs. Identical inputs with differing outputs
            // means execution order matters somewhere, and this is the only
            // concurrency on the encrypted netlist path.
            let serialWavefront = ProcessInfo.processInfo
                .environment["HELUT_SERIAL_WAVEFRONT"] == "1"
            if brReady.count > 1 && !serialWavefront {
                var parallelExtracted: [Int: LWECiphertext] = [:]
                var parallelError: Error?
                let waveLock = NSLock()
                DispatchQueue.concurrentPerform(iterations: brReady.count) { idx in
                    let (lut, aLWEs) = brReady[idx]
                    let table = lut.table.map { UInt32($0) }
                    do {
                        let extracted = try self.evaluateLUTBlindRotateBody(
                            truthTable: table,
                            inputs: aLWEs,
                            bootstrapKey: bk
                        )
                        waveLock.lock()
                        parallelExtracted[lut.yWire] = extracted
                        waveLock.unlock()
                    } catch {
                        waveLock.lock()
                        parallelError = error
                        waveLock.unlock()
                    }
                }
                if let parallelError { throw parallelError }
                extractedByWire = parallelExtracted
            } else {
                for (lut, aLWEs) in brReady {
                    extractedByWire[lut.yWire] = try evaluateLUTBlindRotateBody(
                        truthTable: lut.table.map { UInt32($0) },
                        inputs: aLWEs,
                        bootstrapKey: bk
                    )
                }
            }
            for (lut, aLWEs) in brReady {
                guard let extracted = extractedByWire[lut.yWire] else {
                    preconditionFailure("missing wavefront BR for wire \(lut.yWire)")
                }
                for _ in 0..<aLWEs.count {
                    noiseBudget.consume(.blindRotateLevel)
                }
                noiseBudget.consume(.sampleExtract)
                if !keySwitchKey.isIdentity {
                    noiseBudget.consume(.keySwitch)
                }
                precondition(noiseBudget.isSafe, "noise budget exhausted mid-netlist")
                noiseGrowth.afterBlindRotate(outputNoiseBound: 0)
                switch wireRefresh {
                case .secret:
                    let phase = decryptLWE(extracted, secret: secret)
                    let bit = decodeRotationBoolean(phase, scale: scale)
                    wires[lut.yWire] = encryptLWERotationNative(
                        message: encodeRotationNativeBit(bit, k: booleanK),
                        secret: secret.lweSecret,
                        twoN: twoN,
                        rng: &rng
                    )
                    noiseBudget.consume(.encrypt)
                    noiseGrowth.setEncrypt(noise: .none)
                case .publicMS:
                    wires[lut.yWire] = publicRefreshBit(extracted, twoN: twoN, scale: scale)
                    noiseBudget.consume(.modulusSwitch)
                    noiseGrowth.afterExactModulusSwitch()
                case .none:
                    wires[lut.yWire] = extracted
                }
                noiseGrowth.assertDecodable()
            }
            pending = still
        }

        if !clear.dffs.isEmpty {
            try commitEncryptedDFFs(wires: &wires, bootstrapKey: bk)
        }

        var outputs: [String: [UInt8]] = [:]
        for (port, bits) in clear.outputPorts {
            outputs[port] = bits.map { bit -> UInt8 in
                switch bit {
                case .constant(let value):
                    return UInt8(value)
                case .net(let wire):
                    guard let ct = wires[wire] ?? encryptedQ[wire] else {
                        fatalError("Missing encrypted wire \(wire) for output \(port)")
                    }
                    let phase = decryptLWE(ct, secret: secret)
                    if wireRefresh == .none {
                        return UInt8(decodeRotationBoolean(phase, scale: scale))
                    }
                    // `.secret` and `.publicMS` leave rotation-native / Z_{2N} `{0,k}` bits.
                    return UInt8(decodeRotationNativeBit(phase, twoN: twoN, k: booleanK))
                }
            }
        }
        return outputs
    }

    /// Single MPSGraph for all `$lut`s (dynamic X^p + publicMS). Primary wires already native.
    private func tickBlindRotateMetalNetlist(
        wires: inout [Int: LWECiphertext],
        bootstrapKey: BootstrapKey
    ) throws -> [String: [UInt8]] {
        var pending = clear.luts
        var jobs: [MetalGGSW.NetlistLUTJob] = []
        var guardCount = pending.count * pending.count + 1
        while !pending.isEmpty {
            guardCount -= 1
            precondition(guardCount > 0, "Combinational loop in encrypted metal netlist")
            var still: [CleartextNetlistSimulator.LUTCell] = []
            var progressed = false
            for lut in pending {
                if let aLWEs = resolveLWEBits(lut.aBits, wires: wires) {
                    // Placeholders: mark output as present for topo by inserting a dummy
                    // once scheduled; real values come from the fused graph.
                    _ = aLWEs
                    var inputIds: [Int] = []
                    for bit in lut.aBits {
                        switch bit {
                        case .net(let id):
                            inputIds.append(id)
                        case .constant:
                            preconditionFailure("metal-netlist path expects net inputs (constants via host encrypt)")
                        }
                    }
                    jobs.append(
                        MetalGGSW.NetlistLUTJob(
                            name: lut.name,
                            truthTable: lut.table.map { UInt32($0) },
                            inputWireIds: inputIds,
                            outputWireId: lut.yWire
                        )
                    )
                    // Satisfy topo for subsequent LUTs: temporary zero native LWE.
                    wires[lut.yWire] = encryptLWERotationNative(
                        message: 0,
                        secret: secret.lweSecret,
                        twoN: twoN,
                        rng: &rng
                    )
                    for _ in 0..<inputIds.count {
                        noiseBudget.consume(.blindRotateLevel)
                    }
                    noiseBudget.consume(.sampleExtract)
                    if !keySwitchKey.isIdentity {
                        noiseBudget.consume(.keySwitch)
                    }
                    noiseBudget.consume(.modulusSwitch)
                    noiseGrowth.afterBlindRotate(outputNoiseBound: 0)
                    noiseGrowth.afterExactModulusSwitch()
                    progressed = true
                } else {
                    still.append(lut)
                }
            }
            precondition(progressed, "Stuck metal-netlist LUT resolve")
            pending = still
        }
        precondition(noiseBudget.isSafe, "noise budget exhausted mid-netlist")

        let produced = try MetalGGSW.evaluateTopoNetlistSingleGraph(
            jobs: jobs,
            primaryWires: wires.filter { id, _ in
                !jobs.contains(where: { $0.outputWireId == id })
            },
            bootstrapKey: bootstrapKey,
            scale: scale,
            device: device!,
            commandQueue: commandQueue!,
            keySwitchKey: keySwitchKey
        )
        for (id, ct) in produced {
            wires[id] = ct
        }
        noiseGrowth.assertDecodable()

        var outputs: [String: [UInt8]] = [:]
        for (port, bits) in clear.outputPorts {
            outputs[port] = bits.map { bit -> UInt8 in
                switch bit {
                case .constant(let value):
                    return UInt8(value)
                case .net(let wire):
                    guard let ct = wires[wire] else {
                        fatalError("Missing encrypted wire \(wire) for output \(port)")
                    }
                    let phase = decryptLWE(ct, secret: secret)
                    return UInt8(decodeRotationNativeBit(phase, twoN: twoN, k: booleanK))
                }
            }
        }
        return outputs
    }

    /// Host posedge: mux D/Q/reset in the clear, copy already-native LWE.
    /// A BR+publicMS on native D/Q was folding 1→0 (C46). The DFF primitive is the host clock.
    private func commitEncryptedDFFs(
        wires: inout [Int: LWECiphertext],
        bootstrapKey bk: BootstrapKey
    ) throws {
        _ = bk
        var nextQ: [Int: LWECiphertext] = [:]
        for dff in clear.dffs {
            guard let dLWE = resolveLWEBit(dff.dBit, wires: wires) else {
                fatalError("Missing D for encrypted DFF \(dff.name)")
            }
            let qCur = encryptedQ[dff.qWire] ?? dLWE

            var enabled = true
            if let enableBit = dff.enableBit {
                guard let eLWE = resolveLWEBit(enableBit, wires: wires) else {
                    fatalError("Missing E for encrypted DFF \(dff.name)")
                }
                let rawE = decryptNativeBit(eLWE)
                let enableActiveHigh = dff.polarity.enableActiveHigh ?? true
                enabled = (enableActiveHigh ? rawE : (1 - rawE)) != 0
            }

            var resetAsserted = false
            var resetValue: UInt32 = 0
            if let resetBit = dff.resetBit {
                guard let rLWE = resolveLWEBit(resetBit, wires: wires) else {
                    fatalError("Missing R for encrypted DFF \(dff.name)")
                }
                let rawR = decryptNativeBit(rLWE)
                let sync = dff.polarity.syncReset ?? (activeHigh: true, value: 0)
                resetAsserted = (sync.activeHigh ? rawR : (1 - rawR)) != 0
                resetValue = sync.value & 1
            }

            let qNext: LWECiphertext
            if dff.polarity.clockEnableGatesReset {
                if !enabled {
                    qNext = qCur
                } else if resetAsserted {
                    qNext = encryptLWERotationNative(
                        message: encodeRotationNativeBit(resetValue, k: booleanK),
                        secret: secret.lweSecret,
                        twoN: twoN,
                        rng: &rng
                    )
                } else {
                    qNext = dLWE
                }
            } else if resetAsserted {
                qNext = encryptLWERotationNative(
                    message: encodeRotationNativeBit(resetValue, k: booleanK),
                    secret: secret.lweSecret,
                    twoN: twoN,
                    rng: &rng
                )
            } else if dff.enableBit != nil && !enabled {
                qNext = qCur
            } else {
                qNext = dLWE
            }
            nextQ[dff.qWire] = qNext
            wires[dff.qWire] = qNext
        }
        encryptedQ = nextQ
    }

    private func decryptNativeBit(_ ct: LWECiphertext) -> UInt8 {
        let phase = decryptLWE(ct, secret: secret)
        if wireRefresh == .none {
            return UInt8(decodeRotationBoolean(phase, scale: scale))
        }
        return UInt8(decodeRotationNativeBit(phase, twoN: twoN, k: booleanK))
    }

    /// LUT3 (d, q, e): Y = enabled ? d : q.
    private func enableMuxTable(activeHigh: Bool) -> [UInt32] {
        (0..<8).map { mask in
            let d = UInt32(mask & 1)
            let q = UInt32((mask >> 1) & 1)
            let e = UInt32((mask >> 2) & 1)
            let enabled = activeHigh ? e : (1 &- e)
            return enabled == 1 ? d : q
        }
    }

    /// LUT2 (d, r): Y = asserted ? value : d.
    private func resetMuxTable(activeHigh: Bool, value: UInt32) -> [UInt32] {
        (0..<4).map { mask in
            let d = UInt32(mask & 1)
            let r = UInt32((mask >> 1) & 1)
            let asserted = activeHigh ? r : (1 &- r)
            return asserted == 1 ? (value & 1) : d
        }
    }

    private func refreshExtracted(_ extracted: LWECiphertext) throws -> LWECiphertext {
        switch wireRefresh {
        case .secret:
            let phase = decryptLWE(extracted, secret: secret)
            let bit = decodeRotationBoolean(phase, scale: scale)
            return encryptLWERotationNative(
                message: encodeRotationNativeBit(bit, k: booleanK),
                secret: secret.lweSecret,
                twoN: twoN,
                rng: &rng
            )
        case .publicMS:
            return publicRefreshBit(extracted, twoN: twoN, scale: scale)
        case .none:
            return extracted
        }
    }

    private func resolveLWEBit(_ bit: YosysBit, wires: [Int: LWECiphertext]) -> LWECiphertext? {
        resolveLWEBits([bit], wires: wires)?.first
    }

    private func evaluateLUTBlindRotateBody(
        truthTable: [UInt32],
        inputs: [LWECiphertext],
        bootstrapKey: BootstrapKey
    ) throws -> LWECiphertext {
        switch backend {
        case .blindRotate:
            return evaluateLUTBlindRotate(
                truthTable: truthTable,
                inputs: inputs,
                bootstrapKey: bootstrapKey,
                scale: scale,
                keySwitchKey: keySwitchKey
            )
        case .blindRotateMetal:
            let node = LUTNode(
                name: "enc_lut",
                truthTable: truthTable,
                degree: bootstrapKey.params.tfhe.polynomialDegree,
                batch: 1,
                backend: .encryptedBlindRotate,
                encodingKind: .glwePacked
            )
            let context = EncryptedLUTMetalContext(
                bootKey: bootstrapKey,
                scale: scale,
                device: device!,
                commandQueue: commandQueue!,
                keySwitchKey: keySwitchKey
            )
            return try node.evaluateEncrypted(inputs: inputs, context: context)
        case .blindRotateMetalNetlist:
            preconditionFailure("netlist metal path does not evaluate LUTs individually")
        default:
            preconditionFailure("not a blind-rotate backend")
        }
    }

    private func resolveLWEBits(
        _ bits: [YosysBit],
        wires: [Int: LWECiphertext]
    ) -> [LWECiphertext]? {
        var values: [LWECiphertext] = []
        values.reserveCapacity(bits.count)
        for bit in bits {
            switch bit {
            case .constant(let value):
                values.append(
                    encryptLWERotationNative(
                        message: UInt32(value),
                        secret: secret.lweSecret,
                        twoN: twoN,
                        rng: &rng
                    )
                )
            case .net(let id):
                guard let ct = wires[id] else { return nil }
                values.append(ct)
            }
        }
        return values
    }

    // MARK: - Step 10c (clear selectors)

    private func tickClearSelector(inputs: [String: [UInt8]]) throws -> [String: [UInt8]] {
        precondition(
            clear.dffs.isEmpty,
            "clear-selector encrypted path is combinational-only"
        )
        // Clear-selector path is a correctness oracle for GGSW CMUX trees — still issue
        // the certificate surface so benches / refuse paths stay uniform.
        _ = issueNoiseCertificate()
        _ = issueAsymptoticCertificate()
        _ = issueHardnessCertificate()
        _ = issueNoisyBKCertificate()
        var wires: [Int: GLWECiphertext] = [:]

        // Sorted, NOT raw dictionary order. This loop draws from the shared
        // serial `rng` to encrypt each primary input, and Swift randomises
        // Dictionary iteration order per process — so unsorted iteration hands a
        // different mask vector to a different wire on every run. That made the
        // whole encrypted path non-reproducible: with every seed fixed and an
        // identical measured B_bk, the n=512 covering adder SING alternated
        // between PASS and a `sum mismatch` fatalError, while running under
        // SWIFT_DETERMINISTIC_HASHING=1 passed 4/4. Found 2026-08-15.
        for (port, bits) in inputs.sorted(by: { $0.key < $1.key }) {
            guard let portBits = clear.inputPorts[port] else { continue }
            precondition(bits.count == portBits.count, "Width mismatch on \(port)")
            for (index, bit) in portBits.enumerated() {
                if case .net(let wire) = bit {
                    wires[wire] = encryptGLWEBit(UInt32(bits[index]))
                }
            }
        }

        var pending = clear.luts
        var guardCount = pending.count * pending.count + 1
        while !pending.isEmpty {
            guardCount -= 1
            precondition(guardCount > 0, "Combinational loop in encrypted sim")
            var still: [CleartextNetlistSimulator.LUTCell] = []
            var progressed = false
            for lut in pending {
                if let aCipher = resolveGLWEBits(lut.aBits, wires: wires) {
                    let aBits: [UInt32] = aCipher.map { decryptGLWEBit($0) }
                    let table = lut.table.map { UInt32($0) }
                    let out = try evaluateClearSelectorLUT(truthTable: table, inputs: aBits)
                    wires[lut.yWire] = out
                    progressed = true
                } else {
                    still.append(lut)
                }
            }
            precondition(progressed, "Stuck encrypted LUT resolve")
            pending = still
        }

        var outputs: [String: [UInt8]] = [:]
        for (port, bits) in clear.outputPorts {
            outputs[port] = bits.map { bit -> UInt8 in
                switch bit {
                case .constant(let value):
                    return UInt8(value)
                case .net(let wire):
                    guard let ct = wires[wire] else {
                        fatalError("Missing encrypted wire \(wire) for output \(port)")
                    }
                    return UInt8(decryptGLWEBit(ct))
                }
            }
        }
        return outputs
    }

    private func encryptGLWEBit(_ bit: UInt32) -> GLWECiphertext {
        precondition(bit == 0 || bit == 1)
        var msg = [UInt32](repeating: 0, count: params.tfhe.polynomialDegree)
        msg[0] = bit &* params.tfhe.delta
        return encryptGLWE(message: msg, secret: secret, rng: &rng)
    }

    private func decryptGLWEBit(_ ct: GLWECiphertext) -> UInt32 {
        decodeBooleanPhase(decryptGLWE(ct, secret: secret)[0], delta: params.tfhe.delta)
    }

    private func evaluateClearSelectorLUT(
        truthTable: [UInt32],
        inputs: [UInt32]
    ) throws -> GLWECiphertext {
        switch backend {
        case .cpuGGSW:
            return evaluatePBSGGSWCiphertext(
                truthTable: truthTable,
                inputs: inputs,
                secret: secret,
                params: params,
                rng: &rng
            )
        case .metalGGSW:
            return try MetalGGSW.evaluatePBSCiphertext(
                truthTable: truthTable,
                inputs: inputs,
                secret: secret,
                params: params,
                device: device!,
                commandQueue: commandQueue!,
                rng: &rng
            )
        default:
            preconditionFailure("not a clear-selector backend")
        }
    }

    private func resolveGLWEBits(
        _ bits: [YosysBit],
        wires: [Int: GLWECiphertext]
    ) -> [GLWECiphertext]? {
        var values: [GLWECiphertext] = []
        values.reserveCapacity(bits.count)
        for bit in bits {
            switch bit {
            case .constant(let value):
                values.append(encryptGLWEBit(UInt32(value)))
            case .net(let id):
                guard let ct = wires[id] else { return nil }
                values.append(ct)
            }
        }
        return values
    }
}
