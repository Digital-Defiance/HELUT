import Foundation

// MARK: - TFHE sample shapes
//
// Metal wires: body-only `[B,N]` or packed `[B,2N]` (`glwe-packed`).
// CPU paths support non-zero secrets and optional discrete noise (step 10b).
// Bounded ∞-norm growth: `TFHENoiseGrowth`. Bounded proof: `TFHENoiseProof`.
// Unbounded asymptotic *proofs* still refuse via `TFHENoise.refuse`.

/// Ring / module parameters for HELUT's TFHE-shaped samples.
package struct TFHEParams: Sendable, Equatable {
    /// Polynomial degree `N` (`Z_q[X]/(X^N+1)`).
    package var polynomialDegree: Int
    /// GLWE dimension `k` (mask has `k` polynomials).
    package var glweDimension: Int
    /// LWE dimension `n` after sample-extract (often `k·N`).
    package var lweDimension: Int
    /// Message scaling `μ = bit · Δ`. Boolean Metal path keeps `Δ = 1`.
    package var delta: UInt32

    package init(
        polynomialDegree degree: Int = 1024,
        glweDimension: Int = 1,
        lweDimension: Int? = nil,
        delta: UInt32 = 1
    ) {
        precondition(degree > 0)
        precondition(glweDimension > 0)
        self.polynomialDegree = degree
        self.glweDimension = glweDimension
        self.lweDimension = lweDimension ?? (glweDimension * degree)
        self.delta = delta
    }

    /// Default boolean-safe HELUT params (`k=1`, `Δ=1`, `n=N`).
    package static let booleanTrivial = TFHEParams(
        polynomialDegree: 1024,
        glweDimension: 1,
        delta: 1
    )

    /// Demo noisy boolean: large `Δ` so small discrete noise still round-trips.
    package static func noisyBoolean(degree: Int, deltaLog: Int = 20) -> TFHEParams {
        precondition(deltaLog >= 2 && deltaLog <= 30)
        return TFHEParams(
            polynomialDegree: degree,
            glweDimension: 1,
            delta: (1 as UInt32) &<< UInt32(deltaLog)
        )
    }
}

/// Binary GLWE secret: `k` polynomials with coefficients in `{0,1}`.
package struct TFHESecretKey: Sendable, Equatable {
    package var params: TFHEParams
    /// `polynomials[j][i] ∈ {0,1}`.
    package var polynomials: [[UInt32]]

    package init(params: TFHEParams, polynomials: [[UInt32]]) {
        precondition(polynomials.count == params.glweDimension)
        precondition(polynomials.allSatisfy { $0.count == params.polynomialDegree })
        for poly in polynomials {
            for c in poly {
                precondition(c == 0 || c == 1, "Secret coeffs must be binary")
            }
        }
        self.params = params
        self.polynomials = polynomials
    }

    package static func zero(params: TFHEParams) -> TFHESecretKey {
        let n = params.polynomialDegree
        let k = params.glweDimension
        return TFHESecretKey(
            params: params,
            polynomials: Array(repeating: [UInt32](repeating: 0, count: n), count: k)
        )
    }

    /// Deterministic binary secret from `LCG32`.
    package static func random(params: TFHEParams, seed: UInt32) -> TFHESecretKey {
        var rng = LCG32(state: seed == 0 ? 1 : seed)
        let n = params.polynomialDegree
        var polys: [[UInt32]] = []
        polys.reserveCapacity(params.glweDimension)
        for _ in 0..<params.glweDimension {
            polys.append((0..<n).map { _ in rng.next() & 1 })
        }
        return TFHESecretKey(params: params, polynomials: polys)
    }

    /// Flattened LWE secret matching `sampleExtractLWE` layout.
    package var lweSecret: [UInt32] {
        polynomials.flatMap { $0 }
    }
}

/// GLWE ciphertext: `k` mask polynomials + one body polynomial over `Z/2^{32}Z`.
package struct GLWECiphertext: Sendable, Equatable {
    package var mask: [[UInt32]]
    package var body: [UInt32]

    package var degree: Int { body.count }
    package var glweDimension: Int { mask.count }

    package init(mask: [[UInt32]], body: [UInt32]) {
        precondition(!mask.isEmpty)
        precondition(mask.allSatisfy { $0.count == body.count })
        self.mask = mask
        self.body = body
    }

    /// Trivial ciphertext: zero mask, message in `body[0]` (phase-shaped).
    /// Valid under **any** secret (`a=0` ⇒ decrypt returns body).
    package static func trivial(
        bit: UInt32,
        params: TFHEParams
    ) -> GLWECiphertext {
        precondition(bit == 0 || bit == 1)
        let n = params.polynomialDegree
        let k = params.glweDimension
        let mask = Array(repeating: [UInt32](repeating: 0, count: n), count: k)
        var body = [UInt32](repeating: 0, count: n)
        body[0] = bit &* params.delta
        return GLWECiphertext(mask: mask, body: body)
    }
}

