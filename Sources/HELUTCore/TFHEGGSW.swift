import Foundation

// MARK: - GGSW external product (graduation steps 7–8a)
//
// Step 7: trivial s=0 + boolean gadget (baseLog=32, ℓ=1).
// Step 8a: non-zero binary secret + crypto gadget (β=8, ℓ=4), still e=0.
// Metal `$lut` path remains CMUX/rotate on body-only wires; CPU certifies GGSW.

/// Decomposition gadget for GGSW.
package struct GGSWParams: Sendable, Equatable {
    package var tfhe: TFHEParams
    /// log2(B) for base B.
    package var baseLog: Int
    /// Number of decomposition levels ℓ.
    package var levelCount: Int

    package init(tfhe: TFHEParams, baseLog: Int, levelCount: Int) {
        precondition(baseLog > 0 && baseLog <= 32)
        precondition(levelCount > 0)
        precondition(baseLog * levelCount <= 32)
        self.tfhe = tfhe
        self.baseLog = baseLog
        self.levelCount = levelCount
    }

    /// Exact boolean gadget: one level, digit = full coefficient, `g₀ = 1`.
    /// Use for secret-refresh / paths that do not need a `δ`-lattice. For public MS, use
    /// `booleanPublicMS` (`g₀ = δ`).
    package static func booleanTrivial(degree: Int = 1024, glweDimension: Int = 1) -> GGSWParams {
        GGSWParams(
            tfhe: TFHEParams(polynomialDegree: degree, glweDimension: glweDimension, delta: 1),
            baseLog: 32,
            levelCount: 1
        )
    }

    /// Public-MS boolean gadget: `ℓ = 1`, `g₀ = δ = q/(2N)` so a `δ`-scaled ACC stays on-lattice.
    /// Requires ACC coeffs ≡ 0 (mod δ); rounded MS fails for `n ≳ 256` with `g₀ = 1`.
    package static func booleanPublicMS(degree: Int = 1024, glweDimension: Int = 1) -> GGSWParams {
        precondition(degree >= 2 && degree.nonzeroBitCount == 1, "degree must be a power of two")
        let baseLog = 1 + degree.trailingZeroBitCount // log₂(2N) ⇒ g₀ = δ
        return GGSWParams(
            tfhe: TFHEParams(polynomialDegree: degree, glweDimension: glweDimension, delta: 1),
            baseLog: baseLog,
            levelCount: 1
        )
    }

    /// Cryptographic-shaped gadget (`B = 2^8`, `ℓ = 4`) with `e = 0`.
    /// Exact public MS only when `δ = g₀` (`N = 128`). Prefer `cryptoPublicMS` otherwise.
    package static func crypto(degree: Int = 1024, glweDimension: Int = 1) -> GGSWParams {
        GGSWParams(
            tfhe: TFHEParams(polynomialDegree: degree, glweDimension: glweDimension, delta: 1),
            baseLog: 8,
            levelCount: 4
        )
    }

    /// Exact covering gadget under \(q=2^{32}\): `baseLog·ℓ = 32`.
    /// Smaller `baseLog` ⇒ smaller EP digit bound β ⇒ less BK-noise amplification (H4 Track A).
    package static func covering(
        degree: Int,
        baseLog: Int,
        glweDimension: Int = 1
    ) -> GGSWParams {
        precondition(baseLog > 0 && baseLog <= 32 && 32 % baseLog == 0)
        return GGSWParams(
            tfhe: TFHEParams(polynomialDegree: degree, glweDimension: glweDimension, delta: 1),
            baseLog: baseLog,
            levelCount: 32 / baseLog
        )
    }

    /// Public-MS crypto gadget: `g₀ = δ`, `ℓ = ⌊32 / baseLog⌋` (at `N = 128` matches `.crypto`).
    package static func cryptoPublicMS(degree: Int = 1024, glweDimension: Int = 1) -> GGSWParams {
        precondition(degree >= 2 && degree.nonzeroBitCount == 1, "degree must be a power of two")
        let baseLog = 1 + degree.trailingZeroBitCount // log₂(2N) ⇒ g₀ = δ
        let levelCount = max(1, 32 / baseLog)
        return GGSWParams(
            tfhe: TFHEParams(polynomialDegree: degree, glweDimension: glweDimension, delta: 1),
            baseLog: baseLog,
            levelCount: levelCount
        )
    }

    /// Cut blind-rotate CMUX count (`n` LWE mask bits). Does not change `N` or the gadget.
    package func withLWEDimension(_ n: Int) -> GGSWParams {
        GGSWParams(tfhe: tfhe.withLWEDimension(n), baseLog: baseLog, levelCount: levelCount)
    }
    package var gadget: [UInt32] {
        (0..<levelCount).map { i in
            let shift = 32 - (i + 1) * baseLog
            return shift >= 0 ? (1 as UInt32) &<< UInt32(shift) : 0
        }
    }

    package var rowsPerLevel: Int { tfhe.glweDimension + 1 }
    package var glweCount: Int { rowsPerLevel * levelCount }
}

