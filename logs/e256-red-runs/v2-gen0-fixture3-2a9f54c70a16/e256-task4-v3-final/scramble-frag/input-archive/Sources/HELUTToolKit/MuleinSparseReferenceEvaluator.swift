import HELUTCore

/// Structural failures that make a sparse transcript ineligible for any arithmetic.
enum MuleinSparseEvaluationError: Error, Equatable, Sendable {
    case cellCountMismatch(expected: Int, actual: Int)
    case unexpectedTransmittedStep(cellIndex: Int, expected: Int, actual: Int)

    case geometryRecordedIndexOutOfBounds(
        transmittedStep: Int,
        recordedIndex: Int,
        recordedLength: Int
    )
    case geometryTransmittedStepOutOfBounds(
        recordedIndex: Int,
        transmittedStep: Int,
        transmittedLength: Int
    )
    case geometryReverseMismatch(
        transmittedStep: Int,
        recordedIndex: Int,
        reverseStep: Int?
    )
    case geometryForwardMismatch(
        recordedIndex: Int,
        transmittedStep: Int,
        forwardIndex: Int?
    )

    case recordedCellAtPhysicalHole(transmittedStep: Int)
    case physicalHoleAtRecordedStep(transmittedStep: Int, recordedIndex: Int)
    case recordedIndexMismatch(transmittedStep: Int, expected: Int, actual: Int)

    case edgeStepMismatch(cellStep: Int, edgeStep: Int)
    case edgeRecordedIndexMismatch(
        transmittedStep: Int,
        expected: Int?,
        actual: Int?
    )
    case undeclaredGapMember(transmittedStep: Int)
    case gapMemberDoesNotContainStep(transmittedStep: Int)
    case gapMemberReceiptMismatch(
        transmittedStep: Int,
        expected: MuleinHypothesisID,
        actual: MuleinHypothesisID
    )

    case physicalHoleHasEligiblePlaintext(transmittedStep: Int)
    case physicalHoleMemberMismatch(transmittedStep: Int)
    case physicalHoleHasInvalidBarrier(transmittedStep: Int)
    case unresolvedCorrectionHasEligiblePlaintext(transmittedStep: Int)
    case unresolvedCorrectionHasInvalidBarrier(transmittedStep: Int)
    case excludedEdgeHasNoEdgeID(transmittedStep: Int)
    case recordedCellHasInvalidBarrier(transmittedStep: Int)
}

/// Proof token returned only after a complete topology validation pass.
struct ValidatedMuleinSparseTranscript: Sendable {
    fileprivate let transcript: MuleinSparseTranscript
}

/// Deliberately simple reference path for sparse transcript semantics.
///
/// Validation is kept separate from all IC or language arithmetic. A malformed evidence object
/// throws a typed error and can never be converted into a low score or an empty histogram.
enum MuleinSparseReferenceEvaluator {
    static func validate(
        _ transcript: MuleinSparseTranscript
    ) throws -> ValidatedMuleinSparseTranscript {
        let geometry = transcript.geometry
        let cells = transcript.cells

        guard cells.count == geometry.transmittedLength else {
            throw MuleinSparseEvaluationError.cellCountMismatch(
                expected: geometry.transmittedLength,
                actual: cells.count
            )
        }

        for (cellIndex, cell) in cells.enumerated() {
            guard cell.transmittedStep == cellIndex else {
                throw MuleinSparseEvaluationError.unexpectedTransmittedStep(
                    cellIndex: cellIndex,
                    expected: cellIndex,
                    actual: cell.transmittedStep
                )
            }
        }

        try validateGeometry(geometry)

        for cell in cells {
            try validateCellGeometry(cell, geometry: geometry)
            try validateProvenance(cell, transcript: transcript)
            try validateStatePairing(cell)
        }

        return ValidatedMuleinSparseTranscript(transcript: transcript)
    }

