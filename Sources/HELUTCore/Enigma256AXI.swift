import Foundation

// MARK: - Enigma 256 AXI-lite register map + host driver
//
// Matches ENIGMA256_REGMAP.md / enigma_256_axi.v. SoftBus is a cycle-free
// model of the same programming contract for unit tests and host bring-up.

package enum Enigma256Reg: UInt32, CaseIterable, Sendable {
    case ctrl = 0x00
    case wrSel = 0x04
    case wrAddr = 0x08
    case wrData = 0x0C
    case initLfsrLo = 0x10
    case initLfsrHi = 0x14
    case initR1 = 0x18
    case initR2 = 0x1C
    case initR3 = 0x20
    case initR4 = 0x24
    case dataIn = 0x28
    case dataOut = 0x2C
    case status = 0x30
    /// CTRL-adjacent: bit0 enables stream jitter (SCA DPA alignment break).
    case scaCtrl = 0x34
    /// AXIS table burst: write byte count committed (RO progress) / WO start sel.
    case burstStatus = 0x38

    package var offset: UInt32 { rawValue }
}

package protocol Enigma256MMIO: AnyObject {
    func write32(offset: UInt32, value: UInt32)
    func read32(offset: UInt32) -> UInt32
}

/// Host driver: tables → message key → LOAD_STATE → stream via MMIO.
package final class Enigma256AXIDriver {
    package let bus: Enigma256MMIO

    package init(bus: Enigma256MMIO) {
        self.bus = bus
    }

    package func write(_ reg: Enigma256Reg, _ value: UInt32) {
        bus.write32(offset: reg.offset, value: value)
    }

    package func read(_ reg: Enigma256Reg) -> UInt32 {
        bus.read32(offset: reg.offset)
    }

    package func programTables(_ wiring: Enigma256Wiring) {
        for sel in Enigma256TableSel.allCases {
            write(.wrSel, UInt32(sel.rawValue))
            let bytes = Enigma256Bridge.table(wiring, sel: sel)
            for (addr, byte) in bytes.enumerated() {
                write(.wrAddr, UInt32(addr))
                write(.wrData, UInt32(byte))
            }
        }
    }

    /// Burst table load (2,560 bytes) — SoftBus models AXIS DMA; MMIO falls back to beats.
    package func programTablesBurst(_ wiring: Enigma256Wiring) {
        if let soft = bus as? Enigma256SoftBus {
            soft.burstLoadTables(wiring)
            return
        }
        programTables(wiring)
    }

    package func setStreamJitter(_ enabled: Bool) {
        write(.scaCtrl, enabled ? 1 : 0)
    }

    package func writeMessageKey(_ key: Enigma256MessageKey) {
        let seed = key.lfsrSeed == 0 ? 1 : key.lfsrSeed
        write(.initLfsrLo, UInt32(truncatingIfNeeded: seed & 0xFFFF_FFFF))
        write(.initLfsrHi, UInt32(truncatingIfNeeded: seed >> 32))
        write(.initR1, UInt32(key.positions.0))
        write(.initR2, UInt32(key.positions.1))
        write(.initR3, UInt32(key.positions.2))
        write(.initR4, UInt32(key.positions.3))
    }

    package func pulseLoadState() {
        write(.ctrl, 0x1) // CTRL[0] W1C → load_state
    }

    package func configure(day: Enigma256DayKey, message: Enigma256MessageKey) {
        programTablesBurst(message.wiring(from: day))
        writeMessageKey(message)
        pulseLoadState()
    }

    package func configure(context: Enigma256Context, nonce: Data) {
        let (key, _) = context.messageState(nonce: nonce)
        configure(day: context.day, message: key)
    }

    /// Write DATA_IN; poll STATUS.valid; return DATA_OUT.
    package func transfer(_ byte: UInt8, maxPolls: Int = 8) -> UInt8 {
        write(.dataIn, UInt32(byte))
        for _ in 0 ..< maxPolls {
            let st = read(.status)
            if (st & 0x1) != 0 {
                return UInt8(truncatingIfNeeded: read(.dataOut) & 0xFF)
            }
        }
        preconditionFailure("Enigma256 AXI: DATA_OUT valid timeout")
    }

    package func transfer(_ bytes: [UInt8]) -> [UInt8] {
        bytes.map { transfer($0) }
    }
}