/// GGSW ciphertext: `(k+1)·ℓ` GLWE rows, indexed `[row * levelCount + level]`.
/// Row `0..<k` are mask rows; row `k` is the body row.
package struct GGSWCiphertext: Sendable, Equatable {
    package var params: GGSWParams
    package var rows: [GLWECiphertext]
    /// Clear message bit when trivial; `nil` if unknown / non-trivial.
    package var trivialBit: UInt32?

    package init(params: GGSWParams, rows: [GLWECiphertext], trivialBit: UInt32? = nil) {
        precondition(rows.count == params.glweCount)
        self.params = params
        self.rows = rows
        self.trivialBit = trivialBit
    }

    package func row(glweRow: Int, level: Int) -> GLWECiphertext {
        rows[glweRow * params.levelCount + level]
    }
}

/// Bootstrapping key: one GGSW per LWE mask bit (plus optional body handling).
package struct BootstrapKey: Sendable {
    package var params: GGSWParams
    package var bitKeys: [GGSWCiphertext]

    package init(params: GGSWParams, bitKeys: [GGSWCiphertext]) {
        self.params = params
        self.bitKeys = bitKeys
    }
}

/// Key-switching key: GLev encrypts of each input-secret bit under the output secret.
package struct KeySwitchKey: Sendable {
    package var inputDimension: Int
    package var outputDimension: Int
    package var baseLog: Int
    package var levelCount: Int
    /// `entries[i][level]` encrypts `s_in[i] · g_level` under `s_out` (`e = 0`).
    package var entries: [[LWECiphertext]]
    package var isIdentity: Bool
    /// `1` = 32-bit torus GLev. `δ` = rotation-native extract (decompose `a/δ` in `Z_{2N}`).
    package var inputStride: UInt32

    package init(
        inputDimension: Int,
        outputDimension: Int,
        baseLog: Int,
        levelCount: Int,
        entries: [[LWECiphertext]],
        isIdentity: Bool,
        inputStride: UInt32 = 1
    ) {
        self.inputDimension = inputDimension
        self.outputDimension = outputDimension
        self.baseLog = baseLog
        self.levelCount = levelCount
        self.entries = entries
        self.isIdentity = isIdentity
        self.inputStride = inputStride
        precondition(inputStride >= 1)
    }

    package static func trivialIdentity(dimension: Int) -> KeySwitchKey {
        KeySwitchKey(
            inputDimension: dimension,
            outputDimension: dimension,
            baseLog: 32,
            levelCount: 1,
            entries: [],
            isIdentity: true
        )
    }
}

/// Build a key-switch key from binary LWE secret `from` to `to` (`e = 0`).
package func makeKeySwitchKey(
    from fromSecret: [UInt32],
    to toSecret: [UInt32],
    baseLog: Int = 8,
    levelCount: Int = 4,
    rng: inout LCG32
) -> KeySwitchKey {
    precondition(fromSecret.allSatisfy { $0 == 0 || $0 == 1 })
    precondition(toSecret.allSatisfy { $0 == 0 || $0 == 1 })
    precondition(baseLog * levelCount == 32)
    let gadget: [UInt32] = (0..<levelCount).map { i in
        let shift = 32 - (i + 1) * baseLog
        return (1 as UInt32) &<< UInt32(shift)
    }
    var entries: [[LWECiphertext]] = []
    entries.reserveCapacity(fromSecret.count)
    for sBit in fromSecret {
        var levels: [LWECiphertext] = []
        levels.reserveCapacity(levelCount)
        for level in 0..<levelCount {
            let message = sBit &* gadget[level]
            levels.append(encryptLWE(message: message, secret: toSecret, rng: &rng))
        }
        entries.append(levels)
    }
    return KeySwitchKey(
        inputDimension: fromSecret.count,
        outputDimension: toSecret.count,
        baseLog: baseLog,
        levelCount: levelCount,
        entries: entries,
        isIdentity: false
    )
}

/// KSK from sample-extract (`kN`) down to the LWE secret used for the next MS/BR.
/// Identity when `n = kN` (today's default). Real GLev (`e = 0`) when `--lwe-dimension n < N`.
package func extractToLWEKeySwitchKey(
    secret: TFHESecretKey,
    rng: inout LCG32
) -> KeySwitchKey {
    let from = secret.polynomials.flatMap { $0 }
    let to = secret.lweSecret
    if from.count == to.count {
        return .trivialIdentity(dimension: from.count)
    }
    return makeRotationNativeKeySwitchKey(
        from: from,
        to: to,
        polynomialDegree: secret.params.polynomialDegree,
        rng: &rng
    )
}

