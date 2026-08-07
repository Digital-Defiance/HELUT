import Foundation

/// Isolates edge Steckerboard LUT indices on a flat (abc) TensorLUT Enigma netlist.
///
/// Yosys `abc` erases hierarchical `plugboard` cell names, so we recover the stecker by
/// dataflow cones against the verified flat graph — without re-synthesizing.
///
/// **Why not a naive BFS to the first DFF?**
/// Enigma’s encrypt path is almost entirely combinational between CT and the registered
/// plaintext: CT → stecker → rotors (reading Q) → UKW → rotors → stecker → PT.D → PT.Q.
/// A BFS that only stops at `dWire` therefore swallows the rotor cloud (~700 LUTs).
///
/// **Forward cone (input stecker):**
/// Closure from ciphertext wires: a LUT joins only when *every* input is CT, a constant,
/// or the output of an already-included forward-stecker LUT — and no input is a sequential
/// state Q (rotor / greek / misc DFFs). Crossing into state-Q means rotor entry.
///
/// **Reverse cone (output stecker):**
/// `plaintext_char` bits are DFF Q. Unwrap each to its `dWire`, then take the producer LUT
/// (and any further reverse closure that stays outside the state-polluted cloud). With an
/// identity stecker these are typically a handful of encoding LUTs feeding the PT registers.
package enum TensorLUTConeTagger {

    package struct SteckerCones: Sendable {
        package let forwardLUTIndices: Set<Int>
        package let reverseLUTIndices: Set<Int>
        /// `forward ∪ reverse` — the melt mask for targeted stecker search.
        package let meltLUTIndices: Set<Int>
        package let stateQWires: Set<Int32>
        package let plaintextDWires: Set<Int32>

        package var meltLUTCount: Int { meltLUTIndices.count }

        /// Sorted CSV for `--melt-luts`.
        package var meltLUTCSV: String {
            meltLUTIndices.sorted().map(String.init).joined(separator: ",")
        }
    }

    /// Primary ciphertext wires (`ciphertext_char[7:0]`).
    package static let defaultCiphertextWires: [Int32] = EnigmaStreamBuilder.wireCT
    /// Primary plaintext wires (`plaintext_char[4:0]` live bits).
    package static let defaultPlaintextWires: [Int32] = EnigmaStreamBuilder.wirePT

    /// Tags stecker melt indices on `enigma_m4` (or any netlist with the same I/O / DFF map).
    package static func tagStecker(
        netlist: TensorLUTNetlist,
        ciphertextWires: [Int32] = defaultCiphertextWires,
        plaintextWires: [Int32] = defaultPlaintextWires
    ) -> SteckerCones {
        let luts = netlist.luts
        let dffs = netlist.dffs
        precondition(!luts.isEmpty, "empty TensorLUT netlist")

        var producerLUT: [Int32: Int] = [:]
        for (idx, lut) in luts.enumerated() {
            producerLUT[lut.outWire] = idx
        }

        let plaintextSet = Set(plaintextWires)
        let allQ = Set(dffs.map(\.qWire))
        // PT + linguistic_score registers are outputs, not rotor/greek state.
        let outputRegQ = allQ.filter { wire in
            plaintextSet.contains(wire) || (wire >= 17 && wire <= 32)
        }
        let stateQ = allQ.subtracting(Set(outputRegQ))

        var plaintextD: Set<Int32> = []
        for dff in dffs where plaintextSet.contains(dff.qWire) {
            if dff.dWire >= 0 {
                plaintextD.insert(dff.dWire)
            }
        }

        let forward = forwardSteckerClosure(
            luts: luts,
            seedWires: Set(ciphertextWires),
            stateQ: stateQ
        )

        let reverse = reverseSteckerFromRegisteredOutputs(
            luts: luts,
            producerLUT: producerLUT,
            plaintextDWires: plaintextD,
            stateQ: stateQ
        )

        return SteckerCones(
            forwardLUTIndices: forward,
            reverseLUTIndices: reverse,
            meltLUTIndices: forward.union(reverse),
            stateQWires: stateQ,
            plaintextDWires: plaintextD
        )
    }

    /// Per-LUT freeze mask: `true` = freeze (everything except stecker melt indices).
    package static func steckerFreezeMask(netlist: TensorLUTNetlist) -> [Bool] {
        let cones = tagStecker(netlist: netlist)
        return TensorFreezeMask.meltOnly(lutCount: netlist.luts.count, indices: cones.meltLUTIndices)
    }

    // MARK: - Cones

    /// CT-closure: all inputs known-safe; never read sequential state Q.
    private static func forwardSteckerClosure(
        luts: [TensorLUT6Cell],
        seedWires: Set<Int32>,
        stateQ: Set<Int32>
    ) -> Set<Int> {
        var known = seedWires
        var cone = Set<Int>()
        var changed = true
        while changed {
            changed = false
            for (idx, lut) in luts.enumerated() {
                if cone.contains(idx) { continue }
                let inputs = lutInputs(lut)
                if inputs.isEmpty { continue }
                if inputs.contains(where: { stateQ.contains($0) }) { continue }
                if inputs.allSatisfy({ known.contains($0) }) {
                    cone.insert(idx)
                    known.insert(lut.outWire)
                    changed = true
                }
            }
        }
        return cone
    }

    /// Unwrap PT.Q → PT.D, then reverse-walk. Include boundary LUTs that touch state-polluted
    /// wires; continue only through inputs outside the sequential cloud.
    private static func reverseSteckerFromRegisteredOutputs(
        luts: [TensorLUT6Cell],
        producerLUT: [Int32: Int],
        plaintextDWires: Set<Int32>,
        stateQ: Set<Int32>
    ) -> Set<Int> {
        // Transitive wires polluted by sequential state (rotor / greek cloud).
        var unsafeWires = stateQ
        var changed = true
        while changed {
            changed = false
            for lut in luts {
                if unsafeWires.contains(lut.outWire) { continue }
                let inputs = lutInputs(lut)
                if inputs.contains(where: { unsafeWires.contains($0) }) {
                    unsafeWires.insert(lut.outWire)
                    changed = true
                }
            }
        }

        var cone = Set<Int>()
        var frontier = plaintextDWires
        var seen = plaintextDWires

        while !frontier.isEmpty {
            var next = Set<Int32>()
            for wire in frontier {
                guard let lutIdx = producerLUT[wire] else { continue }
                if cone.contains(lutIdx) { continue }
                let inputs = lutInputs(luts[lutIdx])
                cone.insert(lutIdx)
                for input in inputs {
                    if unsafeWires.contains(input) { continue }
                    if seen.insert(input).inserted {
                        next.insert(input)
                    }
                }
            }
            frontier = next
        }
        return cone
    }

    private static func lutInputs(_ lut: TensorLUT6Cell) -> [Int32] {
        [lut.in0, lut.in1, lut.in2, lut.in3, lut.in4, lut.in5].filter { $0 >= 0 }
    }
}