/// In-process MMIO that mirrors `enigma_256_axi` side-effects (no clock).
package final class Enigma256SoftBus: Enigma256MMIO {
    package private(set) var handle = Enigma256CoreHandle()
    package private(set) var wrSel: UInt8 = 0
    package private(set) var wrAddr: UInt8 = 0
    package private(set) var dataIn: UInt8 = 0
    package private(set) var dataOut: UInt8 = 0
    package private(set) var validOut = false
    package private(set) var busy = false
    package private(set) var mmioLog: [(offset: UInt32, value: UInt32)] = []
    package private(set) var jitterEnabled = false
    package private(set) var lastBurstBytes = 0

    package init() {}

    /// Model AXI-Stream table DMA: one transaction programs all 10×256 BRAMs.
    package func burstLoadTables(_ wiring: Enigma256Wiring) {
        lastBurstBytes = 10 * 256
        handle.programTablesBurst(wiring)
        mmioLog.append((Enigma256Reg.burstStatus.rawValue, UInt32(lastBurstBytes)))
    }

    package func write32(offset: UInt32, value: UInt32) {
        mmioLog.append((offset, value))
        busy = false
        switch offset {
        case Enigma256Reg.ctrl.rawValue:
            if value & 0x1 != 0 {
                handle.pulseLoadState()
            }
            if value & 0x100 != 0 {
                validOut = false
                dataOut = 0
            }
        case Enigma256Reg.scaCtrl.rawValue:
            jitterEnabled = (value & 1) != 0
        case Enigma256Reg.wrSel.rawValue:
            wrSel = UInt8(truncatingIfNeeded: value & 0xF)
        case Enigma256Reg.wrAddr.rawValue:
            wrAddr = UInt8(truncatingIfNeeded: value & 0xFF)
        case Enigma256Reg.wrData.rawValue:
            let sel = Enigma256TableSel(rawValue: Int(wrSel))!
            handle.writeTableByte(sel: sel, addr: wrAddr, data: UInt8(truncatingIfNeeded: value & 0xFF))
        case Enigma256Reg.initLfsrLo.rawValue:
            let hi = handle.regLFSR & 0xFFFF_FFFF_0000_0000
            handle.regLFSR = hi | UInt64(value)
        case Enigma256Reg.initLfsrHi.rawValue:
            let lo = handle.regLFSR & 0xFFFF_FFFF
            handle.regLFSR = (UInt64(value) << 32) | lo
            if handle.regLFSR == 0 { handle.regLFSR = 1 }
        case Enigma256Reg.initR1.rawValue:
            handle.regPos.0 = UInt8(truncatingIfNeeded: value)
        case Enigma256Reg.initR2.rawValue:
            handle.regPos.1 = UInt8(truncatingIfNeeded: value)
        case Enigma256Reg.initR3.rawValue:
            handle.regPos.2 = UInt8(truncatingIfNeeded: value)
        case Enigma256Reg.initR4.rawValue:
            handle.regPos.3 = UInt8(truncatingIfNeeded: value)
        case Enigma256Reg.dataIn.rawValue:
            dataIn = UInt8(truncatingIfNeeded: value)
            dataOut = handle.transfer(dataIn)
            validOut = true
        default:
            break
        }
    }

    package func read32(offset: UInt32) -> UInt32 {
        switch offset {
        case Enigma256Reg.ctrl.rawValue:
            return busy ? 0x100 : 0
        case Enigma256Reg.wrSel.rawValue:
            return UInt32(wrSel)
        case Enigma256Reg.wrAddr.rawValue:
            return UInt32(wrAddr)
        case Enigma256Reg.initLfsrLo.rawValue:
            return UInt32(truncatingIfNeeded: handle.regLFSR & 0xFFFF_FFFF)
        case Enigma256Reg.initLfsrHi.rawValue:
            return UInt32(truncatingIfNeeded: handle.regLFSR >> 32)
        case Enigma256Reg.initR1.rawValue:
            return UInt32(handle.regPos.0)
        case Enigma256Reg.initR2.rawValue:
            return UInt32(handle.regPos.1)
        case Enigma256Reg.initR3.rawValue:
            return UInt32(handle.regPos.2)
        case Enigma256Reg.initR4.rawValue:
            return UInt32(handle.regPos.3)
        case Enigma256Reg.dataIn.rawValue:
            return UInt32(dataIn)
        case Enigma256Reg.dataOut.rawValue:
            return UInt32(dataOut)
        case Enigma256Reg.status.rawValue:
            return (busy ? 0x2 : 0) | (validOut ? 0x1 : 0)
        case Enigma256Reg.scaCtrl.rawValue:
            return jitterEnabled ? 1 : 0
        case Enigma256Reg.burstStatus.rawValue:
            return UInt32(lastBurstBytes)
        default:
            return 0
        }
    }
}
