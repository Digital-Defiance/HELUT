import Foundation

// MARK: - Enigma 256 Blue Team generation (Apple Silicon SoftBus field)
//
// Field fabric = SoftBus + iverilog/Yosys on this Mac — not a Zynq.
// Red Team (TensorLUT / SoftBus KPA) scores the live generation; Blue mutates
// NLFF folds + HKDF domain labels when pressure crosses threshold.

/// NLFF boolean class. Gen 0–2 used quadratic3; gen 3 cubic6; gen 4+ coupledCubic6.
package enum Enigma256NLFFFormula: String, Sendable, Equatable, Codable {
    /// step = (a ∧ b) ⊕ c
    case quadratic3
    /// step = (a ∧ b ∧ c) ⊕ (d ∧ e) ⊕ f  (algebraic degree 3, six taps)
    case cubic6
    /// Coupled cubic6: step_i = f_i ⊕ (f_{i+1} ∧ f_{i+2}) — shared cross terms, denser cone
    case coupledCubic6
}

/// Tap indices into the 64-bit LFSR for one rotor step enable.
package struct Enigma256NLFFFold: Sendable, Equatable, Codable, Hashable {
    package var a: Int
    package var b: Int
    package var c: Int
    /// Used by `.cubic6` (ignored by `.quadratic3`).
    package var d: Int
    package var e: Int
    package var f: Int

    package init(a: Int, b: Int, c: Int, d: Int = 0, e: Int = 0, f: Int = 0) {
        for t in [a, b, c, d, e, f] {
            precondition((0 ..< 64).contains(t))
        }
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.e = e
        self.f = f
    }

    private enum CodingKeys: String, CodingKey {
        case a, b, c, d, e, f
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        a = try container.decode(Int.self, forKey: .a)
        b = try container.decode(Int.self, forKey: .b)
        c = try container.decode(Int.self, forKey: .c)
        d = try container.decodeIfPresent(Int.self, forKey: .d) ?? 0
        e = try container.decodeIfPresent(Int.self, forKey: .e) ?? 0
        f = try container.decodeIfPresent(Int.self, forKey: .f) ?? 0
    }

    package func taps(for formula: Enigma256NLFFFormula) -> [Int] {
        switch formula {
        case .quadratic3: return [a, b, c]
        case .cubic6, .coupledCubic6: return [a, b, c, d, e, f]
        }
    }

    /// Raw cubic6 / quadratic leaf (before any cross-coupling).
    package func leaf(_ state: UInt64, formula: Enigma256NLFFFormula) -> Bool {
        func bit(_ i: Int) -> UInt64 { (state >> i) & 1 }
        switch formula {
        case .quadratic3:
            return ((bit(a) & bit(b)) ^ bit(c)) != 0
        case .cubic6, .coupledCubic6:
            return ((bit(a) & bit(b) & bit(c)) ^ (bit(d) & bit(e)) ^ bit(f)) != 0
        }
    }

    package func evaluate(_ state: UInt64, formula: Enigma256NLFFFormula) -> Bool {
        // Coupling is applied at generation level across all four folds.
        leaf(state, formula: formula)
    }
}

