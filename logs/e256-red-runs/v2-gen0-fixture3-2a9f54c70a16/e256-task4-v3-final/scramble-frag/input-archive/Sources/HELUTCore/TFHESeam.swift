import Foundation
import MetalPerformanceShadersGraph

// MARK: - TFHE graduation seam
//
// HELUT evaluates Yosys netlists under *trivial* (noise-free) torus encodings.
// LUT bodies: multilinear **or** trivial PBS (CMUX + negacyclic rotate).
// Real TFHE still swaps two seams:
//
//   1. `TorusBitEncoding` — trivial → LWE/GLWE samples + noise
//   2. PBS body — trivial CMUX/broadcast → GGSW external product + BK + KS
//
// The Yosys → MPSGraph clock loop (`YosysGraphCompiler`, DFF ping-pong) stays.

/// How a clear boolean becomes a length-`N` `UInt32` vector on the Metal path.
package protocol TorusBitEncoding: Sendable {
    var degree: Int { get }
    func encodeBit(_ bit: UInt32) -> [UInt32]
    func decodeBit(_ polynomial: [UInt32]) -> UInt32
}

/// Named trivial encodings (noise = 0). All are boolean-safe under `.multilinear`
/// when **every** wire and constant uses the same kind (LUT complements, DFF muxes, feeds).
package enum TrivialBitEncodingKind: String, Sendable, CaseIterable {
    /// Legacy: bit `b` ↔ all-`N` coefficients equal to `b`.
    case constantFill = "constant-fill"
    /// TFHE-shaped trivial: bit `b` lives in coefficient 0; remaining coeffs are 0.
    case phase = "phase"
    /// Sample-shaped trivial GLWE body (`k≥1` mask forced zero on Metal path).
    case glweTrivial = "glwe-trivial"
    /// Packed GLWE wire `mask‖body` for `k=1` (width `2N`).
    case glwePacked = "glwe-packed"

    package func makeEncoding(degree polynomialDegree: Int) -> any TorusBitEncoding {
        switch self {
        case .constantFill: return TrivialConstantFillEncoding(degree: polynomialDegree)
        case .phase: return TrivialPhaseEncoding(degree: polynomialDegree)
        case .glweTrivial: return TrivialGLWEEncoding(degree: polynomialDegree)
        case .glwePacked: return PackedGLWEEncoding(polynomialDegree: polynomialDegree)
        }
    }

    /// Metal tensor width for a given polynomial degree `N`.
    package func wireWidth(polynomialDegree: Int) -> Int {
        switch self {
        case .glwePacked: return GLWEPack.packedDegree(polynomialDegree: polynomialDegree, glweDimension: 1)
        case .constantFill, .phase, .glweTrivial: return polynomialDegree
        }
    }

    /// Metal/PBS treat phase and glwe-trivial identically (message in coeff[0]).
    package var usesPhaseShapedBody: Bool {
        self == .phase || self == .glweTrivial
    }

    package var isPackedGLWE: Bool {
        self == .glwePacked
    }
}

/// Packed `k=1` GLWE encoding: wire length `2N = mask ‖ body`.
package struct PackedGLWEEncoding: TorusBitEncoding {
    package let polynomialDegree: Int
    package var degree: Int { GLWEPack.packedDegree(polynomialDegree: polynomialDegree, glweDimension: 1) }

    package init(polynomialDegree: Int) {
        precondition(polynomialDegree > 0)
        self.polynomialDegree = polynomialDegree
    }

    package func encodeBit(_ bit: UInt32) -> [UInt32] {
        let ct = GLWECiphertext.trivial(
            bit: bit,
            params: TFHEParams(polynomialDegree: polynomialDegree, glweDimension: 1, delta: 1)
        )
        return GLWEPack.pack(ct)
    }

    package func decodeBit(_ polynomial: [UInt32]) -> UInt32 {
        let ct = GLWEPack.unpack(
            polynomial,
            polynomialDegree: polynomialDegree,
            glweDimension: 1
        )
        for coeff in ct.mask[0] where coeff != 0 {
            preconditionFailure("Packed GLWE decode expects zero mask on trivial path")
        }
        return decodeBooleanPhase(ct.body[0], delta: 1)
    }
}

/// Mutable encrypt state for packed GLWE wires (secret + PRNG + optional noise).
package final class EncryptedPackedGLWEState: @unchecked Sendable {
    package let secret: TFHESecretKey
    package let noise: TFHENoiseParams
    package var rng: LCG32

    package init(secret: TFHESecretKey, noise: TFHENoiseParams = .none, seed: UInt32) {
        self.secret = secret
        self.noise = noise
        self.rng = LCG32(state: seed == 0 ? 1 : seed)
    }
}

