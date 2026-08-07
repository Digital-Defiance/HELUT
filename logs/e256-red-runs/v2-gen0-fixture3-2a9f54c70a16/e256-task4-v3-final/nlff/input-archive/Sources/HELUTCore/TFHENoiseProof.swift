import Foundation

// MARK: - Bounded ∞-norm noise proof (graduation step 10i)
//
// Machine-checkable lemmas for HELUT’s discrete centered-uniform inject model.
// This is a *bounded engineering proof* under explicit parameter hypotheses —
// not a production TFHE asymptotic security proof (see `TFHENoise.refuse`).

/// Named lemmas in the HELUT noise calculus.
package enum TFHENoiseLemma: String, Sendable {
    /// Encrypt with centered-uniform inject of bound `B` ⇒ `|e| ≤ B`.
    case encrypt
    /// `|e_{x+y}| ≤ |e_x| + |e_y|`.
    case add
    /// `|e_{c·x}| ≤ c · |e_x|` for scalar `c` (torus, no half-gap wrap assumed).
    case scale
    /// Lattice `publicRefreshBit` with `|e| < δ/2` and `a ∈ δℤ` ⇒ exact `Z_{2N}` phase.
    case exactModulusSwitch
    /// Blind-rotate under noiseless BK refreshes `|e| → 0` (HELUT e=0 BK).
    case blindRotateRefresh
    /// Decode correct when `|e| < Δ/2`.
    case decodeMargin
}

/// One step in a noise certificate (predicted bound after the lemma).
package struct TFHENoiseProofStep: Sendable, Equatable {
    package var lemma: TFHENoiseLemma
    package var boundAfter: UInt64
    package var note: String

    package init(lemma: TFHENoiseLemma, boundAfter: UInt64, note: String = "") {
        self.lemma = lemma
        self.boundAfter = boundAfter
        self.note = note
    }
}

/// End-to-end bounded noise certificate for a HELUT encrypted evaluation.
package struct TFHENoiseCertificate: Sendable, Equatable {
    package var delta: UInt32
    package var inputNoiseBound: UInt32
    package var steps: [TFHENoiseProofStep]
    package var finalBound: UInt64
    package var hypotheses: [String]

    package var isDecodable: Bool { finalBound < UInt64(delta / 2) }

    package var decodingHalfGap: UInt32 { delta / 2 }

    package init(
        delta: UInt32,
        inputNoiseBound: UInt32,
        steps: [TFHENoiseProofStep],
        hypotheses: [String]
    ) {
        self.delta = delta
        self.inputNoiseBound = inputNoiseBound
        self.steps = steps
        self.finalBound = steps.last?.boundAfter ?? 0
        self.hypotheses = hypotheses
    }

    package func assertValid(file: StaticString = #file, line: UInt = #line) {
        precondition(
            isDecodable,
            "TFHENoiseCertificate undecodable finalBound=\(finalBound) halfGap=\(decodingHalfGap) at \(file):\(line)"
        )
        precondition(
            UInt64(inputNoiseBound) < UInt64(decodingHalfGap),
            "input noise must be < δ/2 for exact ingest MS"
        )
    }
}

