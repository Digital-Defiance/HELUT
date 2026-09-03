import Foundation

// MARK: - Lattice-estimator verification protocol (step 10q)
//
// HELUT ships a calibrated classical estimate (`estimateClassicalCoreSVPBits`).
// Production / paper claims require an external lattice-estimator run. This
// module freezes the *protocol* and a reproducible JSON artifact shape so CI /
// Scripts/helut_lattice_estimate.py can fill `externalBits`.

/// One verified (or pending) hardness row.
package struct TFHELWEEstimatorRow: Sendable, Equatable {
    package var label: String
    package var dimension: Int
    package var logSigma: Int
    package var helutBits: Double
    /// Bits from lattice-estimator (or compatible). `nil` = not yet run.
    package var externalBits: Double?
    package var notes: String

    package var verified: Bool { externalBits != nil }

    package var absDeltaVsExternal: Double? {
        guard let e = externalBits else { return nil }
        return abs(helutBits - e)
    }

    package var meets128: Bool { helutBits >= 128 }

    package init(
        label: String,
        dimension: Int,
        logSigma: Int,
        helutBits: Double,
        externalBits: Double? = nil,
        notes: String = ""
    ) {
        self.label = label
        self.dimension = dimension
        self.logSigma = logSigma
        self.helutBits = helutBits
        self.externalBits = externalBits
        self.notes = notes
    }
}

/// Protocol + built-in pending verification table.
package enum TFHELWEEstimatorProtocol {
    /// Max |HELUT − estimator| we accept once external fills in.
    package static let maxAbsDeltaBits: Double = 16

    /// Parameter export for Albrecht lattice-estimator style LWE.
    /// q = 2^32, binary secret, Xe = DiscreteGaussian(σ).
    package static func sageSnippet(dimension n: Int, sigma: Double) -> String {
        """
        # HELUT LWE instance — feed to lattice-estimator / estimator.LWE
        # from estimator import *
        n, q, sigma = \(n), 2**32, \(sigma)
        # LWE.estimate(LWE.Parameters(n=n, q=q, Xs=ND.UniformMod(2), Xe=ND.DiscreteGaussian(sigma)))
        """
    }

    /// Pending verification rows derived from `TFHELWECalibration` anchors.
    package static func pendingTable() -> [TFHELWEEstimatorRow] {
        TFHELWECalibration.anchors.map { row in
            let logS = Int(log2(row.sigma).rounded())
            return TFHELWEEstimatorRow(
                label: row.label,
                dimension: row.dimension,
                logSigma: logS,
                helutBits: row.helutEstimateBits,
                externalBits: nil,
                notes: row.source
            )
        }
    }

    /// Merge external JSON results `{ "label": bits, ... }` into pending rows.
    package static func mergeExternal(
        _ bitsByLabel: [String: Double],
        into rows: [TFHELWEEstimatorRow] = pendingTable()
    ) -> [TFHELWEEstimatorRow] {
        rows.map { row in
            var copy = row
            if let e = bitsByLabel[row.label] {
                copy.externalBits = e
            }
            return copy
        }
    }

    package static func allVerifiedWithinTolerance(
        _ rows: [TFHELWEEstimatorRow],
        maxAbsDelta: Double = maxAbsDeltaBits
    ) -> Bool {
        guard !rows.isEmpty, rows.allSatisfy(\.verified) else { return false }
        return rows.allSatisfy { ($0.absDeltaVsExternal ?? .infinity) <= maxAbsDelta }
    }

    package static func markdownTable(_ rows: [TFHELWEEstimatorRow] = pendingTable()) -> String {
        var lines = [
            "| Label | n | σ | HELUT | Estimator | Δ |",
            "|---|---:|---:|---:|---:|---:|"
        ]
        for r in rows {
            let ext = r.externalBits.map { String(format: "%.1f", $0) } ?? "PENDING"
            let d = r.absDeltaVsExternal.map { String(format: "%.1f", $0) } ?? "—"
            lines.append(
                String(
                    format: "| %@ | %d | 2^%d | %.1f | %@ | %@ |",
                    r.label, r.dimension, r.logSigma, r.helutBits, ext, d
                )
            )
        }
        return lines.joined(separator: "\n")
    }

    /// Merge `{ "results": { "label": bits } }` or `{ "label": bits }` JSON.
    package static func loadExternalJSON(_ text: String) -> [String: Double] {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data)
        else { return [:] }
        let raw: [String: Any]
        if let dict = obj as? [String: Any] {
            if let nested = dict["results"] as? [String: Any] {
                raw = nested
            } else {
                raw = dict
            }
        } else {
            return [:]
        }
        var out: [String: Double] = [:]
        for (k, v) in raw {
            if v is NSNull { continue }
            if let d = v as? Double {
                out[k] = d
            } else if let i = v as? Int {
                out[k] = Double(i)
            } else if let n = v as? NSNumber {
                out[k] = n.doubleValue
            }
        }
        return out
    }

    /// Load `logs/helut-estimator-results.json` if present (Sage fill-in).
    package static func mergedFromResultsFile(
        path: String = "logs/helut-estimator-results.json"
    ) -> [TFHELWEEstimatorRow] {
        let cwd = FileManager.default.currentDirectoryPath
        let url = URL(fileURLWithPath: cwd).appendingPathComponent(path)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return pendingTable()
        }
        let bits = loadExternalJSON(text)
        guard !bits.isEmpty else { return pendingTable() }
        return mergeExternal(bits)
    }
    package static func exportPendingJSON() -> String {
        let rows = pendingTable().map { r -> [String: Any] in
            [
                "label": r.label,
                "n": r.dimension,
                "q": 4_294_967_296,
                "sigma": pow(2.0, Double(r.logSigma)),
                "log_sigma": r.logSigma,
                "helut_bits": r.helutBits,
                "secret": "binary",
                "sage_hint": sageSnippet(dimension: r.dimension, sigma: pow(2.0, Double(r.logSigma)))
            ]
        }
        guard JSONSerialization.isValidJSONObject(rows),
              let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return text
    }
}
