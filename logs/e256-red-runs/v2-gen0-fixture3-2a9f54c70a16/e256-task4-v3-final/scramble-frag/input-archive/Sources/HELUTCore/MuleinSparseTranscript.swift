import Foundation

/// A validated Enigma alphabet symbol used at sparse transcript boundaries.
///
/// Existing machine implementations continue to use `Int` internally. This wrapper prevents an
/// absent or invalid value from entering the sparse transcript as an apparent letter.
package struct EnigmaLetter: RawRepresentable, Codable, Hashable, Sendable {
    package let rawValue: Int

    package init?(rawValue: Int) {
        guard (0..<EnigmaAlphabet.size).contains(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(Int.self)
        guard let letter = EnigmaLetter(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Enigma letter must be in 0..<\(EnigmaAlphabet.size)"
            )
        }
        self = letter
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Identity of one concrete physical missing span represented by a Future receipt.
///
/// Execution-equivalent Futures may share board work while retaining distinct receipts. Pairing
/// the receipt with its transmitted span restores the physical placement needed by the host.
package struct MuleinGapMemberID: Codable, Hashable, Sendable {
    package let receiptID: MuleinHypothesisID
    package let transmittedSpan: MuleinSpan

    package init(receiptID: MuleinHypothesisID, transmittedSpan: MuleinSpan) {
        self.receiptID = receiptID
        self.transmittedSpan = transmittedSpan
    }
}

/// Ciphertext evidence at one physical transmitted step.
package enum MuleinCiphertextCell: Codable, Hashable, Sendable {
    /// A recorded symbol. `effective` differs from `observed` only for an explicit correction.
    case recorded(
        observed: EnigmaLetter,
        effective: EnigmaLetter,
        recordedIndex: Int
    )
    /// The machine stepped, but the recording contains no symbol for this transmitted position.
    case physicalHole(member: MuleinGapMemberID)
    /// A recorded symbol whose replacement has not yet been selected.
    case unresolvedCorrection(observed: EnigmaLetter, recordedIndex: Int)
}

/// Why no plaintext symbol is eligible for scoring at a physical transmitted step.
package enum MuleinPlaintextBarrier: Codable, Hashable, Sendable {
    case physicalHole(member: MuleinGapMemberID)
    case unresolvedCorrection
    case excludedEdge
}

/// Plaintext availability at one physical transmitted step.
package enum MuleinPlaintextCell: Codable, Hashable, Sendable {
    case eligible(symbol: EnigmaLetter)
    case barrier(reason: MuleinPlaintextBarrier)
}

/// One element of a sparse transcript, keyed by physical transmitted time.
package struct MuleinSparseTranscriptCell: Codable, Hashable, Sendable {
    package let transmittedStep: Int
    /// Present when this physical step is also a compiled crib constraint.
    package let edgeID: MuleinEdgeID?
    package let ciphertext: MuleinCiphertextCell
    package let plaintext: MuleinPlaintextCell

    package init(
        transmittedStep: Int,
        edgeID: MuleinEdgeID?,
        ciphertext: MuleinCiphertextCell,
        plaintext: MuleinPlaintextCell
    ) {
        self.transmittedStep = transmittedStep
        self.edgeID = edgeID
        self.ciphertext = ciphertext
        self.plaintext = plaintext
    }
}

/// One concrete, auditable projection of recorded evidence onto a physical Enigma timeline.
///
/// Producers must emit exactly one cell per transmitted step in ascending order. Geometry remains
/// authoritative for recorded/transmitted coordinate conversion; no missing symbol is synthesized.
package struct MuleinSparseTranscript: Codable, Hashable, Sendable {
    package let receipt: MuleinHypothesisReceipt
    package let gapMembers: [MuleinGapMemberID]
    package let geometry: MuleinTranscriptGeometry
    package let cells: [MuleinSparseTranscriptCell]

    package init(
        receipt: MuleinHypothesisReceipt,
        gapMembers: [MuleinGapMemberID],
        geometry: MuleinTranscriptGeometry,
        cells: [MuleinSparseTranscriptCell]
    ) {
        self.receipt = receipt
        self.gapMembers = gapMembers
        self.geometry = geometry
        self.cells = cells
    }
}
