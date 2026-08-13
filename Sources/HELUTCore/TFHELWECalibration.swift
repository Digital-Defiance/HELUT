import Foundation

// MARK: - LWE hardness calibration table (step 10o)
//
// Explicit reference anchors (TFHE-style binary-secret LWE ballparks at q=2^{32})
// plus HELUT’s calibrated estimator output. Used to document / test that the
// linear model tracks published-order security levels — not a lattice-estimator
// substitute.

/// One row of the classical LWE hardness calibration table.
package struct TFHELWECalibrationRow: Sendable, Equatable {
    package var label: String
    package var dimension: Int
    package var sigma: Double
    /// Literature / TFHE-parameter note ballpark (classical bits).
    package var referenceBits: Double
    package var source: String

    package init(
        label: String,
        dimension: Int,
        sigma: Double,
        referenceBits: Double,
        source: String
    ) {
        self.label = label
        self.dimension = dimension
        self.sigma = sigma
        self.referenceBits = referenceBits
        self.source = source
    }

    package var lwe: TFHELWEParams {
        TFHELWEParams(dimension: dimension, sigma: sigma, binarySecret: true)
    }

    package var helutEstimateBits: Double {
        estimateClassicalCoreSVPBits(lwe: lwe)
    }

    package var errorBits: Double {
        helutEstimateBits - referenceBits
    }

    package var absErrorBits: Double {
        abs(errorBits)
    }
}

/// Built-in calibration anchors for HELUT’s classical bit estimator.
package enum TFHELWECalibration {
    /// Reference points used to tune / check `estimateClassicalCoreSVPBits`.
    package static let anchors: [TFHELWECalibrationRow] = [
        TFHELWECalibrationRow(
            label: "demo-N8",
            dimension: 8,
            sigma: Double(1 << 12),
            referenceBits: 4,
            source: "HELUT demo (not production)"
        ),
        TFHELWECalibrationRow(
            label: "weak-n256",
            dimension: 256,
            sigma: Double(1 << 17),
            referenceBits: 45,
            source: "TFHE-style ballpark (weak)"
        ),
        TFHELWECalibrationRow(
            label: "mid-n512",
            dimension: 512,
            sigma: Double(1 << 16),
            referenceBits: 95,
            source: "TFHE-style ballpark"
        ),
        TFHELWECalibrationRow(
            label: "classic-n630",
            dimension: 630,
            sigma: Double(1 << 15),
            referenceBits: 128,
            source: "≈ Chillotti boolean 128-bit regime"
        ),
        TFHELWECalibrationRow(
            label: "n768-s16",
            dimension: 768,
            sigma: Double(1 << 16),
            referenceBits: 140,
            source: "TFHE-style ballpark"
        ),
        TFHELWECalibrationRow(
            label: "prod-n1024-s16",
            dimension: 1024,
            sigma: Double(1 << 16),
            referenceBits: 170,
            source: "HELUT productionBoolean64"
        ),
        TFHELWECalibrationRow(
            label: "n1024-s17",
            dimension: 1024,
            sigma: Double(1 << 17),
            referenceBits: 155,
            source: "same n, noisier σ"
        ),
        TFHELWECalibrationRow(
            label: "n2048-s16",
            dimension: 2048,
            sigma: Double(1 << 16),
            referenceBits: 340,
            source: "extrapolated high-security"
        )
    ]

    /// Max |HELUT − reference| allowed across anchors (bits).
    package static let maxAbsErrorBits: Double = 12

    package static func table() -> [TFHELWECalibrationRow] { anchors }

    /// True when every anchor is within `maxAbsErrorBits` of the HELUT estimate.
    package static func isCalibrated(
        maxAbsError: Double = maxAbsErrorBits
    ) -> Bool {
        anchors.allSatisfy { $0.absErrorBits <= maxAbsError }
    }

    /// Markdown table for docs / logs.
    package static func markdownTable() -> String {
        var lines: [String] = [
            "| Label | n | σ | Ref bits | HELUT est | Δ | Source |",
            "|---|---:|---:|---:|---:|---:|---|"
        ]
        for row in anchors {
            let sigmaLog = Int(log2(row.sigma).rounded())
            lines.append(
                String(
                    format: "| %@ | %d | 2^%d | %.0f | %.1f | %+.1f | %@ |",
                    row.label,
                    row.dimension,
                    sigmaLog,
                    row.referenceBits,
                    row.helutEstimateBits,
                    row.errorBits,
                    row.source
                )
            )
        }
        return lines.joined(separator: "\n")
    }

    /// Compact rows for JSON / canvas embedding.
    package static func exportRows() -> [[String: String]] {
        anchors.map { row in
            [
                "label": row.label,
                "n": "\(row.dimension)",
                "sigma": "2^\(Int(log2(row.sigma).rounded()))",
                "referenceBits": String(format: "%.0f", row.referenceBits),
                "helutBits": String(format: "%.1f", row.helutEstimateBits),
                "deltaBits": String(format: "%+.1f", row.errorBits),
                "source": row.source,
                "meets128": row.helutEstimateBits >= 128 ? "yes" : "no"
            ]
        }
    }
}
