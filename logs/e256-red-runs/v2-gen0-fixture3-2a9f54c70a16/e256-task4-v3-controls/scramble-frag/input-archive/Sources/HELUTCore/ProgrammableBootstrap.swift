import Foundation
import Metal
import MetalPerformanceShadersGraph

// MARK: - Trivial programmable bootstrap (CMUX + negacyclic rotate)
//
// Vertical slice: evaluate a Yosys `$lut` as
//   acc ← T;  for i: acc ← CMUX(x_i, X^{-2^i}·acc, acc);  extract coeff[0]
// under noise-free encodings. Selector bits are broadcast from coeff[0] (trivial
// GGSW) so phase-encoded wires work with a full accumulator polynomial.
// Real TFHE replaces broadcast + clear T with GGSW external products + BK.

/// Multiply `coeffs` by `X^power` in `Z/2^{32}Z[X]/(X^N+1)`.
package func negacyclicMultiplyByXPower(_ coeffs: [UInt32], power: Int) -> [UInt32] {
    let n = coeffs.count
    precondition(n > 0)
    var out = [UInt32](repeating: 0, count: n)
    var p = power % (2 * n)
    if p < 0 { p += 2 * n }
    for i in 0..<n {
        let exp = i + p
        let wraps = exp / n
        let r = exp % n
        if wraps & 1 == 0 {
            out[r] &+= coeffs[i]
        } else {
            out[r] &-= coeffs[i]
        }
    }
    return out
}

/// CPU oracle for trivial PBS LUT eval (noise-free).
package func evaluateTrivialPBS(
    truthTable: [UInt32],
    inputs: [UInt32],
    degree: Int,
    delta: UInt32 = 1
) -> UInt32 {
    precondition(truthTable.count == 1 << inputs.count)
    precondition(degree >= truthTable.count)
    for bit in inputs {
        precondition(bit == 0 || bit == 1)
    }
    var acc = ProgrammableBootstrapStub.testPolynomial(
        truthTable: truthTable,
        degree: degree,
        delta: delta
    )
    for (bitIndex, bit) in inputs.enumerated() {
        let rotated = negacyclicMultiplyByXPower(acc, power: -(1 << bitIndex))
        if bit == 0 { continue }
        for j in 0..<degree {
            acc[j] = rotated[j]
        }
    }
    let message = acc[0]
    if delta == 1 {
        precondition(message == 0 || message == 1, "PBS extract not boolean: \(message)")
        return message
    }
    return message >= (delta / 2) ? 1 : 0
}

