import Foundation

// MARK: - Turing–Welchman bombe (deterministic contradiction solver)
//
// Purely Boolean. No IC, no n-grams, no floating point anywhere in this file.
// A rotor setting is eliminated by logical contradiction or it is not eliminated
// at all, so unlike a plugboard hill-climb this cannot overfit 47 bits of stecker
// freedom to 72 letters of ciphertext.
//
// The constraint. Enigma enciphers as C = S(E(S(P))) where S is the plugboard
// involution and E the unsteckered scrambler at that step. Both are involutions,
// so writing σ = S the menu edge at step t reads
//
//     σ(C_t) = E_t(σ(P_t))
//
// Knowing σ of either end gives σ of the other. Welchman's diagonal board adds
// the fact that σ is an involution: σ(x) = y implies σ(y) = x. That single extra
// wiring turns loopless menus into constraint systems that still contradict, and
// it enforces injectivity for free — if two letters were deduced to the same
// stecker value, the diagonal link lights two bits in one row.

/// One crib aligned to one ciphertext offset, as a constraint graph over letters.
package struct BombeMenuAnchor: Codable, Hashable, Sendable {
    package let text: String
    package let offset: Int
    package let letters: [Int]

    package init(text: String, offset: Int) {
        self.text = text
        self.offset = offset
        self.letters = EnigmaAlphabet.normalize(text)
    }

    package var range: Range<Int> { offset..<(offset + letters.count) }
    package var description: String { "\(text)@\(offset)" }
}

package struct BombeMenuConstraint: Hashable, Sendable {
    package let step: Int
    package let plain: Int
    package let cipher: Int
}

package enum BombeMenuBuildError: Error, Equatable, CustomStringConvertible {
    case tooFewAnchors
    case nonCanonicalAnchor(index: Int, text: String)
    case anchorOutOfRange(index: Int, offset: Int, length: Int, ciphertextLength: Int)
    case overlappingAnchors(first: Int, second: Int)
    case selfEncipherment(anchor: Int, index: Int, letter: Int)
    case emptyConstellation
    case tooManyEdges(actual: Int, maximum: Int)

    package var description: String {
        switch self {
        case .tooFewAnchors: return "a constellation requires at least two independent anchors"
        case let .nonCanonicalAnchor(index, text):
            return "anchor \(index) must be nonempty canonical A-Z, got '\(text)'"
        case let .anchorOutOfRange(index, offset, length, ciphertextLength):
            return "anchor \(index) range \(offset)..<\(offset + length) is outside ciphertext 0..<\(ciphertextLength)"
        case let .overlappingAnchors(first, second):
            return "anchors \(first) and \(second) overlap; constellation anchors must be independent"
        case let .selfEncipherment(anchor, index, letter):
            return "anchor \(anchor) self-enciphers at absolute step \(index) (\(EnigmaAlphabet.character(letter)))"
        case .emptyConstellation: return "constellation produced no constraints"
        case let .tooManyEdges(actual, maximum):
            return "constellation has \(actual) constraints; Metal maximum is \(maximum)"
        }
    }
}

