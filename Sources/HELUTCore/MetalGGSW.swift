import Foundation
import Metal
import MetalPerformanceShadersGraph

// MARK: - Metal GGSW kernel (graduation step 9a)
//
// Packed GLWE layout for k=1: `[B, 2N] = mask ‖ body`. Boolean / crypto gadget
// external product + CMUX on MPSGraph; `evaluatePBS` certifies Metal GGSW as a
// `$lut` body (CMUX chain). Netlist-wide encrypted controls still step 10+.

/// Packed GLWE wire width for `glweDimension = 1`: mask then body.
package enum GLWEPack {
    package static func packedDegree(polynomialDegree: Int, glweDimension: Int) -> Int {
        precondition(glweDimension >= 1)
        return (glweDimension + 1) * polynomialDegree
    }

    package static func pack(_ ct: GLWECiphertext) -> [UInt32] {
        var out: [UInt32] = []
        out.reserveCapacity((ct.glweDimension + 1) * ct.degree)
        for poly in ct.mask {
            out.append(contentsOf: poly)
        }
        out.append(contentsOf: ct.body)
        return out
    }

    package static func unpack(
        _ packed: [UInt32],
        polynomialDegree: Int,
        glweDimension: Int
    ) -> GLWECiphertext {
        let need = (glweDimension + 1) * polynomialDegree
        precondition(packed.count == need)
        var mask: [[UInt32]] = []
        mask.reserveCapacity(glweDimension)
        for j in 0..<glweDimension {
            let start = j * polynomialDegree
            mask.append(Array(packed[start..<(start + polynomialDegree)]))
        }
        let bodyStart = glweDimension * polynomialDegree
        let body = Array(packed[bodyStart..<(bodyStart + polynomialDegree)])
        return GLWECiphertext(mask: mask, body: body)
    }

    package static func packBatch(_ cts: [GLWECiphertext]) -> [UInt32] {
        precondition(!cts.isEmpty)
        var out: [UInt32] = []
        for ct in cts {
            out.append(contentsOf: pack(ct))
        }
        return out
    }
}