/// LWE ciphertext: mask vector `a` of length `n` + body scalar `b`.
package struct LWECiphertext: Sendable, Equatable {
    package var a: [UInt32]
    package var b: UInt32

    package var lweDimension: Int { a.count }

    package init(a: [UInt32], b: UInt32) {
        self.a = a
        self.b = b
    }

    package static func trivial(bit: UInt32, params: TFHEParams) -> LWECiphertext {
        precondition(bit == 0 || bit == 1)
        return LWECiphertext(
            a: [UInt32](repeating: 0, count: params.lweDimension),
            b: bit &* params.delta
        )
    }
}

/// Encrypt polynomial message under GLWE. Mask from `rng`; optional discrete noise on body.
/// When `maskStride > 1`, each mask coeff is a multiple of `maskStride` (e=0 lattice
/// compatible with public MS after PBS when the ACC stays on a matching lattice).
package func encryptGLWE(
    message: [UInt32],
    secret: TFHESecretKey,
    rng: inout LCG32,
    noise: TFHENoiseParams = .none,
    maskStride: UInt32 = 1
) -> GLWECiphertext {
    let params = secret.params
    precondition(message.count == params.polynomialDegree)
    precondition(maskStride >= 1)
    let n = params.polynomialDegree
    let k = params.glweDimension
    var mask: [[UInt32]] = []
    mask.reserveCapacity(k)
    var body = message
    for j in 0..<k {
        let a: [UInt32]
        if maskStride == 1 {
            a = (0..<n).map { _ in rng.next() }
        } else {
            precondition(
                maskStride.nonzeroBitCount == 1,
                "maskStride must be a power of two"
            )
            let clear = ~(maskStride &- 1)
            a = (0..<n).map { _ in rng.next() & clear }
        }
        mask.append(a)
        let asj = negacyclicPolynomialMultiply(a, secret.polynomials[j])
        for i in 0..<n {
            body[i] &+= asj[i]
        }
    }
    if noise.bound > 0 {
        let e = TFHENoise.sample(count: n, params: noise, rng: &rng)
        for i in 0..<n {
            body[i] &+= e[i]
        }
    }
    return GLWECiphertext(mask: mask, body: body)
}

/// Zero-mask encrypt (still valid under `secret`; decrypt returns `message`).
package func encryptGLWETrivialMask(
    message: [UInt32],
    secret: TFHESecretKey
) -> GLWECiphertext {
    let params = secret.params
    precondition(message.count == params.polynomialDegree)
    let k = params.glweDimension
    let n = params.polynomialDegree
    return GLWECiphertext(
        mask: Array(repeating: [UInt32](repeating: 0, count: n), count: k),
        body: message
    )
}

/// Decrypt GLWE with `e = 0`: `m = b − Σ a_j · s_j`.
package func decryptGLWE(_ ciphertext: GLWECiphertext, secret: TFHESecretKey) -> [UInt32] {
    precondition(ciphertext.degree == secret.params.polynomialDegree)
    precondition(ciphertext.glweDimension == secret.params.glweDimension)
    var message = ciphertext.body
    for j in 0..<secret.params.glweDimension {
        let asj = negacyclicPolynomialMultiply(ciphertext.mask[j], secret.polynomials[j])
        for i in 0..<message.count {
            message[i] &-= asj[i]
        }
    }
    return message
}

package func decryptLWE(_ ciphertext: LWECiphertext, secret: TFHESecretKey) -> UInt32 {
    let s = secret.lweSecret
    precondition(ciphertext.lweDimension == s.count)
    var phase = ciphertext.b
    for i in 0..<s.count {
        phase &-= ciphertext.a[i] &* s[i]
    }
    return phase
}

package func decodeBooleanPhase(_ torus: UInt32, delta: UInt32) -> UInt32 {
    if delta == 1 {
        precondition(torus == 0 || torus == 1, "Expected boolean phase, got \(torus)")
        return torus
    }
    let half = delta &>> 1
    return ((torus &+ half) / delta) & 1
}