package struct BombeMenu: Sendable {
    package let crib: String
    package let offset: Int
    /// One or more independent plaintext anchors. Legacy menus always carry one.
    package let anchors: [BombeMenuAnchor]
    /// Ciphertext index of each edge — selects which scrambler the edge uses.
    package let steps: [Int]
    /// Letter pair joined by each edge: (crib letter, cipher letter).
    package let ends: [(Int, Int)]
    package let letters: [Int]
    /// Cyclomatic number of the menu graph: edges − vertices + components.
    /// Loops are what make a menu bite; the diagonal board supplies the rest.
    package let loops: Int
    /// Highest-degree letter, used as the test register.
    package let central: Int

    /// Backward-compatible initializer for host-only tests and legacy builders.
    package init(
        crib: String,
        offset: Int,
        steps: [Int],
        ends: [(Int, Int)],
        letters: [Int],
        loops: Int,
        central: Int
    ) {
        self.init(
            crib: crib,
            offset: offset,
            anchors: [BombeMenuAnchor(text: crib, offset: offset)],
            steps: steps,
            ends: ends,
            letters: letters,
            loops: loops,
            central: central
        )
    }

    package init(
        crib: String,
        offset: Int,
        anchors: [BombeMenuAnchor],
        steps: [Int],
        ends: [(Int, Int)],
        letters: [Int],
        loops: Int,
        central: Int
    ) {
        self.crib = crib
        self.offset = offset
        self.anchors = anchors
        self.steps = steps
        self.ends = ends
        self.letters = letters
        self.loops = loops
        self.central = central
    }

    package var edgeCount: Int { steps.count }
    package var constraintCount: Int { edgeCount }
    package var stepHorizon: Int { (steps.max() ?? -1) + 1 }
    package var lastCoveredEnd: Int { anchors.map { $0.range.upperBound }.max() ?? 0 }
    package var coveredPlaintextIndices: [Int] {
        Array(Set(anchors.flatMap { Array($0.range) })).sorted()
    }
    package var constraints: Set<BombeMenuConstraint> {
        Set(zip(steps, ends).map {
            BombeMenuConstraint(step: $0.0, plain: $0.1.0, cipher: $0.1.1)
        })
    }
    package var anchorSummary: String {
        anchors.map(\.description).joined(separator: " + ")
    }

    /// Connected components of the menu graph, from `loops = edges − vertices + components`.
    ///
    /// This is the number that decides whether a menu can force a *whole* board. The bombe
    /// seeds one letter, so it only propagates within that letter's component and never tests
    /// the constraints in the others — which is exactly how a split menu produces stops without
    /// being close to anything. `UUUVIRSIBENNULEINS@0` is the campaign's canonical example: 3
    /// components, 12 raw stops in Phase 3, and 0 joint ≤10-plug completions.
    package var components: Int { loops - edgeCount + letters.count }

    package var description: String {
        // `components` is printed because the ledger's own rule is that menu strength is
        // *connectivity*, not edge count — and without it a split menu producing stops reads
        // like a recurring near-miss rather than a known dud. `comp>1` means the board is only
        // testing part of the menu and the joint plug sieve is doing the real work.
        let name = anchors.count > 1 ? "{\(anchorSummary)}" : "\(crib)@\(offset)"
        return "\(name) edges=\(edgeCount) letters=\(letters.count) "
            + "loops=\(loops) comp=\(components) "
            + "span=\(stepHorizon) central=\(EnigmaAlphabet.character(central))"
    }
}

