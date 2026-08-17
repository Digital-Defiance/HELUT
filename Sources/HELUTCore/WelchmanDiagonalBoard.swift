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
package struct BombeMenu: Sendable {
    package let crib: String
    package let offset: Int
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

    package var edgeCount: Int { steps.count }

    package var description: String {
        "\(crib)@\(offset) edges=\(edgeCount) letters=\(letters.count) "
            + "loops=\(loops) central=\(EnigmaAlphabet.character(central))"
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
        var degree = [Int](repeating: 0, count: 26)
        var present = [Bool](repeating: false, count: 26)

        for index in letters.indices {
            let step = offset + index
            let plain = letters[index]
            let cipher = ciphertext[step]
            // Enigma never encrypts a letter to itself.
            if plain == cipher { return nil }
            steps.append(step)
            ends.append((plain, cipher))
            degree[plain] += 1
            degree[cipher] += 1
            present[plain] = true
            present[cipher] = true
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
        var live = [UInt32](repeating: 0, count: 26)
        live[seedLetter] = UInt32(1) << UInt32(seedValue)

        var changed = true
        while changed {
            changed = false

            for index in menu.ends.indices {
                let (a, b) = menu.ends[index]
                let table = scramblers[index]

                var mask = live[a]
                var image: UInt32 = 0
                while mask != 0 {
                    let bit = mask.trailingZeroBitCount
                    mask &= mask &- 1
                    image |= UInt32(1) << UInt32(table[bit])
                }
                if image & ~live[b] != 0 {
                    live[b] |= image
                    if live[b].nonzeroBitCount > 1 { return nil }
                    changed = true
                }

                mask = live[b]
                image = 0
                while mask != 0 {
                    let bit = mask.trailingZeroBitCount
                    mask &= mask &- 1
                    image |= UInt32(1) << UInt32(table[bit])
                }
                if image & ~live[a] != 0 {
                    live[a] |= image
                    if live[a].nonzeroBitCount > 1 { return nil }
                    changed = true
                }
            }

            // Diagonal board: σ(x) = y is the same wire as σ(y) = x.
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