    private static func validateGeometry(
        _ geometry: MuleinTranscriptGeometry
    ) throws {
        let recordedByTransmitted = geometry.recordedIndexByTransmittedStep
        let transmittedByRecorded = geometry.transmittedStepByRecordedIndex

        for (transmittedStep, recordedIndex) in recordedByTransmitted.enumerated() {
            guard let recordedIndex else { continue }
            guard transmittedByRecorded.indices.contains(recordedIndex) else {
                throw MuleinSparseEvaluationError.geometryRecordedIndexOutOfBounds(
                    transmittedStep: transmittedStep,
                    recordedIndex: recordedIndex,
                    recordedLength: transmittedByRecorded.count
                )
            }
            let reverseStep = transmittedByRecorded[recordedIndex]
            guard reverseStep == transmittedStep else {
                throw MuleinSparseEvaluationError.geometryReverseMismatch(
                    transmittedStep: transmittedStep,
                    recordedIndex: recordedIndex,
                    reverseStep: reverseStep
                )
            }
        }

        for (recordedIndex, transmittedStep) in transmittedByRecorded.enumerated() {
            guard let transmittedStep else { continue }
            guard recordedByTransmitted.indices.contains(transmittedStep) else {
                throw MuleinSparseEvaluationError.geometryTransmittedStepOutOfBounds(
                    recordedIndex: recordedIndex,
                    transmittedStep: transmittedStep,
                    transmittedLength: recordedByTransmitted.count
                )
            }
            let forwardIndex = recordedByTransmitted[transmittedStep]
            guard forwardIndex == recordedIndex else {
                throw MuleinSparseEvaluationError.geometryForwardMismatch(
                    recordedIndex: recordedIndex,
                    transmittedStep: transmittedStep,
                    forwardIndex: forwardIndex
                )
            }
        }
    }

    private static func validateCellGeometry(
        _ cell: MuleinSparseTranscriptCell,
        geometry: MuleinTranscriptGeometry
    ) throws {
        let transmittedStep = cell.transmittedStep
        let expectedRecordedIndex = geometry.recordedIndexByTransmittedStep[transmittedStep]

        switch cell.ciphertext {
        case let .recorded(_, _, actualRecordedIndex),
             let .unresolvedCorrection(_, actualRecordedIndex):
            guard let expectedRecordedIndex else {
                throw MuleinSparseEvaluationError.recordedCellAtPhysicalHole(
                    transmittedStep: transmittedStep
                )
            }
            guard actualRecordedIndex == expectedRecordedIndex else {
                throw MuleinSparseEvaluationError.recordedIndexMismatch(
                    transmittedStep: transmittedStep,
                    expected: expectedRecordedIndex,
                    actual: actualRecordedIndex
                )
            }

        case .physicalHole:
            if let expectedRecordedIndex {
                throw MuleinSparseEvaluationError.physicalHoleAtRecordedStep(
                    transmittedStep: transmittedStep,
                    recordedIndex: expectedRecordedIndex
                )
            }
        }
    }

    private static func validateProvenance(
        _ cell: MuleinSparseTranscriptCell,
        transcript: MuleinSparseTranscript
    ) throws {
        let transmittedStep = cell.transmittedStep
        let expectedRecordedIndex = transcript.geometry
            .recordedIndexByTransmittedStep[transmittedStep]

        if let edgeID = cell.edgeID {
            guard edgeID.transmittedStep == transmittedStep else {
                throw MuleinSparseEvaluationError.edgeStepMismatch(
                    cellStep: transmittedStep,
                    edgeStep: edgeID.transmittedStep
                )
            }
            guard edgeID.recordedIndex == expectedRecordedIndex else {
                throw MuleinSparseEvaluationError.edgeRecordedIndexMismatch(
                    transmittedStep: transmittedStep,
                    expected: expectedRecordedIndex,
                    actual: edgeID.recordedIndex
                )
            }
        }

        guard case let .physicalHole(member) = cell.ciphertext else { return }
        guard transcript.gapMembers.contains(member) else {
            throw MuleinSparseEvaluationError.undeclaredGapMember(
                transmittedStep: transmittedStep
            )
        }
        guard member.receiptID == transcript.receipt.id else {
            throw MuleinSparseEvaluationError.gapMemberReceiptMismatch(
                transmittedStep: transmittedStep,
                expected: transcript.receipt.id,
                actual: member.receiptID
            )
        }
        guard member.transmittedSpan.range.contains(transmittedStep) else {
            throw MuleinSparseEvaluationError.gapMemberDoesNotContainStep(
                transmittedStep: transmittedStep
            )
        }
    }

