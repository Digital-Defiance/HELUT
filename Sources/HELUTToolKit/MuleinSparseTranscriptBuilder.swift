import Foundation
import HELUTCore

/// Structural failures while projecting real campaign state onto a physical Enigma timeline.
///
/// Every case is a refusal, not a degraded score. A transcript that cannot be built honestly is
/// never built at all, so `MuleinSparseReferenceEvaluator` can assume its input is a real
/// projection rather than a best effort.
enum MuleinSparseTranscriptBuildError: Error, Equatable {
    case recordedLengthMismatch(geometryRecordedLength: Int, ciphertextCount: Int)
    case recordedIndexOutOfBounds(transmittedStep: Int, recordedIndex: Int, recordedLength: Int)
    case invalidCiphertextSymbol(recordedIndex: Int, value: Int)
    case invalidPlaintextSymbol(transmittedStep: Int, value: Int)
    case holeWithoutDeclaredGapMember(transmittedStep: Int)
    case droppedEdgeNotOnBoard(edgeID: MuleinEdgeID)
    case droppedEdgeHasNoRecordedIndex(edgeID: MuleinEdgeID)
    case duplicateEdgeAtTransmittedStep(transmittedStep: Int)
    case steckerIsNotAnInvolution
}

/// Builds the one artifact the sparse evaluator has never had: a transcript from campaign state.
///
/// The sparse evaluator, the frozen n-gram adapters, and the receipt types all predate this file.
/// What was missing was a producer — `MuleinSparseTranscript` was constructed only inside tests,
/// so no campaign candidate could ever be scored with hole-aware semantics.
///
/// Two coordinate systems are load-bearing here and are deliberately never conflated:
///
/// * **transmitted step** — physical rotor time. The machine advances once per step whether or
///   not the recording preserved the symbol.
/// * **recorded index** — position in the ciphertext we actually possess.
///
/// Under a post-gap hypothesis these diverge, which is exactly why the dense
/// `PostBombeDiscriminator.decrypt` is wrong for such a candidate: it builds one key and walks a
/// single contiguous array, so every symbol after the gap is enciphered at a rotor position δ too
/// low. Here the walk is over transmitted steps, and at a physical hole the machine is stepped
/// with a filler symbol whose output is discarded — stepping is input-independent, so burning the
/// step is exact even though the lost symbol is unknown.
enum MuleinSparseTranscriptBuilder {
    /// Filler fed at a physical hole. Rotor stepping does not depend on the input, so this value
    /// cannot change any later position; the enciphered result is discarded unread.
    private static let holeFiller = 0