package enum BombeMenuBuilder {
    /// Build a menu, or nil if the crib cannot legally sit at this offset.
    package static func menu(crib: String, offset: Int, ciphertext: [Int]) -> BombeMenu? {
        let letters = EnigmaAlphabet.normalize(crib)
        guard !letters.isEmpty, offset >= 0, offset + letters.count <= ciphertext.count else {
            return nil
        }

        var steps: [Int] = []
        var ends: [(Int, Int)] = []

        for index in letters.indices {
            let step = offset + index
            let plain = letters[index]
            let cipher = ciphertext[step]
            // Enigma never encrypts a letter to itself.
            if plain == cipher { return nil }
            steps.append(step)
            ends.append((plain, cipher))
        }

        let anchor = BombeMenuAnchor(text: crib, offset: offset)
        return assemble(crib: crib, offset: offset, steps: steps, ends: ends, anchors: [anchor])
    }

    /// Build one joint hypothesis from several independent short plaintext anchors.
    ///
    /// The anchors remain separate evidence. They are never concatenated into an invented
    /// sentence: only their absolute `(step, plaintext, ciphertext)` constraints are unioned.
    /// A malformed or illegal anchor rejects the whole constellation rather than silently
    /// weakening it by dropping one member.
    package static func constellation(
        anchors specs: [(text: String, offset: Int)],
        ciphertext: [Int],
        maximumEdges: Int = 40
    ) throws -> BombeMenu {
        guard specs.count >= 2 else { throw BombeMenuBuildError.tooFewAnchors }
        var anchors: [BombeMenuAnchor] = []
        for (index, spec) in specs.enumerated() {
            let letters = EnigmaAlphabet.normalize(spec.text)
            guard !letters.isEmpty, EnigmaAlphabet.string(from: letters) == spec.text else {
                throw BombeMenuBuildError.nonCanonicalAnchor(index: index, text: spec.text)
            }
            guard spec.offset >= 0, spec.offset + letters.count <= ciphertext.count else {
                throw BombeMenuBuildError.anchorOutOfRange(
                    index: index, offset: spec.offset, length: letters.count,
                    ciphertextLength: ciphertext.count
                )
            }
            let anchor = BombeMenuAnchor(text: spec.text, offset: spec.offset)
            for (priorIndex, prior) in anchors.enumerated()
            where anchor.range.overlaps(prior.range) {
                throw BombeMenuBuildError.overlappingAnchors(
                    first: priorIndex, second: index
                )
            }
            anchors.append(anchor)
        }

        var constraints: [(step: Int, plain: Int, cipher: Int)] = []
        for (anchorIndex, anchor) in anchors.enumerated() {
            for local in anchor.letters.indices {
                let step = anchor.offset + local
                let plain = anchor.letters[local]
                let cipher = ciphertext[step]
                guard plain != cipher else {
                    throw BombeMenuBuildError.selfEncipherment(
                        anchor: anchorIndex, index: step, letter: plain
                    )
                }
                constraints.append((step, plain, cipher))
            }
        }
        constraints.sort {
            ($0.step, $0.plain, $0.cipher) < ($1.step, $1.plain, $1.cipher)
        }
        guard !constraints.isEmpty else { throw BombeMenuBuildError.emptyConstellation }
        guard constraints.count <= maximumEdges else {
            throw BombeMenuBuildError.tooManyEdges(
                actual: constraints.count, maximum: maximumEdges
            )
        }
        let label = anchors.map(\.text).joined(separator: "+")
        guard let menu = assemble(
            crib: label,
            offset: anchors.map(\.offset).min() ?? 0,
            steps: constraints.map(\.step),
            ends: constraints.map { ($0.plain, $0.cipher) },
            anchors: anchors
        ) else { throw BombeMenuBuildError.emptyConstellation }
        return menu
    }

    /// Build the menu graph from an edge list: connected components, cyclomatic number, and
    /// the highest-degree letter to use as the test register.
    ///
    /// Shared by the ordinary builder above and by the spliced (indel) builder in
    /// `SpliceMenu.swift`, so menu *topology* has exactly one implementation. The two differ
    /// only in how they pair a crib letter with a ciphertext letter and a step number; once
    /// that pairing exists, a menu is a menu.
    ///
    /// `steps` is the ciphertext/rotor index per edge and selects which scrambler the edge
    /// uses. For an ordinary menu it equals `offset + i`; for a spliced menu it does **not**,
    /// which is the entire mechanism of the indel hypothesis.
    package static func assemble(
        crib: String,
        offset: Int,
        steps: [Int],
        ends: [(Int, Int)],
        anchors explicitAnchors: [BombeMenuAnchor]? = nil
    ) -> BombeMenu? {
        guard !ends.isEmpty, steps.count == ends.count,
              steps.allSatisfy({ $0 >= 0 }),
              ends.allSatisfy({ (0..<26).contains($0.0) && (0..<26).contains($0.1) }) else {
            return nil
        }
        let anchors = explicitAnchors ?? [BombeMenuAnchor(text: crib, offset: offset)]

        var degree = [Int](repeating: 0, count: 26)
        var present = [Bool](repeating: false, count: 26)
        for (a, b) in ends {
            degree[a] += 1
            degree[b] += 1
            present[a] = true
            present[b] = true
        }

        var parent = Array(0..<26)
        func find(_ x: Int) -> Int {
            var root = x
            while parent[root] != root { root = parent[root] }
            var walk = x
            while parent[walk] != root {
                let next = parent[walk]
                parent[walk] = root
                walk = next
            }
            return root
        }
        for (a, b) in ends {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[ra] = rb }
        }

        let vertices = present.indices.filter { present[$0] }
        var roots = Set<Int>()
        for letter in vertices { roots.insert(find(letter)) }
        let loops = ends.count - vertices.count + roots.count
        let central = vertices.max(by: { degree[$0] < degree[$1] }) ?? 0

        return BombeMenu(
            crib: crib,
            offset: offset,
            anchors: anchors,
            steps: steps,
            ends: ends,
            letters: vertices,
            loops: loops,
            central: central
        )
    }

    /// Menus for every legal placement of every crib, best deduction power first.
    package static func menus(cribs: [String], ciphertext: [Int]) -> [BombeMenu] {
        var built: [BombeMenu] = []
        for crib in cribs {
            let length = EnigmaAlphabet.normalize(crib).count
            guard length > 0, ciphertext.count >= length else { continue }
            for offset in 0...(ciphertext.count - length) {
                if let menu = menu(crib: crib, offset: offset, ciphertext: ciphertext) {
                    built.append(menu)
                }
            }
        }
        return built.sorted {
            ($0.loops, $0.edgeCount) > ($1.loops, $1.edgeCount)
        }
    }
}

