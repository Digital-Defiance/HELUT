import Foundation

/// Reciprocal Steckerbrett (involution): at most `maxPairs` disjoint letter swaps.
///
/// Used as the TensorLUT stecker genotype. The compiled `enigma_m4` core has an
/// *identity* plugboard baked into its LUT INITs; a non-identity stecker is realized
/// by sandwiching this involution around the frozen core:
///
///   inject `S(CT)` → identity TensorLUT → soft PT ≈ `S(PT_true)`
///
/// so \(F_{crypto}\) compares outputs to bits of `S(P)`. Symmetry is structural —
/// the GA cannot invent non-reciprocal maps.
package struct SteckerInvolution: Sendable, Hashable {
    /// Unordered pairs with `first < second`.
    package var pairs: [(Int, Int)]
    package var fitness: Float

    package init(pairs: [(Int, Int)] = [], fitness: Float = -Float.greatestFiniteMagnitude) {
        self.pairs = pairs.map { (min($0.0, $0.1), max($0.0, $0.1)) }
            .filter { $0.0 != $0.1 }
            .sorted { $0.0 < $1.0 }
        self.fitness = fitness
        precondition(Self.isValid(self.pairs), "stecker pairs must be a partial involution")
    }

    package static func == (lhs: SteckerInvolution, rhs: SteckerInvolution) -> Bool {
        lhs.pairs.count == rhs.pairs.count
            && zip(lhs.pairs, rhs.pairs).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
            && lhs.fitness == rhs.fitness
    }

    package func hash(into hasher: inout Hasher) {
        for (a, b) in pairs {
            hasher.combine(a)
            hasher.combine(b)
        }
        hasher.combine(fitness)
    }

    package static func identity() -> SteckerInvolution {
        SteckerInvolution(pairs: [])
    }

    /// 26-entry map; fixed points are unmarked letters.
    package func mapTable() -> [Int] {
        var map = Array(0..<26)
        for (a, b) in pairs {
            map[a] = b
            map[b] = a
        }
        return map
    }

    package func apply(_ letter: Int) -> Int {
        precondition((0..<26).contains(letter))
        return mapTable()[letter]
    }

    package var pairCount: Int { pairs.count }

    package func descriptionPairs() -> String {
        if pairs.isEmpty { return "(identity)" }
        return pairs
            .map { "\(EnigmaAlphabet.character($0.0))\(EnigmaAlphabet.character($0.1))" }
            .joined(separator: " ")
    }

    /// True when both involutions induce the same image on every letter in `letters`.
    package func agrees(with other: SteckerInvolution, on letters: some Sequence<Int>) -> Bool {
        let a = mapTable()
        let b = other.mapTable()
        for letter in letters {
            precondition((0..<26).contains(letter))
            if a[letter] != b[letter] { return false }
        }
        return true
    }

    /// Observed CT for plaintext under this stecker around an identity-stecker clear harness:
    /// `C = S(encrypt_identity(S(P)))`.
    package static func fabricateCiphertext(
        plaintext: [Int],
        stecker: SteckerInvolution,
        harness: EnigmaNetlistHarness,
        left: Int,
        middle: Int,
        right: Int
    ) -> [Int] {
        let map = stecker.mapTable()
        harness.seedGrundstellung(left: left, middle: middle, right: right)
        let mid = harness.process(ciphertext: plaintext.map { map[$0] })
        return mid.map { map[$0] }
    }

    package static func isValid(_ pairs: [(Int, Int)]) -> Bool {
        var used = Set<Int>()
        for (a, b) in pairs {
            if a == b || !(0...25).contains(a) || !(0...25).contains(b) || a > b { return false }
            if used.contains(a) || used.contains(b) { return false }
            used.insert(a)
            used.insert(b)
        }
        return true
    }

    package static func random(maxPairs: Int, rng: inout some RandomNumberGenerator) -> SteckerInvolution {
        var used = Set<Int>()
        var pairs: [(Int, Int)] = []
        let count = Int.random(in: 0...max(0, maxPairs), using: &rng)
        var pool = Array(0..<26)
        pool.shuffle(using: &rng)
        for letter in pool {
            if pairs.count >= count { break }
            if used.contains(letter) { continue }
            let partners = pool.filter { !used.contains($0) && $0 != letter }
            guard let other = partners.randomElement(using: &rng) else { break }
            pairs.append((min(letter, other), max(letter, other)))
            used.insert(letter)
            used.insert(other)
        }
        return SteckerInvolution(pairs: pairs)
    }

    package func mutated(maxPairs: Int, rng: inout some RandomNumberGenerator) -> SteckerInvolution {
        var next = pairs
        let roll = Int.random(in: 0..<5, using: &rng)
        switch roll {
        case 0 where !next.isEmpty:
            next.remove(at: Int.random(in: 0..<next.count, using: &rng))
        case 1 where next.count < maxPairs:
            let used = Set(next.flatMap { [$0.0, $0.1] })
            let free = (0..<26).filter { !used.contains($0) }
            if free.count >= 2 {
                let i = Int.random(in: 0..<free.count, using: &rng)
                var j = Int.random(in: 0..<free.count, using: &rng)
                while j == i { j = Int.random(in: 0..<free.count, using: &rng) }
                next.append((min(free[i], free[j]), max(free[i], free[j])))
            }
        case 2 where !next.isEmpty:
            let idx = Int.random(in: 0..<next.count, using: &rng)
            var used = Set(next.flatMap { [$0.0, $0.1] })
            used.remove(next[idx].0)
            used.remove(next[idx].1)
            let free = (0..<26).filter { !used.contains($0) }
            if let neu = free.randomElement(using: &rng) {
                let keep = Bool.random(using: &rng) ? next[idx].0 : next[idx].1
                let a = min(keep, neu)
                let b = max(keep, neu)
                if a != b { next[idx] = (a, b) }
            }
        default:
            if next.count >= 1 {
                let idx = Int.random(in: 0..<next.count, using: &rng)
                var used = Set(next.flatMap { [$0.0, $0.1] })
                used.remove(next[idx].0)
                used.remove(next[idx].1)
                let free = (0..<26).filter { !used.contains($0) }
                if free.count >= 2 {
                    let i = Int.random(in: 0..<free.count, using: &rng)
                    var j = Int.random(in: 0..<free.count, using: &rng)
                    while j == i { j = Int.random(in: 0..<free.count, using: &rng) }
                    next[idx] = (min(free[i], free[j]), max(free[i], free[j]))
                }
            } else if maxPairs > 0 {
                return SteckerInvolution.random(maxPairs: 1, rng: &rng)
            }
        }
        next.sort { $0.0 < $1.0 }
        return SteckerInvolution(pairs: next)
    }

    /// Mutate only the free (non-frozen) region; frozen pairs always survive.
    package func mutatedPreserving(
        frozen: [(Int, Int)],
        maxPairs: Int,
        rng: inout some RandomNumberGenerator
    ) -> SteckerInvolution {
        let frozenNorm = frozen.map { (min($0.0, $0.1), max($0.0, $0.1)) }
        let frozenSet = Set(frozenNorm.map { ($0.0 << 8) | $0.1 })
        let free = pairs.filter { !frozenSet.contains(($0.0 << 8) | $0.1) }
        var base = SteckerInvolution(pairs: frozenNorm)
        let room = max(0, maxPairs - base.pairCount)
        if room == 0 { return base }
        if free.isEmpty {
            return SteckerInvolution.randomPreserving(frozen: frozenNorm, maxPairs: maxPairs, rng: &rng)
        }
        let freeChromo = SteckerInvolution(pairs: free).mutated(maxPairs: room, rng: &rng)
        var used = Set(frozenNorm.flatMap { [$0.0, $0.1] })
        var merged = frozenNorm
        for (a, b) in freeChromo.pairs {
            if merged.count >= maxPairs { break }
            if used.contains(a) || used.contains(b) { continue }
            merged.append((a, b))
            used.insert(a)
            used.insert(b)
        }
        return SteckerInvolution(pairs: merged)
    }

    /// Random involution that always includes `frozen` pairs.
    package static func randomPreserving(
        frozen: [(Int, Int)],
        maxPairs: Int,
        rng: inout some RandomNumberGenerator
    ) -> SteckerInvolution {
        let frozenNorm = frozen.map { (min($0.0, $0.1), max($0.0, $0.1)) }
        precondition(frozenNorm.count <= maxPairs)
        var used = Set(frozenNorm.flatMap { [$0.0, $0.1] })
        var pairs = frozenNorm
        let extras = Int.random(in: 0...(maxPairs - frozenNorm.count), using: &rng)
        var pool = (0..<26).filter { !used.contains($0) }
        pool.shuffle(using: &rng)
        var added = 0
        var i = 0
        while added < extras, i + 1 < pool.count {
            let a = pool[i]
            let b = pool[i + 1]
            pairs.append((min(a, b), max(a, b)))
            used.insert(a)
            used.insert(b)
            added += 1
            i += 2
        }
        return SteckerInvolution(pairs: pairs)
    }

    package static func crossover(
        _ a: SteckerInvolution,
        _ b: SteckerInvolution,
        maxPairs: Int,
        rng: inout some RandomNumberGenerator
    ) -> SteckerInvolution {
        var used = Set<Int>()
        var pairs: [(Int, Int)] = []
        var pool = a.pairs + b.pairs
        pool.shuffle(using: &rng)
        for (x, y) in pool {
            if pairs.count >= maxPairs { break }
            if used.contains(x) || used.contains(y) { continue }
            pairs.append((x, y))
            used.insert(x)
            used.insert(y)
        }
        return SteckerInvolution(pairs: pairs)
    }
}

/// Packs a 0…25 letter into 8 CT bit floats (LSB first) for TensorLUT injection.
package enum SteckerIOProjection {
    package static func ciphertextBits(_ letter: Int) -> [Float] {
        precondition((0..<26).contains(letter))
        return (0..<8).map { Float((letter >> $0) & 1) }
    }

    /// Live plaintext letter bits on `enigma_m4` (`plaintext_char[4:0]`).
    package static func plaintextBits(_ letter: Int) -> [Float] {
        precondition((0..<26).contains(letter))
        return (0..<5).map { Float((letter >> $0) & 1) }
    }
}