/// Encrypted packed `mask‖body` encoding under a binary secret (CPU / pack path).
/// Metal netlist `$lut` still body-slices; use `MetalGGSW.evaluatePBS` for GGSW LUT body.
package struct EncryptedPackedGLWEEncoding: SampleBitEncoding {
    package let state: EncryptedPackedGLWEState

    package var params: TFHEParams { state.secret.params }
    package var degree: Int {
        GLWEPack.packedDegree(polynomialDegree: params.polynomialDegree, glweDimension: 1)
    }

    package init(state: EncryptedPackedGLWEState) {
        precondition(state.secret.params.glweDimension == 1)
        self.state = state
    }

    package func encryptBit(_ bit: UInt32) -> GLWECiphertext {
        precondition(bit == 0 || bit == 1)
        var msg = [UInt32](repeating: 0, count: params.polynomialDegree)
        msg[0] = bit &* params.delta
        return encryptGLWE(
            message: msg,
            secret: state.secret,
            rng: &state.rng,
            noise: state.noise
        )
    }

    package func decryptBit(_ ciphertext: GLWECiphertext) -> UInt32 {
        let phase = decryptGLWE(ciphertext, secret: state.secret)[0]
        return decodeBooleanPhase(phase, delta: params.delta)
    }

    package func encodeBit(_ bit: UInt32) -> [UInt32] {
        GLWEPack.pack(encryptBit(bit))
    }

    package func decodeBit(_ polynomial: [UInt32]) -> UInt32 {
        let ct = GLWEPack.unpack(
            polynomial,
            polynomialDegree: params.polynomialDegree,
            glweDimension: 1
        )
        return decryptBit(ct)
    }
}

/// Trivial noise-free encoding: bit `b` ↔ constant-fill length-`N` vector of `b`.
package struct TrivialConstantFillEncoding: TorusBitEncoding {
    package let degree: Int

    package init(degree: Int = polynomialDegree) {
        precondition(degree > 0)
        self.degree = degree
    }

    package func encodeBit(_ bit: UInt32) -> [UInt32] {
        MockTorusEncoding.encodeBit(bit, degree: degree)
    }

    package func decodeBit(_ polynomial: [UInt32]) -> UInt32 {
        precondition(polynomial.count == degree)
        return MockTorusEncoding.decodeBit(polynomial)
    }
}

/// Trivial phase / message-slot encoding: bit in `coeff[0]`, zeros elsewhere.
/// Closer to TFHE trivial ciphertexts; multilinear stays exact if constants use this too.
package struct TrivialPhaseEncoding: TorusBitEncoding {
    package let degree: Int

    package init(degree: Int = polynomialDegree) {
        precondition(degree > 0)
        self.degree = degree
    }

    package func encodeBit(_ bit: UInt32) -> [UInt32] {
        precondition(bit == 0 || bit == 1)
        var poly = [UInt32](repeating: 0, count: degree)
        poly[0] = bit
        return poly
    }

    package func decodeBit(_ polynomial: [UInt32]) -> UInt32 {
        precondition(polynomial.count == degree)
        let bit = polynomial[0]
        precondition(bit == 0 || bit == 1, "Phase message must be 0 or 1, got \(bit)")
        for i in 1..<degree where polynomial[i] != 0 {
            preconditionFailure("Phase encoding has non-zero pad at coeff[\(i)]")
        }
        return bit
    }
}

/// `$lut` body backends.
package enum LUTEvaluationBackend: String, Sendable, CaseIterable {
    /// Exact on trivial encodings (fast Metal graph / cleartext-shaped oracle).
    case multilinear
    /// Phase-1 modular kernel / shape stress — **not** a netlist LUT backend.
    case denseNegacyclicMatvec
    /// Trivial PBS: CMUX + negacyclic rotate (Metal) / scalar CMUX (CPU).
    case programmableBootstrap = "pbs"
    /// GGSW-shaped PBS on trivial Metal wires; CPU certifies GGSW ⋉ + KS.
    case programmableBootstrapGGSW = "pbs-ggsw"
    /// Encrypted LWE + BK blind-rotate netlist (`EncryptedNetlistSimulator`).
    case encryptedBlindRotate = "encrypted"

    package var isBooleanSafeUnderTrivialEncoding: Bool {
        switch self {
        case .multilinear, .programmableBootstrap, .programmableBootstrapGGSW: return true
        case .denseNegacyclicMatvec, .encryptedBlindRotate: return false
        }
    }

    package var isImplemented: Bool {
        switch self {
        case .multilinear, .denseNegacyclicMatvec,
             .programmableBootstrap, .programmableBootstrapGGSW,
             .encryptedBlindRotate:
            return true
        }
    }

    /// Metal `$lut` lowering uses the CMUX/rotate subgraph for trivial PBS flavours.
    package var usesPBSMetalSubgraph: Bool {
        self == .programmableBootstrap || self == .programmableBootstrapGGSW
    }

    /// Host-driven encrypted path (Metal GGSW CMUX inside blind-rotate).
    package var usesEncryptedNetlist: Bool {
        self == .encryptedBlindRotate
    }
}