/// Mutable Blue Team genes for SoftBus + Verilog NLFF cones.
package struct Enigma256Generation: Sendable, Equatable, Codable {
    package var id: Int
    package var formula: Enigma256NLFFFormula
    /// Exactly four folds (rotors R1…R4).
    package var folds: [Enigma256NLFFFold]

    /// Process-wide live generation (SoftBus / oracle / Red campaigns).
    nonisolated(unsafe) package static var current = Enigma256Generation.gen0

    /// Historical default — quadratic3 (matches early campaign gens).
    package static let gen0 = Enigma256Generation(
        id: 0,
        formula: .quadratic3,
        folds: [
            Enigma256NLFFFold(a: 0, b: 7, c: 12),
            Enigma256NLFFFold(a: 15, b: 22, c: 29),
            Enigma256NLFFFold(a: 31, b: 38, c: 45),
            Enigma256NLFFFold(a: 47, b: 54, c: 61)
        ]
    )

    /// First structural harden: cubic6 with spread taps (gen 3).
    package static let gen3Cubic = Enigma256Generation(
        id: 3,
        formula: .cubic6,
        folds: [
            Enigma256NLFFFold(a: 0, b: 13, c: 27, d: 5, e: 41, f: 62),
            Enigma256NLFFFold(a: 1, b: 18, c: 33, d: 9, e: 44, f: 58),
            Enigma256NLFFFold(a: 2, b: 21, c: 36, d: 11, e: 48, f: 55),
            Enigma256NLFFFold(a: 3, b: 24, c: 39, d: 14, e: 51, f: 60)
        ]
    )

    /// Gen 5: cubic6 with bred taps — balanced ~0.5 step rates, low φ (stronger stepping).
    package static let gen5Balanced = Enigma256Generation(
        id: 5,
        formula: .cubic6,
        folds: [
            Enigma256NLFFFold(a: 4, b: 15, c: 17, d: 23, e: 26, f: 61),
            Enigma256NLFFFold(a: 7, b: 9, c: 31, d: 38, e: 50, f: 59),
            Enigma256NLFFFold(a: 30, b: 43, c: 46, d: 49, e: 51, f: 60),
            Enigma256NLFFFold(a: 12, b: 29, c: 54, d: 55, e: 57, f: 62)
        ]
    )

    /// Gen 4 experiment: coupled enables — rejected (correlates rotor steps). Kept for stats/regression.
    package static let gen4Coupled = Enigma256Generation(
        id: 4,
        formula: .coupledCubic6,
        folds: Enigma256Generation.gen3Cubic.folds
    )

    package init(id: Int, formula: Enigma256NLFFFormula = .quadratic3, folds: [Enigma256NLFFFold]) {
        precondition(folds.count == 4)
        for fold in folds {
            let taps = fold.taps(for: formula)
            precondition(Set(taps).count == taps.count, "NLFF fold taps must be distinct")
        }
        self.id = id
        self.formula = formula
        self.folds = folds
    }

    package var dayInfo: Data {
        if id == 0 { return Data("enigma256-day-v2".utf8) }
        return Data("enigma256-day-v2-g\(id)".utf8)
    }

    package var messageInfo: Data {
        if id == 0 { return Data("enigma256-msg-v2".utf8) }
        return Data("enigma256-msg-v2-g\(id)".utf8)
    }

    package static func load(from url: URL) throws -> Enigma256Generation {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Enigma256Generation.self, from: data)
    }

    package func save(to url: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: url, options: .atomic)
    }

    /// Activate as SoftBus / oracle generation.
    package func activate() {
        Enigma256Generation.current = self
    }

    /// Load `Fixtures/enigma256_generation.json` if present; otherwise keep `current`.
    @discardableResult
    package static func bootstrapFromFixture(
        path: String = "Fixtures/enigma256_generation.json"
    ) -> Enigma256Generation {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path),
              let gen = try? Enigma256Generation.load(from: url) else {
            return current
        }
        gen.activate()
        return gen
    }

    private enum CodingKeys: String, CodingKey {
        case id, formula, folds
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        formula = try container.decodeIfPresent(Enigma256NLFFFormula.self, forKey: .formula) ?? .quadratic3
        folds = try container.decode([Enigma256NLFFFold].self, forKey: .folds)
        precondition(folds.count == 4)
    }

    /// Breed a new cubic6 tap schedule and bump generation id.
    /// Stays on independent cubic6 — coupling was rejected (correlated step enables).
    package func mutated(rng: inout some RandomNumberGenerator) -> Enigma256Generation {
        var used = Set<Int>()
        var nextFolds: [Enigma256NLFFFold] = []
        nextFolds.reserveCapacity(4)
        for _ in 0 ..< 4 {
            var candidates = Array(0 ..< 64).filter { !used.contains($0) }
            candidates.shuffle(using: &rng)
            let windowOrigin = candidates[0]
            let window = candidates.filter { abs($0 - windowOrigin) <= 23 }
            let pickPool = window.count >= 6 ? window : candidates
            let picks = Array(pickPool.prefix(6))
            used.formUnion(picks)
            let sorted = picks.sorted()
            nextFolds.append(
                Enigma256NLFFFold(
                    a: sorted[0], b: sorted[1], c: sorted[2],
                    d: sorted[3], e: sorted[4], f: sorted[5]
                )
            )
        }
        return Enigma256Generation(id: id + 1, formula: .cubic6, folds: nextFolds)
    }

    /// Structural upgrade toward stronger independent NLFF (never toward coupledCubic6).
    /// quadratic3 → gen3 cubic6; coupledCubic6 → rollback gen3; cubic6 → retap mutate.
    package func hardenedCubic() -> Enigma256Generation {
        switch formula {
        case .quadratic3:
            return .gen3Cubic
        case .coupledCubic6:
            // Coupling bought TensorLUT hardness by correlating rotors — reject.
            return .gen3Cubic
        case .cubic6:
            var rng = SystemRandomNumberGenerator()
            return mutated(rng: &rng)
        }
    }

    package func leafExpression(_ fold: Enigma256NLFFFold) -> String {
        switch formula {
        case .quadratic3:
            return "(lfsr[\(fold.a)] & lfsr[\(fold.b)]) ^ lfsr[\(fold.c)]"
        case .cubic6, .coupledCubic6:
            return "(lfsr[\(fold.a)] & lfsr[\(fold.b)] & lfsr[\(fold.c)]) ^ (lfsr[\(fold.d)] & lfsr[\(fold.e)]) ^ lfsr[\(fold.f)]"
        }
    }

    package func nlffAssignLines(indent: String = "    ") -> String {
        switch formula {
        case .quadratic3, .cubic6:
            return folds.enumerated().map { i, fold in
                "\(indent)assign step_r\(i + 1) = \(leafExpression(fold));"
            }.joined(separator: "\n")
        case .coupledCubic6:
            var lines: [String] = []
            for (i, fold) in folds.enumerated() {
                lines.append("\(indent)wire nlff_f\(i + 1) = \(leafExpression(fold));")
            }
            lines.append("\(indent)assign step_r1 = nlff_f1 ^ (nlff_f2 & nlff_f3);")
            lines.append("\(indent)assign step_r2 = nlff_f2 ^ (nlff_f3 & nlff_f4);")
            lines.append("\(indent)assign step_r3 = nlff_f3 ^ (nlff_f4 & nlff_f1);")
            lines.append("\(indent)assign step_r4 = nlff_f4 ^ (nlff_f1 & nlff_f2);")
            return lines.joined(separator: "\n")
        }
    }

    package func nlffWireLines(indent: String = "    ") -> String {
        switch formula {
        case .quadratic3, .cubic6:
            return folds.enumerated().map { i, fold in
                "\(indent)wire step_r\(i + 1) = \(leafExpression(fold));"
            }.joined(separator: "\n")
        case .coupledCubic6:
            var lines: [String] = []
            for (i, fold) in folds.enumerated() {
                lines.append("\(indent)wire nlff_f\(i + 1) = \(leafExpression(fold));")
            }
            lines.append("\(indent)wire step_r1 = nlff_f1 ^ (nlff_f2 & nlff_f3);")
            lines.append("\(indent)wire step_r2 = nlff_f2 ^ (nlff_f3 & nlff_f4);")
            lines.append("\(indent)wire step_r3 = nlff_f3 ^ (nlff_f4 & nlff_f1);")
            lines.append("\(indent)wire step_r4 = nlff_f4 ^ (nlff_f1 & nlff_f2);")
            return lines.joined(separator: "\n")
        }
    }

    package func emitNLFFComboVerilog() -> String {
        """
        `timescale 1ns / 1ps

        // Combinational NLFF only — TensorLUT-friendly (no DFFs).
        // Blue generation \(id) formula=\(formula.rawValue) — SoftBus field on Apple Silicon.

        module enigma_256_nlff_combo (
            input  wire [63:0] lfsr,
            output wire        step_r1,
            output wire        step_r2,
            output wire        step_r3,
            output wire        step_r4
        );
        \(nlffAssignLines())
        endmodule

        """
    }

    /// Rewrite NLFF step / leaf lines in core / cone / combo sources.
    package func rewritingNLFF(in verilog: String) -> String {
        var out = verilog
        let pattern = #"(?m)^[ \t]*(?:wire|assign)[ \t]+(?:nlff_f|step_r)[1-4][ \t]*=[ \t]*[^;]+;"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return out }
        let range = NSRange(out.startIndex ..< out.endIndex, in: out)
        let matches = re.matches(in: out, range: range)
        guard let first = matches.first, let last = matches.last,
              let firstR = Range(first.range, in: out),
              let lastR = Range(last.range, in: out) else { return out }
        let sample = String(out[firstR])
        let replacement = sample.contains("assign") ? nlffAssignLines() : nlffWireLines()
        out.replaceSubrange(firstR.lowerBound ..< lastR.upperBound, with: replacement)
        return out
    }
}