/// Metal `$lut` body: trivial PBS (test poly + CMUX rotates + sample extract).
package enum ProgrammableBootstrap {
    /// Compile one LUT as a PBS-shaped subgraph. Inputs and output use `encodingKind`.
    package static func compileLUT(
        name: String,
        truthTable: [UInt32],
        graph: MPSGraph,
        inputs: [MPSGraphTensor],
        degree: Int,
        batch: Int,
        encodingKind: TrivialBitEncodingKind,
        delta: UInt32 = 1
    ) -> MPSGraphTensor {
        let width = inputs.count
        precondition(truthTable.count == 1 << width)
        precondition(
            degree >= truthTable.count,
            "PBS requires degree >= 2^width (got N=\(degree), width=\(width))"
        )

        if width == 0 {
            return encodedConstant(
                graph: graph,
                bit: truthTable[0],
                name: "\(name)_const",
                degree: degree,
                batch: batch,
                encodingKind: encodingKind
            )
        }

        var acc = testPolynomialTensor(
            graph: graph,
            name: "\(name)_T",
            truthTable: truthTable,
            degree: degree,
            batch: batch,
            delta: delta
        )

        for bitIndex in 0..<width {
            let rotated = mulByXPower(
                graph: graph,
                poly: acc,
                power: -(1 << bitIndex),
                name: "\(name)_rot\(bitIndex)",
                degree: degree,
                batch: batch
            )
            let sel = broadcastCoeff0(
                graph: graph,
                bitPoly: inputs[bitIndex],
                name: "\(name)_sel\(bitIndex)",
                degree: degree,
                batch: batch
            )
            // CMUX(sel, rotated, acc) = acc + sel * (rotated - acc)
            let diff = graph.subtraction(rotated, acc, name: "\(name)_diff\(bitIndex)")
            let gated = graph.multiplication(sel, diff, name: "\(name)_gated\(bitIndex)")
            acc = graph.addition(acc, gated, name: "\(name)_cmux\(bitIndex)")
        }

        return sampleExtract(
            graph: graph,
            glwe: acc,
            name: "\(name)_extract",
            degree: degree,
            batch: batch,
            encodingKind: encodingKind,
            delta: delta
        )
    }

    // MARK: - Graph helpers

    private static func testPolynomialTensor(
        graph: MPSGraph,
        name: String,
        truthTable: [UInt32],
        degree: Int,
        batch: Int,
        delta: UInt32
    ) -> MPSGraphTensor {
        let lane = ProgrammableBootstrapStub.testPolynomial(
            truthTable: truthTable,
            degree: degree,
            delta: delta
        )
        var values: [UInt32] = []
        values.reserveCapacity(batch * degree)
        for _ in 0..<batch {
            values.append(contentsOf: lane)
        }
        let shape: [NSNumber] = [NSNumber(value: batch), NSNumber(value: degree)]
        let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
        return graph.constant(data, shape: shape, dataType: .uInt32)
    }

    /// Broadcast wire coeff[0] across all N lanes (trivial GGSW / fill for CMUX).
    private static func broadcastCoeff0(
        graph: MPSGraph,
        bitPoly: MPSGraphTensor,
        name: String,
        degree: Int,
        batch: Int
    ) -> MPSGraphTensor {
        if degree == 1 { return bitPoly }
        let c0 = graph.sliceTensor(
            bitPoly,
            dimension: 1,
            start: 0,
            length: 1,
            name: "\(name)_c0"
        )
        let onesLane = [UInt32](repeating: 1, count: degree)
        var onesHost: [UInt32] = []
        onesHost.reserveCapacity(batch * degree)
        for _ in 0..<batch {
            onesHost.append(contentsOf: onesLane)
        }
        let onesShape: [NSNumber] = [NSNumber(value: batch), NSNumber(value: degree)]
        let onesData = onesHost.withUnsafeBufferPointer { Data(buffer: $0) }
        let ones = graph.constant(onesData, shape: onesShape, dataType: .uInt32)
        // c0 is [B,1]; ones is [B,N] — MPSGraph broadcasts the length-1 axis.
        return graph.multiplication(c0, ones, name: name)
    }

    /// `X^power · poly` via slice/concat (no dense Toeplitz).
    private static func mulByXPower(
        graph: MPSGraph,
        poly: MPSGraphTensor,
        power: Int,
        name: String,
        degree: Int,
        batch: Int
    ) -> MPSGraphTensor {
        _ = batch
        var p = power % (2 * degree)
        if p < 0 { p += 2 * degree }
        if p == 0 { return poly }
        if p >= degree {
            // X^{N+r} = -X^r
            let reduced = mulByXPowerPositive(
                graph: graph,
                poly: poly,
                power: p - degree,
                name: "\(name)_red",
                degree: degree
            )
            let zero = encodedZero(graph: graph, name: "\(name)_z", degree: degree, batch: batch)
            return graph.subtraction(zero, reduced, name: name)
        }
        return mulByXPowerPositive(
            graph: graph,
            poly: poly,
            power: p,
            name: name,
            degree: degree
        )
    }

    /// `0 < power < N`: out = concat(-poly[N-k..<N], poly[0..<N-k]).
    private static func mulByXPowerPositive(
        graph: MPSGraph,
        poly: MPSGraphTensor,
        power: Int,
        name: String,
        degree: Int
    ) -> MPSGraphTensor {
        precondition(power > 0 && power < degree)
        let k = power
        let left = graph.sliceTensor(
            poly,
            dimension: 1,
            start: 0,
            length: degree - k,
            name: "\(name)_left"
        )
        let right = graph.sliceTensor(
            poly,
            dimension: 1,
            start: degree - k,
            length: k,
            name: "\(name)_right"
        )
        let zeroK = graph.multiplication(
            right,
            graph.constant(0, dataType: .uInt32),
            name: "\(name)_zeroK"
        )
        let negRight = graph.subtraction(zeroK, right, name: "\(name)_neg")
        return graph.concatTensors([negRight, left], dimension: 1, name: name)
    }

    private static func encodedZero(
        graph: MPSGraph,
        name: String,
        degree: Int,
        batch: Int
    ) -> MPSGraphTensor {
        let shape: [NSNumber] = [NSNumber(value: batch), NSNumber(value: degree)]
        let values = [UInt32](repeating: 0, count: batch * degree)
        let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
        return graph.constant(data, shape: shape, dataType: .uInt32)
    }

    private static func sampleExtract(
        graph: MPSGraph,
        glwe: MPSGraphTensor,
        name: String,
        degree: Int,
        batch: Int,
        encodingKind: TrivialBitEncodingKind,
        delta: UInt32
    ) -> MPSGraphTensor {
        let c0 = graph.sliceTensor(
            glwe,
            dimension: 1,
            start: 0,
            length: 1,
            name: "\(name)_c0"
        )
        // Boolean path: delta == 1 → message already 0/1.
        let bitSlot: MPSGraphTensor
        if delta == 1 {
            bitSlot = c0
        } else {
            // Threshold at delta/2 without floats: compare via wrapping subtract heuristic skipped;
            // trivial boolean PBS always uses delta == 1.
            bitSlot = c0
            precondition(delta == 1)
        }

        switch encodingKind {
        case .phase, .glweTrivial:
            if degree == 1 { return bitSlot }
            let zeros = encodedZero(
                graph: graph,
                name: "\(name)_pad",
                degree: degree - 1,
                batch: batch
            )
            return graph.concatTensors([bitSlot, zeros], dimension: 1, name: name)
        case .constantFill:
            return broadcastCoeff0(
                graph: graph,
                bitPoly: bitSlot,
                name: name,
                degree: degree,
                batch: batch
            )
        case .glwePacked:
            preconditionFailure("glwe-packed body eval should use phase extract; wrap in LUTNode.compilePacked")
        }
    }

    private static func encodedConstant(
        graph: MPSGraph,
        bit: UInt32,
        name: String,
        degree: Int,
        batch: Int,
        encodingKind: TrivialBitEncodingKind
    ) -> MPSGraphTensor {
        let shape: [NSNumber] = [NSNumber(value: batch), NSNumber(value: degree)]
        let lane = encodingKind.makeEncoding(degree: degree).encodeBit(bit)
        var values: [UInt32] = []
        values.reserveCapacity(batch * degree)
        for _ in 0..<batch {
            values.append(contentsOf: lane)
        }
        let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
        return graph.constant(data, shape: shape, dataType: .uInt32)
    }
}
