import Foundation

/// Wire map + data batch for TensorLUT adversarial scoring.
package struct AdversarialTarget: Sendable {
    /// Primary input wire IDs (ciphertext bits, control pins, …).
    package let inputWireIDs: [Int32]
    /// Output wires sampled for soft MSE vs `expectedOutputs`.
    package let outputWireIDs: [Int32]
    /// `[batch][inputWireIDs.count]` primary activations.
    package let inputVectors: [[Float]]
    /// `[batch][outputWireIDs.count]` target bits in `[0, 1]`.
    package let expectedOutputs: [[Float]]
    /// Number of TensorLUT `evaluateTick` cycles before sampling (`0` ⇒ one combinational `evaluateForward`).
    package let clockTicks: Int

    package init(
        inputWireIDs: [Int32],
        outputWireIDs: [Int32],
        inputVectors: [[Float]],
        expectedOutputs: [[Float]],
        clockTicks: Int = 0
    ) {
        precondition(inputVectors.count == expectedOutputs.count, "batch size mismatch")
        precondition(!inputVectors.isEmpty, "empty batch")
        for (b, row) in inputVectors.enumerated() {
            precondition(row.count == inputWireIDs.count, "input row \(b) width mismatch")
            precondition(
                expectedOutputs[b].count == outputWireIDs.count,
                "expected row \(b) width mismatch"
            )
        }
        self.inputWireIDs = inputWireIDs
        self.outputWireIDs = outputWireIDs
        self.inputVectors = inputVectors
        self.expectedOutputs = expectedOutputs
        self.clockTicks = clockTicks
    }

    package var batchSize: Int { inputVectors.count }
}