/// GLev on the `δ`-lattice: digits of `a/δ ∈ Z_{2N}` so public-MS after KS stays exact.
package func makeRotationNativeKeySwitchKey(
    from fromSecret: [UInt32],
    to toSecret: [UInt32],
    polynomialDegree n: Int,
    rng: inout LCG32
) -> KeySwitchKey {
    precondition(fromSecret.allSatisfy { $0 == 0 || $0 == 1 })
    precondition(toSecret.allSatisfy { $0 == 0 || $0 == 1 })
    let twoN = 2 * n
    precondition(twoN > 1 && twoN.nonzeroBitCount == 1)
    let bits = twoN.trailingZeroBitCount
    let baseLog = 4
    let levelCount = (bits + baseLog - 1) / baseLog
    let delta = rotationScale(polynomialDegree: n)
    let gadget: [UInt32] = (0..<levelCount).map { i in
        delta &<< UInt32(i * baseLog)
    }
    var entries: [[LWECiphertext]] = []
    entries.reserveCapacity(fromSecret.count)
    for sBit in fromSecret {
        var levels: [LWECiphertext] = []
        levels.reserveCapacity(levelCount)
        for level in 0..<levelCount {
            let message = sBit &* gadget[level]
            levels.append(
                encryptLWE(
                    message: message,
                    secret: toSecret,
                    rng: &rng,
                    maskStride: delta
                )
            )
        }
        entries.append(levels)
    }
    return KeySwitchKey(
        inputDimension: fromSecret.count,
        outputDimension: toSecret.count,
        baseLog: baseLog,
        levelCount: levelCount,
        entries: entries,
        isIdentity: false,
        inputStride: delta
    )
}

/// Sample-extract then key-switch. Closes PBS when `n < kN` (cannot truncate extract).
package func sampleExtractKeySwitch(
    _ acc: GLWECiphertext,
    params: TFHEParams,
    key: KeySwitchKey
) -> LWECiphertext {
    keySwitch(sampleExtractLWE(acc, params: params), key: key)
}

package func encryptLWE(
    message: UInt32,
    secret: [UInt32],
    rng: inout LCG32,
    noise: TFHENoiseParams = .none,
    maskStride: UInt32 = 1
) -> LWECiphertext {
    precondition(maskStride >= 1)
    let n = secret.count
    let a: [UInt32]
    if maskStride == 1 {
        a = (0..<n).map { _ in rng.next() }
    } else {
        precondition(maskStride.nonzeroBitCount == 1, "maskStride must be a power of two")
        let clear = ~(maskStride &- 1)
        a = (0..<n).map { _ in rng.next() & clear }
    }
    var b = message
    for i in 0..<n {
        b &+= a[i] &* secret[i]
    }
    if noise.bound > 0 || noise.usesGaussian {
        b &+= TFHENoise.sample(count: 1, params: noise, rng: &rng)[0]
    }
    return LWECiphertext(a: a, b: b)
}

package func addLWE(_ x: LWECiphertext, _ y: LWECiphertext) -> LWECiphertext {
    precondition(x.lweDimension == y.lweDimension)
    return LWECiphertext(
        a: zip(x.a, y.a).map { $0 &+ $1 },
        b: x.b &+ y.b
    )
}

package func subLWE(_ x: LWECiphertext, _ y: LWECiphertext) -> LWECiphertext {
    precondition(x.lweDimension == y.lweDimension)
    return LWECiphertext(
        a: zip(x.a, y.a).map { $0 &- $1 },
        b: x.b &- y.b
    )
}

package func scaleLWE(_ ct: LWECiphertext, _ scalar: UInt32) -> LWECiphertext {
    LWECiphertext(
        a: ct.a.map { $0 &* scalar },
        b: ct.b &* scalar
    )
}

package func gadgetDecomposeScalar(
    _ value: UInt32,
    baseLog: Int,
    levelCount: Int
) -> [UInt32] {
    let baseMask = baseLog == 32 ? UInt32.max : (UInt32(1) &<< UInt32(baseLog)) &- 1
    var remaining = value
    var digits = [UInt32](repeating: 0, count: levelCount)
    for level in 0..<levelCount {
        let shift = 32 - (level + 1) * baseLog
        let digit: UInt32
        if shift >= 0 {
            digit = (remaining &>> UInt32(shift)) & baseMask
            remaining &-= digit &<< UInt32(shift)
        } else {
            digit = remaining & baseMask
            remaining = 0
        }
        digits[level] = digit
    }
    return digits
}