/// Sample-aware bit encoding: Metal path still uses the GLWE **body** only.
package protocol SampleBitEncoding: TorusBitEncoding {
    var params: TFHEParams { get }
    func encryptBit(_ bit: UInt32) -> GLWECiphertext
    func decryptBit(_ ciphertext: GLWECiphertext) -> UInt32
}

/// Trivial GLWE encoding (`s = 0`, noise = 0). `encodeBit` returns the body poly
/// so existing `[B,N]` Metal wires and multilinear/PBS paths keep working.
package struct TrivialGLWEEncoding: SampleBitEncoding {
    package let params: TFHEParams

    package var degree: Int { params.polynomialDegree }

    package init(params: TFHEParams = .booleanTrivial) {
        self.params = params
    }

    package init(degree: Int, glweDimension: Int = 1, delta: UInt32 = 1) {
        self.params = TFHEParams(
            polynomialDegree: degree,
            glweDimension: glweDimension,
            delta: delta
        )
    }

    package func encryptBit(_ bit: UInt32) -> GLWECiphertext {
        GLWECiphertext.trivial(bit: bit, params: params)
    }

    package func decryptBit(_ ciphertext: GLWECiphertext) -> UInt32 {
        precondition(ciphertext.degree == degree)
        precondition(ciphertext.glweDimension == params.glweDimension)
        for poly in ciphertext.mask {
            for coeff in poly where coeff != 0 {
                preconditionFailure(
                    "TrivialGLWEEncoding decrypt saw non-zero mask; use decryptGLWE(secret:)"
                )
            }
        }
        return decodeBooleanPhase(ciphertext.body[0], delta: params.delta)
    }

    package func encodeBit(_ bit: UInt32) -> [UInt32] {
        encryptBit(bit).body
    }

    package func decodeBit(_ polynomial: [UInt32]) -> UInt32 {
        precondition(polynomial.count == degree)
        for i in 1..<degree where polynomial[i] != 0 {
            preconditionFailure("GLWE body pad non-zero at coeff[\(i)] under trivial decode")
        }
        return decodeBooleanPhase(polynomial[0], delta: params.delta)
    }
}

/// Sample-extract constant term of a GLWE into an LWE (standard TFHE extract).
package func sampleExtractLWE(
    _ ciphertext: GLWECiphertext,
    params: TFHEParams
) -> LWECiphertext {
    precondition(ciphertext.degree == params.polynomialDegree)
    precondition(ciphertext.glweDimension == params.glweDimension)
    let n = params.polynomialDegree
    let k = params.glweDimension
    var a = [UInt32](repeating: 0, count: k * n)
    for j in 0..<k {
        let poly = ciphertext.mask[j]
        a[j * n] = poly[0]
        for i in 1..<n {
            a[j * n + i] = UInt32(0) &- poly[n - i]
        }
    }
    return LWECiphertext(a: a, b: ciphertext.body[0])
}

/// Discrete centered-uniform torus noise (graduation step 10b).
/// Bound `B`: each coeff is uniform in `{-B,…,B}` (torus wrap). `B=0` → noiseless.
package struct TFHENoiseParams: Sendable, Equatable {
    package var bound: UInt32

    package init(bound: UInt32) {
        self.bound = bound
    }

    package static let none = TFHENoiseParams(bound: 0)

    /// Small demo noise for `TFHEParams.noisyBoolean` (`Δ = 2^20`).
    package static let demo = TFHENoiseParams(bound: 64)
}

package enum TFHENoise {
    /// Sample `count` centered-uniform coeffs in `[-bound, bound]`.
    package static func sample(
        count: Int,
        params: TFHENoiseParams,
        rng: inout LCG32
    ) -> [UInt32] {
        precondition(count >= 0)
        if params.bound == 0 {
            return [UInt32](repeating: 0, count: count)
        }
        let span = params.bound &* 2 &+ 1
        return (0..<count).map { _ in
            let u = rng.next() % span
            if u <= params.bound {
                return u
            }
            return UInt32(0) &- (u &- params.bound)
        }
    }

    /// Unbounded claims without Gaussian / LWE certificates refuse.
    /// Discrete: `TFHENoiseProof`. Gaussian ε: `TFHEAsymptoticSecurityCertificate`.
    /// LWE binding: `TFHELWEHardnessCertificate`.
    package static func refuse(reason: String = "missing security certificate") -> Never {
        fatalError(
            "TFHENoise refuse (\(reason)). "
                + "Use TFHELWEHardnessCertificate / TFHEAsymptoticSecurityCertificate / TFHENoiseProof. "
                + "See directives/fhe-graduation.md."
        )
    }
}