    private static func validateStatePairing(
        _ cell: MuleinSparseTranscriptCell
    ) throws {
        let transmittedStep = cell.transmittedStep

        switch cell.ciphertext {
        case let .physicalHole(member):
            switch cell.plaintext {
            case .eligible:
                throw MuleinSparseEvaluationError.physicalHoleHasEligiblePlaintext(
                    transmittedStep: transmittedStep
                )
            case let .barrier(.physicalHole(barrierMember)):
                guard barrierMember == member else {
                    throw MuleinSparseEvaluationError.physicalHoleMemberMismatch(
                        transmittedStep: transmittedStep
                    )
                }
            case .barrier:
                throw MuleinSparseEvaluationError.physicalHoleHasInvalidBarrier(
                    transmittedStep: transmittedStep
                )
            }

        case .unresolvedCorrection:
            switch cell.plaintext {
            case .eligible:
                throw MuleinSparseEvaluationError.unresolvedCorrectionHasEligiblePlaintext(
                    transmittedStep: transmittedStep
                )
            case .barrier(.unresolvedCorrection):
                break
            case .barrier:
                throw MuleinSparseEvaluationError.unresolvedCorrectionHasInvalidBarrier(
                    transmittedStep: transmittedStep
                )
            }

        case .recorded:
            switch cell.plaintext {
            case .eligible:
                break
            case .barrier(.excludedEdge):
                guard cell.edgeID != nil else {
                    throw MuleinSparseEvaluationError.excludedEdgeHasNoEdgeID(
                        transmittedStep: transmittedStep
                    )
                }
            case .barrier:
                throw MuleinSparseEvaluationError.recordedCellHasInvalidBarrier(
                    transmittedStep: transmittedStep
                )
            }
        }
    }

    /// Exact IC counts over every eligible plaintext symbol in physical step order.
    ///
    /// No floating-point ratio is formed here. A zero denominator explicitly represents fewer
    /// than two eligible symbols and cannot become NaN or infinity inside the reference path.
    static func accumulateIC(
        _ validated: ValidatedMuleinSparseTranscript
    ) -> MuleinICTrace {
        let cells = validated.transcript.cells
        var frequencies = [Int](repeating: 0, count: EnigmaAlphabet.size)
        var transmittedSteps: [Int] = []
        transmittedSteps.reserveCapacity(cells.count)

        for cell in cells {
            guard case let .eligible(symbol) = cell.plaintext else { continue }
            frequencies[symbol.rawValue] += 1
            transmittedSteps.append(cell.transmittedStep)
        }

        let sampleCount = transmittedSteps.count
        let coincidencePairCount = frequencies.reduce(0) { total, frequency in
            total + frequency * (frequency - 1)
        }
        let possiblePairCount = sampleCount * max(0, sampleCount - 1)

        assert(frequencies.reduce(0, +) == sampleCount)

        return MuleinICTrace(
            transmittedSteps: transmittedSteps,
            frequencies: frequencies,
            sampleCount: sampleCount,
            coincidencePairCount: coincidencePairCount,
            possiblePairCount: possiblePairCount
        )
    }