// MARK: - NLFF step-enable statistics (Blue quality, not TensorLUT score)

package struct Enigma256NLFFStepStats: Sendable {
    package var steps: Int
    package var rates: [Double]          // P(step_ri)
    package var phi: [[Double]]          // pairwise φ correlation
    package var meanRate: Double
    package var maxAbsOffDiagPhi: Double
    package var allFourOnRate: Double

    package var meanRateOK: Bool { abs(meanRate - 0.5) < 0.08 }
    /// Independent enables should keep |φ| small off-diagonal.
    package var independenceOK: Bool { maxAbsOffDiagPhi < 0.20 }
    /// All four rotors should step with non-trivial probability.
    package var rateFloorOK: Bool { rates.allSatisfy { $0 > 0.25 && $0 < 0.75 } }
}

extension Enigma256Generation {
    /// Monte-Carlo step-enable rates / correlations under Galois LFSR clocks.
    package func stepEnableStats(
        steps: Int = 200_000,
        seed: UInt64 = 0xC0FF_EE12_3456_789A
    ) -> Enigma256NLFFStepStats {
        var lfsr = Enigma256LFSR(seed: seed == 0 ? 1 : seed)
        var counts = [0, 0, 0, 0]
        var pair = Array(repeating: Array(repeating: 0, count: 4), count: 4)
        var allOn = 0
        for _ in 0 ..< steps {
            let m = lfsr.stepMask(using: self)
            let bits = [m.0, m.1, m.2, m.3]
            for i in 0 ..< 4 {
                if bits[i] { counts[i] += 1 }
                for j in 0 ..< 4 where bits[i] && bits[j] {
                    pair[i][j] += 1
                }
            }
            if bits[0] && bits[1] && bits[2] && bits[3] { allOn += 1 }
            lfsr.clock()
        }
        let n = Double(steps)
        let rates = counts.map { Double($0) / n }
        var phi = Array(repeating: Array(repeating: 0.0, count: 4), count: 4)
        var maxAbs = 0.0
        for i in 0 ..< 4 {
            for j in 0 ..< 4 {
                let pij = Double(pair[i][j]) / n
                let denom = (rates[i] * (1 - rates[i]) * rates[j] * (1 - rates[j])).squareRoot()
                let v = denom > 1e-12 ? (pij - rates[i] * rates[j]) / denom : 0
                phi[i][j] = v
                if i != j { maxAbs = max(maxAbs, abs(v)) }
            }
        }
        return Enigma256NLFFStepStats(
            steps: steps,
            rates: rates,
            phi: phi,
            meanRate: rates.reduce(0, +) / 4,
            maxAbsOffDiagPhi: maxAbs,
            allFourOnRate: Double(allOn) / n
        )
    }