/// Active HELUT datapath configuration (encoding × LUT backend).
package struct HELUTDatapathConfig: Sendable {
    package var encodingDegree: Int
    package var encodingKind: TrivialBitEncodingKind
    package var lutBackend: LUTEvaluationBackend

    package init(
        encodingDegree: Int,
        encodingKind: TrivialBitEncodingKind,
        lutBackend: LUTEvaluationBackend
    ) {
        self.encodingDegree = encodingDegree
        self.encodingKind = encodingKind
        self.lutBackend = lutBackend
    }

    package static let booleanSafeTrivial = HELUTDatapathConfig(
        encodingDegree: polynomialDegree,
        encodingKind: .constantFill,
        lutBackend: .multilinear
    )

    package static let clearShapeBoolean = HELUTDatapathConfig(
        encodingDegree: 1,
        encodingKind: .constantFill,
        lutBackend: .multilinear
    )

    package static let booleanSafePhase = HELUTDatapathConfig(
        encodingDegree: polynomialDegree,
        encodingKind: .phase,
        lutBackend: .multilinear
    )

    package static let booleanSafeGLWE = HELUTDatapathConfig(
        encodingDegree: polynomialDegree,
        encodingKind: .glweTrivial,
        lutBackend: .multilinear
    )

    package static let booleanSafeGLWEPacked = HELUTDatapathConfig(
        encodingDegree: polynomialDegree,
        encodingKind: .glwePacked,
        lutBackend: .multilinear
    )

    /// Graduated FHE path: encrypted LWE + BK blind-rotate (`EncryptedNetlistSimulator`).
    package static let encryptedBlindRotate = HELUTDatapathConfig(
        encodingDegree: 8,
        encodingKind: .glwePacked,
        lutBackend: .encryptedBlindRotate
    )

    package var encoding: any TorusBitEncoding {
        encodingKind.makeEncoding(degree: encodingDegree)
    }

    package var wireDegree: Int {
        encodingKind.wireWidth(polynomialDegree: encodingDegree)
    }

    package func assertRunnable() {
        if lutBackend == .denseNegacyclicMatvec {
            preconditionFailure(
                "denseNegacyclicMatvec is not a netlist LUT backend; use NegacyclicMatvecNode"
            )
        }
        precondition(
            lutBackend.isImplemented,
            "LUT backend '\(lutBackend.rawValue)' is not implemented"
        )
        if lutBackend == .programmableBootstrap || lutBackend == .programmableBootstrapGGSW {
            precondition(
                encodingDegree >= 2,
                "PBS needs degree >= 2 (and >= 2^lutWidth per cell); use N>=8 for typical Yosys LUTs"
            )
        }
        if lutBackend == .encryptedBlindRotate {
            precondition(
                encodingDegree >= 2,
                "encrypted blind-rotate needs poly degree >= 2^lutWidth"
            )
        }
    }
}

// MARK: - PBS stub (fail-closed)

/// Placeholders for real programmable bootstrapping. Calling compile paths refuses.
package enum ProgrammableBootstrapStub {
    /// Message scaling for future trivial-PBS experiments (`μ = b · Δ`).
    package static let defaultDelta: UInt32 = 1 << 31

    package static func refuse(reason: String) -> Never {
        fatalError(
            "ProgrammableBootstrap refuse (\(reason)). "
                + "Use --lut-backend pbs|pbs-ggsw for trivial Metal graphs, "
                + "or --lut-backend encrypted / --bench-encrypted for BK blind-rotate. "
                + "See directives/fhe-graduation.md."
        )
    }

    /// Test polynomial skeleton: `T[addr] = LUT[addr] · Δ` in the low `2^k` slots.
    /// Not consumed by any live path yet — API for the future PBS subgraph.
    package static func testPolynomial(
        truthTable: [UInt32],
        degree: Int,
        delta: UInt32 = defaultDelta
    ) -> [UInt32] {
        precondition(truthTable.count.nonzeroBitCount == 1)
        precondition(truthTable.count <= degree)
        var poly = [UInt32](repeating: 0, count: degree)
        for (addr, bit) in truthTable.enumerated() where bit != 0 {
            poly[addr] = delta
        }
        return poly
    }

    /// MPSGraph entry — delegates to trivial PBS (CMUX + negacyclic rotate).
    package static func compileLUTNode(
        name: String,
        truthTable: [UInt32],
        graph: MPSGraph,
        inputs: [MPSGraphTensor],
        degree: Int,
        batch: Int,
        encodingKind: TrivialBitEncodingKind
    ) -> MPSGraphTensor {
        ProgrammableBootstrap.compileLUT(
            name: name,
            truthTable: truthTable,
            graph: graph,
            inputs: inputs,
            degree: degree,
            batch: batch,
            encodingKind: encodingKind
        )
    }
}
