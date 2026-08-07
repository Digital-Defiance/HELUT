import Foundation

/// Half-open coordinate span used by transcript hypotheses.
package struct MuleinSpan: Codable, Hashable, Sendable {
    package let start: Int
    package let length: Int

    package init(start: Int, length: Int) {
        self.start = start
        self.length = length
    }

    package var end: Int { start + length }
    package var range: Range<Int> { start..<end }
}

/// One explicit claim about how the recorded transcript differs from the transmitted stream.
///
/// Geometry edits and value edits are deliberately separate. A symbol missing from the recording
/// changes every later rotor-step coordinate; a replacement changes one observed constraint but
/// does not consume or invent an Enigma step.
package enum MuleinTranscriptEdit: Codable, Hashable, Sendable {
    /// Symbols were transmitted, advanced the machine, but are absent from the recording.
    case missingFromRecording(transmitted: MuleinSpan, recordedBoundary: Int)
    /// Symbols appear in the recording but did not consume Enigma steps in this hypothesis.
    case extraInRecording(recorded: MuleinSpan, transmittedBoundary: Int)
    /// Replace one recorded ciphertext symbol without changing geometry.
    case replacement(recordedIndex: Int, observed: Int, hypothesized: Int)
    /// Reorder a recorded span. `permutation[destination]` names its source within the span.
    case transposition(recorded: MuleinSpan, permutation: [Int])

    fileprivate var canonicalDescription: String {
        switch self {
        case let .missingFromRecording(span, boundary):
            return "missing:T\(span.start)+\(span.length)@R\(boundary)"
        case let .extraInRecording(span, boundary):
            return "extra:R\(span.start)+\(span.length)@T\(boundary)"
        case let .replacement(index, observed, hypothesized):
            return "replace:R\(index):\(observed)>\(hypothesized)"
        case let .transposition(span, permutation):
            return "transpose:R\(span.start)+\(span.length):"
                + permutation.map(String.init).joined(separator: ",")
        }
    }
}

/// Stable source evidence from which bounded futures are compiled.
package struct MuleinFutureEvidence: Codable, Hashable, Sendable {
    package let targetID: String
    package let sourceID: String
    package let cribID: String
    package let crib: String
    package let transmittedOffset: Int
    package let ciphertext: [Int]

    package init(
        targetID: String,
        sourceID: String,
        cribID: String,
        crib: String,
        transmittedOffset: Int,
        ciphertext: [Int]
    ) {
        self.targetID = targetID
        self.sourceID = sourceID
        self.cribID = cribID
        self.crib = crib
        self.transmittedOffset = transmittedOffset
        self.ciphertext = ciphertext
    }
}

/// A bounded path requested from the Future Lattice.
package struct MuleinFutureHypothesis: Codable, Hashable, Sendable {
    package let label: String
    package let edits: [MuleinTranscriptEdit]

    package init(label: String, edits: [MuleinTranscriptEdit]) {
        self.label = label
        self.edits = edits
    }

    package static let exact = MuleinFutureHypothesis(label: "exact", edits: [])
}

/// Deterministic identity for one evidence path. This is a receipt key, not a security hash.
package struct MuleinHypothesisID: Codable, Hashable, Sendable, CustomStringConvertible {
    package let rawValue: String
    package var description: String { rawValue }
}

/// Stable identity of a crib constraint before it is packed into an execution menu.
package struct MuleinEdgeID: Codable, Hashable, Sendable {
    package let sourceID: String
    package let cribID: String
    package let cribIndex: Int
    package let transmittedStep: Int
    package let recordedIndex: Int?
}

/// One crib position with both coordinate systems and both observed/effective symbols retained.
/// A missing-recording position has no recorded index and is evidence, but not a board edge.
package struct MuleinFutureEdge: Codable, Hashable, Sendable {
    package let id: MuleinEdgeID
    package let plaintext: Int
    package let observedCiphertext: Int?
    package let effectiveCiphertext: Int?

    package var isBoardConstraint: Bool { effectiveCiphertext != nil }
}

/// Bidirectional geometry between transmitted rotor steps and recorded symbol positions.
package struct MuleinTranscriptGeometry: Codable, Hashable, Sendable {
    package let recordedIndexByTransmittedStep: [Int?]
    package let transmittedStepByRecordedIndex: [Int?]

    package var transmittedLength: Int { recordedIndexByTransmittedStep.count }
    package var recordedLength: Int { transmittedStepByRecordedIndex.count }
}

/// Auditable claim retained even when several hypotheses compile to identical board work.
package struct MuleinHypothesisReceipt: Codable, Hashable, Sendable {
    package let id: MuleinHypothesisID
    package let targetID: String
    package let sourceID: String
    package let cribID: String
    package let label: String
    package let edits: [MuleinTranscriptEdit]
}