    /// Search disjoint cubic6 tap schedules for balanced rates + low step correlation.
    package static func breedBalancedCubic6(
        id: Int = 5,
        trials: Int = 2_000,
        sampleSteps: Int = 40_000,
        rng: inout some RandomNumberGenerator
    ) -> (generation: Enigma256Generation, stats: Enigma256NLFFStepStats) {
        var best: Enigma256Generation?
        var bestStats: Enigma256NLFFStepStats?
        var bestScore = Double.infinity
        for _ in 0 ..< trials {
            var used = Set<Int>()
            var folds: [Enigma256NLFFFold] = []
            var ok = true
            for _ in 0 ..< 4 {
                var pool = Array(0 ..< 64).filter { !used.contains($0) }
                if pool.count < 6 { ok = false; break }
                pool.shuffle(using: &rng)
                let picks = Array(pool.prefix(6)).sorted()
                used.formUnion(picks)
                folds.append(Enigma256NLFFFold(
                    a: picks[0], b: picks[1], c: picks[2],
                    d: picks[3], e: picks[4], f: picks[5]
                ))
            }
            guard ok else { continue }
            let gen = Enigma256Generation(id: id, formula: .cubic6, folds: folds)
            let stats = gen.stepEnableStats(steps: sampleSteps)
            let rateErr = stats.rates.map { abs($0 - 0.5) }.reduce(0, +)
            let score = rateErr * 2.0 + stats.maxAbsOffDiagPhi * 3.0 + abs(stats.meanRate - 0.5) * 2.0
            if score < bestScore {
                bestScore = score
                best = gen
                bestStats = stats
            }
        }
        guard let best, let bestStats else {
            return (.gen3Cubic, Enigma256Generation.gen3Cubic.stepEnableStats(steps: sampleSteps))
        }
        return (best, bestStats)
    }
}