    /// Enumerates physically contiguous windows without consulting a language model.
    ///
    /// Requested orders are trusted program configuration and must be unique, ascending, and at
    /// least two. Every plaintext barrier closes the current run and destroys rolling prefix state.
    static func traceAdjacency(
        _ validated: ValidatedMuleinSparseTranscript,
        orders: [Int]
    ) -> MuleinAdjacencyTrace {
        precondition(!orders.isEmpty, "at least one adjacency order is required")
        precondition(orders == orders.sorted(), "adjacency orders must be ascending")
        precondition(Set(orders).count == orders.count, "adjacency orders must be unique")
        precondition(orders.allSatisfy { $0 >= 2 }, "adjacency orders must be at least two")

        let maximumOrder = orders[orders.count - 1]
        var eligiblePlaintext: [MuleinEligiblePlaintextTrace] = []
        var runs: [MuleinKnownRunTrace] = []
        var barriers: [MuleinScoreBarrierTrace] = []
        var windowsByOrder = orders.map { _ in [MuleinAdjacencyWindowTrace]() }
        var rolling: [(transmittedStep: Int, symbol: EnigmaLetter)] = []
        rolling.reserveCapacity(maximumOrder)

        var runStartEligibleIndex: Int?
        var runStartTransmittedStep: Int?

        func closeRun() {
            guard let eligibleStart = runStartEligibleIndex,
                  let transmittedStart = runStartTransmittedStep else { return }
            let length = eligiblePlaintext.count - eligibleStart
            assert(length > 0)
            runs.append(
                MuleinKnownRunTrace(
                    eligibleRange: eligibleStart..<eligiblePlaintext.count,
                    transmittedSpan: MuleinSpan(start: transmittedStart, length: length)
                )
            )
            runStartEligibleIndex = nil
            runStartTransmittedStep = nil
        }

        for cell in validated.transcript.cells {
            switch cell.plaintext {
            case let .eligible(symbol):
                if runStartEligibleIndex == nil {
                    runStartEligibleIndex = eligiblePlaintext.count
                    runStartTransmittedStep = cell.transmittedStep
                }
                if let previous = rolling.last {
                    assert(cell.transmittedStep == previous.transmittedStep + 1)
                }

                eligiblePlaintext.append(
                    MuleinEligiblePlaintextTrace(
                        transmittedStep: cell.transmittedStep,
                        edgeID: cell.edgeID,
                        symbol: symbol
                    )
                )
                rolling.append((cell.transmittedStep, symbol))
                if rolling.count > maximumOrder {
                    rolling.removeFirst()
                }

                for (orderIndex, order) in orders.enumerated() where rolling.count >= order {
                    let window = rolling.suffix(order)
                    windowsByOrder[orderIndex].append(
                        MuleinAdjacencyWindowTrace(
                            transmittedSteps: window.map(\.transmittedStep),
                            symbols: window.map(\.symbol)
                        )
                    )
                }

            case let .barrier(reason):
                closeRun()
                barriers.append(
                    MuleinScoreBarrierTrace(
                        transmittedStep: cell.transmittedStep,
                        edgeID: cell.edgeID,
                        reason: reason
                    )
                )
                rolling.removeAll(keepingCapacity: true)
            }
        }

        closeRun()
        return MuleinAdjacencyTrace(
            eligiblePlaintext: eligiblePlaintext,
            runs: runs,
            barriers: barriers,
            orderTraces: zip(orders, windowsByOrder).map { order, windows in
                MuleinAdjacencyOrderTrace(order: order, windows: windows)
            }
        )
    }

