import Foundation

// MARK: - Enigma 256 Blue Team generation (Apple Silicon SoftBus field)
//
// Field fabric = SoftBus + iverilog/Yosys on this Mac — not a Zynq.
// Red Team (TensorLUT / SoftBus KPA) scores the live generation; Blue mutates
// NLFF folds + HKDF domain labels when pressure crosses threshold.

/// NLFF boolean class. Gen 0–2 used quadratic3; gen 3+ uses cubic6 after TensorLUT
/// repeatedly recovered the 3-input AND-XOR cone.
package enum Enigma256NLFFFormula: String, Sendable, Equatable, Codable {
    /// step = (a ∧ b) ⊕ c
    case quadratic3
    /// step = (a ∧ b ∧ c) ⊕ (d ∧ e) ⊕ f  (algebraic degree 3, six taps)
    case cubic6
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
        case .cubic6: return [a, b, c, d, e, f]
        }
    }

    package func evaluate(_ state: UInt64, formula: Enigma256NLFFFormula) -> Bool {
        func bit(_ i: Int) -> UInt64 { (state >> i) & 1 }
        switch formula {
        case .quadratic3:
            return ((bit(a) & bit(b)) ^ bit(c)) != 0
        case .cubic6:
            return ((bit(a) & bit(b) & bit(c)) ^ (bit(d) & bit(e)) ^ bit(f)) != 0
        }
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

    /// Breed a new NLFF schedule and bump generation id.
    /// Always emits `.cubic6` — quadratic3 lost the TensorLUT arms race.
    package func mutated(rng: inout some RandomNumberGenerator) -> Enigma256Generation {
        var used = Set<Int>()
        var nextFolds: [Enigma256NLFFFold] = []
        nextFolds.reserveCapacity(4)
        for _ in 0 ..< 4 {
            var candidates = Array(0 ..< 64).filter { !used.contains($0) }
            candidates.shuffle(using: &rng)
            // Prefer a ~24-bit window so taps stay mixed but local enough for synth.
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

    /// Structural upgrade path: jump to cubic6 gen3 schedule (or id+1 if already ≥3).
    package func hardenedCubic() -> Enigma256Generation {
        if id < 3 {
            return .gen3Cubic
        }
        var rng = SystemRandomNumberGenerator()
        return mutated(rng: &rng)
    }

    package func nlffExpression(_ fold: Enigma256NLFFFold) -> String {
        switch formula {
        case .quadratic3:
            return "(lfsr[\(fold.a)] & lfsr[\(fold.b)]) ^ lfsr[\(fold.c)]"
        case .cubic6:
            return "(lfsr[\(fold.a)] & lfsr[\(fold.b)] & lfsr[\(fold.c)]) ^ (lfsr[\(fold.d)] & lfsr[\(fold.e)]) ^ lfsr[\(fold.f)]"
        }
    }

    package func nlffAssignLines(indent: String = "    ") -> String {
        folds.enumerated().map { i, fold in
            "\(indent)assign step_r\(i + 1) = \(nlffExpression(fold));"
        }.joined(separator: "\n")
    }

    package func nlffWireLines(indent: String = "    ") -> String {
        folds.enumerated().map { i, fold in
            "\(indent)wire step_r\(i + 1) = \(nlffExpression(fold));"
        }.joined(separator: "\n")
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

    /// Rewrite `wire` / `assign` step_rN lines in core / cone sources.
    package func rewritingNLFF(in verilog: String) -> String {
        var out = verilog
        let pattern = #"(?m)^[ \t]*(?:wire|assign)[ \t]+step_r[1-4][ \t]*=[ \t]*[^;]+;"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return out }
        let range = NSRange(out.startIndex ..< out.endIndex, in: out)
        let matches = re.matches(in: out, range: range)
        guard matches.count >= 4 else { return out }
        let firstFour = Array(matches.prefix(4))
        let first = Range(firstFour[0].range, in: out)!
        let last = Range(firstFour[3].range, in: out)!
        let replacement = out[first].contains("assign") ? nlffAssignLines() : nlffWireLines()
        out.replaceSubrange(first.lowerBound ..< last.upperBound, with: replacement)
        return out
    }
}
