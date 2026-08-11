import Foundation

/// Temporally unrolled TensorLUT target: `[step][batch][pin]` streams + DFF seed map.
package struct AdversarialStreamTarget: Sendable {
    package let inputWireIDs: [Int32]
    package let outputWireIDs: [Int32]
    /// `[step][batch][inputWireIDs.count]`
    package let inputSequence: [[[Float]]]
    /// `[step][batch][outputWireIDs.count]`
    package let expectedSequence: [[[Float]]]
    /// Q-wire seed values applied after wipe, before step 0 (Grundstellung / delay state).
    package let initialDFFStates: [Int32: Float]

    package init(
        inputWireIDs: [Int32],
        outputWireIDs: [Int32],
        inputSequence: [[[Float]]],
        expectedSequence: [[[Float]]],
        initialDFFStates: [Int32: Float] = [:]
    ) {
        precondition(!inputSequence.isEmpty, "empty stream")
        precondition(inputSequence.count == expectedSequence.count, "step count mismatch")
        let batchSize = inputSequence[0].count
        precondition(batchSize > 0, "empty batch")
        for (s, step) in inputSequence.enumerated() {
            precondition(step.count == batchSize, "batch size drift at input step \(s)")
            precondition(expectedSequence[s].count == batchSize, "batch size drift at expected step \(s)")
            for (b, row) in step.enumerated() {
                precondition(row.count == inputWireIDs.count, "input width mismatch step \(s) batch \(b)")
                precondition(
                    expectedSequence[s][b].count == outputWireIDs.count,
                    "expected width mismatch step \(s) batch \(b)"
                )
            }
        }
        self.inputWireIDs = inputWireIDs
        self.outputWireIDs = outputWireIDs
        self.inputSequence = inputSequence
        self.expectedSequence = expectedSequence
        self.initialDFFStates = initialDFFStates
    }

    package var stepCount: Int { inputSequence.count }
    package var batchSize: Int { inputSequence[0].count }
}