/// Metal GGSW ops (k=1; boolean or crypto gadget).
package enum MetalGGSW {
    /// Run `externalProduct` on Metal; returns decrypted-comparable ciphertext.
    package static func externalProduct(
        ggsw: GGSWCiphertext,
        ciphertext: GLWECiphertext,
        device: MTLDevice,
        commandQueue: MTLCommandQueue
    ) throws -> GLWECiphertext {
        precondition(ggsw.params.tfhe.glweDimension == 1, "Metal GGSW kernel is k=1 only")
        precondition(ciphertext.glweDimension == 1)
        precondition(ciphertext.degree == ggsw.params.tfhe.polynomialDegree)
        precondition(ggsw.params.baseLog * ggsw.params.levelCount == 32)

        let degree = ciphertext.degree
        let batch = 1
        let levels = ggsw.params.levelCount
        let baseLog = ggsw.params.baseLog
        let packedWidth = GLWEPack.packedDegree(polynomialDegree: degree, glweDimension: 1)
        let graph = MPSGraph()
        let bank = GraphConstBank(graph: graph, degree: degree, batch: batch)

        let ctPack = GLWEPack.pack(ciphertext)
        let ctTensor = constantPacked(graph: graph, values: ctPack, batch: batch, width: packedWidth, name: "ct")
        let mask = graph.sliceTensor(ctTensor, dimension: 1, start: 0, length: degree, name: "ct_mask")
        let body = graph.sliceTensor(ctTensor, dimension: 1, start: degree, length: degree, name: "ct_body")

        let maskDigits = gadgetDecomposeMetal(
            graph: graph,
            poly: mask,
            baseLog: baseLog,
            levelCount: levels,
            degree: degree,
            batch: batch,
            name: "dmask"
        )
        let bodyDigits = gadgetDecomposeMetal(
            graph: graph,
            poly: body,
            baseLog: baseLog,
            levelCount: levels,
            degree: degree,
            batch: batch,
            name: "dbody"
        )

        var outMask: MPSGraphTensor?
        var outBody: MPSGraphTensor?
        for level in 0..<levels {
            let gMask = constantGLWE(
                graph: graph,
                ct: ggsw.row(glweRow: 0, level: level),
                batch: batch,
                name: "gm\(level)"
            )
            let gBody = constantGLWE(
                graph: graph,
                ct: ggsw.row(glweRow: 1, level: level),
                batch: batch,
                name: "gb\(level)"
            )
            let t0 = scaleGLWE(
                graph: graph,
                ct: gMask,
                poly: maskDigits[level],
                degree: degree,
                batch: batch,
                name: "t0_\(level)",
                bank: bank
            )
            let t1 = scaleGLWE(
                graph: graph,
                ct: gBody,
                poly: bodyDigits[level],
                degree: degree,
                batch: batch,
                name: "t1_\(level)",
                bank: bank
            )
            let levelMask = graph.addition(t0.mask, t1.mask, name: "lm\(level)")
            let levelBody = graph.addition(t0.body, t1.body, name: "lb\(level)")
            outMask = outMask.map { graph.addition($0, levelMask, name: "om\(level)") } ?? levelMask
            outBody = outBody.map { graph.addition($0, levelBody, name: "ob\(level)") } ?? levelBody
        }
        let packed = graph.concatTensors([outMask!, outBody!], dimension: 1, name: "out_pack")

        let resultPack = try runUnary(
            graph: graph,
            output: packed,
            device: device,
            commandQueue: commandQueue,
            elementCount: packedWidth
        )
        return GLWEPack.unpack(resultPack, polynomialDegree: degree, glweDimension: 1)
    }

    package static func cmux(
        control: GGSWCiphertext,
        d1: GLWECiphertext,
        d0: GLWECiphertext,
        device: MTLDevice,
        commandQueue: MTLCommandQueue
    ) throws -> GLWECiphertext {
        let diff = subGLWE(d1, d0)
        let gated = try externalProduct(
            ggsw: control,
            ciphertext: diff,
            device: device,
            commandQueue: commandQueue
        )
        return addGLWE(d0, gated)
    }

    /// One `$lut` via Metal GGSW CMUX + CPU rotate (e=0); returns output GLWE.
    package static func evaluatePBSCiphertext(
        truthTable: [UInt32],
        inputs: [UInt32],
        secret: TFHESecretKey,
        params: GGSWParams,
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        rng: inout LCG32
    ) throws -> GLWECiphertext {
        precondition(secret.params == params.tfhe)
        precondition(params.tfhe.glweDimension == 1)
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
            let power = -(1 << bitIndex)
            let rotated = GLWECiphertext(
                mask: acc.mask.map { negacyclicMultiplyByXPower($0, power: power) },
                body: negacyclicMultiplyByXPower(acc.body, power: power)
            )
            acc = try cmux(
                control: control,
                d1: rotated,
                d0: acc,
                device: device,
                commandQueue: commandQueue
            )
        }
        return acc
    }

    /// One `$lut` via Metal GGSW CMUX + CPU rotate (e=0). Certifies GGSW as LUT body
    /// against `evaluatePBSGGSW`. Netlist use: `EncryptedNetlistSimulator`.
    package static func evaluatePBS(
        truthTable: [UInt32],
        inputs: [UInt32],
        secret: TFHESecretKey,
        params: GGSWParams,
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        rng: inout LCG32
    ) throws -> UInt32 {
        let acc = try evaluatePBSCiphertext(
            truthTable: truthTable,
            inputs: inputs,
            secret: secret,
            params: params,
            device: device,
            commandQueue: commandQueue,
            rng: &rng
        )
        let phase = decryptGLWE(acc, secret: secret)[0]
        return decodeBooleanPhase(phase, delta: params.tfhe.delta)
    }

    /// Blind rotate on Metal. Default: fused MPSGraph at *N*≤64; tiled kernel otherwise.
    package static func blindRotate(
        testPolynomial: [UInt32],
        lwe: LWECiphertext,
        bootstrapKey: BootstrapKey,
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        lowering: MetalBRLowering? = nil,
        tileWidth: Int? = nil
    ) throws -> GLWECiphertext {
        let n = bootstrapKey.params.tfhe.polynomialDegree
        let mode = lowering ?? MetalBRControl.overrideLowering ?? MetalBRLowering.automatic(degree: n)
        let w = tileWidth ?? MetalBRControl.defaultTileWidth
        switch mode {
        case .tiledKernel:
            return try blindRotateTiledKernel(
                testPolynomial: testPolynomial,
                lwe: lwe,
                bootstrapKey: bootstrapKey,
                device: device,
                commandQueue: commandQueue,
                tileWidth: w
            )
        case .fused:
            return try blindRotateFused(
                testPolynomial: testPolynomial,
                lwe: lwe,
                bootstrapKey: bootstrapKey,
                device: device,
                commandQueue: commandQueue
            )
        }
    }

    /// One MPSGraph for all CMUX levels (schoolbook poly-mul expanded to MLIR).
    /// Do not use at *N*=1024 — encode does not finish (H3 fused kill 2026-08-13).
    private static func blindRotateFused(
        testPolynomial: [UInt32],
        lwe: LWECiphertext,
        bootstrapKey: BootstrapKey,
        device: MTLDevice,
        commandQueue: MTLCommandQueue
    ) throws -> GLWECiphertext {
        let params = bootstrapKey.params
        precondition(params.tfhe.glweDimension == 1, "Metal BR is k=1 only")
        let n = params.tfhe.polynomialDegree
        let twoN = 2 * n
        let batch = 1
        let levels = params.levelCount
        let baseLog = params.baseLog
        precondition(testPolynomial.count == n)
        precondition(lwe.lweDimension == bootstrapKey.bitKeys.count)
        precondition(baseLog * levels == 32)

        let encode0 = CFAbsoluteTimeGetCurrent()
        let bPow = rotationPower(lwe.b, twoN: twoN)
        let acc0Body = negacyclicMultiplyByXPower(testPolynomial, power: -bPow)
        let packedWidth = GLWEPack.packedDegree(polynomialDegree: n, glweDimension: 1)

        let graph = MPSGraph()
        let bank = GraphConstBank(graph: graph, degree: n, batch: batch)
        var acc = GLWETensors(
            mask: bank.zeros,
            body: constantPacked(graph: graph, values: acc0Body, batch: batch, width: n, name: "acc0_b")
        )

        MetalBRControl.progress?("BR fused encode N=\(n) CMUX=0..<\(lwe.lweDimension)")
        for j in 0..<lwe.lweDimension {
            let aPow = rotationPower(lwe.a[j], twoN: twoN)
            let rotMask = mulByXPower(
                graph: graph, poly: acc.mask, power: aPow, name: "rot_m\(j)", degree: n, batch: batch,
                bank: bank
            )
            let rotBody = mulByXPower(
                graph: graph, poly: acc.body, power: aPow, name: "rot_b\(j)", degree: n, batch: batch,
                bank: bank
            )
            let diff = GLWETensors(
                mask: graph.subtraction(rotMask, acc.mask, name: "diff_m\(j)"),
                body: graph.subtraction(rotBody, acc.body, name: "diff_b\(j)")
            )
            let gated = externalProductOnGraph(
                graph: graph,
                ggsw: bootstrapKey.bitKeys[j],
                ciphertext: diff,
                degree: n,
                batch: batch,
                baseLog: baseLog,
                levelCount: levels,
                name: "ep\(j)",
                bank: bank
            )
            acc = GLWETensors(
                mask: graph.addition(acc.mask, gated.mask, name: "acc_m\(j)"),
                body: graph.addition(acc.body, gated.body, name: "acc_b\(j)")
            )
        }

        let packed = graph.concatTensors([acc.mask, acc.body], dimension: 1, name: "br_out")
        let encodeSeconds = CFAbsoluteTimeGetCurrent() - encode0
        let run0 = CFAbsoluteTimeGetCurrent()
        let resultPack = try runUnary(
            graph: graph,
            output: packed,
            device: device,
            commandQueue: commandQueue,
            elementCount: packedWidth
        )
        let gpuSeconds = CFAbsoluteTimeGetCurrent() - run0
        MetalBRControl.lastTelemetry = MetalBRTelemetry(
            lowering: MetalBRLowering.fused.rawValue,
            tileWidth: lwe.lweDimension,
            tileCount: 1,
            encodeSeconds: encodeSeconds,
            gpuRunSeconds: gpuSeconds,
            hostRepackSeconds: 0,
            ring: "mlir"
        )
        return GLWEPack.unpack(resultPack, polynomialDegree: n, glweDimension: 1)
    }

    package static func evaluateLUTBlindRotate(
        truthTable: [UInt32],
        inputs: [LWECiphertext],
        bootstrapKey: BootstrapKey,
        scale: UInt32? = nil,
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        lowering: MetalBRLowering? = nil,
        tileWidth: Int? = nil
    ) throws -> LWECiphertext {
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
        let acc = try blindRotate(
            testPolynomial: testPoly,
            lwe: packed,
            bootstrapKey: bootstrapKey,
            device: device,
            commandQueue: commandQueue,
            lowering: lowering,
            tileWidth: tileWidth
        )
        return sampleExtractLWE(acc, params: params.tfhe)
    }

    // MARK: - Whole-netlist single MPSGraph (step 10l)
    //
    // Rotation-native LWE wires + publicMS: each BR uses dynamic X^p select so
    // dependent `$lut`s chain in one graph / one GPU submit.

    /// Topo-ordered LUT jobs for a combinational encrypted netlist tick.
    package struct NetlistLUTJob: Sendable {
        package var name: String
        package var truthTable: [UInt32]
        package var inputWireIds: [Int]
        package var outputWireId: Int

        package init(name: String, truthTable: [UInt32], inputWireIds: [Int], outputWireId: Int) {
            self.name = name
            self.truthTable = truthTable
            self.inputWireIds = inputWireIds
            self.outputWireId = outputWireId
        }
    }

    /// Evaluate a combinational LUT netlist after ingest publicMS.
    /// Default: host-scheduled per-LUT BR (tiled-kernel at *N*>64).
    /// `--metal-br-fused` keeps the legacy single MPSGraph (do not use at *N*=1024).
    package static func evaluateTopoNetlistSingleGraph(
        jobs: [NetlistLUTJob],
        primaryWires: [Int: LWECiphertext],
        bootstrapKey: BootstrapKey,
        scale: UInt32,
        device: MTLDevice,
        commandQueue: MTLCommandQueue
    ) throws -> [Int: LWECiphertext] {
        let n = bootstrapKey.params.tfhe.polynomialDegree
        let mode = MetalBRControl.overrideLowering ?? MetalBRLowering.automatic(degree: n)
        switch mode {
        case .tiledKernel:
            return try evaluateTopoNetlistTiledKernel(
                jobs: jobs,
                primaryWires: primaryWires,
                bootstrapKey: bootstrapKey,
                scale: scale,
                device: device,
                commandQueue: commandQueue
            )
        case .fused:
            return try evaluateTopoNetlistFusedGraph(
                jobs: jobs,
                primaryWires: primaryWires,
                bootstrapKey: bootstrapKey,
                scale: scale,
                device: device,
                commandQueue: commandQueue
            )
        }
    }

    /// Host-scheduled LUT BRs + `publicRefreshBit` (Phase 2.3 netlist lowering).
    private static func evaluateTopoNetlistTiledKernel(
        jobs: [NetlistLUTJob],
        primaryWires: [Int: LWECiphertext],
        bootstrapKey: BootstrapKey,
        scale: UInt32,
        device: MTLDevice,
        commandQueue: MTLCommandQueue
    ) throws -> [Int: LWECiphertext] {
        let params = bootstrapKey.params
        precondition(params.tfhe.glweDimension == 1)
        let n = params.tfhe.polynomialDegree
        let twoN = 2 * n
        var wires = primaryWires
        var produced: [Int: LWECiphertext] = [:]
        for (jobIndex, job) in jobs.enumerated() {
            MetalBRControl.progress?(
                "netlist LUT \(jobIndex + 1)/\(jobs.count) \(job.name)"
            )
            var inputs: [LWECiphertext] = []
            inputs.reserveCapacity(job.inputWireIds.count)
            for wid in job.inputWireIds {
                guard let ct = wires[wid] else {
                    preconditionFailure("missing wire \(wid) for LUT \(job.name)")
                }
                inputs.append(ct)
            }
            let extracted = try evaluateLUTBlindRotate(
                truthTable: job.truthTable,
                inputs: inputs,
                bootstrapKey: bootstrapKey,
                scale: scale,
                device: device,
                commandQueue: commandQueue,
                lowering: .tiledKernel
            )
            let refreshed = publicRefreshBit(extracted, twoN: twoN, scale: scale)
            wires[job.outputWireId] = refreshed
            produced[job.outputWireId] = refreshed
        }
        return produced
    }

    /// Legacy whole-netlist **one** MPSGraph submit (schoolbook-in-MLIR).
    private static func evaluateTopoNetlistFusedGraph(
        jobs: [NetlistLUTJob],
        primaryWires: [Int: LWECiphertext],
        bootstrapKey: BootstrapKey,
        scale: UInt32,
        device: MTLDevice,
        commandQueue: MTLCommandQueue
    ) throws -> [Int: LWECiphertext] {
        let params = bootstrapKey.params
        precondition(params.tfhe.glweDimension == 1)
        precondition(params.baseLog * params.levelCount == 32)
        let n = params.tfhe.polynomialDegree
        let twoN = 2 * n
        precondition(twoN.nonzeroBitCount == 1, "2N must be a power of two")
        precondition(twoN <= 4096, "binary X^p supports 2N ≤ 4096")
        let batch = 1
        let lweN = params.tfhe.lweDimension
        precondition(lweN == n)

        let graph = MPSGraph()
        let bank = GraphConstBank(graph: graph, degree: n, batch: batch)
        var wireTensors: [Int: LWETensors] = [:]
        for (id, ct) in primaryWires {
            precondition(ct.lweDimension == lweN)
            wireTensors[id] = constantLWE(graph: graph, ct: ct, batch: batch, name: "w\(id)")
        }

        var outputIds: [Int] = []
        // Share constantPacked test-poly tensors across identical INITs (N=1024 lever).
        var testPolyTensorByInit: [TFHELUTInitKey: MPSGraphTensor] = [:]
        TFHETestPolyCache.shared.resetStats()
        for (jobIndex, job) in jobs.enumerated() {
            precondition(job.truthTable.count == 1 << job.inputWireIds.count)
            precondition(n >= job.truthTable.count)
            var inputs: [LWETensors] = []
            for wid in job.inputWireIds {
                guard let t = wireTensors[wid] else {
                    preconditionFailure("missing wire \(wid) for LUT \(job.name)")
                }
                inputs.append(t)
            }
            let packed = packLWEOnGraph(
                graph: graph,
                bits: inputs,
                lweDimension: lweN,
                batch: batch,
                name: "pack\(jobIndex)"
            )
            let initKey = TFHELUTInitKey(truthTable: job.truthTable, degree: n, scale: scale)
            let testPolyTensor: MPSGraphTensor
            if let existing = testPolyTensorByInit[initKey] {
                testPolyTensor = existing
            } else {
                let testPoly = TFHETestPolyCache.shared.testPolynomial(
                    truthTable: job.truthTable,
                    degree: n,
                    scale: scale
                )
                testPolyTensor = constantPacked(
                    graph: graph,
                    values: testPoly,
                    batch: batch,
                    width: n,
                    name: "T\(testPolyTensorByInit.count)"
                )
                testPolyTensorByInit[initKey] = testPolyTensor
            }
            let acc = blindRotateOnGraphDynamicSharedTestPoly(
                graph: graph,
                testPolynomialTensor: testPolyTensor,
                lwe: packed,
                bootstrapKey: bootstrapKey,
                degree: n,
                batch: batch,
                name: "br\(jobIndex)",
                bank: bank
            )
            let extracted = sampleExtractOnGraph(
                graph: graph,
                acc: acc,
                degree: n,
                batch: batch,
                name: "ex\(jobIndex)"
            )
            // Extracted phase is scaled; fold to Z_{2N} (exact on δ-lattice).
            let refreshed = publicRefreshBitOnGraph(
                graph: graph,
                lwe: extracted,
                scale: scale,
                twoN: twoN,
                lweDimension: lweN,
                batch: batch,
                name: "ms\(jobIndex)"
            )
            wireTensors[job.outputWireId] = refreshed
            outputIds.append(job.outputWireId)
        }

        // Concat all produced LUT outputs for a single readback.
        var slices: [MPSGraphTensor] = []
        let outWidth = lweN + 1
        for oid in outputIds {
            let t = wireTensors[oid]!
            let packed = graph.concatTensors([t.a, t.b], dimension: 1, name: "out\(oid)")
            slices.append(packed)
        }
        let mega = graph.concatTensors(slices, dimension: 1, name: "net_out")
        let host = try runUnary(
            graph: graph,
            output: mega,
            device: device,
            commandQueue: commandQueue,
            elementCount: outputIds.count * outWidth
        )
        var result: [Int: LWECiphertext] = [:]
        for (i, oid) in outputIds.enumerated() {
            let base = i * outWidth
            let a = Array(host[base..<(base + lweN)])
            let b = host[base + lweN]
            result[oid] = LWECiphertext(a: a, b: b)
        }
        return result
    }

    // MARK: - Graph building blocks

    /// Shared splats for one MPSGraph (Phase 1.2 CSE).
    private final class GraphConstBank {
        let graph: MPSGraph
        let degree: Int
        let batch: Int
        let ones: MPSGraphTensor
        let zeros: MPSGraphTensor
        let scalarZero: MPSGraphTensor

        init(graph: MPSGraph, degree: Int, batch: Int) {
            self.graph = graph
            self.degree = degree
            self.batch = batch
            self.ones = constantPacked(
                graph: graph,
                values: [UInt32](repeating: 1, count: degree),
                batch: batch,
                width: degree,
                name: "cse_ones"
            )
            self.zeros = constantPacked(
                graph: graph,
                values: [UInt32](repeating: 0, count: degree),
                batch: batch,
                width: degree,
                name: "cse_zeros"
            )
            self.scalarZero = graph.constant(0, dataType: .uInt32)
        }
    }

    private struct GLWETensors {
        var mask: MPSGraphTensor
        var body: MPSGraphTensor
    }

    private struct LWETensors {
        var a: MPSGraphTensor // [B, n]
        var b: MPSGraphTensor // [B, 1]
    }

    private static func constantLWE(
        graph: MPSGraph,
        ct: LWECiphertext,
        batch: Int,
        name: String
    ) -> LWETensors {
        LWETensors(
            a: constantPacked(
                graph: graph,
                values: ct.a,
                batch: batch,
                width: ct.lweDimension,
                name: "\(name)_a"
            ),
            b: constantPacked(
                graph: graph,
                values: [ct.b],
                batch: batch,
                width: 1,
                name: "\(name)_b"
            )
        )
    }

    private static func packLWEOnGraph(
        graph: MPSGraph,
        bits: [LWETensors],
        lweDimension: Int,
        batch: Int,
        name: String
    ) -> LWETensors {
        precondition(!bits.isEmpty)
        var accA = bits[0].a
        var accB = bits[0].b
        for i in 1..<bits.count {
            let scalar = (1 as UInt32) &<< UInt32(i)
            let s = constantPacked(
                graph: graph,
                values: [UInt32](repeating: scalar, count: lweDimension),
                batch: batch,
                width: lweDimension,
                name: "\(name)_sa\(i)"
            )
            let sb = constantPacked(
                graph: graph,
                values: [scalar],
                batch: batch,
                width: 1,
                name: "\(name)_sb\(i)"
            )
            let scaledA = graph.multiplication(bits[i].a, s, name: "\(name)_xa\(i)")
            let scaledB = graph.multiplication(bits[i].b, sb, name: "\(name)_xb\(i)")
            accA = graph.addition(accA, scaledA, name: "\(name)_aa\(i)")
            accB = graph.addition(accB, scaledB, name: "\(name)_ab\(i)")
        }
        return LWETensors(a: accA, b: accB)
    }

    private static func remUInt32(
        graph: MPSGraph,
        value: MPSGraphTensor,
        modulus: Int,
        width: Int,
        batch: Int,
        name: String
    ) -> MPSGraphTensor {
        let m = UInt32(modulus)
        let mod = constantPacked(
            graph: graph,
            values: [UInt32](repeating: m, count: width),
            batch: batch,
            width: width,
            name: "\(name)_m"
        )
        let q = graph.division(value, mod, name: "\(name)_q")
        let prod = graph.multiplication(q, mod, name: "\(name)_p")
        return graph.subtraction(value, prod, name: name)
    }

    /// Cost model for dynamic monomial multiply on Metal (step 10m).
    package enum DynamicRotateCost {
        /// Legacy full mux: `(lweDim+1) · 2N` static rotates per BR.
        package static func muxRotates(twoN: Int, lweDimension: Int) -> Int {
            (lweDimension + 1) * twoN
        }

        /// Binary decomposition: `(lweDim+1) · log2(2N)` static rotates per BR.
        package static func binaryRotates(twoN: Int, lweDimension: Int) -> Int {
            precondition(twoN > 1 && twoN.nonzeroBitCount == 1)
            return (lweDimension + 1) * twoN.trailingZeroBitCount
        }
    }

    /// `X^p · poly` for runtime `p ∈ Z_{2N}` via binary digits (O(log N), not O(2N)).
    private static func mulByXPowerDynamic(
        graph: MPSGraph,
        poly: MPSGraphTensor,
        powerMod2N: MPSGraphTensor, // [B, 1]
        degree: Int,
        batch: Int,
        name: String,
        bank: GraphConstBank
    ) -> MPSGraphTensor {
        let twoN = 2 * degree
        precondition(twoN.nonzeroBitCount == 1)
        let logTwoN = twoN.trailingZeroBitCount
        let ones = bank.ones
        var acc = poly
        var power = powerMod2N
        for i in 0..<logTwoN {
            // bit_i = power mod 2; then power ← ⌊power/2⌋
            let bit = remUInt32(
                graph: graph, value: power, modulus: 2, width: 1, batch: batch, name: "\(name)_bit\(i)"
            )
            let two = constantPacked(
                graph: graph, values: [2], batch: batch, width: 1, name: "\(name)_two\(i)"
            )
            power = graph.division(power, two, name: "\(name)_shr\(i)")
            let rotated = mulByXPower(
                graph: graph,
                poly: acc,
                power: 1 << i,
                name: "\(name)_x\(i)",
                degree: degree,
                batch: batch,
                bank: bank
            )
            let bitB = graph.multiplication(bit, ones, name: "\(name)_bb\(i)")
            let oneMinus = graph.subtraction(ones, bitB, name: "\(name)_om\(i)")
            let t1 = graph.multiplication(rotated, bitB, name: "\(name)_t1_\(i)")
            let t0 = graph.multiplication(acc, oneMinus, name: "\(name)_t0_\(i)")
            acc = graph.addition(t1, t0, name: "\(name)_sel\(i)")
        }
        return acc
    }

    private static func blindRotateOnGraphDynamic(
        graph: MPSGraph,
        testPolynomial: [UInt32],
        lwe: LWETensors,
        bootstrapKey: BootstrapKey,
        degree: Int,
        batch: Int,
        name: String,
        bank: GraphConstBank
    ) -> GLWETensors {
        let twoN = 2 * degree
        let levels = bootstrapKey.params.levelCount
        let baseLog = bootstrapKey.params.baseLog
        let bPow = remUInt32(
            graph: graph, value: lwe.b, modulus: twoN, width: 1, batch: batch, name: "\(name)_bp"
        )
        // X^{-b} = X^{2N-b} when b≠0; X^0 when b=0.
        let twoNConst = constantPacked(
            graph: graph, values: [UInt32(twoN)], batch: batch, width: 1, name: "\(name)_2n"
        )
        let negB = remUInt32(
            graph: graph,
            value: graph.subtraction(twoNConst, bPow, name: "\(name)_nb"),
            modulus: twoN,
            width: 1,
            batch: batch,
            name: "\(name)_nb2"
        )
        let acc0Body = mulByXPowerDynamic(
            graph: graph,
            poly: constantPacked(
                graph: graph, values: testPolynomial, batch: batch, width: degree, name: "\(name)_T"
            ),
            powerMod2N: negB,
            degree: degree,
            batch: batch,
            name: "\(name)_acc0",
            bank: bank
        )
        var acc = GLWETensors(
            mask: bank.zeros,
            body: acc0Body
        )
        for j in 0..<bootstrapKey.bitKeys.count {
            let aSlice = graph.sliceTensor(
                lwe.a, dimension: 1, start: j, length: 1, name: "\(name)_a\(j)"
            )
            let aPow = remUInt32(
                graph: graph, value: aSlice, modulus: twoN, width: 1, batch: batch, name: "\(name)_ap\(j)"
            )
            let rotMask = mulByXPowerDynamic(
                graph: graph, poly: acc.mask, powerMod2N: aPow, degree: degree, batch: batch,
                name: "\(name)_rm\(j)", bank: bank
            )
            let rotBody = mulByXPowerDynamic(
                graph: graph, poly: acc.body, powerMod2N: aPow, degree: degree, batch: batch,
                name: "\(name)_rb\(j)", bank: bank
            )
            let diff = GLWETensors(
                mask: graph.subtraction(rotMask, acc.mask, name: "\(name)_dm\(j)"),
                body: graph.subtraction(rotBody, acc.body, name: "\(name)_db\(j)")
            )
            let gated = externalProductOnGraph(
                graph: graph,
                ggsw: bootstrapKey.bitKeys[j],
                ciphertext: diff,
                degree: degree,
                batch: batch,
                baseLog: baseLog,
                levelCount: levels,
                name: "\(name)_ep\(j)",
                bank: bank
            )
            acc = GLWETensors(
                mask: graph.addition(acc.mask, gated.mask, name: "\(name)_am\(j)"),
                body: graph.addition(acc.body, gated.body, name: "\(name)_ab\(j)")
            )
        }
        return acc
    }

    /// Blind-rotate with a shared test-polynomial tensor (identical INIT reuse).
    private static func blindRotateOnGraphDynamicSharedTestPoly(
        graph: MPSGraph,
        testPolynomialTensor: MPSGraphTensor,
        lwe: LWETensors,
        bootstrapKey: BootstrapKey,
        degree: Int,
        batch: Int,
        name: String,
        bank: GraphConstBank
    ) -> GLWETensors {
        let twoN = 2 * degree
        let levels = bootstrapKey.params.levelCount
        let baseLog = bootstrapKey.params.baseLog
        let bPow = remUInt32(
            graph: graph, value: lwe.b, modulus: twoN, width: 1, batch: batch, name: "\(name)_bp"
        )
        let twoNConst = constantPacked(
            graph: graph, values: [UInt32(twoN)], batch: batch, width: 1, name: "\(name)_2n"
        )
        let negB = remUInt32(
            graph: graph,
            value: graph.subtraction(twoNConst, bPow, name: "\(name)_nb"),
            modulus: twoN,
            width: 1,
            batch: batch,
            name: "\(name)_nb2"
        )
        let acc0Body = mulByXPowerDynamic(
            graph: graph,
            poly: testPolynomialTensor,
            powerMod2N: negB,
            degree: degree,
            batch: batch,
            name: "\(name)_acc0",
            bank: bank
        )
        var acc = GLWETensors(
            mask: bank.zeros,
            body: acc0Body
        )
        for j in 0..<bootstrapKey.bitKeys.count {
            let aSlice = graph.sliceTensor(
                lwe.a, dimension: 1, start: j, length: 1, name: "\(name)_a\(j)"
            )
            let aPow = remUInt32(
                graph: graph, value: aSlice, modulus: twoN, width: 1, batch: batch, name: "\(name)_ap\(j)"
            )
            let rotMask = mulByXPowerDynamic(
                graph: graph, poly: acc.mask, powerMod2N: aPow, degree: degree, batch: batch,
                name: "\(name)_rm\(j)", bank: bank
            )
            let rotBody = mulByXPowerDynamic(
                graph: graph, poly: acc.body, powerMod2N: aPow, degree: degree, batch: batch,
                name: "\(name)_rb\(j)", bank: bank
            )
            let diff = GLWETensors(
                mask: graph.subtraction(rotMask, acc.mask, name: "\(name)_dm\(j)"),
                body: graph.subtraction(rotBody, acc.body, name: "\(name)_db\(j)")
            )
            let gated = externalProductOnGraph(
                graph: graph,
                ggsw: bootstrapKey.bitKeys[j],
                ciphertext: diff,
                degree: degree,
                batch: batch,
                baseLog: baseLog,
                levelCount: levels,
                name: "\(name)_ep\(j)",
                bank: bank
            )
            acc = GLWETensors(
                mask: graph.addition(acc.mask, gated.mask, name: "\(name)_am\(j)"),
                body: graph.addition(acc.body, gated.body, name: "\(name)_ab\(j)")
            )
        }
        return acc
    }

    private static func sampleExtractOnGraph(
        graph: MPSGraph,
        acc: GLWETensors,
        degree: Int,
        batch: Int,
        name: String
    ) -> LWETensors {
        let b = graph.sliceTensor(acc.body, dimension: 1, start: 0, length: 1, name: "\(name)_b")
        var aParts: [MPSGraphTensor] = [
            graph.sliceTensor(acc.mask, dimension: 1, start: 0, length: 1, name: "\(name)_a0")
        ]
        let zero = constantPacked(
            graph: graph, values: [0], batch: batch, width: 1, name: "\(name)_z"
        )
        for i in 1..<degree {
            let coeff = graph.sliceTensor(
                acc.mask, dimension: 1, start: degree - i, length: 1, name: "\(name)_m\(i)"
            )
            aParts.append(graph.subtraction(zero, coeff, name: "\(name)_a\(i)"))
        }
        let a = graph.concatTensors(aParts, dimension: 1, name: "\(name)_a")
        return LWETensors(a: a, b: b)
    }

    private static func publicRefreshBitOnGraph(
        graph: MPSGraph,
        lwe: LWETensors,
        scale: UInt32,
        twoN: Int,
        lweDimension: Int,
        batch: Int,
        name: String
    ) -> LWETensors {
        precondition(scale > 1)
        let n = twoN / 2
        let step = rotationScale(polynomialDegree: n)
        precondition(scale % step == 0)
        let scaleA = constantPacked(
            graph: graph,
            values: [UInt32](repeating: step, count: lweDimension),
            batch: batch,
            width: lweDimension,
            name: "\(name)_sa"
        )
        let scaleB = constantPacked(
            graph: graph, values: [step], batch: batch, width: 1, name: "\(name)_sb"
        )
        let aDiv = graph.division(lwe.a, scaleA, name: "\(name)_ad")
        let bDiv = graph.division(lwe.b, scaleB, name: "\(name)_bd")
        return LWETensors(
            a: remUInt32(
                graph: graph, value: aDiv, modulus: twoN, width: lweDimension, batch: batch,
                name: "\(name)_ar"
            ),
            b: remUInt32(
                graph: graph, value: bDiv, modulus: twoN, width: 1, batch: batch, name: "\(name)_br"
            )
        )
    }

    /// GGSW ⋉ GLWE on an existing graph (ciphertext already tensors).
    private static func externalProductOnGraph(
        graph: MPSGraph,
        ggsw: GGSWCiphertext,
        ciphertext: GLWETensors,
        degree: Int,
        batch: Int,
        baseLog: Int,
        levelCount: Int,
        name: String,
        bank: GraphConstBank
    ) -> GLWETensors {
        let maskDigits = gadgetDecomposeMetal(
            graph: graph,
            poly: ciphertext.mask,
            baseLog: baseLog,
            levelCount: levelCount,
            degree: degree,
            batch: batch,
            name: "\(name)_dm"
        )
        let bodyDigits = gadgetDecomposeMetal(
            graph: graph,
            poly: ciphertext.body,
            baseLog: baseLog,
            levelCount: levelCount,
            degree: degree,
            batch: batch,
            name: "\(name)_db"
        )
        var outMask: MPSGraphTensor?
        var outBody: MPSGraphTensor?
        for level in 0..<levelCount {
            let gMask = constantGLWE(
                graph: graph,
                ct: ggsw.row(glweRow: 0, level: level),
                batch: batch,
                name: "\(name)_gm\(level)"
            )
            let gBody = constantGLWE(
                graph: graph,
                ct: ggsw.row(glweRow: 1, level: level),
                batch: batch,
                name: "\(name)_gb\(level)"
            )
            let t0 = scaleGLWE(
                graph: graph,
                ct: gMask,
                poly: maskDigits[level],
                degree: degree,
                batch: batch,
                name: "\(name)_t0_\(level)",
                bank: bank
            )
            let t1 = scaleGLWE(
                graph: graph,
                ct: gBody,
                poly: bodyDigits[level],
                degree: degree,
                batch: batch,
                name: "\(name)_t1_\(level)",
                bank: bank
            )
            let levelMask = graph.addition(t0.mask, t1.mask, name: "\(name)_lm\(level)")
            let levelBody = graph.addition(t0.body, t1.body, name: "\(name)_lb\(level)")
            outMask = outMask.map { graph.addition($0, levelMask, name: "\(name)_om\(level)") } ?? levelMask
            outBody = outBody.map { graph.addition($0, levelBody, name: "\(name)_ob\(level)") } ?? levelBody
        }
        return GLWETensors(mask: outMask!, body: outBody!)
    }

    /// Matches CPU `gadgetDecompose` via exact UInt32 divisions by powers of two.
    private static func gadgetDecomposeMetal(
        graph: MPSGraph,
        poly: MPSGraphTensor,
        baseLog: Int,
        levelCount: Int,
        degree: Int,
        batch: Int,
        name: String
    ) -> [MPSGraphTensor] {
        var remaining = poly
        var levels: [MPSGraphTensor] = []
        levels.reserveCapacity(levelCount)
        for level in 0..<levelCount {
            let shift = 32 - (level + 1) * baseLog
            let divisorVal: UInt32 = shift >= 0 ? (1 as UInt32) &<< UInt32(shift) : 1
            let divisor = constantPacked(
                graph: graph,
                values: [UInt32](repeating: divisorVal, count: degree),
                batch: batch,
                width: degree,
                name: "\(name)_div\(level)"
            )
            let digit = graph.division(remaining, divisor, name: "\(name)_dig\(level)")
            let contrib = graph.multiplication(digit, divisor, name: "\(name)_c\(level)")
            remaining = graph.subtraction(remaining, contrib, name: "\(name)_rem\(level)")
            levels.append(digit)
        }
        return levels
    }

    private static func constantPacked(
        graph: MPSGraph,
        values: [UInt32],
        batch: Int,
        width: Int,
        name: String
    ) -> MPSGraphTensor {
        precondition(values.count == width)
        var host: [UInt32] = []
        host.reserveCapacity(batch * width)
        for _ in 0..<batch {
            host.append(contentsOf: values)
        }
        let shape: [NSNumber] = [NSNumber(value: batch), NSNumber(value: width)]
        let data = host.withUnsafeBufferPointer { Data(buffer: $0) }
        return graph.constant(data, shape: shape, dataType: .uInt32)
    }

    private static func constantGLWE(
        graph: MPSGraph,
        ct: GLWECiphertext,
        batch: Int,
        name: String
    ) -> GLWETensors {
        let degree = ct.degree
        let mask = constantPacked(
            graph: graph,
            values: ct.mask[0],
            batch: batch,
            width: degree,
            name: "\(name)_m"
        )
        let body = constantPacked(
            graph: graph,
            values: ct.body,
            batch: batch,
            width: degree,
            name: "\(name)_b"
        )
        return GLWETensors(mask: mask, body: body)
    }

    private static func scaleGLWE(
        graph: MPSGraph,
        ct: GLWETensors,
        poly: MPSGraphTensor,
        degree: Int,
        batch: Int,
        name: String,
        bank: GraphConstBank
    ) -> GLWETensors {
        GLWETensors(
            mask: negacyclicPolyMul(
                graph: graph,
                a: ct.mask,
                b: poly,
                degree: degree,
                batch: batch,
                name: "\(name)_sm",
                bank: bank
            ),
            body: negacyclicPolyMul(
                graph: graph,
                a: ct.body,
                b: poly,
                degree: degree,
                batch: batch,
                name: "\(name)_sb",
                bank: bank
            )
        )
    }

    /// `a * b` in `Z/2^{32}Z[X]/(X^N+1)` via `Σ_j b_j · X^j a`.
    private static func negacyclicPolyMul(
        graph: MPSGraph,
        a: MPSGraphTensor,
        b: MPSGraphTensor,
        degree: Int,
        batch: Int,
        name: String,
        bank: GraphConstBank
    ) -> MPSGraphTensor {
        var acc: MPSGraphTensor?
        for j in 0..<degree {
            let bj = graph.sliceTensor(b, dimension: 1, start: j, length: 1, name: "\(name)_b\(j)")
            let bjBroadcast = graph.multiplication(bj, bank.ones, name: "\(name)_bj\(j)")
            let shifted = mulByXPower(
                graph: graph,
                poly: a,
                power: j,
                name: "\(name)_x\(j)",
                degree: degree,
                batch: batch,
                bank: bank
            )
            let term = graph.multiplication(shifted, bjBroadcast, name: "\(name)_t\(j)")
            if let existing = acc {
                acc = graph.addition(existing, term, name: "\(name)_acc\(j)")
            } else {
                acc = term
            }
        }
        return acc ?? bank.zeros
    }

    private static func mulByXPower(
        graph: MPSGraph,
        poly: MPSGraphTensor,
        power: Int,
        name: String,
        degree: Int,
        batch: Int,
        bank: GraphConstBank
    ) -> MPSGraphTensor {
        var p = power % (2 * degree)
        if p < 0 { p += 2 * degree }
        if p == 0 { return poly }
        if p >= degree {
            let rem = p - degree
            let reduced: MPSGraphTensor
            if rem == 0 {
                reduced = poly
            } else {
                reduced = mulByXPowerPositive(
                    graph: graph,
                    poly: poly,
                    power: rem,
                    name: "\(name)_red",
                    degree: degree,
                    bank: bank
                )
            }
            return graph.subtraction(bank.zeros, reduced, name: name)
        }
        return mulByXPowerPositive(
            graph: graph,
            poly: poly,
            power: p,
            name: name,
            degree: degree,
            bank: bank
        )
    }

    private static func mulByXPowerPositive(
        graph: MPSGraph,
        poly: MPSGraphTensor,
        power: Int,
        name: String,
        degree: Int,
        bank: GraphConstBank
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
            bank.scalarZero,
            name: "\(name)_zeroK"
        )
        let negRight = graph.subtraction(zeroK, right, name: "\(name)_neg")
        return graph.concatTensors([negRight, left], dimension: 1, name: name)
    }

    private static func runUnary(
        graph: MPSGraph,
        output: MPSGraphTensor,
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        elementCount: Int
    ) throws -> [UInt32] {
        let shape: [NSNumber] = [1, NSNumber(value: elementCount)]
        let buffer = device.makeBuffer(
            length: elementCount * MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        )!
        let results: [MPSGraphTensor: MPSGraphTensorData] = [
            output: MPSGraphTensorData(buffer, shape: shape, dataType: .uInt32)
        ]
        graph.run(
            with: commandQueue,
            feeds: [:],
            targetOperations: nil,
            resultsDictionary: results
        )
        let ptr = buffer.contents().bindMemory(to: UInt32.self, capacity: elementCount)
        return Array(UnsafeBufferPointer(start: ptr, count: elementCount))
    }
}