/// Key-switch under `e = 0`. Identity keys return the input unchanged.
package func keySwitch(_ lwe: LWECiphertext, key: KeySwitchKey) -> LWECiphertext {
    precondition(lwe.lweDimension == key.inputDimension)
    if key.isIdentity {
        precondition(key.inputDimension == key.outputDimension)
        return lwe
    }
    precondition(key.entries.count == key.inputDimension)
    var acc = LWECiphertext(
        a: [UInt32](repeating: 0, count: key.outputDimension),
        b: lwe.b
    )
    for i in 0..<key.inputDimension {
        let digits: [UInt32]
        if key.inputStride > 1 {
            let stride = key.inputStride
            let half = stride &>> 1
            let folded = lwe.a[i] % stride == 0
                ? lwe.a[i] / stride
                : (lwe.a[i] &+ half) / stride
            digits = gadgetDecomposeLSB(
                folded,
                baseLog: key.baseLog,
                levelCount: key.levelCount
            )
        } else {
            digits = gadgetDecomposeScalar(
                lwe.a[i],
                baseLog: key.baseLog,
                levelCount: key.levelCount
            )
        }
        for level in 0..<key.levelCount {
            let term = scaleLWE(key.entries[i][level], digits[level])
            acc = subLWE(acc, term)
        }
    }
    return acc
}

package func gadgetDecomposeLSB(
    _ value: UInt32,
    baseLog: Int,
    levelCount: Int
) -> [UInt32] {
    let baseMask = baseLog == 32 ? UInt32.max : (UInt32(1) &<< UInt32(baseLog)) &- 1
    var remaining = value
    var digits = [UInt32](repeating: 0, count: levelCount)
    for level in 0..<levelCount {
        digits[level] = remaining & baseMask
        remaining &>>= UInt32(baseLog)
    }
    return digits
}

// MARK: - Polynomial / GLWE helpers

package func zeroGLWE(params: TFHEParams) -> GLWECiphertext {
    let n = params.polynomialDegree
    let k = params.glweDimension
    return GLWECiphertext(
        mask: Array(repeating: [UInt32](repeating: 0, count: n), count: k),
        body: [UInt32](repeating: 0, count: n)
    )
}

package func addGLWE(_ a: GLWECiphertext, _ b: GLWECiphertext) -> GLWECiphertext {
    precondition(a.degree == b.degree && a.glweDimension == b.glweDimension)
    let mask = zip(a.mask, b.mask).map { pa, pb in
        zip(pa, pb).map { $0 &+ $1 }
    }
    let body = zip(a.body, b.body).map { $0 &+ $1 }
    return GLWECiphertext(mask: mask, body: body)
}

package func subGLWE(_ a: GLWECiphertext, _ b: GLWECiphertext) -> GLWECiphertext {
    precondition(a.degree == b.degree && a.glweDimension == b.glweDimension)
    let mask = zip(a.mask, b.mask).map { pa, pb in
        zip(pa, pb).map { $0 &- $1 }
    }
    let body = zip(a.body, b.body).map { $0 &- $1 }
    return GLWECiphertext(mask: mask, body: body)
}

/// Negacyclic schoolbook product in `Z/2^{32}Z[X]/(X^N+1)`.
package func negacyclicPolynomialMultiply(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
    precondition(a.count == b.count)
    let n = a.count
    var out = [UInt32](repeating: 0, count: n)
    for i in 0..<n {
        for j in 0..<n {
            let exp = i + j
            let term = a[i] &* b[j]
            if exp < n {
                out[exp] &+= term
            } else {
                out[exp - n] &-= term
            }
        }
    }
    return out
}

package func scaleGLWEByPolynomial(_ ct: GLWECiphertext, _ poly: [UInt32]) -> GLWECiphertext {
    precondition(poly.count == ct.degree)
    let mask = ct.mask.map { negacyclicPolynomialMultiply($0, poly) }
    let body = negacyclicPolynomialMultiply(ct.body, poly)
    return GLWECiphertext(mask: mask, body: body)
}

/// Unsigned gadget digits for one polynomial (exact when baseLog·ℓ = 32).
package func gadgetDecompose(
    _ poly: [UInt32],
    baseLog: Int,
    levelCount: Int
) -> [[UInt32]] {
    let baseMask = baseLog == 32 ? UInt32.max : (UInt32(1) &<< UInt32(baseLog)) &- 1
    var levels = Array(
        repeating: [UInt32](repeating: 0, count: poly.count),
        count: levelCount
    )
    for (coeffIndex, value) in poly.enumerated() {
        var remaining = value
        for level in 0..<levelCount {
            let shift = 32 - (level + 1) * baseLog
            let digit: UInt32
            if shift >= 0 {
                digit = (remaining &>> UInt32(shift)) & baseMask
                remaining &-= digit &<< UInt32(shift)
            } else {
                digit = remaining & baseMask
                remaining = 0
            }
            levels[level][coeffIndex] = digit
        }
    }
    return levels
}

// MARK: - Encrypt / external product / CMUX

