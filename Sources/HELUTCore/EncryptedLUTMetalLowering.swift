import Foundation
import Metal
import MetalPerformanceShadersGraph

// MARK: - Encrypted LUT → Metal lowering (graduation step 10j)
//
// `LUTNode` with `.encryptedBlindRotate` lowers each `$lut` through
// `MetalGGSW.evaluateLUTBlindRotate` (fused at *N*≤64, tiled-kernel otherwise).

/// Metal + BK context required to lower an encrypted `LUTNode`.
package struct EncryptedLUTMetalContext: Sendable {
    package var bootKey: BootstrapKey
    package var scale: UInt32
    package var device: MTLDevice
    package var commandQueue: MTLCommandQueue

    package init(
        bootKey: BootstrapKey,
        scale: UInt32,
        device: MTLDevice,
        commandQueue: MTLCommandQueue
    ) {
        self.bootKey = bootKey
        self.scale = scale
        self.device = device
        self.commandQueue = commandQueue
    }

    package static func make(
        secret: TFHESecretKey,
        params: GGSWParams,
        publicRefreshCompatible: Bool,
        seed: UInt32,
        device: MTLDevice,
        commandQueue: MTLCommandQueue
    ) -> EncryptedLUTMetalContext {
        var rng = LCG32(state: seed == 0 ? 1 : seed)
        let key = bootstrapKey(
            secret: secret,
            params: params,
            rng: &rng,
            publicRefreshCompatible: publicRefreshCompatible,
            noise: .none
        )
        let scale = rotationScale(polynomialDegree: params.tfhe.polynomialDegree)
        return EncryptedLUTMetalContext(
            bootKey: key,
            scale: scale,
            device: device,
            commandQueue: commandQueue
        )
    }
}

extension LUTNode {
    /// Metal lowering for `.encryptedBlindRotate`: fused BR MPSGraph per LUT.
    package func evaluateEncrypted(
        inputs: [LWECiphertext],
        context: EncryptedLUTMetalContext
    ) throws -> LWECiphertext {
        precondition(
            backend == .encryptedBlindRotate,
            "evaluateEncrypted requires .encryptedBlindRotate backend"
        )
        precondition(truthTable.count == 1 << inputs.count)
        let n = context.bootKey.params.tfhe.polynomialDegree
        precondition(n >= truthTable.count)
        return try MetalGGSW.evaluateLUTBlindRotate(
            truthTable: truthTable,
            inputs: inputs,
            bootstrapKey: context.bootKey,
            scale: context.scale,
            device: context.device,
            commandQueue: context.commandQueue
        )
    }
}
