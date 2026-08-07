import Foundation
import Metal

// MARK: - Encrypted Yosys netlist (graduation steps 10c–10d)
//
// Combinational `$lut` netlists under a binary secret + bootstrap key.
//
// Step 10d–10i (`.blindRotate`): wires are LWE; each `$lut` is pack + blind-rotate +
// sample-extract (no clear GGSW selectors). Inter-LUT handling is configurable:
// `.publicMS` (default) keeps full-torus wires, switches each weighted LUT aggregate once
// before blind rotation, then publicly canonicalizes each extracted bit before reuse;
// `.secret` re-encrypts rotation-native wires; `.none` leaves extracted LWE (single-LUT only).
// Optional `inputNoise` uses scaled lattice LWE + `TFHENoiseGrowth` / `TFHENoiseCertificate`.
// Metal BR fuses the CMUX chain into one MPSGraph per LUT.
//
// Step 10c (`.cpuGGSW` / `.metalGGSW`): legacy clear-selector CMUX PBS on GLWE
// wires (decrypt → GGSW encrypt per LUT).

/// Inter-LUT wire-domain policy for `EncryptedNetlistSimulator`.
package enum EncryptedWireRefresh: String, Sendable {
    /// Re-encrypt rotation-native under the secret (always e=0-exact multi-LUT).
    case secret = "secret"
    /// Keep full-torus wires, switch each weighted LUT aggregate before BR, and
    /// publicly canonicalize each extracted bit before downstream reuse.
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
    /// Blind rotate with Metal CMUX steps (step 10d); per-LUT or tiled netlist.
    case blindRotateMetal = "blind-rotate-metal"
    /// Whole-netlist one MPSGraph (dynamic X^p; full-torus public-MS wires).
    case blindRotateMetalNetlist = "blind-rotate-metal-netlist"
}