    /// Converts proven adjacency windows into fixed-order statistical receipts.
    ///
    /// All identities, order matching, table capacities, cardinalities, window shapes, and table
    /// indices are validated before the first model lookup. Models therefore receive only an
    /// in-bounds index and cannot observe a partially validated batch.
    static func evaluateNGrams(
        _ adjacency: MuleinAdjacencyTrace,
        using models: [any MuleinNGramModel]
    ) throws -> [MuleinNGramTrace] {
        var modelIDs = Set<String>()
        var modelOrders = Set<Int>()
        for (modelIndex, model) in models.enumerated() {
            guard !model.modelID.isEmpty else {
                throw MuleinNGramEvaluationError.emptyModelID(modelIndex: modelIndex)
            }
            guard modelIDs.insert(model.modelID).inserted else {
                throw MuleinNGramEvaluationError.duplicateModelID(modelID: model.modelID)
            }
            guard model.order >= 2 else {
                throw MuleinNGramEvaluationError.invalidModelOrder(
                    modelID: model.modelID,
                    order: model.order
                )
            }
            modelOrders.insert(model.order)
        }

        var orderTraceByOrder: [Int: MuleinAdjacencyOrderTrace] = [:]
        for (orderTraceIndex, orderTrace) in adjacency.orderTraces.enumerated() {
            guard orderTrace.order >= 2 else {
                throw MuleinNGramEvaluationError.invalidAdjacencyOrder(
                    orderTraceIndex: orderTraceIndex,
                    order: orderTrace.order
                )
            }
            guard orderTraceByOrder[orderTrace.order] == nil else {
                throw MuleinNGramEvaluationError.duplicateAdjacencyOrder(
                    order: orderTrace.order
                )
            }
            orderTraceByOrder[orderTrace.order] = orderTrace
        }

        for model in models where orderTraceByOrder[model.order] == nil {
            throw MuleinNGramEvaluationError.missingAdjacencyOrder(
                modelID: model.modelID,
                order: model.order
            )
        }
        for orderTrace in adjacency.orderTraces where !modelOrders.contains(orderTrace.order) {
            throw MuleinNGramEvaluationError.missingModelForAdjacencyOrder(
                order: orderTrace.order
            )
        }

        var expectedEntryCountByOrder: [Int: Int] = [:]
        for model in models {
            let expectedEntryCount: Int
            if let cached = expectedEntryCountByOrder[model.order] {
                expectedEntryCount = cached
            } else {
                expectedEntryCount = try nGramEntryCount(order: model.order)
                expectedEntryCountByOrder[model.order] = expectedEntryCount
            }
            guard model.entryCount == expectedEntryCount else {
                throw MuleinNGramEvaluationError.entryCountMismatch(
                    modelID: model.modelID,
                    order: model.order,
                    expected: expectedEntryCount,
                    actual: model.entryCount
                )
            }
        }

        var indexedWindowsByOrder:
            [Int: [(window: MuleinAdjacencyWindowTrace, tableIndex: Int)]] = [:]
        for orderTrace in adjacency.orderTraces {
            var indexedWindows: [(window: MuleinAdjacencyWindowTrace, tableIndex: Int)] = []
            indexedWindows.reserveCapacity(orderTrace.windows.count)
            for (windowIndex, window) in orderTrace.windows.enumerated() {
                let tableIndex = try nGramTableIndex(
                    window,
                    order: orderTrace.order,
                    windowIndex: windowIndex
                )
                indexedWindows.append((window, tableIndex))
            }
            indexedWindowsByOrder[orderTrace.order] = indexedWindows
        }

        return try models.map { model in
            guard let indexedWindows = indexedWindowsByOrder[model.order] else {
                throw MuleinNGramEvaluationError.missingAdjacencyOrder(
                    modelID: model.modelID,
                    order: model.order
                )
            }

            var windows: [MuleinNGramWindowTrace] = []
            windows.reserveCapacity(indexedWindows.count)
            var totalLogProbability = 0.0

            for (windowIndex, indexedWindow) in indexedWindows.enumerated() {
                guard indexedWindow.tableIndex < model.entryCount else {
                    throw MuleinNGramEvaluationError.tableIndexOutOfBounds(
                        modelID: model.modelID,
                        order: model.order,
                        tableIndex: indexedWindow.tableIndex,
                        entryCount: model.entryCount
                    )
                }

                let lookup = model.lookup(tableIndex: indexedWindow.tableIndex)
                let logProbability: Double
                let usedFloor: Bool
                switch lookup {
                case let .entry(value):
                    logProbability = value
                    usedFloor = false
                case let .floor(value):
                    logProbability = value
                    usedFloor = true
                }

                guard logProbability.isFinite else {
                    throw MuleinNGramEvaluationError.nonFiniteLogProbability(
                        modelID: model.modelID,
                        order: model.order,
                        tableIndex: indexedWindow.tableIndex
                    )
                }
                let nextTotal = totalLogProbability + logProbability
                guard nextTotal.isFinite else {
                    throw MuleinNGramEvaluationError.nonFiniteTotal(
                        modelID: model.modelID,
                        order: model.order,
                        windowIndex: windowIndex
                    )
                }
                totalLogProbability = nextTotal

                windows.append(
                    MuleinNGramWindowTrace(
                        transmittedSteps: indexedWindow.window.transmittedSteps,
                        symbols: indexedWindow.window.symbols,
                        tableIndex: indexedWindow.tableIndex,
                        logProbability: logProbability,
                        usedFloor: usedFloor
                    )
                )
            }

            let normalizationCount = windows.count
            let meanLogProbability = normalizationCount == 0
                ? nil
                : totalLogProbability / Double(normalizationCount)
            return MuleinNGramTrace(
                modelID: model.modelID,
                order: model.order,
                windows: windows,
                totalLogProbability: totalLogProbability,
                normalizationCount: normalizationCount,
                meanLogProbability: meanLogProbability
            )
        }
    }