/// GGSW encrypt of bit `b` under `secret`. Rows: encrypt `b·g_i·s_j` (mask) and `b·g_i` (body).
/// `maskStride` > 1 keeps GGSW rows on a lattice so crypto-gadget BR of a `δ`-scaled
/// test polynomial stays `δ`-lattice-compatible for `publicRefreshBit`.
package func encryptGGSW(
    bit: UInt32,
    secret: TFHESecretKey,
    params: GGSWParams,
    rng: inout LCG32,
    noise: TFHENoiseParams = .none,
    maskStride: UInt32 = 1
) -> GGSWCiphertext {
    precondition(bit == 0 || bit == 1)
    precondition(secret.params == params.tfhe)
    let k = params.tfhe.glweDimension
    let n = params.tfhe.polynomialDegree
    let gadget = params.gadget
    var rows: [GLWECiphertext] = []
    rows.reserveCapacity(params.glweCount)
    for glweRow in 0...k {
        for level in 0..<params.levelCount {
            let scale = bit &* gadget[level]
            let message: [UInt32]
            if glweRow < k {
                // Decrypt is m = b − Σ a·s, so mask rows encrypt −μ·g·s_j.
                message = secret.polynomials[glweRow].map { UInt32(0) &- ($0 &* scale) }
            } else {
                var body = [UInt32](repeating: 0, count: n)
                body[0] = scale
                message = body
            }
            rows.append(
                encryptGLWE(
                    message: message,
                    secret: secret,
                    rng: &rng,
                    noise: noise,
                    maskStride: maskStride
                )
            )
        }
    }
    return GGSWCiphertext(
        params: params,
        rows: rows,
        trivialBit: secret.polynomials.allSatisfy { $0.allSatisfy { $0 == 0 } }
            && noise.bound == 0 && !noise.usesGaussian
            ? bit
            : nil
    )
}

/// GGSW encrypt under the zero secret (mask may still be random).
package func trivialEncryptGGSW(bit: UInt32, params: GGSWParams) -> GGSWCiphertext {
    var rng = LCG32(state: 0xC0FFEE)
    return encryptGGSW(
        bit: bit,
        secret: .zero(params: params.tfhe),
        params: params,
        rng: &rng
    )
}

/// External product `GGSW ⋉ GLWE` (schoolbook; exact for e=0 when gadget covers 32 bits).
package func externalProduct(_ ggsw: GGSWCiphertext, _ ct: GLWECiphertext) -> GLWECiphertext {
    let params = ggsw.params
    precondition(ct.degree == params.tfhe.polynomialDegree)
    precondition(ct.glweDimension == params.tfhe.glweDimension)
    let k = params.tfhe.glweDimension
    var acc = zeroGLWE(params: params.tfhe)

    for glweRow in 0..<k {
        let digits = gadgetDecompose(
            ct.mask[glweRow],
            baseLog: params.baseLog,
            levelCount: params.levelCount
        )
        for level in 0..<params.levelCount {
            acc = addGLWE(acc, scaleGLWEByPolynomial(ggsw.row(glweRow: glweRow, level: level), digits[level]))
        }
    }
    let bodyDigits = gadgetDecompose(
        ct.body,
        baseLog: params.baseLog,
        levelCount: params.levelCount
    )
    for level in 0..<params.levelCount {
        acc = addGLWE(acc, scaleGLWEByPolynomial(ggsw.row(glweRow: k, level: level), bodyDigits[level]))
    }
    return acc
}

/// `CMUX(c, d1, d0) = d0 + c ⋉ (d1 − d0)`.
package func cmuxGGSW(
    _ control: GGSWCiphertext,
    d1: GLWECiphertext,
    d0: GLWECiphertext
) -> GLWECiphertext {
    addGLWE(d0, externalProduct(control, subGLWE(d1, d0)))
}

/// One blind-rotate CMux step: `CMUX(b, X^power · acc, acc)`.
package func blindRotateCMuxStep(
    accumulator: GLWECiphertext,
    control: GGSWCiphertext,
    monomialPower: Int
) -> GLWECiphertext {
    let rotatedMask = accumulator.mask.map { negacyclicMultiplyByXPower($0, power: monomialPower) }
    let rotatedBody = negacyclicMultiplyByXPower(accumulator.body, power: monomialPower)
    let rotated = GLWECiphertext(mask: rotatedMask, body: rotatedBody)
    return cmuxGGSW(control, d1: rotated, d0: accumulator)
}