/// Stable packed-work identity used only for execution deduplication.
package struct MuleinExecutionGeometryKey: Hashable, Sendable {
    package let steps: [Int]
    package let endpointA: [Int]
    package let endpointB: [Int]
}

/// One executable future plus every evidence path that compiled to the same board geometry.
package struct MuleinFuture: Sendable {
    package let receipts: [MuleinHypothesisReceipt]
    package let geometry: MuleinTranscriptGeometry
    package let edges: [MuleinFutureEdge]
    package let menu: BombeMenu
    package let executionKey: MuleinExecutionGeometryKey

    package var id: MuleinHypothesisID { receipts[0].id }
    package var boardEdges: [MuleinFutureEdge] { edges.filter(\.isBoardConstraint) }

    fileprivate func merging(_ receipt: MuleinHypothesisReceipt) -> MuleinFuture {
        guard !receipts.contains(where: { $0.id == receipt.id }) else { return self }
        return MuleinFuture(
            receipts: receipts + [receipt], geometry: geometry, edges: edges,
            menu: menu, executionKey: executionKey
        )
    }
}

/// Stable repair receipt emitted after host replay. Edge erasure never masquerades as geometry.
package struct MuleinBoardRepairReceipt: Codable, Hashable, Sendable {
    package let droppedEdgeIDs: [MuleinEdgeID]
    package let minimumDropCount: Int

    package init(droppedEdgeIDs: [MuleinEdgeID]) {
        self.droppedEdgeIDs = droppedEdgeIDs
        self.minimumDropCount = droppedEdgeIDs.count
    }

    package static let exact = MuleinBoardRepairReceipt(droppedEdgeIDs: [])
}

package struct MuleinRejectedFuture: Codable, Hashable, Sendable {
    package let hypothesis: MuleinFutureHypothesis
    package let reason: String
}

package enum MuleinFutureError: Error, Equatable, CustomStringConvertible {
    case invalidEvidence(String)
    case invalidEdit(String)
    case inconsistentGeometry(String)
    case illegalSelfEncipherment(cribIndex: Int, letter: Int)
    case tooFewEdges(actual: Int, minimum: Int)

    package var description: String {
        switch self {
        case let .invalidEvidence(message), let .invalidEdit(message),
             let .inconsistentGeometry(message):
            return message
        case let .illegalSelfEncipherment(index, letter):
            return "crib index \(index) self-enciphers as \(letter)"
        case let .tooFewEdges(actual, minimum):
            return "future has \(actual) usable edges; minimum is \(minimum)"
        }
    }
}

