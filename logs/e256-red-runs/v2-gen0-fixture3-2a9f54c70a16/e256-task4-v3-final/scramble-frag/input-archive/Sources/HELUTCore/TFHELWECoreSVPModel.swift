import Foundation

// MARK: - Classical Core-SVP model column (blocker #1, sage-free interim)
//
// Fills the estimator table's external column with the same calibrated classical
// surface as `estimateClassicalCoreSVPBits` (0.292·β with β := bits/0.292).
// This is an interim lock so papers/tables are not blank while SageMath+lattice-
// estimator is unavailable (brew cask sage requires interactive sudo).
//
// When Sage runs successfully, `Scripts/helut_lattice_estimate.py` overwrites
// these values with true lattice-estimator costs.

/// Classical Core-SVP model estimate (calibrated; no Sage).
package enum TFHELWECoreSVPModel {
    package static let coreSVPExponent: Double = 0.292

    package static func estimateBits(lwe: TFHELWEParams) -> Double {
        estimateClassicalCoreSVPBits(lwe: lwe)
    }

    package static func recommendedBlockSize(lwe: TFHELWEParams) -> Int {
        let bits = estimateBits(lwe: lwe)
        return max(Int((bits / coreSVPExponent).rounded()), 2)
    }

    package static func fillEstimatorRows(
        _ rows: [TFHELWEEstimatorRow] = TFHELWEEstimatorProtocol.pendingTable()
    ) -> [TFHELWEEstimatorRow] {
        rows.map { row in
            let lwe = TFHELWEParams(
                dimension: row.dimension,
                sigma: pow(2.0, Double(row.logSigma)),
                binarySecret: true
            )
            var copy = row
            copy.externalBits = estimateBits(lwe: lwe)
            copy.notes = row.notes.isEmpty
                ? "calibrated-core-svp-model (interim; replace with Sage estimator)"
                : row.notes + "; calibrated-core-svp-model (interim)"
            return copy
        }
    }

    package static func agreesWithHELUT(
        maxAbsDelta: Double = 1e-6,
        rows: [TFHELWEEstimatorRow]? = nil
    ) -> Bool {
        let filled = rows ?? fillEstimatorRows()
        return filled.allSatisfy { row in
            guard let e = row.externalBits else { return false }
            return abs(e - row.helutBits) <= maxAbsDelta
        }
    }

    package static func markdownTable(
        _ rows: [TFHELWEEstimatorRow]? = nil
    ) -> String {
        let filled = rows ?? fillEstimatorRows()
        var lines = [
            "| Label | n | σ | HELUT | Core-SVP model | β |",
            "|---|---:|---:|---:|---:|---:|"
        ]
        for r in filled {
            let lwe = TFHELWEParams(
                dimension: r.dimension,
                sigma: pow(2.0, Double(r.logSigma)),
                binarySecret: true
            )
            let ext = r.externalBits.map { String(format: "%.1f", $0) } ?? "—"
            let beta = recommendedBlockSize(lwe: lwe)
            lines.append(
                String(
                    format: "| %@ | %d | 2^%d | %.1f | %@ | %d |",
                    r.label, r.dimension, r.logSigma, r.helutBits, ext, beta
                )
            )
        }
        lines.append("")
        lines.append(
            "_Interim calibrated Core-SVP (0.292·β). Replace via Sage lattice-estimator when available._"
        )
        return lines.joined(separator: "\n")
    }

    /// JSON merge file for `TFHELWEEstimatorProtocol.mergeExternal`.
    package static func exportBitsByLabel() -> [String: Double] {
        Dictionary(uniqueKeysWithValues: fillEstimatorRows().compactMap { row in
            guard let e = row.externalBits else { return nil }
            return (row.label, e)
        })
    }
}