/// A rotor setting that survived the diagonal board, with the stecker it forces.
package struct BombeStop: Sendable {
    package let positions: (Int, Int, Int, Int)
    /// The hypothesis σ(letter) = value that survived.
    package let seedLetter: Int
    package let seedValue: Int
    /// Deduced plugboard: `stecker[x] == x` for self-steckered or undetermined,
    /// with `determined` marking which letters the menu actually pinned down.
    package let stecker: [Int]
    package let determined: [Bool]
    package let pairCount: Int

    package var positionsString: String {
        EnigmaAlphabet.string(from: [positions.0, positions.1, positions.2, positions.3])
    }

    package var pairsString: String {
        var seen = Set<Int>()
        var pairs: [String] = []
        for x in 0..<26 where determined[x] && stecker[x] != x && !seen.contains(x) {
            let y = stecker[x]
            seen.insert(x)
            seen.insert(y)
            pairs.append("\(EnigmaAlphabet.character(x))\(EnigmaAlphabet.character(y))")
        }
        return pairs.isEmpty ? "(none)" : pairs.sorted().joined(separator: " ")
    }
}

/// Rotor hardware for one bombe run. Rings are part of the setting because they
/// govern turnover; see `WelchmanBombe.spanIsTurnoverFree`.
package struct WelchmanBombe: Sendable {
    package let greek: EnigmaRotorSpec
    package let left: EnigmaRotorSpec
    package let middle: EnigmaRotorSpec
    package let right: EnigmaRotorSpec
    package let reflector: [Int]
    package let rings: (Int, Int, Int, Int)
    /// Kriegsmarine boards carried exactly ten leads. Historical, not logical:
    /// a menu forcing more than ten pairs is rejected only when this is set.
    package let maxPlugs: Int

    package init(
        greek: EnigmaRotorSpec,
        left: EnigmaRotorSpec,
        middle: EnigmaRotorSpec,
        right: EnigmaRotorSpec,
        reflector: [Int],
        rings: (Int, Int, Int, Int),
        maxPlugs: Int = 10
    ) {
        self.greek = greek
        self.left = left
        self.middle = middle
        self.right = right
        self.reflector = reflector
        self.rings = rings
        self.maxPlugs = maxPlugs
    }

    // MARK: Scrambler construction

    /// Window positions after each step, starting from `start` and stepping before
    /// each character — matching `EnigmaM4Machine.process`.
    package func positionTrail(start: (Int, Int, Int, Int), length: Int) -> [(Int, Int, Int)] {
        var l = start.1, m = start.2, r = start.3
        var trail: [(Int, Int, Int)] = []
        trail.reserveCapacity(length)
        for _ in 0..<length {
            let notchMiddle = middle.isAtNotch(position: m)
            let notchRight = right.isAtNotch(position: r)
            if notchMiddle { l = (l + 1) % 26 }
            if notchMiddle || notchRight { m = (m + 1) % 26 }
            r = (r + 1) % 26
            trail.append((l, m, r))
        }
        return trail
    }

    /// True when neither the middle nor the left wheel turns over inside the menu
    /// span. Under this condition the middle and right Ringstellung are absorbed
    /// into the window positions, so a sweep at rings AAAA covers every wiring.
    package func spanIsTurnoverFree(menu: BombeMenu, start: (Int, Int, Int, Int)) -> Bool {
        guard let last = menu.steps.max() else { return true }
        let trail = positionTrail(start: start, length: last + 1)
        guard let first = menu.steps.min() else { return true }
        let window = trail[first...last]
        guard let head = window.first else { return true }
        return window.allSatisfy { $0.0 == head.0 && $0.1 == head.1 }
    }

    /// Everything above the fast wheel, folded into one involution: M → L → G →
    /// UKW → G⁻¹ → L⁻¹ → M⁻¹. Depends only on the slow window positions, so it is
    /// computed once and reused for every step where they do not move.
    private func upperInvolution(greekPos: Int, leftPos: Int, middlePos: Int) -> [UInt8] {
        let offsetG = ((greekPos - rings.0) % 26 + 26) % 26
        let offsetL = ((leftPos - rings.1) % 26 + 26) % 26
        let offsetM = ((middlePos - rings.2) % 26 + 26) % 26
        var table = [UInt8](repeating: 0, count: 26)
        for input in 0..<26 {
            var value = input
            value = (middle.wiring[(value + offsetM) % 26] - offsetM + 26) % 26
            value = (left.wiring[(value + offsetL) % 26] - offsetL + 26) % 26
            value = (greek.wiring[(value + offsetG) % 26] - offsetG + 26) % 26
            value = reflector[value]
            value = (greek.inverse[(value + offsetG) % 26] - offsetG + 26) % 26
            value = (left.inverse[(value + offsetL) % 26] - offsetL + 26) % 26
            value = (middle.inverse[(value + offsetM) % 26] - offsetM + 26) % 26
            table[input] = UInt8(value)
        }
        return table
    }

    /// Unsteckered scrambler for each menu edge.
    package func scramblers(menu: BombeMenu, start: (Int, Int, Int, Int)) -> [[UInt8]] {
        guard let last = menu.steps.max() else { return [] }
        let trail = positionTrail(start: start, length: last + 1)

        var cache: [UInt8] = []
        var cachedSlow = (-1, -1)
        var tables: [[UInt8]] = []
        tables.reserveCapacity(menu.steps.count)

        for step in menu.steps {
            let (leftPos, middlePos, rightPos) = trail[step]
            if cachedSlow != (leftPos, middlePos) {
                cache = upperInvolution(
                    greekPos: start.0, leftPos: leftPos, middlePos: middlePos
                )
                cachedSlow = (leftPos, middlePos)
            }
            let offsetR = ((rightPos - rings.3) % 26 + 26) % 26
            var table = [UInt8](repeating: 0, count: 26)
            for input in 0..<26 {
                let forward = (right.wiring[(input + offsetR) % 26] - offsetR + 26) % 26
                let upper = Int(cache[forward])
                table[input] = UInt8((right.inverse[(upper + offsetR) % 26] - offsetR + 26) % 26)
            }
            tables.append(table)
        }
        return tables
    }

    // MARK: Implication closure

    /// Tolerant propagation (the **Mulein board**) lives in `MuleinBoard.swift`.
    ///
    /// It is deliberately not in this file: this type is the faithful historical board,
    /// and `propagate` below short-circuits on the first contradiction exactly as copper
    /// does. The tolerant board is a separate contribution built *on* this one, and it
    /// calls `propagateCore` so there is only ever one implementation of the closure.

    /// The closure itself, over an explicit edge list. Shared by the exact and tolerant
    /// entry points so there is exactly one implementation of the board's logic.
    package static func propagateCore(
        ends: [(Int, Int)],
        scramblers: [[UInt8]],
        seedLetter: Int,
        seedValue: Int
    ) -> [UInt32]? {
        var live = [UInt32](repeating: 0, count: 26)
        live[seedLetter] = UInt32(1) << UInt32(seedValue)

        var changed = true
        while changed {
            changed = false
            for index in ends.indices {
                let (a, b) = ends[index]
                let table = scramblers[index]
                for (from, to) in [(a, b), (b, a)] {
                    var mask = live[from]
                    var image: UInt32 = 0
                    while mask != 0 {
                        let bit = mask.trailingZeroBitCount
                        mask &= mask &- 1
                        image |= UInt32(1) << UInt32(table[bit])
                    }
                    if image & ~live[to] != 0 {
                        live[to] |= image
                        if live[to].nonzeroBitCount > 1 { return nil }
                        changed = true
                    }
                }
            }
            for x in 0..<26 {
                var mask = live[x]
                while mask != 0 {
                    let y = mask.trailingZeroBitCount
                    mask &= mask &- 1
                    let bit = UInt32(1) << UInt32(x)
                    if live[y] & bit == 0 {
                        live[y] |= bit
                        if live[y].nonzeroBitCount > 1 { return nil }
                        changed = true
                    }
                }
            }
        }
        return live
    }

    /// Propagate σ(seedLetter) = seedValue through the menu and the diagonal board.
    ///
    /// `live[x]` is a 26-bit mask of the values still implied for σ(x). Any row
    /// reaching two bits means the hypothesis forced σ(x) to two distinct letters:
    /// a hard contradiction, and the reason this returns nil.
    package static func propagate(
        menu: BombeMenu,
        scramblers: [[UInt8]],
        seedLetter: Int,
        seedValue: Int
    ) -> [UInt32]? {
        propagateCore(
            ends: menu.ends, scramblers: scramblers,
            seedLetter: seedLetter, seedValue: seedValue
        )
    }

    // MARK: Setting test

    /// Every hypothesis for the central letter: the full 26-bit seed space.
    package static let allSeeds: UInt32 = 0x03FF_FFFF

    /// Test one rotor setting against one menu.
    ///
    /// Every one of the 26 hypotheses for the central letter is tried. If all 26
    /// contradict, the setting is impossible — not unlikely, impossible. Any that
    /// survive are returned with the stecker the menu forces.
    package func test(menu: BombeMenu, start: (Int, Int, Int, Int)) -> [BombeStop] {
        test(menu: menu, start: start, seedMask: Self.allSeeds)
    }

    /// Same test, restricted to the hypotheses in `seedMask`.
    ///
    /// The GPU already decides all 26 seeds and reports them as a 26-bit mask, so the
    /// host has no reason to re-run the closures the GPU already killed. Passing the
    /// mask back is worth up to 26x on the drain path, where a surviving lane usually
    /// carries one or two live seeds. `allSeeds` reproduces the original behaviour.
    package func test(
        menu: BombeMenu,
        start: (Int, Int, Int, Int),
        seedMask: UInt32
    ) -> [BombeStop] {
        guard seedMask != 0 else { return [] }
        let tables = scramblers(menu: menu, start: start)
        var stops: [BombeStop] = []

        for value in 0..<26 where seedMask & (UInt32(1) << UInt32(value)) != 0 {
            guard let live = Self.propagate(
                menu: menu,
                scramblers: tables,
                seedLetter: menu.central,
                seedValue: value
            ) else { continue }

            var stecker = Array(0..<26)
            var determined = [Bool](repeating: false, count: 26)
            var pairs = 0
            for x in 0..<26 where live[x] != 0 {
                let y = live[x].trailingZeroBitCount
                stecker[x] = y
                determined[x] = true
                if y != x { pairs += 1 }
            }
            pairs /= 2
            if maxPlugs > 0 && pairs > maxPlugs { continue }

            stops.append(
                BombeStop(
                    positions: start,
                    seedLetter: menu.central,
                    seedValue: value,
                    stecker: stecker,
                    determined: determined,
                    pairCount: pairs
                )
            )
        }
        return stops
    }

    /// Whether the setting is logically excluded by this menu.
    package func isDead(menu: BombeMenu, start: (Int, Int, Int, Int)) -> Bool {
        let tables = scramblers(menu: menu, start: start)
        for value in 0..<26 {
            if Self.propagate(
                menu: menu, scramblers: tables, seedLetter: menu.central, seedValue: value
            ) != nil {
                return false
            }
        }
        return true
    }
}
