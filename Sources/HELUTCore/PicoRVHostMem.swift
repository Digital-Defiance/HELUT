import Foundation

/// Tiny RV32I program for `--encrypted-mem prog`:
/// `addi x1,x0,1`; NOP; `sw x1,0(x0)`; NOP; `lw x2,0(x0)`; NOPs.
/// Instruction fetches always hit ROM (Harvard). Stores/loads overlay host RAM.
package enum PicoRVTinyProgram {
    package static let addiX1Imm1: UInt32 = 0x0010_0093
    package static let swX1At0: UInt32 = 0x0010_2023
    package static let lwX2At0: UInt32 = 0x0000_2103
    package static let nop: UInt32 = 0x0000_0013

    package static func romWord(addr: UInt32) -> UInt32 {
        switch addr & ~UInt32(3) {
        case 0: return addiX1Imm1
        case 8: return swX1At0
        case 0x10: return lwX2At0
        default: return nop
        }
    }
}

package struct PicoRVHostMem {
    package var ram: [UInt32: UInt32] = [:]
    package var stores: [(tick: Int, addr: UInt32, wstrb: UInt8, wdata: UInt32)] = []
    package var fetches: [(tick: Int, addr: UInt32)] = []
    package var loads: [(tick: Int, addr: UInt32, rdata: UInt32)] = []
    package var loadXfers: [(tick: Int, addr: UInt32, rdata: UInt32)] = []
    /// Next instruction word on `mem_rdata` (always-ready; advance after each instr xfer).
    package var pendingRdata: UInt32 = PicoRVTinyProgram.addiX1Imm1

    /// First cycle of valid&&ready&&instr: hold `pendingRdata` so the NBA xfer
    /// (next posedge) still sees the same word. PicoRV samples `mem_rdata` on `mem_xfer`,
    /// which is combo of the *new* `mem_valid` and is therefore one tick after we first
    /// observe valid in post-update outputs.
    package var instrHold = false

    package init() {}

    package mutating func noteFetch(tick: Int, addr: UInt32) {
        fetches.append((tick, addr))
        instrHold = true
    }

    package mutating func afterTick(valid: UInt8, ready: UInt8, instr: UInt8, addr: UInt32) {
        let live = valid == 1 && ready == 1 && instr == 1
        if instrHold && !live {
            pendingRdata = PicoRVTinyProgram.romWord(addr: (fetches.last?.addr ?? addr) &+ 4)
            instrHold = false
        }
        if live {
            instrHold = true
        }
    }

    package mutating func noteLoad(tick: Int, addr: UInt32, rdata: UInt32) {
        loads.append((tick, addr, rdata))
    }

    package mutating func noteStore(tick: Int, addr: UInt32, wstrb: UInt8, wdata: UInt32) {
        stores.append((tick, addr, wstrb, wdata))
        let key = addr & ~UInt32(3)
        var word = ram[key] ?? 0
        for i in 0..<4 {
            if (wstrb & (1 << i)) != 0 {
                let shift = UInt32(i * 8)
                let byte = (wdata >> shift) & 0xff
                word = (word & ~(UInt32(0xff) << shift)) | (byte << shift)
            }
        }
        ram[key] = word
    }
}

package func makePicoRVHostMemInputs(
    clear: CleartextNetlistSimulator,
    tick: Int,
    resetHold: Int,
    lastOutputs: [String: [UInt8]]?,
    kind: String,
    host: inout PicoRVHostMem
) -> [String: [UInt8]] {
    var row: [String: [UInt8]] = [:]
    for p in clear.inputPorts.keys.sorted() {
        let width = clear.inputPorts[p]!.count
        row[p] = [UInt8](repeating: 0, count: width)
    }
    let live: UInt8 = tick <= resetHold ? 0 : 1
    if let w = row["resetn"]?.count {
        row["resetn"] = [UInt8](repeating: live, count: w)
    }
    guard live == 1 else { return row }
    row["mem_ready"] = [1]
    let rdataWidth = row["mem_rdata"]?.count ?? 32
    var word = kind == "nop" ? PicoRVTinyProgram.nop : host.pendingRdata
    if kind == "prog", let last = lastOutputs {
        let lastValid = (last["mem_valid"] ?? [0]).first ?? 0
        let lastInstr = (last["mem_instr"] ?? [0]).first ?? 0
        let lastWstrb = unpackHostLE(last["mem_wstrb"] ?? [])
        if lastValid == 1 && lastInstr == 0 && lastWstrb == 0 {
            let addr = unpackHostLE(last["mem_addr"] ?? [])
            word = host.ram[addr & ~UInt32(3)] ?? 0
            host.loadXfers.append((tick: tick, addr: addr, rdata: word))
        }
    }
    row["mem_rdata"] = packHostLE(word, width: rdataWidth)
    return row
}

package func packHostLE(_ value: UInt32, width: Int) -> [UInt8] {
    (0..<width).map { i in UInt8((value >> i) & 1) }
}

package func unpackHostLE(_ bits: [UInt8]) -> UInt32 {
    var v: UInt32 = 0
    for (i, b) in bits.enumerated() where i < 32 {
        if b != 0 { v |= (1 << i) }
    }
    return v
}