/// Bootstrap key: GGSW encrypt of each LWE secret bit (for future full blind rotate).
/// When `publicRefreshCompatible` is set, BK masks use `max(g₀, δ)` stride so a
/// `δ`-scaled blind-rotate stays on the `δ`-lattice for exact `publicRefreshBit`.
/// Prefer `GGSWParams.booleanPublicMS` / `.cryptoPublicMS` (where `g₀ = δ`) for public-MS paths.
package func bootstrapKey(
    secret: TFHESecretKey,
    params: GGSWParams,
    rng: inout LCG32,
    publicRefreshCompatible: Bool = false,
    noise: TFHENoiseParams = .none
) -> BootstrapKey {
    let bits = secret.lweSecret
    let delta = rotationScale(polynomialDegree: params.tfhe.polynomialDegree)
    let stride: UInt32 =
        publicRefreshCompatible ? max(max(params.gadget[0], 1), delta) : 1
    let keys = bits.map {
        encryptGGSW(
            bit: $0,
            secret: secret,
            params: params,
            rng: &rng,
            noise: noise,
            maskStride: stride
        )
    }
    return BootstrapKey(params: params, bitKeys: keys)
}

/// Trivial bootstrap key for an LWE of dimension `n`: GGSW(0) under s=0.
package func trivialBootstrapKey(lweDimension: Int, params: GGSWParams) -> BootstrapKey {
    let zeros = (0..<lweDimension).map { _ in trivialEncryptGGSW(bit: 0, params: params) }
    return BootstrapKey(params: params, bitKeys: zeros)
}

/// Blind rotation under trivial LWE `(a=0, b=μ)` with GGSW(control=μ).
package func blindRotateTrivial(
    testPolynomial: [UInt32],
    lwe: LWECiphertext,
    bootstrapKey: BootstrapKey,
    messageBitCount: Int = 1
) -> GLWECiphertext {
    _ = bootstrapKey
    precondition(messageBitCount == 1, "Multi-bit blind rotate not in this slice")
    let params = bootstrapKey.params
    precondition(testPolynomial.count == params.tfhe.polynomialDegree)
    let bit = decodeBooleanPhase(lwe.b, delta: params.tfhe.delta)
    for a in lwe.a where a != 0 {
        preconditionFailure("blindRotateTrivial requires trivial LWE mask (a=0)")
    }
    var acc = encryptGLWETrivialMask(
        message: testPolynomial,
        secret: .zero(params: params.tfhe)
    )
    let control = trivialEncryptGGSW(bit: bit, params: params)
    return blindRotateCMuxStep(accumulator: acc, control: control, monomialPower: -1)
}

// MARK: - LWE blind rotate (graduation step 10d)

/// Map a torus / rotation-native coeff to a power in `Z_{2N}`.
/// - Rotation-native in `[0, 2N)` (after encrypt/pack reduction): identity
/// - Scaled samples (`k · q/2N`): exact `k % 2N`
/// - Full-torus: modulus-switch via top bits
package func rotationPower(_ coeff: UInt32, twoN: Int) -> Int {
    precondition(twoN > 1 && twoN.nonzeroBitCount == 1)
    let mod = UInt32(twoN)
    let shift = 32 - twoN.trailingZeroBitCount
    let scale = (1 as UInt32) &<< UInt32(shift)
    // Prefer exact Z_{2N} representatives (rotation-native encrypt / publicMS / pack).
    if coeff < mod {
        return Int(coeff)
    }
    if scale > 1 && coeff % scale == 0 {
        return Int((coeff / scale) % mod)
    }
    // Legacy unreduced native sums (pre-reduction callers): keep % 2N while clearly
    // below the δ-lattice / full-torus regime.
    if scale > 1 && coeff < scale {
        return Int(coeff % mod)
    }
    return Int(coeff >> UInt32(shift))
}

/// Torus scale `q / 2N` so boolean `0/1` survive modulus switching.
package func rotationScale(polynomialDegree n: Int) -> UInt32 {
    let twoN = 2 * n
    precondition(twoN.nonzeroBitCount == 1)
    return (1 as UInt32) &<< UInt32(32 - twoN.trailingZeroBitCount)
}

/// Boolean test-poly / decode spacing `k·δ` with `δ = q/(2N)`. `k=1` is native.
/// `k=2` at `N=1024` restores the `N=512` half-gap (H4 encoding retune).
package func rotationBooleanScale(polynomialDegree n: Int, mul: Int) -> UInt32 {
    precondition(mul >= 1 && mul <= 16)
    let base = rotationScale(polynomialDegree: n)
    let product = UInt64(base) &* UInt64(mul)
    precondition(product > 0 && product <= UInt64(UInt32.max), "kδ overflow")
    return UInt32(product)
}

/// `k` such that `scale = k·δ`. Public-MS uses native `δ`; wires live in `{0,k}⊂Z_{2N}`.
package func booleanScaleFactor(polynomialDegree n: Int, scale: UInt32) -> Int {
    let base = rotationScale(polynomialDegree: n)
    precondition(scale % base == 0, "scale must be an integer multiple of δ")
    let k = Int(scale / base)
    precondition(k >= 1 && k <= 16)
    return k
}