    /// Returns 26^order only after proving that every base-26 index for that order fits in Int.
    private static func nGramEntryCount(order: Int) throws -> Int {
        var maximumIndex = 0
        let maximumDigit = EnigmaAlphabet.size - 1
        for symbolOffset in 0..<order {
            let (scaled, multiplyOverflow) = maximumIndex.multipliedReportingOverflow(
                by: EnigmaAlphabet.size
            )
            let (next, addOverflow) = scaled.addingReportingOverflow(maximumDigit)
            guard !multiplyOverflow, !addOverflow else {
                throw MuleinNGramEvaluationError.tableIndexSpaceOverflow(
                    order: order,
                    symbolOffset: symbolOffset
                )
            }
            maximumIndex = next
        }

        let (entryCount, countOverflow) = maximumIndex.addingReportingOverflow(1)
        guard !countOverflow else {
            throw MuleinNGramEvaluationError.tableIndexSpaceOverflow(
                order: order,
                symbolOffset: order
            )
        }
        return entryCount
    }

    /// Big-endian Horner reduction over one already-proven physical window.
    private static func nGramTableIndex(
        _ window: MuleinAdjacencyWindowTrace,
        order: Int,
        windowIndex: Int
    ) throws -> Int {
        guard window.transmittedSteps.count == order, window.symbols.count == order else {
            throw MuleinNGramEvaluationError.windowOrderMismatch(
                order: order,
                windowIndex: windowIndex,
                transmittedStepCount: window.transmittedSteps.count,
                symbolCount: window.symbols.count
            )
        }

        var tableIndex = 0
        for (symbolOffset, symbol) in window.symbols.enumerated() {
            let (scaled, multiplyOverflow) = tableIndex.multipliedReportingOverflow(
                by: EnigmaAlphabet.size
            )
            let (next, addOverflow) = scaled.addingReportingOverflow(symbol.rawValue)
            guard !multiplyOverflow, !addOverflow else {
                throw MuleinNGramEvaluationError.tableIndexOverflow(
                    order: order,
                    windowIndex: windowIndex,
                    symbolOffset: symbolOffset
                )
            }
            tableIndex = next
        }
        return tableIndex
    }
}
