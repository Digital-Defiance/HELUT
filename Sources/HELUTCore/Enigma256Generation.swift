import Foundation

// MARK: - Enigma 256 Blue Team generation (Apple Silicon SoftBus field)
//
// Field fabric = SoftBus + iverilog/Yosys on this Mac — not a Zynq.
// Red Team (TensorLUT / SoftBus KPA) scores the live generation; Blue mutates
// NLFF folds + HKDF domain labels when pressure crosses threshold.

/// One NLFF triple: step = (lfsr[a] & lfsr[b]) ^ lfsr[c].
package struct Enigma256NLFFFold: Sendable, Equatable, Codable, Hashable {
    package var a: Int
    package var b: Int
    package var c: Int

    package init(a: Int, b: Int, c: Int) {
        precondition((0 ..< 64).contains(a) && (0 ..< 64).contains(b) && (0 ..< 64).contains(c))
        precondition(Set([a, b, c]).count == 3, "NLFF fold bits must be distinct")
        self.a = a
        self.b = b
        self.c = c
    }
}

/// Mutable Blue Team genes for SoftBus + Verilog NLFF cones.
package struct Enigma256Generation: Sendable, Equatable, Codable {
    package var id: Int
    /// Exactly four folds (rotors R1…R4).
    package var folds: [Enigma256NLFFFold]

    /// Process-wide live generation (SoftBus / oracle / Red campaigns).
    nonisolated(unsafe) package static var current = Enigma256Generation.gen0

    /// Shipping default — matches historical enigma_256_core / nlff_combo.
    package static let gen0 = Enigma256Generation(
        id: 0,
        folds: [
            Enigma256NLFFFold(a: 0, b: 7, c: 12),
            Enigma256NLFFFold(a: 15, b: 22, c: 29),
            Enigma256NLFFFold(a: 31, b: 38, c: 45),
            Enigma256NLFFFold(a: 47, b: 54, c: 61)
        ]
    )

    package init(id: Int, folds: [Enigma256NLFFFold]) {
        precondition(folds.count == 4)
        self.id = id
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

    /// Breed a new NLFF schedule (disjoint triples) and bump generation id.
    package func mutated(rng: inout some RandomNumberGenerator) -> Enigma256Generation {
        var used = Set<Int>()
        var nextFolds: [Enigma256NLFFFold] = []
        nextFolds.reserveCapacity(4)
        for _ in 0 ..< 4 {
            var candidates = Array(0 ..< 64).filter { !used.contains($0) }
            candidates.shuffle(using: &rng)
            // Prefer a compact window (~16 bits) like gen0, falling back to any triple.
            let windowOrigin = candidates[0]
            let window = candidates.filter { abs($0 - windowOrigin) <= 15 }
            let pickPool = window.count >= 3 ? window : candidates
            let a = pickPool[0]
            let b = pickPool[1]
            let c = pickPool[2]
            used.formUnion([a, b, c])
            let sorted = [a, b, c].sorted()
            nextFolds.append(Enigma256NLFFFold(a: sorted[0], b: sorted[1], c: sorted[2]))
        }
        return Enigma256Generation(id: id + 1, folds: nextFolds)
    }

    package func nlffAssignLines(indent: String = "    ") -> String {
        folds.enumerated().map { i, f in
            "\(indent)assign step_r\(i + 1) = (lfsr[\(f.a)] & lfsr[\(f.b)]) ^ lfsr[\(f.c)];"
        }.joined(separator: "\n")
    }

    package func nlffWireLines(indent: String = "    ") -> String {
        folds.enumerated().map { i, f in
            "\(indent)wire step_r\(i + 1) = (lfsr[\(f.a)] & lfsr[\(f.b)]) ^ lfsr[\(f.c)];"
        }.joined(separator: "\n")
    }

    package func emitNLFFComboVerilog() -> String {
        """
        `timescale 1ns / 1ps

        // Combinational NLFF only — TensorLUT-friendly (no DFFs).
        // Blue generation \(id) — SoftBus field on Apple Silicon.

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

    /// Rewrite `wire step_rN = …` / `assign step_rN = …` blocks in core / cone sources.
    package func rewritingNLFF(in verilog: String) -> String {
        var out = verilog
        let wirePattern = #"wire\s+step_r[1-4]\s*=\s*\(lfsr\[\d+\]\s*&\s*lfsr\[\d+\]\)\s*\^\s*lfsr\[\d+\]\s*;"#
        let assignPattern = #"assign\s+step_r[1-4]\s*=\s*\(lfsr\[\d+\]\s*&\s*lfsr\[\d+\]\)\s*\^\s*lfsr\[\d+\]\s*;"#
        if let wireRe = try? NSRegularExpression(pattern: wirePattern) {
            let range = NSRange(out.startIndex ..< out.endIndex, in: out)
            let matches = wireRe.matches(in: out, range: range)
            if matches.count == 4 {
                let first = Range(matches[0].range, in: out)!
                let last = Range(matches[3].range, in: out)!
                out.replaceSubrange(first.lowerBound ..< last.upperBound, with: nlffWireLines())
            }
        }
        if let assignRe = try? NSRegularExpression(pattern: assignPattern) {
            let range = NSRange(out.startIndex ..< out.endIndex, in: out)
            let matches = assignRe.matches(in: out, range: range)
            if matches.count == 4 {
                let first = Range(matches[0].range, in: out)!
                let last = Range(matches[3].range, in: out)!
                out.replaceSubrange(first.lowerBound ..< last.upperBound, with: nlffAssignLines())
            }
        }
        return out
    }
}
