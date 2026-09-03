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
    package var inputPacking: LWEInputPackingMode
    package var device: MTLDevice
    package var commandQueue: MTLCommandQueue
    package var keySwitchKey: KeySwitchKey?

    package init(
        bootKey: BootstrapKey,
        scale: UInt32,
        inputPacking: LWEInputPackingMode = .rotationNative,
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        keySwitchKey: KeySwitchKey? = nil
    ) {
        self.bootKey = bootKey
        self.scale = scale
        self.inputPacking = inputPacking
        self.device = device
        self.commandQueue = commandQueue
        self.keySwitchKey = keySwitchKey
    }

    package static func make(
        secret: TFHESecretKey,
        params: GGSWParams,
        publicRefreshCompatible: Bool,
        seed: UInt32,
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        inputPacking: LWEInputPackingMode = .rotationNative
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
            inputPacking: inputPacking,
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
            inputPacking: context.inputPacking,
            device: context.device,
            commandQueue: context.commandQueue,
            keySwitchKey: context.keySwitchKey
        )
    }
}
