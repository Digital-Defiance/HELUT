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
/// Native `k=1`: `T[addr]=bit·δ`. Boolean `kδ`: `T[k·addr]=bit·kδ` so public-MS
/// wires in `{0,k}` rotate onto the LUT slot.
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
        let last = (truthTable.count - 1) * k
        precondition(
            last < degree,
            "k-stride test poly needs k*(2^arity-1) < N (k=\(k) aritySlots=\(truthTable.count) N=\(degree))"
        )
        for (addr, bit) in truthTable.enumerated() {
            poly[addr * k] = bit &* scale
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