/// Map a boolean to the rotation-native message `k·bit`.
package func encodeRotationNativeBit(_ bit: UInt32, k: Int) -> UInt32 {
    precondition(k >= 1)
    return (bit & 1) &* UInt32(k)
}

/// Decode a `Z_{2N}` phase near `{0,k}` (after native-δ public MS).
package func decodeRotationNativeBit(_ phase: UInt32, twoN: Int, k: Int) -> UInt32 {
    precondition(twoN > 1 && twoN.nonzeroBitCount == 1)
    precondition(k >= 1)
    if k == 1 {
        return phase & 1
    }
    let p = Int(phase % UInt32(twoN))
    func circ(_ a: Int, _ b: Int) -> Int {
        let d = abs(a - b)
        return min(d, twoN - d)
    }
    return circ(p, k) < circ(p, 0) ? 1 : 0
}

/// LWE encrypt with mask coeffs in `Z_{2N}` (exact blind-rotate powers under e=0).
package func encryptLWERotationNative(
    message: UInt32,
    secret: [UInt32],
    twoN: Int,
    rng: inout LCG32
) -> LWECiphertext {
    precondition(twoN > 1 && twoN.nonzeroBitCount == 1)
    precondition(secret.allSatisfy { $0 == 0 || $0 == 1 })
    let n = secret.count
    let mod = UInt32(twoN)
    let a = (0..<n).map { _ in rng.next() % mod }
    var b = message % mod
    for i in 0..<n {
        b &+= a[i] &* secret[i]
    }
    b %= mod
    return LWECiphertext(a: a, b: b)
}

/// Public modulus-switch of an LWE into rotation-native `Z_{2N}` coeffs.
package func modulusSwitchLWE(_ lwe: LWECiphertext, twoN: Int) -> LWECiphertext {
    precondition(twoN > 1 && twoN.nonzeroBitCount == 1)
    let shift = 32 - twoN.trailingZeroBitCount
    return LWECiphertext(
        a: lwe.a.map { $0 >> UInt32(shift) },
        b: lwe.b >> UInt32(shift)
    )
}

/// Pack boolean LWE bits into one address ciphertext: `Σ 2^i · ct_i` (mod `2N`).
/// `twoN` is the **polynomial** torus `2N` (`N = deg`), not `2·n` when `n < N`.
package func packLWEBits(_ bits: [LWECiphertext], twoN: Int? = nil) -> LWECiphertext {
    precondition(!bits.isEmpty)
    let dim = bits[0].lweDimension
    precondition(bits.allSatisfy { $0.lweDimension == dim })
    let ring = twoN ?? (2 * dim)
    precondition(ring > 1 && ring.nonzeroBitCount == 1)
    let mod = UInt32(ring)
    func reduce(_ ct: LWECiphertext) -> LWECiphertext {
        LWECiphertext(a: ct.a.map { $0 % mod }, b: ct.b % mod)
    }
    var acc = reduce(bits[0])
    for i in 1..<bits.count {
        let scaled = scaleLWE(reduce(bits[i]), (1 as UInt32) &<< UInt32(i))
        acc = reduce(addLWE(acc, scaled))
    }
    return acc
}

/// Standard binary-secret blind rotate: `ACC ← X^{-b}·v`; then
/// `ACC ← CMUX(BK_j, X^{a_j}·ACC, ACC)`.
package func blindRotate(
    testPolynomial: [UInt32],
    lwe: LWECiphertext,
    bootstrapKey: BootstrapKey
) -> GLWECiphertext {
    let params = bootstrapKey.params
    let n = params.tfhe.polynomialDegree
    let twoN = 2 * n
    precondition(testPolynomial.count == n)
    precondition(lwe.lweDimension == bootstrapKey.bitKeys.count)
    precondition(lwe.lweDimension == params.tfhe.lweDimension)

    let bPow = rotationPower(lwe.b, twoN: twoN)
    var acc = encryptGLWETrivialMask(
        message: negacyclicMultiplyByXPower(testPolynomial, power: -bPow),
        secret: .zero(params: params.tfhe)
    )
    for j in 0..<lwe.lweDimension {
        let aPow = rotationPower(lwe.a[j], twoN: twoN)
        acc = blindRotateCMuxStep(
            accumulator: acc,
            control: bootstrapKey.bitKeys[j],
            monomialPower: aPow
        )
    }
    return acc
}

