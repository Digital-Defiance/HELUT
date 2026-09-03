import Foundation

// MARK: - INIT / truth-table → test-polynomial cache (N=1024 lever)
//
// PicoRV shows ~75× unique-INIT reuse. Encrypted Metal BR was rebuilding
// `T[addr]=LUT[addr]·δ` per `$lut`. Cache host arrays by (INIT, degree, scale).

/// Fingerprint of a boolean truth table (LSB-address bits) + poly layout.
package struct TFHELUTInitKey: Hashable, Sendable {
    package var bitstring: String
    package var degree: Int
    package var scale: UInt32

    package init(truthTable: [UInt32], degree: Int, scale: UInt32) {
        var s = String()
        s.reserveCapacity(truthTable.count)
        for b in truthTable {
            precondition(b == 0 || b == 1)
            s.append(b == 0 ? "0" : "1")
        }
        self.bitstring = s
        self.degree = degree
        self.scale = scale
    }
}

/// Host-side cache: INIT → degree-N test polynomial.
/// Native `k=1`: `T[addr]=bit·δ`. Boolean `kδ`: nearest-address bands around
/// `k·addr` carry `bit·kδ`, so public-MS wires in `{0,k}` tolerate native jitter.
package final class TFHETestPolyCache: @unchecked Sendable {
    package static let shared = TFHETestPolyCache()

    private var store: [TFHELUTInitKey: [UInt32]] = [:]
    private var hits: Int = 0
    private var misses: Int = 0
    private let lock = NSLock()

    package init() {}

    package var stats: (hits: Int, misses: Int, entries: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (hits, misses, store.count)
    }

    package func resetStats() {
        lock.lock()
        defer { lock.unlock() }
        hits = 0
        misses = 0
    }

    package func clear() {
        lock.lock()
        defer { lock.unlock() }
        store.removeAll(keepingCapacity: false)
        hits = 0
        misses = 0
    }

    /// Return cached or freshly built test polynomial of length `degree`.
    package func testPolynomial(
        truthTable: [UInt32],
        degree: Int,
        scale: UInt32
    ) -> [UInt32] {
        precondition(truthTable.count.nonzeroBitCount == 1)
        precondition(degree >= truthTable.count)
        let key = TFHELUTInitKey(truthTable: truthTable, degree: degree, scale: scale)
        lock.lock()
        if let cached = store[key] {
            hits += 1
            lock.unlock()
            return cached
        }
        misses += 1
        lock.unlock()

        var poly = [UInt32](repeating: 0, count: degree)
        let k = booleanScaleFactor(polynomialDegree: degree, scale: scale)
        let lastCenter = (truthTable.count - 1) * k
        precondition(
            lastCenter < degree,
            "k-stride test poly needs k*(2^arity-1) < N (k=\(k) aritySlots=\(truthTable.count) N=\(degree))"
        )

        // Public MS rounds every LWE coefficient independently. After decryption,
        // a logical {0,k} wire can therefore land a few native units away from its
        // center even when decodeRotationNativeBit still recovers the right bit.
        // A single populated coefficient per address turns that harmless jitter
        // into the zero/default LUT value. Fill nearest-address Voronoi bands;
        // ties go to the lower address, matching the native decoder's strict
        // distance comparison. Exact center values are unchanged.
        let tieToLowerOffset = (k - 1) / 2
        let positiveMax = min(degree - 1, lastCenter + k / 2)
        for nativeIndex in 0...positiveMax {
            let address = (nativeIndex + tieToLowerOffset) / k
            guard address < truthTable.count else { break }
            poly[nativeIndex] = truthTable[address] &* scale
        }

        // A small negative phase around logical address zero appears near 2N.
        // Negacyclic lookup maps it through the tail of the degree-N polynomial
        // with a sign flip, so store the torus negation there. If a saturated
        // highest-address band overlaps this tail, preserve the positive band;
        // those edge tuples do not have a full two-sided jitter margin.
        if k / 2 > 0 {
            let negativeZero = UInt32(0) &- (truthTable[0] &* scale)
            for distance in 1...(k / 2) {
                let index = degree - distance
                if index > positiveMax {
                    poly[index] = negativeZero
                }
            }
        }
        lock.lock()
        store[key] = poly
        lock.unlock()
        return poly
    }
}

/// Dedup report for logs / SING.
package struct TFHEInitDedupReport: Sendable, Equatable {
    package var totalLUTs: Int
    package var uniqueInits: Int
    package var cacheHits: Int
    package var cacheMisses: Int

    package var reuseFactor: Double {
        uniqueInits == 0 ? 0 : Double(totalLUTs) / Double(uniqueInits)
    }

    package var summaryLine: String {
        String(
            format: "INIT dedup: %d LUTs → %d unique (%.1f×); cache hits=%d misses=%d",
            totalLUTs, uniqueInits, reuseFactor, cacheHits, cacheMisses
        )
    }

    package static func forJobs(_ jobs: [MetalGGSW.NetlistLUTJob]) -> TFHEInitDedupReport {
        var keys = Set<String>()
        for job in jobs {
            keys.insert(TFHELUTInitKey(truthTable: job.truthTable, degree: 0, scale: 0).bitstring)
        }
        let (hits, misses, _) = TFHETestPolyCache.shared.stats
        return TFHEInitDedupReport(
            totalLUTs: jobs.count,
            uniqueInits: keys.count,
            cacheHits: hits,
            cacheMisses: misses
        )
    }
}