/// Bounded worst-case centered ∞-norm noise accounting (graduation step 10h).
/// Tracks torus magnitude against message spacing `delta` (decode half-gap `delta/2`).
/// This is an engineering bound for HELUT’s discrete-inject path — not a production TFHE proof.
package struct TFHENoiseGrowth: Sendable, Equatable {
    /// Worst-case |e| bound on the noise term.
    package private(set) var bound: UInt64
    /// Message spacing Δ.
    package var delta: UInt32

    package init(bound: UInt64 = 0, delta: UInt32) {
        precondition(delta >= 2, "delta must leave a decode half-gap")
        self.bound = bound
        self.delta = delta
    }

    /// Boolean rotation scale `q/(2N)` as Δ.
    package static func forRotationScale(polynomialDegree n: Int) -> TFHENoiseGrowth {
        TFHENoiseGrowth(bound: 0, delta: rotationScale(polynomialDegree: n))
    }

    package var decodingHalfGap: UInt32 { delta / 2 }

    package var isDecodable: Bool { bound < UInt64(decodingHalfGap) }

    package var remainingMargin: UInt64 {
        let gap = UInt64(decodingHalfGap)
        return bound < gap ? gap &- bound : 0
    }

    package mutating func reset(bound newBound: UInt64 = 0) {
        bound = newBound
    }

    package mutating func setEncrypt(noise: TFHENoiseParams) {
        bound = UInt64(noise.bound)
    }

    package mutating func afterAdd(_ other: TFHENoiseGrowth) {
        precondition(delta == other.delta)
        bound &+= other.bound
    }

    package mutating func scale(by scalar: UInt32) {
        bound &*= UInt64(scalar)
    }

    package mutating func afterKeySwitch(addedBound: UInt32) {
        bound &+= UInt64(addedBound)
    }

    /// Exact lattice modulus-switch (`publicRefreshBit` when coeffs lie on `δℤ`): +0.
    package mutating func afterExactModulusSwitch() {}

    /// Approximate MS: ≤ `lweDimension/2` units of `Z_{2N}`, each worth `delta` on the torus.
    package mutating func afterApproxModulusSwitch(lweDimension: Int) {
        precondition(lweDimension >= 0)
        bound &+= UInt64(lweDimension / 2) &* UInt64(delta)
    }

    /// Blind-rotate / PBS refreshes the sample; output bound is the BK/encrypt noise floor.
    package mutating func afterBlindRotate(outputNoiseBound: UInt32) {
        bound = UInt64(outputNoiseBound)
    }

    package func assertDecodable(
        file: StaticString = #file,
        line: UInt = #line
    ) {
        precondition(
            isDecodable,
            "TFHENoiseGrowth undecodable bound=\(bound) halfGap=\(decodingHalfGap) at \(file):\(line)"
        )
    }
}

/// Tracked abstract margin for HELUT’s e=0 / discrete-noise path (graduation step 10e).
/// Units are “levels”: encrypt starts at `capacity`; each PBS/KS consumes cost.
package struct TFHENoiseBudget: Sendable, Equatable {
    package var capacity: Int
    package private(set) var remaining: Int

    package init(capacity: Int) {
        precondition(capacity >= 0)
        self.capacity = capacity
        self.remaining = capacity
    }

    /// Demo boolean margin (enough for a small combinational netlist at e≈0).
    package static let demoBoolean = TFHENoiseBudget(capacity: 64)

    /// Scale abstract budget with `$lut` count (publicMS ≈ 3 units/LUT).
    package static func forLUTCount(_ lutCount: Int) -> TFHENoiseBudget {
        precondition(lutCount >= 0)
        let perLUT = 4 // blindRotateLevel(2) + MS(1) + slack
        return TFHENoiseBudget(capacity: max(64, lutCount * perLUT + 16))
    }

    package var isSafe: Bool { remaining >= 0 }

    package mutating func reset() {
        remaining = capacity
    }

    package mutating func consume(_ op: TFHENoiseOp) {
        remaining -= op.cost
        precondition(remaining >= 0, "TFHENoiseBudget exhausted by \(op.rawValue)")
    }
}

package enum TFHENoiseOp: String, Sendable {
    case encrypt
    case externalProduct
    case cmux
    case blindRotateLevel
    case keySwitch
    case modulusSwitch
    case sampleExtract

    package var cost: Int {
        switch self {
        case .encrypt, .sampleExtract: return 0
        case .keySwitch, .modulusSwitch: return 1
        case .externalProduct, .cmux: return 2
        case .blindRotateLevel: return 2
        }
    }
}