/// LUT via packed LWE address + blind rotate + sample-extract (no clear selectors).
package func evaluateLUTBlindRotate(
    truthTable: [UInt32],
    inputs: [LWECiphertext],
    bootstrapKey: BootstrapKey,
    scale: UInt32? = nil,
    keySwitchKey: KeySwitchKey? = nil
) -> LWECiphertext {
    let params = bootstrapKey.params
    let n = params.tfhe.polynomialDegree
    precondition(truthTable.count == 1 << inputs.count)
    precondition(n >= truthTable.count)
    let δ = scale ?? rotationScale(polynomialDegree: n)
    let testPoly = TFHETestPolyCache.shared.testPolynomial(
        truthTable: truthTable,
        degree: n,
        scale: δ
    )
    let packed = packLWEBits(inputs, twoN: 2 * n)
    let acc = blindRotate(
        testPolynomial: testPoly,
        lwe: packed,
        bootstrapKey: bootstrapKey
    )
    let ksk = keySwitchKey ?? .trivialIdentity(
        dimension: params.tfhe.glweDimension * n
    )
    return sampleExtractKeySwitch(acc, params: params.tfhe, key: ksk)
}

/// Public bit refresh after PBS extract: native-δ MS into `Z_{2N}`.
/// Boolean `kδ` encoding keeps the message as `{0,k}` (not `/kδ`, which
/// quantizes the mask too coarsely and breaks chained public-ms LUTs).
package func publicRefreshBit(
    _ lwe: LWECiphertext,
    twoN: Int,
    scale: UInt32
) -> LWECiphertext {
    precondition(scale > 1)
    precondition(twoN > 1 && twoN.nonzeroBitCount == 1)
    let n = twoN / 2
    let step = rotationScale(polynomialDegree: n)
    precondition(scale % step == 0)
    let half = step &>> 1
    func fold(_ v: UInt32) -> UInt32 {
        if v % step == 0 {
            return (v / step) % UInt32(twoN)
        }
        return ((v &+ half) / step) % UInt32(twoN)
    }
    return LWECiphertext(a: lwe.a.map(fold), b: fold(lwe.b))
}

/// Decode a rotation-scaled boolean phase (`0` or `δ`).
package func decodeRotationBoolean(_ phase: UInt32, scale: UInt32) -> UInt32 {
    if scale <= 1 {
        return decodeBooleanPhase(phase, delta: 1)
    }
    let half = scale &>> 1
    return ((phase &+ half) / scale) & 1
}

/// PBS via GGSW CMUX; returns the output GLWE (e=0).
package func evaluatePBSGGSWCiphertext(
    truthTable: [UInt32],
    inputs: [UInt32],
    secret: TFHESecretKey,
    params: GGSWParams,
    rng: inout LCG32
) -> GLWECiphertext {
    precondition(secret.params == params.tfhe)
    let degree = params.tfhe.polynomialDegree
    precondition(truthTable.count == 1 << inputs.count)
    precondition(degree >= truthTable.count)
    for bit in inputs {
        precondition(bit == 0 || bit == 1)
    }
    let testPoly = ProgrammableBootstrapStub.testPolynomial(
        truthTable: truthTable,
        degree: degree,
        delta: params.tfhe.delta
    )
    var acc = encryptGLWETrivialMask(message: testPoly, secret: secret)
    for (bitIndex, bit) in inputs.enumerated() {
        let control = encryptGGSW(bit: bit, secret: secret, params: params, rng: &rng)
        acc = blindRotateCMuxStep(
            accumulator: acc,
            control: control,
            monomialPower: -(1 << bitIndex)
        )
    }
    return acc
}

/// PBS via GGSW CMUX under an arbitrary binary secret (`e = 0`).
package func evaluatePBSGGSW(
    truthTable: [UInt32],
    inputs: [UInt32],
    secret: TFHESecretKey,
    params: GGSWParams,
    rng: inout LCG32
) -> UInt32 {
    let acc = evaluatePBSGGSWCiphertext(
        truthTable: truthTable,
        inputs: inputs,
        secret: secret,
        params: params,
        rng: &rng
    )
    let ksk = extractToLWEKeySwitchKey(secret: secret, rng: &rng)
    let switched = sampleExtractKeySwitch(acc, params: params.tfhe, key: ksk)
    let phaseFromLWE = decryptLWE(switched, secret: secret)
    let phaseFromGLWE = decryptGLWE(acc, secret: secret)[0]
    precondition(
        phaseFromLWE == phaseFromGLWE,
        "sample-extract decrypt \(phaseFromLWE) != GLWE decrypt \(phaseFromGLWE)"
    )
    return decodeBooleanPhase(phaseFromGLWE, delta: params.tfhe.delta)
}

/// Zero-secret convenience wrapper (step 7 oracle).
package func evaluateTrivialPBSGGSW(
    truthTable: [UInt32],
    inputs: [UInt32],
    params: GGSWParams
) -> UInt32 {
    var rng = LCG32(state: 0xA11CE)
    return evaluatePBSGGSW(
        truthTable: truthTable,
        inputs: inputs,
        secret: .zero(params: params.tfhe),
        params: params,
        rng: &rng
    )
}