/// Compiles explicitly bounded transcript hypotheses and merges identical board executions while
/// retaining every hypothesis receipt. It is a finite front end, not an unbounded edit search.
package struct MuleinFutureLattice: Sendable {
    package let futures: [MuleinFuture]
    package let rejected: [MuleinRejectedFuture]

    package static func build(
        evidence: MuleinFutureEvidence,
        hypotheses: [MuleinFutureHypothesis],
        minimumEdges: Int = 1
    ) -> MuleinFutureLattice {
        var futures: [MuleinFuture] = []
        var indexByExecution: [MuleinExecutionGeometryKey: Int] = [:]
        var rejected: [MuleinRejectedFuture] = []

        for hypothesis in hypotheses {
            do {
                let future = try compile(
                    evidence: evidence, hypothesis: hypothesis, minimumEdges: minimumEdges
                )
                if let index = indexByExecution[future.executionKey] {
                    futures[index] = futures[index].merging(future.receipts[0])
                } else {
                    indexByExecution[future.executionKey] = futures.count
                    futures.append(future)
                }
            } catch let error as MuleinFutureError {
                rejected.append(MuleinRejectedFuture(hypothesis: hypothesis, reason: error.description))
            } catch {
                rejected.append(MuleinRejectedFuture(hypothesis: hypothesis, reason: String(describing: error)))
            }
        }

        futures.sort {
            ($0.menu.loops, $0.menu.edgeCount, $0.id.rawValue)
                > ($1.menu.loops, $1.menu.edgeCount, $1.id.rawValue)
        }
        return MuleinFutureLattice(futures: futures, rejected: rejected)
    }

    package static func compile(
        evidence: MuleinFutureEvidence,
        hypothesis: MuleinFutureHypothesis,
        minimumEdges: Int = 1
    ) throws -> MuleinFuture {
        guard !evidence.targetID.isEmpty, !evidence.sourceID.isEmpty,
              !evidence.cribID.isEmpty else {
            throw MuleinFutureError.invalidEvidence("target/source/crib IDs must be non-empty")
        }
        guard evidence.transmittedOffset >= 0 else {
            throw MuleinFutureError.invalidEvidence("transmitted offset must be non-negative")
        }
        guard !evidence.ciphertext.isEmpty,
              evidence.ciphertext.allSatisfy({ (0..<26).contains($0) }) else {
            throw MuleinFutureError.invalidEvidence("ciphertext must contain letters 0...25")
        }
        let crib = EnigmaAlphabet.normalize(evidence.crib)
        guard !crib.isEmpty else {
            throw MuleinFutureError.invalidEvidence("crib must contain alphabetic letters")
        }
        guard minimumEdges > 0 else {
            throw MuleinFutureError.invalidEvidence("minimum edge count must be positive")
        }

        let geometry = try buildGeometry(
            recordedLength: evidence.ciphertext.count, edits: hypothesis.edits
        )
        guard evidence.transmittedOffset + crib.count <= geometry.transmittedLength else {
            throw MuleinFutureError.invalidEvidence(
                "crib extends beyond the hypothesized transmitted timeline"
            )
        }
        let effectiveCiphertext = try applyValueEdits(
            evidence.ciphertext, edits: hypothesis.edits
        )

        var richEdges: [MuleinFutureEdge] = []
        var steps: [Int] = []
        var ends: [(Int, Int)] = []
        richEdges.reserveCapacity(crib.count)
        steps.reserveCapacity(crib.count)
        ends.reserveCapacity(crib.count)

        for cribIndex in crib.indices {
            let transmittedStep = evidence.transmittedOffset + cribIndex
            let recordedIndex = geometry.recordedIndexByTransmittedStep[transmittedStep]
            let observed = recordedIndex.map { evidence.ciphertext[$0] }
            let effective = recordedIndex.map { effectiveCiphertext[$0] }
            let plaintext = crib[cribIndex]
            let edgeID = MuleinEdgeID(
                sourceID: evidence.sourceID,
                cribID: evidence.cribID,
                cribIndex: cribIndex,
                transmittedStep: transmittedStep,
                recordedIndex: recordedIndex
            )
            richEdges.append(
                MuleinFutureEdge(
                    id: edgeID, plaintext: plaintext,
                    observedCiphertext: observed, effectiveCiphertext: effective
                )
            )

            guard let effective else { continue }
            guard plaintext != effective else {
                throw MuleinFutureError.illegalSelfEncipherment(
                    cribIndex: cribIndex, letter: plaintext
                )
            }
            steps.append(transmittedStep)
            ends.append((plaintext, effective))
        }

        guard ends.count >= minimumEdges else {
            throw MuleinFutureError.tooFewEdges(actual: ends.count, minimum: minimumEdges)
        }
        guard let menu = BombeMenuBuilder.assemble(
            crib: evidence.crib,
            offset: evidence.transmittedOffset,
            steps: steps,
            ends: ends
        ) else {
            throw MuleinFutureError.invalidEvidence("compiled future produced no legal menu")
        }

        let canonical = [
            evidence.targetID, evidence.sourceID, evidence.cribID,
            String(evidence.transmittedOffset), hypothesis.label,
            hypothesis.edits.map(\.canonicalDescription).joined(separator: ";")
        ].joined(separator: "|")
        let receipt = MuleinHypothesisReceipt(
            id: MuleinHypothesisID(rawValue: stableID(canonical)),
            targetID: evidence.targetID,
            sourceID: evidence.sourceID,
            cribID: evidence.cribID,
            label: hypothesis.label,
            edits: hypothesis.edits
        )
        let key = MuleinExecutionGeometryKey(
            steps: steps,
            endpointA: ends.map(\.0),
            endpointB: ends.map(\.1)
        )
        return MuleinFuture(
            receipts: [receipt], geometry: geometry, edges: richEdges,
            menu: menu, executionKey: key
        )
    }

    private static func buildGeometry(
        recordedLength: Int,
        edits: [MuleinTranscriptEdit]
    ) throws -> MuleinTranscriptGeometry {
        var missing: [(span: MuleinSpan, recordedBoundary: Int)] = []
        var extra: [(span: MuleinSpan, transmittedBoundary: Int)] = []
        for edit in edits {
            switch edit {
            case let .missingFromRecording(span, boundary):
                guard span.start >= 0, span.length > 0, boundary >= 0 else {
                    throw MuleinFutureError.invalidEdit("missing-recording span is invalid")
                }
                missing.append((span, boundary))
            case let .extraInRecording(span, boundary):
                guard span.start >= 0, span.length > 0, span.end <= recordedLength,
                      boundary >= 0 else {
                    throw MuleinFutureError.invalidEdit("extra-recording span is invalid")
                }
                extra.append((span, boundary))
            case .replacement, .transposition:
                break
            }
        }
        missing.sort { $0.span.start < $1.span.start }
        extra.sort { $0.transmittedBoundary < $1.transmittedBoundary }
        try requireDisjoint(missing.map(\.span), label: "missing-recording")
        try requireDisjoint(extra.map(\.span), label: "extra-recording")

        let transmittedLength = recordedLength
            + missing.reduce(0) { $0 + $1.span.length }
            - extra.reduce(0) { $0 + $1.span.length }
        guard transmittedLength >= 0 else {
            throw MuleinFutureError.inconsistentGeometry(
                "extra recorded symbols exceed the available timeline"
            )
        }
        guard missing.allSatisfy({ $0.span.end <= transmittedLength }),
              extra.allSatisfy({ $0.transmittedBoundary <= transmittedLength }) else {
            throw MuleinFutureError.inconsistentGeometry("geometry edit lies outside its timeline")
        }

        var recordedByTransmitted = [Int?](repeating: nil, count: transmittedLength)
        var transmittedByRecorded = [Int?](repeating: nil, count: recordedLength)
        var transmitted = 0
        var recorded = 0
        var missingIndex = 0
        var extraIndex = 0

        while transmitted <= transmittedLength {
            while extraIndex < extra.count
                && extra[extraIndex].transmittedBoundary == transmitted {
                let event = extra[extraIndex]
                guard event.span.start == recorded else {
                    throw MuleinFutureError.inconsistentGeometry(
                        "extra-recording boundary disagrees with the current coordinate map"
                    )
                }
                recorded = event.span.end
                extraIndex += 1
            }
            guard transmitted < transmittedLength else { break }

            if missingIndex < missing.count && missing[missingIndex].span.start == transmitted {
                let event = missing[missingIndex]
                guard event.recordedBoundary == recorded else {
                    throw MuleinFutureError.inconsistentGeometry(
                        "missing-recording boundary disagrees with the current coordinate map"
                    )
                }
                transmitted = event.span.end
                missingIndex += 1
                continue
            }

            guard recorded < recordedLength else {
                throw MuleinFutureError.inconsistentGeometry(
                    "transmitted timeline has no recorded symbol at step \(transmitted)"
                )
            }
            recordedByTransmitted[transmitted] = recorded
            transmittedByRecorded[recorded] = transmitted
            transmitted += 1
            recorded += 1
        }

        guard missingIndex == missing.count, extraIndex == extra.count,
              transmitted == transmittedLength, recorded == recordedLength else {
            throw MuleinFutureError.inconsistentGeometry(
                "geometry edits do not consume both timelines exactly"
            )
        }
        return MuleinTranscriptGeometry(
            recordedIndexByTransmittedStep: recordedByTransmitted,
            transmittedStepByRecordedIndex: transmittedByRecorded
        )
    }

    private static func applyValueEdits(
        _ ciphertext: [Int],
        edits: [MuleinTranscriptEdit]
    ) throws -> [Int] {
        var effective = ciphertext
        for edit in edits {
            switch edit {
            case let .replacement(index, observed, hypothesized):
                guard ciphertext.indices.contains(index),
                      (0..<26).contains(observed), (0..<26).contains(hypothesized),
                      ciphertext[index] == observed, observed != hypothesized else {
                    throw MuleinFutureError.invalidEdit(
                        "replacement does not match the recorded evidence"
                    )
                }
                effective[index] = hypothesized
            case let .transposition(span, permutation):
                guard span.start >= 0, span.length > 1, span.end <= ciphertext.count,
                      permutation.count == span.length,
                      Set(permutation) == Set(0..<span.length) else {
                    throw MuleinFutureError.invalidEdit("transposition permutation is invalid")
                }
                let source = Array(effective[span.range])
                for destination in 0..<span.length {
                    effective[span.start + destination] = source[permutation[destination]]
                }
            case .missingFromRecording, .extraInRecording:
                break
            }
        }
        return effective
    }

    private static func requireDisjoint(
        _ spans: [MuleinSpan],
        label: String
    ) throws {
        for (left, right) in zip(spans, spans.dropFirst()) where left.end > right.start {
            throw MuleinFutureError.invalidEdit("overlapping \(label) spans are ambiguous")
        }
    }

    /// Fixed FNV-1a receipt ID: deterministic across Swift hash seeds and process launches.
    private static func stableID(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "mulein-%016llx", hash)
    }
}