/// Prove / check bounded noise lemmas for HELUT’s discrete-inject path.
package enum TFHENoiseProof {
    /// Centered magnitude of a torus residual.
    package static func centeredMagnitude(_ value: UInt32) -> UInt32 {
        min(value, UInt32(0) &- value)
    }

    /// Lemma encrypt: measured `|e| ≤ B` over `trials` fresh samples.
    @discardableResult
    package static func checkEncrypt(
        bound: UInt32,
        secret: [UInt32],
        trials: Int = 256,
        seed: UInt32 = 0xE001
    ) -> Bool {
        var rng = LCG32(state: seed == 0 ? 1 : seed)
        let noise = TFHENoiseParams(bound: bound)
        for _ in 0..<trials {
            let message: UInt32 = rng.next() & 1
            let ct = encryptLWE(message: message, secret: secret, rng: &rng, noise: noise)
            var phase = ct.b
            for i in 0..<secret.count {
                phase &-= ct.a[i] &* secret[i]
            }
            let err = phase &- message
            if centeredMagnitude(err) > bound {
                return false
            }
        }
        return true
    }

    /// Lemma add: `|e_{x+y}| ≤ Bx + By`.
    @discardableResult
    package static func checkAdd(
        boundX: UInt32,
        boundY: UInt32,
        secret: [UInt32],
        trials: Int = 128,
        seed: UInt32 = 0xE002
    ) -> Bool {
        var rng = LCG32(state: seed == 0 ? 1 : seed)
        let nx = TFHENoiseParams(bound: boundX)
        let ny = TFHENoiseParams(bound: boundY)
        let lim = UInt64(boundX) &+ UInt64(boundY)
        for _ in 0..<trials {
            let mx: UInt32 = rng.next() & 1
            let my: UInt32 = rng.next() & 1
            let x = encryptLWE(message: mx, secret: secret, rng: &rng, noise: nx)
            let y = encryptLWE(message: my, secret: secret, rng: &rng, noise: ny)
            let z = addLWE(x, y)
            var phase = z.b
            for i in 0..<secret.count {
                phase &-= z.a[i] &* secret[i]
            }
            let err = phase &- (mx &+ my)
            if UInt64(centeredMagnitude(err)) > lim {
                return false
            }
        }
        return true
    }

    /// Lemma scale: `|e_{c·x}| ≤ c · Bx` for small `c`.
    @discardableResult
    package static func checkScale(
        bound: UInt32,
        scalar: UInt32,
        secret: [UInt32],
        trials: Int = 128,
        seed: UInt32 = 0xE003
    ) -> Bool {
        precondition(scalar >= 1 && scalar <= 16)
        var rng = LCG32(state: seed == 0 ? 1 : seed)
        let noise = TFHENoiseParams(bound: bound)
        let lim = UInt64(bound) &* UInt64(scalar)
        for _ in 0..<trials {
            let message: UInt32 = rng.next() & 1
            let x = encryptLWE(message: message, secret: secret, rng: &rng, noise: noise)
            let z = scaleLWE(x, scalar)
            var phase = z.b
            for i in 0..<secret.count {
                phase &-= z.a[i] &* secret[i]
            }
            let err = phase &- (message &* scalar)
            if UInt64(centeredMagnitude(err)) > lim {
                return false
            }
        }
        return true
    }

    /// Lemma exact MS: scaled lattice encrypt with `|e| < δ/2` folds to exact native bit.
    @discardableResult
    package static func checkExactModulusSwitch(
        polynomialDegree n: Int,
        noiseBound: UInt32,
        secret: TFHESecretKey,
        trials: Int = 128,
        seed: UInt32 = 0xE004
    ) -> Bool {
        let twoN = 2 * n
        let scale = rotationScale(polynomialDegree: n)
        precondition(UInt64(noiseBound) < UInt64(scale / 2))
        var rng = LCG32(state: seed == 0 ? 1 : seed)
        let noise = TFHENoiseParams(bound: noiseBound)
        for bit: UInt32 in [0, 1] {
            for _ in 0..<trials {
                let scaled = encryptLWE(
                    message: bit &* scale,
                    secret: secret.lweSecret,
                    rng: &rng,
                    noise: noise,
                    maskStride: scale
                )
                let native = publicRefreshBit(scaled, twoN: twoN, scale: scale)
                let phase = decryptLWE(native, secret: secret)
                if (phase & 1) != bit {
                    return false
                }
            }
        }
        return true
    }

    /// Lemma BR refresh: after LUT blind-rotate under noiseless BK, residual `|e| = 0`
    /// relative to the scaled boolean message (decode exact).
    @discardableResult
    package static func checkBlindRotateRefresh(
        params: GGSWParams,
        secret: TFHESecretKey,
        inputNoiseBound: UInt32,
        trials: Int = 32,
        seed: UInt32 = 0xE005
    ) -> Bool {
        let n = params.tfhe.polynomialDegree
        let twoN = 2 * n
        let scale = rotationScale(polynomialDegree: n)
        precondition(UInt64(inputNoiseBound) < UInt64(scale / 2))
        var rng = LCG32(state: seed == 0 ? 1 : seed)
        let bk = bootstrapKey(
            secret: secret,
            params: params,
            rng: &rng,
            publicRefreshCompatible: true
        )
        let noise = TFHENoiseParams(bound: inputNoiseBound)
        let xor: [UInt32] = [0, 1, 1, 0]
        for _ in 0..<trials {
            let x = rng.next() & 1
            let y = rng.next() & 1
            let lx = publicRefreshBit(
                encryptLWE(
                    message: x &* scale,
                    secret: secret.lweSecret,
                    rng: &rng,
                    noise: noise,
                    maskStride: scale
                ),
                twoN: twoN,
                scale: scale
            )
            let ly = publicRefreshBit(
                encryptLWE(
                    message: y &* scale,
                    secret: secret.lweSecret,
                    rng: &rng,
                    noise: noise,
                    maskStride: scale
                ),
                twoN: twoN,
                scale: scale
            )
            let out = evaluateLUTBlindRotate(
                truthTable: xor,
                inputs: [lx, ly],
                bootstrapKey: bk,
                scale: scale
            )
            let got = decodeRotationBoolean(decryptLWE(out, secret: secret), scale: scale)
            if got != (x ^ y) {
                return false
            }
        }
        return true
    }

    /// Certificate for HELUT’s encrypted netlist ingest → PBS → publicMS path.
    ///
    /// Hypotheses:
    /// 1. `inputNoiseBound < δ/2`
    /// 2. BK encrypted noiseless (`e = 0`) with lattice-compatible masks when using public MS
    /// 3. Primary scaled inputs folded to `Z_{2N}` before pack
    /// 4. Inter-LUT refresh is `.publicMS` or `.secret` (not raw `.none` mixing)
    package static func certificateEncryptedNetlist(
        polynomialDegree n: Int,
        inputNoiseBound: UInt32,
        lutCount: Int,
        wireRefresh: EncryptedWireRefresh
    ) -> TFHENoiseCertificate {
        let delta = rotationScale(polynomialDegree: n)
        var steps: [TFHENoiseProofStep] = []
        var bound = UInt64(inputNoiseBound)
        steps.append(
            TFHENoiseProofStep(
                lemma: .encrypt,
                boundAfter: bound,
                note: "scaled lattice primary encrypt"
            )
        )
        // Ingest MS: |e| < δ/2 ⇒ exact Z_{2N} (noise floor 0).
        bound = 0
        steps.append(
            TFHENoiseProofStep(
                lemma: .exactModulusSwitch,
                boundAfter: bound,
                note: "fold to Z_{2N} before packLWEBits"
            )
        )
        for i in 0..<lutCount {
            bound = 0
            steps.append(
                TFHENoiseProofStep(
                    lemma: .blindRotateRefresh,
                    boundAfter: bound,
                    note: "LUT[\(i)] noiseless BK PBS"
                )
            )
            switch wireRefresh {
            case .publicMS:
                steps.append(
                    TFHENoiseProofStep(
                        lemma: .exactModulusSwitch,
                        boundAfter: 0,
                        note: "inter-LUT publicRefreshBit"
                    )
                )
            case .secret:
                steps.append(
                    TFHENoiseProofStep(
                        lemma: .encrypt,
                        boundAfter: 0,
                        note: "inter-LUT secret rotation-native re-encrypt"
                    )
                )
            case .none:
                // No refresh: certificate only valid for single-LUT depth.
                precondition(lutCount <= 1, "certificate requires refresh for multi-LUT")
            }
        }
        steps.append(
            TFHENoiseProofStep(
                lemma: .decodeMargin,
                boundAfter: bound,
                note: "require bound < δ/2"
            )
        )
        return TFHENoiseCertificate(
            delta: delta,
            inputNoiseBound: inputNoiseBound,
            steps: steps,
            hypotheses: [
                "inputNoiseBound < δ/2 (δ = q/(2N))",
                "BK noiseless (e=0) with lattice masks when publicMS",
                "scaled primaries folded to Z_{2N} before pack",
                "wireRefresh ∈ {publicMS, secret} for multi-LUT",
                "centered-uniform discrete inject model (not Gaussian TFHE)"
            ]
        )
    }

    /// Run all core lemma checks; returns false on first failure.
    package static func verifyCoreLemmas(
        degree: Int = 8,
        seed: UInt32 = 0xE100
    ) -> Bool {
        let params = GGSWParams.crypto(degree: degree)
        let secret = TFHESecretKey.random(params: params.tfhe, seed: seed)
        let s = secret.lweSecret
        let scale = rotationScale(polynomialDegree: degree)
        let demo = TFHENoiseParams.demo.bound
        precondition(UInt64(demo) < UInt64(scale / 2))

        guard checkEncrypt(bound: demo, secret: s, seed: seed &+ 1) else { return false }
        guard checkAdd(boundX: demo, boundY: demo, secret: s, seed: seed &+ 2) else { return false }
        guard checkScale(bound: demo, scalar: 4, secret: s, seed: seed &+ 3) else { return false }
        guard checkExactModulusSwitch(
            polynomialDegree: degree,
            noiseBound: demo,
            secret: secret,
            seed: seed &+ 4
        ) else { return false }
        guard checkBlindRotateRefresh(
            params: params,
            secret: secret,
            inputNoiseBound: demo,
            seed: seed &+ 5
        ) else { return false }

        let cert = certificateEncryptedNetlist(
            polynomialDegree: degree,
            inputNoiseBound: demo,
            lutCount: 3,
            wireRefresh: .publicMS
        )
        cert.assertValid()
        return cert.isDecodable
    }
}
