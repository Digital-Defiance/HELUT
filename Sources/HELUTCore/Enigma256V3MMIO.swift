import Foundation

/// Frozen table-slot numbering shared with the hand RTL. A v3 configuration
/// plan is fully validated before any sink receives its first write.
package enum Enigma256V3TableSlot: UInt8, CaseIterable, Sendable {
    case plugboard = 0
    case r1Forward = 1
    case r1Reverse = 2
    case r2Forward = 3
    case r2Reverse = 4
    case r3Forward = 5
    case r3Reverse = 6
    case r4Forward = 7
    case r4Reverse = 8
}

package protocol Enigma256V3MMIOSink {
    /// Begin a failure-atomic configuration transaction against an inactive
    /// table/state bank and quiesce payload traffic. A thrown operation must
    /// leave the active configuration unchanged after `abortConfiguration()`.
    mutating func beginConfiguration(
        profileHash: String,
        centerMaskKey: Data
    ) throws

    mutating func writeTable(
        slot: Enigma256V3TableSlot,
        address: UInt8,
        value: UInt8
    ) throws

    /// Stage state in the inactive transaction; this must not activate it.
    mutating func loadState(
        lfsr: UInt64,
        positions: [UInt8],
        absoluteByteCounter: UInt64
    ) throws

    /// Atomically replace tables, state, profile binding, and host mask key.
    /// If this throws, activation must not have occurred.
    mutating func commitConfiguration() throws

    /// Discard all staged writes. This operation must be idempotent and must
    /// never activate a partially programmed configuration.
    mutating func abortConfiguration()
}

package struct Enigma256V3ConfigurationPlan: Sendable, Equatable {
    package let profileHash: String
    package let wiring: Enigma256V3Wiring
    package let lfsr: UInt64
    package let positions: [UInt8]
    package let centerMaskKey: Data
    package let absoluteByteCounter: UInt64

    /// Throwing raw ingress. No precondition, zero coercion, table remapping, or
    /// MMIO side effect is permitted while this initializer runs.
    package init(
        profile: Enigma256V3Profile,
        declaredProfileHash: String,
        plugboard: [UInt8],
        r1Fwd: [UInt8], r1Rev: [UInt8],
        r2Fwd: [UInt8], r2Rev: [UInt8],
        r3Fwd: [UInt8], r3Rev: [UInt8],
        r4Fwd: [UInt8], r4Rev: [UInt8],
        lfsr: UInt64,
        positions: [UInt8],
        centerMaskKey: Data,
        absoluteByteCounter: UInt64
    ) throws {
        guard declaredProfileHash == profile.profileHashHex else {
            throw Enigma256V3Error.invalidProfileHash(
                expected: profile.profileHashHex,
                actual: declaredProfileHash
            )
        }
        guard lfsr != 0 else { throw Enigma256V3Error.zeroLFSRState }
        guard positions.count == 4 else {
            throw Enigma256V3Error.tableLength(name: "positions", actual: positions.count)
        }
        guard centerMaskKey.count == Enigma256V3Profile.centerMaskKeyLength else {
            throw Enigma256V3Error.centerMaskKeyLength(actual: centerMaskKey.count)
        }
        guard absoluteByteCounter != UInt64.max else {
            throw Enigma256V3Error.counterExhausted
        }
        let wiring = try Enigma256V3Wiring(
            profile: profile,
            plugboard: plugboard,
            r1Fwd: r1Fwd, r1Rev: r1Rev,
            r2Fwd: r2Fwd, r2Rev: r2Rev,
            r3Fwd: r3Fwd, r3Rev: r3Rev,
            r4Fwd: r4Fwd, r4Rev: r4Rev
        )
        self.profileHash = profile.profileHashHex
        self.wiring = wiring
        self.lfsr = lfsr
        self.positions = positions
        self.centerMaskKey = centerMaskKey
        self.absoluteByteCounter = absoluteByteCounter
    }

    package init(
        state: Enigma256V3ValidatedState,
        absoluteByteCounter: UInt64 = 0
    ) throws {
        try self.init(
            profile: state.profile,
            declaredProfileHash: state.profile.profileHashHex,
            plugboard: state.wiring.plugboard,
            r1Fwd: state.wiring.r1Fwd, r1Rev: state.wiring.r1Rev,
            r2Fwd: state.wiring.r2Fwd, r2Rev: state.wiring.r2Rev,
            r3Fwd: state.wiring.r3Fwd, r3Rev: state.wiring.r3Rev,
            r4Fwd: state.wiring.r4Fwd, r4Rev: state.wiring.r4Rev,
            lfsr: state.message.lfsrSeed,
            positions: state.message.positions,
            centerMaskKey: state.message.centerMaskKey,
            absoluteByteCounter: absoluteByteCounter
        )
    }

    package func program<Sink: Enigma256V3MMIOSink>(
        into sink: inout Sink
    ) throws {
        let tables: [(Enigma256V3TableSlot, [UInt8])] = [
            (.plugboard, wiring.plugboard),
            (.r1Forward, wiring.r1Fwd), (.r1Reverse, wiring.r1Rev),
            (.r2Forward, wiring.r2Fwd), (.r2Reverse, wiring.r2Rev),
            (.r3Forward, wiring.r3Fwd), (.r3Reverse, wiring.r3Rev),
            (.r4Forward, wiring.r4Fwd), (.r4Reverse, wiring.r4Rev)
        ]
        do {
            try sink.beginConfiguration(
                profileHash: profileHash,
                centerMaskKey: centerMaskKey
            )
            for (slot, table) in tables {
                for address in 0 ..< 256 {
                    try sink.writeTable(
                        slot: slot,
                        address: UInt8(address),
                        value: table[address]
                    )
                }
            }
            try sink.loadState(
                lfsr: lfsr,
                positions: positions,
                absoluteByteCounter: absoluteByteCounter
            )
            try sink.commitConfiguration()
        } catch {
            sink.abortConfiguration()
            throw error
        }
    }
}