    /// Project one candidate onto its physical timeline.
    ///
    /// - Parameters:
    ///   - future: compiled geometry, edges, and receipts for this hypothesis.
    ///   - key: the full machine under test, including the completed plugboard.
    ///   - recordedCiphertext: the ciphertext we hold, in recorded coordinates.
    ///   - droppedEdgeIDs: edges the tolerant board deleted for this stop. Their plaintext is
    ///     emitted as an `.excludedEdge` barrier so no n-gram window may span the excision.
    static func build(
        future: MuleinFuture,
        key: EnigmaM4Key,
        recordedCiphertext: [Int],
        droppedEdgeIDs: [MuleinEdgeID] = []
    ) throws -> MuleinSparseTranscript {
        let geometry = future.geometry
        guard geometry.recordedLength == recordedCiphertext.count else {
            throw MuleinSparseTranscriptBuildError.recordedLengthMismatch(
                geometryRecordedLength: geometry.recordedLength,
                ciphertextCount: recordedCiphertext.count
            )
        }
        for x in 0..<26 where key.plugboard[key.plugboard[x]] != x {
            throw MuleinSparseTranscriptBuildError.steckerIsNotAnInvolution
        }

        let receipt = future.receipts[0]

        // A hole is only legal where the hypothesis actually claims one, and the claim must be
        // carried by *this* receipt — the evaluator rejects a member borrowed from a sibling
        // hypothesis that merely compiled to the same board work.
        var gapMembers: [MuleinGapMemberID] = []
        for edit in receipt.edits {
            guard case let .missingFromRecording(span, _) = edit else { continue }
            gapMembers.append(
                MuleinGapMemberID(receiptID: receipt.id, transmittedSpan: span)
            )
        }

        var edgeByStep: [Int: MuleinFutureEdge] = [:]
        for edge in future.edges {
            guard edgeByStep.updateValue(edge, forKey: edge.id.transmittedStep) == nil else {
                throw MuleinSparseTranscriptBuildError.duplicateEdgeAtTransmittedStep(
                    transmittedStep: edge.id.transmittedStep
                )
            }
        }

        // Validate the repair provenance against the board before it can silence a symbol.
        let boardEdgeIDs = Set(future.boardEdges.map(\.id))
        var dropped = Set<MuleinEdgeID>()
        for id in droppedEdgeIDs {
            guard boardEdgeIDs.contains(id) else {
                throw MuleinSparseTranscriptBuildError.droppedEdgeNotOnBoard(edgeID: id)
            }
            guard id.recordedIndex != nil else {
                throw MuleinSparseTranscriptBuildError.droppedEdgeHasNoRecordedIndex(edgeID: id)
            }
            dropped.insert(id)
        }

        var machine = EnigmaM4Machine(key: key)
        var cells: [MuleinSparseTranscriptCell] = []
        cells.reserveCapacity(geometry.transmittedLength)

        for step in 0..<geometry.transmittedLength {
            let edge = edgeByStep[step]

            guard let recordedIndex = geometry.recordedIndexByTransmittedStep[step] else {
                // The machine advanced but the recording kept nothing. Burn the step.
                guard let member = gapMembers.first(where: {
                    $0.transmittedSpan.range.contains(step)
                }) else {
                    throw MuleinSparseTranscriptBuildError.holeWithoutDeclaredGapMember(
                        transmittedStep: step
                    )
                }
                _ = machine.process(Self.holeFiller)
                cells.append(
                    MuleinSparseTranscriptCell(
                        transmittedStep: step,
                        edgeID: edge?.id,
                        ciphertext: .physicalHole(member: member),
                        plaintext: .barrier(reason: .physicalHole(member: member))
                    )
                )
                continue
            }

            guard recordedCiphertext.indices.contains(recordedIndex) else {
                throw MuleinSparseTranscriptBuildError.recordedIndexOutOfBounds(
                    transmittedStep: step,
                    recordedIndex: recordedIndex,
                    recordedLength: recordedCiphertext.count
                )
            }
            let observedValue = recordedCiphertext[recordedIndex]
            guard let observed = EnigmaLetter(rawValue: observedValue) else {
                throw MuleinSparseTranscriptBuildError.invalidCiphertextSymbol(
                    recordedIndex: recordedIndex, value: observedValue
                )
            }
            // `effective` is where an explicit correction would enter. For an exact hypothesis it
            // equals `observed`; a replacement edit is a value edit, never a geometry edit.
            let effectiveValue = edge?.effectiveCiphertext ?? observedValue
            guard let effective = EnigmaLetter(rawValue: effectiveValue) else {
                throw MuleinSparseTranscriptBuildError.invalidCiphertextSymbol(
                    recordedIndex: recordedIndex, value: effectiveValue
                )
            }

            let plainValue = machine.process(effective.rawValue)
            guard let plainSymbol = EnigmaLetter(rawValue: plainValue) else {
                throw MuleinSparseTranscriptBuildError.invalidPlaintextSymbol(
                    transmittedStep: step, value: plainValue
                )
            }

            let isDropped = edge.map { dropped.contains($0.id) } ?? false
            cells.append(
                MuleinSparseTranscriptCell(
                    transmittedStep: step,
                    edgeID: edge?.id,
                    ciphertext: .recorded(
                        observed: observed,
                        effective: effective,
                        recordedIndex: recordedIndex
                    ),
                    // A deleted edge carried no verified constraint, so its plaintext must not be
                    // scored and must not let a window bridge across it.
                    plaintext: isDropped
                        ? .barrier(reason: .excludedEdge)
                        : .eligible(symbol: plainSymbol)
                )
            )
        }

        return MuleinSparseTranscript(
            receipt: receipt,
            gapMembers: gapMembers,
            geometry: geometry,
            cells: cells
        )
    }

    /// Recovered plaintext in **recorded** coordinates, for human reading only.
    ///
    /// Holes contribute nothing (the symbol is genuinely unknown) and excluded edges are rendered
    /// as `.` so a reader can see where the board declined to constrain the text. This is a
    /// presentation helper: it is never the object that gets scored.
    static func recordedPlaintextRendering(
        _ transcript: MuleinSparseTranscript
    ) -> String {
        var rendered = [Character](
            repeating: "?", count: transcript.geometry.recordedLength
        )
        for cell in transcript.cells {
            guard case let .recorded(_, _, recordedIndex) = cell.ciphertext,
                  rendered.indices.contains(recordedIndex) else { continue }
            switch cell.plaintext {
            case let .eligible(symbol):
                rendered[recordedIndex] = Character(
                    UnicodeScalar(UInt8(65 + symbol.rawValue))
                )
            case .barrier:
                rendered[recordedIndex] = "."
            }
        }
        return String(rendered)
    }
}