package final class EncryptedNetlistSimulator {
    package let clear: CleartextNetlistSimulator
    package let secret: TFHESecretKey
    package let params: GGSWParams
    package let backend: EncryptedLUTBackend
    package let wireRefresh: EncryptedWireRefresh
    /// Discrete body noise on primary inputs (`0` → exact domain-appropriate encrypt).
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
    /// Noisy/noiseless BK deterministic-bound certificate. Noisy measurements
    /// do not populate this field unless a caller supplies a conservative bound.
    package private(set) var noisyBKCertificate: TFHENoisyBKCertificate?
    /// Identity-LUT residual observation when the BK is noisy.
    package private(set) var noisyBKMeasurement: TFHENoisyBKMeasurement?
    /// 95%-confidence Gaussian union bound over the configured circuit events.
    package private(set) var noisyBKGaussianCertificate: TFHENoisyBKGaussianCertificate?
    package let noisyBKExecutionPolicy: NoisyBKExecutionPolicy
    package let noisyBKEventCount: Int
    package let diagnosticsMode: EncryptedNetlistDiagnosticsMode
    package private(set) var lastTickDiagnostics: EncryptedTickDiagnostics?

    private let diagnosticClear: CleartextNetlistSimulator?
    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private let twoN: Int
    private let torusStep: UInt32
    private let scale: UInt32
    private let booleanK: Int
    /// Encrypted DFF Q in the selected wire domain. Host clock; clk is not a torus wire.
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
        booleanScaleMul: Int = 1,
        diagnosticsMode: EncryptedNetlistDiagnosticsMode = .off,
        noisyBKExecutionPolicy: NoisyBKExecutionPolicy = .requireCircuitConfidence,
        noisyBKIdentityTrials: Int? = nil,
        noisyBKEventCount: Int? = nil
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
        self.diagnosticsMode = diagnosticsMode
        self.diagnosticClear = diagnosticsMode == .off
            ? nil
            : CleartextNetlistSimulator(moduleName: moduleName, module: module, traceLUTs: true)
        self.noisyBKExecutionPolicy = noisyBKExecutionPolicy
        self.noisyBKEventCount = noisyBKEventCount ?? max(self.clear.luts.count, 1)
        precondition(self.noisyBKEventCount >= max(self.clear.luts.count, 1))
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
        self.torusStep = rotationScale(polynomialDegree: n)
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
        self.lastTickDiagnostics = nil
        self.keySwitchKey = .trivialIdentity(dimension: params.tfhe.glweDimension * n)
        if backend == .metalGGSW || backend == .blindRotateMetal || backend == .blindRotateMetalNetlist {
            precondition(device != nil && commandQueue != nil, "Metal backend needs device + queue")
        }
        self.device = device
        self.commandQueue = commandQueue
        self.bootstrappingKey = nil
        if backend == .blindRotateMetalNetlist {
            precondition(
                self.clear.dffs.isEmpty,
                "blind-rotate-metal-netlist is combinational-only (M1 sequential uses per-LUT BR)"
            )
            precondition(
                diagnosticsMode == .off,
                "first-divergence diagnostics require a per-LUT blind-rotate backend"
            )
        }
        for dff in self.clear.dffs {
            encryptedQ[dff.qWire] = encryptWireBit(0)
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
                // This is an observation, not a hard bound. Large production
                // experiments default to one trial for cost, which necessarily
                // leaves the 95% confidence bound unresolved unless the caller
                // requests more trials or explicitly selects diagnostic-only mode.
                let lweN = params.tfhe.lweDimension
                let defaultTrials: Int
                if n <= 16 {
                    defaultTrials = 16
                } else if lweN >= 256 {
                    defaultTrials = 1
                } else {
                    defaultTrials = 4
                }
                let trials = noisyBKIdentityTrials ?? defaultTrials
                precondition(trials > 0, "noisyBKIdentityTrials must be positive")
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
                print("  identity observed max|e| \(measured.maxAbsError)  (sample-decodable \(measured.eachLUTDecodable))")
                fflush(stdout)
                self.noisyBKMeasurement = measured
                self.noisyBKGaussianCertificate = measured.gaussianCertificate(
                    lutCount: self.noisyBKEventCount
                )
            }
        } else {
            self.bootstrappingKey = nil
        }
    }

    /// Decrypt host-clocked Q for SING diagnostics using the selected wire domain.
    package func decryptedRegisterBits() -> [Int: UInt8] {
        var out: [Int: UInt8] = [:]
        out.reserveCapacity(encryptedQ.count)
        for (wire, ct) in encryptedQ {
            let phase = decryptLWE(ct, secret: secret)
            let bit: UInt32
            if wireRefresh == .publicMS {
                bit = decodeRotationBoolean(phase, scale: scale)
            } else {
                bit = decodeRotationNativeBit(phase, twoN: twoN, k: booleanK)
            }
            out[wire] = UInt8(bit)
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
        var g: TFHEGaussianParams
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
        // Decision-LWE hardness binds the actual LWE sample dimension, not the
        // GLWE polynomial degree. They differ on the preserved n=512 rung.
        g.lweDimension = params.tfhe.lweDimension
        let cert = TFHELWEHardnessCertificate.forHELUTEncrypt(
            gaussian: g,
            targetSecurityBits: targetSecurityBits
        )
        hardnessCertificate = cert
        return cert
    }

    /// Issue a deterministic noisy/noiseless BK bound certificate.
    ///
    /// A finite measurement cannot call this API implicitly: noisy callers must
    /// supply a separately justified conservative bound. Statistical evidence
    /// lives in `noisyBKGaussianCertificate`.
    @discardableResult
    package func issueNoisyBKCertificate(
        outputNoiseBound: UInt32? = nil
    ) -> TFHENoisyBKCertificate {
        let hasNoisyBK = bkNoise.bound > 0 || bkNoise.usesGaussian
        precondition(
            !hasNoisyBK || outputNoiseBound != nil,
            "Noisy BK requires an explicit conservative bound; sampled max|e| is observational only"
        )
        let bound = outputNoiseBound ?? 0
        let certificateParams = TFHENoisyBKParams(
            outputNoiseBound: bound,
            delta: scale,
            lutCount: noisyBKEventCount
        )
        let provenance: TFHENoisyBKBoundProvenance = outputNoiseBound == nil
            ? .exactNoiselessConstruction
            : .callerSuppliedConservative
        let cert = TFHENoisyBKCertificate.forNetlist(
            params: certificateParams,
            provenance: provenance
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
        lastTickDiagnostics = nil
        noiseBudget.reset()
        noiseGrowth = .forRotationScale(polynomialDegree: params.tfhe.polynomialDegree)
        let cert = issueNoiseCertificate()
        if inputNoise.bound > 0 || scaledPrimaryInputs {
            cert.assertValid()
        }
        let asym = issueAsymptoticCertificate()
        asym.assertSecure()
        let hard = issueHardnessCertificate()
        if params.tfhe.polynomialDegree >= 1024 && params.tfhe.lweDimension >= 1024 {
            hard.assertMeetsTarget()
        }
        let hasNoisyBK = bkNoise.bound > 0 || bkNoise.usesGaussian
        if hasNoisyBK {
            guard let measured = noisyBKMeasurement,
                  let gaussian = noisyBKGaussianCertificate else {
                preconditionFailure("noisy BK has no empirical confidence measurement")
            }
            if noisyBKExecutionPolicy == .requireCircuitConfidence {
                precondition(
                    measured.decodeFailures == 0,
                    "noisy-BK identity observation already contains \(measured.decodeFailures) decode failure(s)"
                )
                gaussian.assertSecure()
            }
        } else {
            let bkCert = issueNoisyBKCertificate()
            bkCert.assertDecodable()
        }
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
                    if wireRefresh == .publicMS {
                        if useScaledInputs {
                            wires[wire] = encryptLWE(
                                message: UInt32(bits[index]) &* scale,
                                secret: secret.lweSecret,
                                rng: &rng,
                                noise: inputNoise,
                                maskStride: torusStep
                            )
                            noiseGrowth.setEncrypt(noise: inputNoise)
                        } else {
                            wires[wire] = encryptWireBit(UInt32(bits[index]))
                        }
                    } else if useScaledInputs {
                        let scaled = encryptLWE(
                            message: UInt32(bits[index]) &* scale,
                            secret: secret.lweSecret,
                            rng: &rng,
                            noise: inputNoise,
                            maskStride: torusStep
                        )
                        noiseGrowth.setEncrypt(noise: inputNoise)
                        // Secret/native compatibility path: preserve the historical ingest fold.
                        wires[wire] = publicRefreshBit(scaled, twoN: twoN, scale: scale)
                        noiseBudget.consume(.modulusSwitch)
                        if inputNoise.bound == 0 {
                            noiseGrowth.afterExactModulusSwitch()
                        } else {
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
        lastInputFingerprint = Self.fingerprint(wires: wires, ports: clear.inputPorts)

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

        let targetOnlyName = ProcessInfo.processInfo
            .environment["HELUT_DIAGNOSTIC_TARGET_LUT_ONLY"]
        let initialPending: [CleartextNetlistSimulator.LUTCell]
        if let targetOnlyName {
            precondition(
                ProcessInfo.processInfo.environment["HELUT_DIAGNOSTIC_CPU_REPLAY_LUT"]
                    == targetOnlyName,
                "target-only diagnostics require the same HELUT_DIAGNOSTIC_CPU_REPLAY_LUT"
            )
            guard let target = clear.luts.first(where: { $0.name == targetOnlyName }) else {
                preconditionFailure("unknown target-only LUT \(targetOnlyName)")
            }
            let producerByWire = Dictionary(
                uniqueKeysWithValues: clear.luts.map { ($0.yWire, $0) }
            )
            var requiredNames: Set<String> = []
            var stack = [target]
            while let lut = stack.popLast() {
                guard requiredNames.insert(lut.name).inserted else { continue }
                for bit in lut.aBits {
                    if case .net(let wire) = bit,
                       let producer = producerByWire[wire] {
                        stack.append(producer)
                    }
                }
            }
            initialPending = clear.luts.filter { requiredNames.contains($0.name) }
            print(
                "ENCRYPTED TARGET CONE name=\(targetOnlyName) "
                    + "LUTs=\(initialPending.count)/\(clear.luts.count)"
            )
            fflush(stdout)
        } else {
            initialPending = clear.luts
        }
        var pending = initialPending
        let diagnosticOrdinals: [String: Int] = diagnosticsMode == .off
            ? [:]
            : Dictionary(uniqueKeysWithValues: clear.luts.enumerated().map {
                ($0.element.name, $0.offset)
            })
        var diagnosticLUTs: [EncryptedLUTDiagnostic] = []
        var wavefront = 0
        var guardCount = pending.count * pending.count + 1
        while !pending.isEmpty {
            wavefront += 1
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
                        wires[lut.yWire] = encryptWireBit(UInt32(bit))
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

            // Opt-in exact-sample differential: replay one Metal LUT on the CPU
            // with the same noisy BK and the same upstream ciphertexts. This is
            // intentionally scoped to first-divergence diagnostics; a full
            // N=1024 CPU netlist tick would take many hours.
            if let replayName = ProcessInfo.processInfo
                .environment["HELUT_DIAGNOSTIC_CPU_REPLAY_LUT"],
               let (lut, aLWEs) = brReady.first(where: { $0.0.name == replayName }) {
                precondition(
                    diagnosticsMode != .off && backend == .blindRotateMetal,
                    "HELUT_DIAGNOSTIC_CPU_REPLAY_LUT requires Metal first-divergence diagnostics"
                )
                precondition(
                    wireRefresh == .publicMS,
                    "HELUT_DIAGNOSTIC_CPU_REPLAY_LUT currently requires public-MS"
                )
                guard let metalExtracted = extractedByWire[lut.yWire] else {
                    preconditionFailure("missing Metal extraction for replay LUT \(lut.name)")
                }
                let cpuExtracted = evaluateLUTBlindRotate(
                    truthTable: lut.table.map { UInt32($0) },
                    inputs: aLWEs,
                    bootstrapKey: bk,
                    scale: scale,
                    inputPacking: inputPackingMode,
                    keySwitchKey: keySwitchKey
                )
                let packedInputs = inspectPackedInputs(
                    aLWEs,
                    truthTableCount: lut.table.count
                )
                let expectedLogical = UInt32(lut.table[packedInputs.logicalAddress])
                let expectedPacked = UInt32(lut.table[packedInputs.packedAddress])
                func observation(_ extracted: LWECiphertext) -> String {
                    let raw = decryptLWE(extracted, secret: secret)
                    let rawWrapped = raw &- (expectedPacked &* scale)
                    let refreshed = publicRefreshBit(
                        extracted,
                        twoN: twoN,
                        scale: scale
                    )
                    let native = decryptLWE(refreshed, secret: secret) % UInt32(twoN)
                    let normalized = native &* torusStep
                    let refreshedWrapped = normalized &- (expectedPacked &* scale)
                    return String(
                        format: "raw=%u raw-bit=%u raw-residual=%lld raw-|e|=%u refreshed-native=%u refreshed-bit=%u refreshed-residual=%lld refreshed-|e|=%u",
                        raw,
                        decodeRotationBoolean(raw, scale: scale),
                        Int64(Int32(bitPattern: rawWrapped)),
                        torusCenteredMagnitude(rawWrapped),
                        native,
                        decodeRotationNativeBit(native, twoN: twoN, k: booleanK),
                        Int64(Int32(bitPattern: refreshedWrapped)),
                        torusCenteredMagnitude(refreshedWrapped)
                    )
                }
                print("ENCRYPTED LUT CPU REPLAY")
                print(
                    "  name=\(lut.name) wavefront=\(wavefront) y=\(lut.yWire) "
                        + "address-logical=\(packedInputs.logicalAddress) "
                        + "address-packed=\(packedInputs.packedAddress) "
                        + "expected-logical=\(expectedLogical) expected-packed=\(expectedPacked)"
                )
                print(
                    "  input-domain=\(packedInputs.inputPhaseDomain) "
                        + "input-phases=\(packedInputs.inputPhases) "
                        + "input-bits=\(packedInputs.inputBits) "
                        + "packed-native=\(packedInputs.packedNativePhase) "
                        + "expected-packed=\(packedInputs.expectedPackedPhase) "
                        + "offset=\(packedInputs.packedOffset)"
                )
                print("  cpu    \(observation(cpuExtracted))")
                print("  metal  \(observation(metalExtracted))")
                print("  ciphertext-equal=\(cpuExtracted == metalExtracted ? "yes" : "no")")
                fflush(stdout)
                if targetOnlyName != nil {
                    print("ENCRYPTED TARGET CONE result COMPLETE diagnostic-only=true")
                    fflush(stdout)
                    return [:]
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
                switch wireRefresh {
                case .secret:
                    noiseGrowth.afterBlindRotate(outputNoiseBound: 0)
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
                    // The public switch occurred on the weighted aggregate before BR.
                    // Canonicalize the extracted bit before downstream weighted packing;
                    // otherwise residual phase is multiplied by later LUT address weights.
                    noiseBudget.consume(.modulusSwitch)
                    noiseGrowth.afterExactModulusSwitch()
                    noiseGrowth.afterBlindRotate(outputNoiseBound: 0)
                    wires[lut.yWire] = scaleLWE(
                        publicRefreshBit(extracted, twoN: twoN, scale: scale),
                        torusStep
                    )
                case .none:
                    noiseGrowth.afterBlindRotate(outputNoiseBound: 0)
                    wires[lut.yWire] = extracted
                }
                noiseGrowth.assertDecodable()
            }
            if diagnosticsMode != .off {
                for (lut, aLWEs) in ready {
                    guard let output = wires[lut.yWire] else {
                        preconditionFailure("missing diagnostic output for LUT \(lut.name)")
                    }
                    diagnosticLUTs.append(
                        makeLUTDiagnostic(
                            lut: lut,
                            inputs: aLWEs,
                            output: output,
                            extracted: extractedByWire[lut.yWire],
                            wavefront: wavefront,
                            ordinal: diagnosticOrdinals[lut.name] ?? 0
                        )
                    )
                }
                if targetOnlyName != nil,
                   ProcessInfo.processInfo
                    .environment["HELUT_DIAGNOSTIC_STOP_AT_FIRST_CORRUPTION"] == "1",
                   let firstFailure = diagnosticLUTs
                    .sorted(by: {
                        ($0.wavefront, $0.ordinal) < ($1.wavefront, $1.ordinal)
                    })
                    .first(where: { $0.hasAddressAlias || $0.locallyCorrupt }) {
                    let kind = firstFailure.hasAddressAlias
                        ? "PACKED-ADDRESS-ALIAS"
                        : "LOCAL-CORRUPTION"
                    print("ENCRYPTED TARGET CONE FIRST \(kind)")
                    print(
                        "  name=\(firstFailure.name) wavefront=\(firstFailure.wavefront) "
                            + "ordinal=\(firstFailure.ordinal) y=\(firstFailure.yWire)"
                    )
                    print(
                        "  address-logical=\(firstFailure.encryptedAddress) "
                            + "address-packed=\(firstFailure.packedAddress) "
                            + "expected-logical=\(firstFailure.localExpectedBit) "
                            + "expected-packed=\(firstFailure.packedExpectedBit) "
                            + "actual=\(firstFailure.actualBit)"
                    )
                    print(
                        "  packed-domain=\(firstFailure.inputPhaseDomain) "
                            + "native=\(firstFailure.packedNativePhase) "
                            + "expected=\(firstFailure.expectedPackedPhase) "
                            + "offset=\(firstFailure.packedOffset)"
                    )
                    print(
                        String(
                            format: "  phase %@ raw=%u residual=%lld |e|=%u half-gap=%u",
                            firstFailure.phaseDomain,
                            firstFailure.rawPhase,
                            firstFailure.signedResidual,
                            firstFailure.residualMagnitude,
                            firstFailure.halfGap
                        )
                    )
                    print("ENCRYPTED TARGET CONE result FIRST-\(kind) diagnostic-only=true")
                    fflush(stdout)
                    return [:]
                }
            }
            pending = still
        }

        if !clear.dffs.isEmpty {
            try commitEncryptedDFFs(wires: &wires, bootstrapKey: bk)
        }

        if diagnosticsMode != .off, let diagnosticClear {
            _ = diagnosticClear.tick(inputs: inputs)
            for index in diagnosticLUTs.indices {
                if let clearEvaluation = diagnosticClear.lastLUTEvaluations[
                    diagnosticLUTs[index].name
                ] {
                    diagnosticLUTs[index].clearAddress = clearEvaluation.address
                    diagnosticLUTs[index].clearExpectedBit = clearEvaluation.output
                }
            }
            diagnosticLUTs.sort {
                ($0.wavefront, $0.ordinal) < ($1.wavefront, $1.ordinal)
            }
            let producerByWire = Dictionary(
                uniqueKeysWithValues: diagnosticLUTs.map { ($0.yWire, $0) }
            )
            var wrongDFFs: [EncryptedDFFDiagnostic] = []
            for dff in clear.dffs {
                let expected = diagnosticClear.state[dff.qWire] ?? 0
                guard let encrypted = encryptedQ[dff.qWire] else { continue }
                let raw = decryptLWE(encrypted, secret: secret)
                let usesTorusDomain = wireRefresh == .publicMS || wireRefresh == .none
                let rawPhase = usesTorusDomain ? raw : raw % UInt32(twoN)
                let actual = UInt8(
                    usesTorusDomain
                        ? decodeRotationBoolean(rawPhase, scale: scale)
                        : decodeRotationNativeBit(rawPhase, twoN: twoN, k: booleanK)
                )
                guard actual != expected else { continue }
                let normalized = usesTorusDomain ? rawPhase : rawPhase &* torusStep
                let expectedPhase = UInt32(expected) &* scale
                let wrapped = normalized &- expectedPhase
                let producer: EncryptedLUTDiagnostic?
                if case .net(let dWire) = dff.dBit {
                    producer = producerByWire[dWire]
                } else {
                    producer = nil
                }
                wrongDFFs.append(
                    EncryptedDFFDiagnostic(
                        name: dff.name,
                        type: dff.type,
                        qWire: dff.qWire,
                        dBit: Self.describe(bit: dff.dBit),
                        expectedBit: expected,
                        actualBit: actual,
                        rawPhase: rawPhase,
                        phaseDomain: usesTorusDomain ? "full-torus-wire" : "rotation-native",
                        normalizedTorusPhase: normalized,
                        signedResidual: Int64(Int32(bitPattern: wrapped)),
                        residualMagnitude: torusCenteredMagnitude(wrapped),
                        halfGap: scale >> 1,
                        producerName: producer?.name,
                        producerWavefront: producer?.wavefront,
                        producerArity: producer?.arity,
                        producerINIT: producer?.initMSBFirst
                    )
                )
            }
            lastTickDiagnostics = EncryptedTickDiagnostics(
                backend: backend.rawValue,
                wireRefresh: wireRefresh.rawValue,
                serialWavefront: ProcessInfo.processInfo
                    .environment["HELUT_SERIAL_WAVEFRONT"] == "1",
                lutRecords: diagnosticLUTs,
                wrongDFFs: wrongDFFs
            )
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
                    if wireRefresh == .publicMS || wireRefresh == .none {
                        return UInt8(decodeRotationBoolean(phase, scale: scale))
                    }
                    return UInt8(decodeRotationNativeBit(phase, twoN: twoN, k: booleanK))
                }
            }
        }
        lastTickFingerprint = Self.fingerprint(
            wires: wires.merging(encryptedQ) { current, _ in current },
            ports: clear.outputPorts
        )
        return outputs
    }

    private struct PackedInputInspection {
        var inputPhaseDomain: String
        var inputPhases: [UInt32]
        var inputBits: [UInt32]
        var logicalAddress: Int
        var packedNativePhase: UInt32
        var expectedPackedPhase: UInt32
        var packedOffset: Int
        var packedAddress: Int
    }

    private func inspectPackedInputs(
        _ inputs: [LWECiphertext],
        truthTableCount: Int
    ) -> PackedInputInspection {
        let usesTorusDomain = wireRefresh == .publicMS || wireRefresh == .none
        var inputPhases: [UInt32] = []
        var inputBits: [UInt32] = []
        var logicalAddress = 0
        for (index, input) in inputs.enumerated() {
            let raw = decryptLWE(input, secret: secret)
            let phase = usesTorusDomain ? raw : raw % UInt32(twoN)
            let bit = usesTorusDomain
                ? decodeRotationBoolean(phase, scale: scale)
                : decodeRotationNativeBit(phase, twoN: twoN, k: booleanK)
            inputPhases.append(phase)
            inputBits.append(bit)
            if bit != 0 { logicalAddress |= 1 << index }
        }

        let packed = packLWEBits(
            inputs,
            twoN: twoN,
            scale: scale,
            mode: inputPackingMode
        )
        let packedNativePhase = decryptLWE(packed, secret: secret) % UInt32(twoN)
        let expectedPackedPhase = UInt32(booleanK * logicalAddress)
        let forwardOffset = (
            Int(packedNativePhase) - Int(expectedPackedPhase) + twoN
        ) % twoN
        let packedOffset = forwardOffset > twoN / 2
            ? forwardOffset - twoN
            : forwardOffset

        func circularDistance(_ lhs: Int, _ rhs: Int) -> Int {
            let direct = abs(lhs - rhs)
            return min(direct, twoN - direct)
        }
        var packedAddress = 0
        var bestDistance = Int.max
        for address in 0..<truthTableCount {
            let center = (booleanK * address) % twoN
            let distance = circularDistance(Int(packedNativePhase), center)
            if distance < bestDistance {
                bestDistance = distance
                packedAddress = address
            }
        }

        return PackedInputInspection(
            inputPhaseDomain: inputPackingMode.rawValue,
            inputPhases: inputPhases,
            inputBits: inputBits,
            logicalAddress: logicalAddress,
            packedNativePhase: packedNativePhase,
            expectedPackedPhase: expectedPackedPhase,
            packedOffset: packedOffset,
            packedAddress: packedAddress
        )
    }

    private func makeLUTDiagnostic(
        lut: CleartextNetlistSimulator.LUTCell,
        inputs: [LWECiphertext],
        output: LWECiphertext,
        extracted: LWECiphertext?,
        wavefront: Int,
        ordinal: Int
    ) -> EncryptedLUTDiagnostic {
        let packedInputs = inspectPackedInputs(inputs, truthTableCount: lut.table.count)
        let localExpected = lut.table[packedInputs.logicalAddress]
        let packedExpected = lut.table[packedInputs.packedAddress]
        let isExtracted = extracted != nil
        let outputUsesTorusDomain = isExtracted
            || wireRefresh == .publicMS
            || wireRefresh == .none
        let outputCiphertext = extracted ?? output
        let decrypted = decryptLWE(outputCiphertext, secret: secret)
        let rawPhase = outputUsesTorusDomain ? decrypted : decrypted % UInt32(twoN)
        let actual: UInt8
        let normalized: UInt32
        let phaseDomain: String
        if outputUsesTorusDomain {
            actual = UInt8(decodeRotationBoolean(rawPhase, scale: scale))
            normalized = rawPhase
            phaseDomain = isExtracted ? "torus-extracted" : "full-torus-wire"
        } else {
            actual = UInt8(
                decodeRotationNativeBit(rawPhase, twoN: twoN, k: booleanK)
            )
            normalized = rawPhase &* torusStep
            phaseDomain = "rotation-native"
        }
        let wrapped = normalized &- (UInt32(packedExpected) &* scale)
        return EncryptedLUTDiagnostic(
            wavefront: wavefront,
            ordinal: ordinal,
            name: lut.name,
            yWire: lut.yWire,
            aBits: lut.aBits.map { Self.describe(bit: $0) },
            arity: lut.aBits.count,
            initMSBFirst: lut.initMSBFirst,
            tableLSBFirst: lut.table.map(String.init).joined(),
            clearAddress: nil,
            encryptedAddress: packedInputs.logicalAddress,
            packedAddress: packedInputs.packedAddress,
            clearExpectedBit: nil,
            localExpectedBit: localExpected,
            packedExpectedBit: packedExpected,
            actualBit: actual,
            inputPhaseDomain: packedInputs.inputPhaseDomain,
            packedNativePhase: packedInputs.packedNativePhase,
            expectedPackedPhase: packedInputs.expectedPackedPhase,
            packedOffset: packedInputs.packedOffset,
            rawPhase: rawPhase,
            phaseDomain: phaseDomain,
            signedResidual: Int64(Int32(bitPattern: wrapped)),
            residualMagnitude: torusCenteredMagnitude(wrapped),
            halfGap: scale >> 1,
            skippedBlindRotate: !isExtracted
        )
    }

    private static func describe(bit: YosysBit) -> String {
        switch bit {
        case .net(let id): return "net(\(id))"
        case .constant(let value): return "const(\(value))"
        }
    }

    /// Single MPSGraph for all `$lut`s (dynamic X^p + publicMS). Primary wires are full-torus.
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
                    // Satisfy topo for subsequent LUTs with a temporary full-torus zero.
                    wires[lut.yWire] = encryptWireBit(0)
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
            keySwitchKey: keySwitchKey,
            inputPacking: .fullTorusPublicMS
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
                    return UInt8(decodeRotationBoolean(phase, scale: scale))
                }
            }
        }
        lastTickFingerprint = Self.fingerprint(wires: wires, ports: clear.outputPorts)
        return outputs
    }

    /// Stable fingerprint of the ciphertexts backing this tick's outputs.
    ///
    /// Exists so a test can see *ciphertext* divergence, not just decoded bits.
    /// A decoded output can agree while the underlying ciphertexts differ, which
    /// is exactly how the 2026-08-15 determinism bug hid: it only flipped a bit
    /// where the noise margin was thin, so small-N tests passed.
    ///
    /// Deliberately FNV-1a and not Swift's `Hasher`: `Hasher` is seeded per
    /// process, so using it here would make the fingerprint vary run to run and
    /// destroy the property being tested.
    package private(set) var lastTickFingerprint: UInt64 = 0

    /// Fingerprint of the freshly encrypted *primary input* ciphertexts, taken
    /// immediately after the input-encryption loop.
    ///
    /// This is the surface the 2026-08-15 determinism bug actually lived on, and
    /// it is the right place to test it. Fingerprinting the tick *outputs*
    /// cannot see the fault under an e=0 bootstrap key, because blind rotation
    /// cancels the input mask exactly; and turning the BK noise up far enough to
    /// make masks matter downstream pushes `booleanPublicMS` past δ/2 and traps.
    /// Observing the inputs sidesteps both problems.
    package private(set) var lastInputFingerprint: UInt64 = 0

    static func fingerprint(
        wires: [Int: LWECiphertext],
        ports: [String: [YosysBit]]
    ) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        func mix(_ v: UInt32) {
            for shift in [0, 8, 16, 24] {
                h ^= UInt64((v >> UInt32(shift)) & 0xFF)
                h = h &* 0x0000_0100_0000_01B3
            }
        }
        // Sorted so the fingerprint itself is order-independent.
        for (port, bits) in ports.sorted(by: { $0.key < $1.key }) {
            for byte in port.utf8 {
                h ^= UInt64(byte)
                h = h &* 0x0000_0100_0000_01B3
            }
            for bit in bits {
                guard case .net(let wire) = bit, let ct = wires[wire] else { continue }
                mix(ct.b)
                for coeff in ct.a { mix(coeff) }
            }
        }
        return h
    }

    /// Host posedge: mux D/Q/reset in the clear, copying ciphertexts in their wire domain.
    /// The DFF primitive is the host clock; public-MS Q remains full-torus across ticks.
    private func commitEncryptedDFFs(
        wires: inout [Int: LWECiphertext],
        bootstrapKey bk: BootstrapKey
    ) throws {
        _ = bk
        // Every DFF samples the same pre-edge wire image. Mutating `wires`
        // inside this loop made direct Q→D chains depend on cell-name order.
        let preCommitWires = wires
        var nextQ: [Int: LWECiphertext] = [:]
        for dff in clear.dffs {
            guard let dLWE = resolveLWEBit(dff.dBit, wires: preCommitWires) else {
                fatalError("Missing D for encrypted DFF \(dff.name)")
            }
            let qCur = encryptedQ[dff.qWire] ?? dLWE

            var enabled = true
            if let enableBit = dff.enableBit {
                guard let eLWE = resolveLWEBit(enableBit, wires: preCommitWires) else {
                    fatalError("Missing E for encrypted DFF \(dff.name)")
                }
                let rawE = decryptWireBit(eLWE)
                let enableActiveHigh = dff.polarity.enableActiveHigh ?? true
                enabled = (enableActiveHigh ? rawE : (1 - rawE)) != 0
            }

            var resetAsserted = false
            var resetValue: UInt32 = 0
            if let resetBit = dff.resetBit {
                guard let rLWE = resolveLWEBit(resetBit, wires: preCommitWires) else {
                    fatalError("Missing R for encrypted DFF \(dff.name)")
                }
                let rawR = decryptWireBit(rLWE)
                let sync = dff.polarity.syncReset ?? (activeHigh: true, value: 0)
                resetAsserted = (sync.activeHigh ? rawR : (1 - rawR)) != 0
                resetValue = sync.value & 1
            }

            let qNext: LWECiphertext
            if dff.polarity.clockEnableGatesReset {
                if !enabled {
                    qNext = qCur
                } else if resetAsserted {
                    qNext = encryptWireBit(resetValue)
                } else {
                    qNext = dLWE
                }
            } else if resetAsserted {
                qNext = encryptWireBit(resetValue)
            } else if dff.enableBit != nil && !enabled {
                qNext = qCur
            } else {
                qNext = dLWE
            }
            nextQ[dff.qWire] = qNext
        }
        for (wire, value) in nextQ { wires[wire] = value }
        encryptedQ = nextQ
    }

    private var inputPackingMode: LWEInputPackingMode {
        wireRefresh == .publicMS ? .fullTorusPublicMS : .rotationNative
    }

    /// Encrypt one boolean in the simulator's inter-LUT wire domain.
    private func encryptWireBit(_ bit: UInt32) -> LWECiphertext {
        let native = encryptLWERotationNative(
            message: encodeRotationNativeBit(bit, k: booleanK),
            secret: secret.lweSecret,
            twoN: twoN,
            rng: &rng
        )
        if wireRefresh == .publicMS {
            return scaleLWE(native, torusStep)
        }
        return native
    }

    private func decryptWireBit(_ ct: LWECiphertext) -> UInt8 {
        let phase = decryptLWE(ct, secret: secret)
        if wireRefresh == .publicMS || wireRefresh == .none {
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
            return extracted
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
                inputPacking: inputPackingMode,
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
                inputPacking: inputPackingMode,
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
                values.append(encryptWireBit(UInt32(value)))
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
        if bkNoise.bound == 0 && !bkNoise.usesGaussian {
            _ = issueNoisyBKCertificate()
        }
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
