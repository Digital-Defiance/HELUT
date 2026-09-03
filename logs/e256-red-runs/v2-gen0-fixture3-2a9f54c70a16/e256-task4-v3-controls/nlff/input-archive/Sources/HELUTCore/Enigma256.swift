import CryptoKit
import Foundation

// MARK: - Enigma 256 (base-256 polymorphic stream cipher)
//
// Software oracle matching `enigma_256_core.v` + HKDF day/message keying from Enigma256.md.
// TensorLUT melt is intentionally out of scope until golden vectors exist.

/// 64-bit right-shift Galois LFSR using LSB feedback and mask
/// `0xD800_0000_0000_0000` (polynomial taps 64, 63, 61, 60).
package struct Enigma256LFSR: Sendable, Equatable {
    package static let feedbackMask: UInt64 = 0xD800_0000_0000_0000

    package var state: UInt64

    package init(seed: UInt64) {
        self.state = seed
    }

    /// Next state after one clock (does not mutate).
    package var next: UInt64 {
        let feedback = state & 1
        return (state >> 1) ^ (feedback == 0 ? 0 : Self.feedbackMask)
    }

    /// Unique state that precedes `state` under the invertible transition.
    package var previous: UInt64 {
        let feedback = state >> 63
        let unmasked = state ^ (feedback == 0 ? 0 : Self.feedbackMask)
        return (unmasked << 1) | feedback
    }

    package mutating func clock() {
        state = next
    }

    /// Stepping triggers via the selected native NLFF profile.
    package var stepMask: (Bool, Bool, Bool, Bool) {
        stepMask(using: Enigma256Generation.v2Gen0)
    }

    package func stepMask(using generation: Enigma256Generation) -> (Bool, Bool, Bool, Bool) {
        generation.stepMask(state: state)
    }
}

/// Validation failures for active tables before they enter a machine state.
package enum Enigma256WiringValidationError: Error, Equatable {
    case tableLength(name: String, actual: Int)
    case notPermutation(String)
    case plugboardNotInvolution(index: Int)
    case rotorPairNotInverse(rotor: Int, index: Int)
    case reflectorNotInvolution(index: Int)
    case reflectorFixedPoint(Int)
    case reflectorReservedPair
}

/// Active slot wiring loaded into the FPGA core (4 rotors + plugboard + base reflector).
package struct Enigma256Wiring: Sendable, Equatable {
    /// Full-spectrum plugboard involution (256 entries).
    package var plugboard: [UInt8]
    package var r1Fwd: [UInt8]
    package var r1Rev: [UInt8]
    package var r2Fwd: [UInt8]
    package var r2Rev: [UInt8]
    package var r3Fwd: [UInt8]
    package var r3Rev: [UInt8]
    package var r4Fwd: [UInt8]
    package var r4Rev: [UInt8]
    /// Fixed-point-free base involution with the reserved transposition 0 ↔ 1.
    package var reflector: [UInt8]

    package init(
        plugboard: [UInt8],
        r1Fwd: [UInt8], r1Rev: [UInt8],
        r2Fwd: [UInt8], r2Rev: [UInt8],
        r3Fwd: [UInt8], r3Rev: [UInt8],
        r4Fwd: [UInt8], r4Rev: [UInt8],
        reflector: [UInt8]
    ) {
        precondition(plugboard.count == 256)
        precondition(r1Fwd.count == 256 && r1Rev.count == 256)
        precondition(r2Fwd.count == 256 && r2Rev.count == 256)
        precondition(r3Fwd.count == 256 && r3Rev.count == 256)
        precondition(r4Fwd.count == 256 && r4Rev.count == 256)
        precondition(reflector.count == 256)
        self.plugboard = plugboard
        self.r1Fwd = r1Fwd; self.r1Rev = r1Rev
        self.r2Fwd = r2Fwd; self.r2Rev = r2Rev
        self.r3Fwd = r3Fwd; self.r3Rev = r3Rev
        self.r4Fwd = r4Fwd; self.r4Rev = r4Rev
        self.reflector = reflector
    }

    /// Validate the complete committed table set. Staging writers may be
    /// transiently invalid, but no machine may be built until this succeeds.
    package func validate() throws {
        let tables: [(String, [UInt8])] = [
            ("plugboard", plugboard),
            ("r1_fwd", r1Fwd), ("r1_rev", r1Rev),
            ("r2_fwd", r2Fwd), ("r2_rev", r2Rev),
            ("r3_fwd", r3Fwd), ("r3_rev", r3Rev),
            ("r4_fwd", r4Fwd), ("r4_rev", r4Rev),
            ("reflector", reflector)
        ]
        for (name, table) in tables {
            guard table.count == 256 else {
                throw Enigma256WiringValidationError.tableLength(name: name, actual: table.count)
            }
            guard Set(table).count == 256 else {
                throw Enigma256WiringValidationError.notPermutation(name)
            }
        }

        for i in 0 ..< 256 where Int(plugboard[Int(plugboard[i])]) != i {
            throw Enigma256WiringValidationError.plugboardNotInvolution(index: i)
        }

        let rotorPairs = [(r1Fwd, r1Rev), (r2Fwd, r2Rev), (r3Fwd, r3Rev), (r4Fwd, r4Rev)]
        for (rotor, pair) in rotorPairs.enumerated() {
            for i in 0 ..< 256 where Int(pair.1[Int(pair.0[i])]) != i || Int(pair.0[Int(pair.1[i])]) != i {
                throw Enigma256WiringValidationError.rotorPairNotInverse(rotor: rotor + 1, index: i)
            }
        }

        for i in 0 ..< 256 {
            let reflected = Int(reflector[i])
            guard Int(reflector[reflected]) == i else {
                throw Enigma256WiringValidationError.reflectorNotInvolution(index: i)
            }
            guard reflected != i else {
                throw Enigma256WiringValidationError.reflectorFixedPoint(i)
            }
        }
        guard reflector[0] == 1, reflector[1] == 0 else {
            throw Enigma256WiringValidationError.reflectorReservedPair
        }
    }

    /// Identity outer tables plus the canonical fixed-point-free base center.
    /// This remains useful for datapath/LFSR tests but is not an identity cipher.
    package static var identity: Enigma256Wiring {
        let id = [UInt8](0 ... 255)
        let baseCenter = (0 ... 255).map { UInt8($0 ^ 1) }
        return Enigma256Wiring(
            plugboard: id,
            r1Fwd: id, r1Rev: id,
            r2Fwd: id, r2Rev: id,
            r3Fwd: id, r3Rev: id,
            r4Fwd: id, r4Rev: id,
            reflector: baseCenter
        )
    }
}

/// Position-dependent reciprocal center bound by the schema-3 profile.
package enum Enigma256Center {
    package static func mode(mask: (Bool, Bool, Bool, Bool)) -> Bool {
        (mask.0 != mask.1) != (mask.2 != mask.3)
    }

    package static func apply(_ input: UInt8, baseReflector: [UInt8], mode: Bool) -> UInt8 {
        precondition(baseReflector.count == 256)
        if mode, input < 2 { return input }
        return baseReflector[Int(input)]
    }
}

/// Day-key blueprint: 16-rotor virtual pool + plugboard + reflector.
package struct Enigma256DayKey: Sendable, Equatable {
    package var plugboard: [UInt8]
    /// 16 distinct 256-byte forward wirings.
    package var rotorPoolFwd: [[UInt8]]
    package var rotorPoolRev: [[UInt8]]
    package var reflector: [UInt8]

    package init(plugboard: [UInt8], rotorPoolFwd: [[UInt8]], rotorPoolRev: [[UInt8]], reflector: [UInt8]) {
        precondition(plugboard.count == 256)
        precondition(rotorPoolFwd.count == 16 && rotorPoolRev.count == 16)
        precondition(reflector.count == 256)
        self.plugboard = plugboard
        self.rotorPoolFwd = rotorPoolFwd
        self.rotorPoolRev = rotorPoolRev
        self.reflector = reflector
    }
}

/// Per-message Walzenlage + LFSR seed (derived from nonce ∥ master).
package struct Enigma256MessageKey: Sendable, Equatable {
    /// Indices into the 16-rotor day pool (order = active R1…R4).
    package var rotorIndices: (Int, Int, Int, Int)
    package var positions: (UInt8, UInt8, UInt8, UInt8)
    package var lfsrSeed: UInt64

    package init(
        rotorIndices: (Int, Int, Int, Int),
        positions: (UInt8, UInt8, UInt8, UInt8),
        lfsrSeed: UInt64
    ) {
        for i in [rotorIndices.0, rotorIndices.1, rotorIndices.2, rotorIndices.3] {
            precondition((0 ..< 16).contains(i))
        }
        self.rotorIndices = rotorIndices
        self.positions = positions
        self.lfsrSeed = lfsrSeed
    }

    package static func == (lhs: Enigma256MessageKey, rhs: Enigma256MessageKey) -> Bool {
        lhs.rotorIndices.0 == rhs.rotorIndices.0
            && lhs.rotorIndices.1 == rhs.rotorIndices.1
            && lhs.rotorIndices.2 == rhs.rotorIndices.2
            && lhs.rotorIndices.3 == rhs.rotorIndices.3
            && lhs.positions.0 == rhs.positions.0
            && lhs.positions.1 == rhs.positions.1
            && lhs.positions.2 == rhs.positions.2
            && lhs.positions.3 == rhs.positions.3
            && lhs.lfsrSeed == rhs.lfsrSeed
    }

    package func wiring(from day: Enigma256DayKey) -> Enigma256Wiring {
        let i = rotorIndices
        return Enigma256Wiring(
            plugboard: day.plugboard,
            r1Fwd: day.rotorPoolFwd[i.0], r1Rev: day.rotorPoolRev[i.0],
            r2Fwd: day.rotorPoolFwd[i.1], r2Rev: day.rotorPoolRev[i.1],
            r3Fwd: day.rotorPoolFwd[i.2], r3Rev: day.rotorPoolRev[i.2],
            r4Fwd: day.rotorPoolFwd[i.3], r4Rev: day.rotorPoolRev[i.3],
            reflector: day.reflector
        )
    }
}

/// One accepted byte's complete schema-3 state transition. This is a KAT/co-sim
/// surface, not an additional wire-format or security claim.
package struct Enigma256ByteTrace: Sendable, Equatable {
    package let input: UInt8
    package let output: UInt8
    package let lfsrBefore: UInt64
    package let lfsrAfter: UInt64
    package let offsetR1Before: UInt8
    package let offsetR2Before: UInt8
    package let offsetR3Before: UInt8
    package let offsetR4Before: UInt8
    package let offsetR1After: UInt8
    package let offsetR2After: UInt8
    package let offsetR3After: UInt8
    package let offsetR4After: UInt8
    /// Bit 0 is R1, …, bit 3 is R4.
    package let stepMaskBits: UInt8
    package let centerMode: Bool
    package let centerInput: UInt8
    package let centerOutput: UInt8
}

/// Byte-oriented Enigma 256 state machine (encrypt ≡ decrypt; step after each byte).
package struct Enigma256Machine: Sendable {
    package let wiring: Enigma256Wiring
    package let generation: Enigma256Generation
    package var lfsr: Enigma256LFSR
    package var offsetR1: UInt8
    package var offsetR2: UInt8
    package var offsetR3: UInt8
    package var offsetR4: UInt8

    package init(
        wiring: Enigma256Wiring,
        lfsrSeed: UInt64,
        positions: (UInt8, UInt8, UInt8, UInt8),
        generation: Enigma256Generation = .v2Gen0
    ) {
        precondition((try? wiring.validate()) != nil, "invalid E256 wiring")
        precondition((try? generation.validate()) != nil, "invalid E256 generation")
        self.wiring = wiring
        self.generation = generation
        self.lfsr = Enigma256LFSR(seed: lfsrSeed)
        self.offsetR1 = positions.0
        self.offsetR2 = positions.1
        self.offsetR3 = positions.2
        self.offsetR4 = positions.3
    }

    package init(
        day: Enigma256DayKey,
        message: Enigma256MessageKey,
        generation: Enigma256Generation = .v2Gen0
    ) {
        self.init(
            wiring: message.wiring(from: day),
            lfsrSeed: message.lfsrSeed,
            positions: message.positions,
            generation: generation
        )
    }

    package var currentStepMask: (Bool, Bool, Bool, Bool) {
        lfsr.stepMask(using: generation)
    }

    package var centerMode: Bool {
        Enigma256Center.mode(mask: currentStepMask)
    }

    /// Scramble under the current state, then step with that exact pre-step mask.
    package mutating func process(_ input: UInt8) -> UInt8 {
        processTraced(input).output
    }

    package mutating func process(_ bytes: [UInt8]) -> [UInt8] {
        bytes.map { process($0) }
    }

    /// One accepted-byte trace for long-form Swift/RTL state parity.
    package mutating func processTraced(_ input: UInt8) -> Enigma256ByteTrace {
        let lfsrBefore = lfsr.state
        let before = (offsetR1, offsetR2, offsetR3, offsetR4)
        let mask = currentStepMask
        let mode = Enigma256Center.mode(mask: mask)
        let result = scrambleResult(input, centerMode: mode)
        let maskBits = UInt8(mask.0 ? 1 : 0)
            | UInt8(mask.1 ? 2 : 0)
            | UInt8(mask.2 ? 4 : 0)
            | UInt8(mask.3 ? 8 : 0)
        step(mask: mask)
        return Enigma256ByteTrace(
            input: input,
            output: result.output,
            lfsrBefore: lfsrBefore,
            lfsrAfter: lfsr.state,
            offsetR1Before: before.0,
            offsetR2Before: before.1,
            offsetR3Before: before.2,
            offsetR4Before: before.3,
            offsetR1After: offsetR1,
            offsetR2After: offsetR2,
            offsetR3After: offsetR3,
            offsetR4After: offsetR4,
            stepMaskBits: maskBits,
            centerMode: mode,
            centerInput: result.centerInput,
            centerOutput: result.centerOutput
        )
    }

    /// Combinational scrambler only (no step) — for Verilog parity on a frozen state.
    package func scramble(_ input: UInt8) -> UInt8 {
        scrambleResult(input, centerMode: centerMode).output
    }

    /// Frozen-state scramble with an explicit center branch for exhaustive checks.
    package func scramble(_ input: UInt8, centerMode: Bool) -> UInt8 {
        scrambleResult(input, centerMode: centerMode).output
    }

    private func scrambleResult(
        _ input: UInt8,
        centerMode: Bool
    ) -> (output: UInt8, centerInput: UInt8, centerOutput: UInt8) {
        let pbIn = wiring.plugboard[Int(input)]

        let r1In = pbIn &+ offsetR1
        let r1Out = wiring.r1Fwd[Int(r1In)] &- offsetR1

        let r2In = r1Out &+ offsetR2
        let r2Out = wiring.r2Fwd[Int(r2In)] &- offsetR2

        let r3In = r2Out &+ offsetR3
        let r3Out = wiring.r3Fwd[Int(r3In)] &- offsetR3

        let r4In = r3Out &+ offsetR4
        let r4Out = wiring.r4Fwd[Int(r4In)] &- offsetR4

        let refOut = Enigma256Center.apply(
            r4Out,
            baseReflector: wiring.reflector,
            mode: centerMode
        )

        let r4InRev = refOut &+ offsetR4
        let r4OutRev = wiring.r4Rev[Int(r4InRev)] &- offsetR4

        let r3InRev = r4OutRev &+ offsetR3
        let r3OutRev = wiring.r3Rev[Int(r3InRev)] &- offsetR3

        let r2InRev = r3OutRev &+ offsetR2
        let r2OutRev = wiring.r2Rev[Int(r2InRev)] &- offsetR2

        let r1InRev = r2OutRev &+ offsetR1
        let r1OutRev = wiring.r1Rev[Int(r1InRev)] &- offsetR1

        return (
            wiring.plugboard[Int(r1OutRev)],
            centerInput: r4Out,
            centerOutput: refOut
        )
    }

    package mutating func step() {
        step(mask: currentStepMask)
    }

    package mutating func step(mask: (Bool, Bool, Bool, Bool)) {
        if mask.0 { offsetR1 &+= 1 }
        if mask.1 { offsetR2 &+= 1 }
        if mask.2 { offsetR3 &+= 1 }
        if mask.3 { offsetR4 &+= 1 }
        lfsr.clock()
    }
}

// MARK: - Key derivation (HKDF-SHA512)

package enum Enigma256KDF {
    /// Domain-separated labels (v2 = SHA-512 OKM; v1 was SHA-256).
    package static let dayInfo = Data("enigma256-day-v2".utf8)
    package static let messageInfo = Data("enigma256-msg-v2".utf8)

    /// Bytes consumed from the day-key OKM (Fisher–Yates entropy + tables).
    package static let dayOKMLength = 512 + (16 * 512) + 512 // plug + 16 rotors + reflector

    /// Derive the heavy day-key blueprint from IKM (ECDH secret, Argon2 output, …).
    /// Default `info` follows the live Blue generation (Apple Silicon SoftBus field).
    package static func deriveDayKey(
        ikm: Data,
        salt: Data = Data(),
        info: Data? = nil
    ) -> Enigma256DayKey {
        let info = info ?? Enigma256Generation.v2Gen0.dayInfo
        let okm = hkdf(ikm: ikm, salt: salt, info: info, length: dayOKMLength)
        var cursor = 0
        func take(_ n: Int) -> Data {
            let slice = okm[cursor ..< (cursor + n)]
            cursor += n
            return Data(slice)
        }

        let plugboard = involution(from: take(512), allowFixedPoints: false)
        var fwdPool: [[UInt8]] = []
        var revPool: [[UInt8]] = []
        fwdPool.reserveCapacity(16)
        revPool.reserveCapacity(16)
        for _ in 0 ..< 16 {
            let (fwd, rev) = permutationAndInverse(from: take(512))
            fwdPool.append(fwd)
            revPool.append(rev)
        }
        let reflector = fixedPointFreeReflector(from: take(512))
        precondition(cursor == dayOKMLength)
        return Enigma256DayKey(
            plugboard: plugboard,
            rotorPoolFwd: fwdPool,
            rotorPoolRev: revPool,
            reflector: reflector
        )
    }

    /// Derive Walzenlage + Grundstellung + LFSR seed for one nonce.
    package static func deriveMessageKey(
        masterIKM: Data,
        nonce: Data,
        info: Data? = nil
    ) -> Enigma256MessageKey {
        let info = info ?? Enigma256Generation.v2Gen0.messageInfo
        // Salt with the public nonce so each message gets a fresh micro-stream.
        let okm = hkdf(ikm: masterIKM, salt: nonce, info: info, length: 16)
        let bytes = [UInt8](okm)

        var available = Array(0 ..< 16)
        var picked: [Int] = []
        for i in 0 ..< 4 {
            let idx = Int(bytes[i]) % available.count
            picked.append(available.remove(at: idx))
        }

        let positions: (UInt8, UInt8, UInt8, UInt8) = (bytes[4], bytes[5], bytes[6], bytes[7])
        var seed: UInt64 = 0
        for i in 0 ..< 8 {
            seed |= UInt64(bytes[8 + i]) << (8 * i)
        }
        // LFSR all-zero lockup → force a non-zero seed.
        if seed == 0 { seed = 1 }

        return Enigma256MessageKey(
            rotorIndices: (picked[0], picked[1], picked[2], picked[3]),
            positions: positions,
            lfsrSeed: seed
        )
    }

    package static func hkdf(ikm: Data, salt: Data, info: Data, length: Int) -> Data {
        // RFC 5869: L ≤ 255·HashLen. CryptoKit traps above that; chunk via distinct info labels.
        let hashLen = 64 // SHA-512
        let maxChunk = 255 * hashLen
        precondition(length > 0)
        let key = SymmetricKey(data: ikm)
        if length <= maxChunk {
            return HKDF<SHA512>.deriveKey(
                inputKeyMaterial: key,
                salt: salt,
                info: info,
                outputByteCount: length
            ).withUnsafeBytes { Data($0) }
        }
        var out = Data()
        out.reserveCapacity(length)
        var chunkIndex: UInt32 = 0
        while out.count < length {
            let need = min(maxChunk, length - out.count)
            var chunkInfo = info
            chunkInfo.append(contentsOf: withUnsafeBytes(of: chunkIndex.bigEndian) { Array($0) })
            let piece = HKDF<SHA512>.deriveKey(
                inputKeyMaterial: key,
                salt: salt,
                info: chunkInfo,
                outputByteCount: need
            ).withUnsafeBytes { Data($0) }
            out.append(piece)
            chunkIndex += 1
        }
        return out
    }

    // MARK: Deterministic table builders

    /// Fisher–Yates driven by successive big-endian u16s from `entropy`.
    package static func fisherYatesOrder(count: Int, entropy: Data) -> [Int] {
        precondition(entropy.count >= count * 2)
        var items = Array(0 ..< count)
        var offset = 0
        for i in stride(from: count - 1, through: 1, by: -1) {
            let rnd = (Int(entropy[offset]) << 8) | Int(entropy[offset + 1])
            offset += 2
            let j = rnd % (i + 1)
            items.swapAt(i, j)
        }
        return items
    }

    package static func involution(from entropy: Data, allowFixedPoints: Bool) -> [UInt8] {
        let order = fisherYatesOrder(count: 256, entropy: entropy)
        var table = [UInt8](repeating: 0, count: 256)
        var i = 0
        while i < 256 {
            if allowFixedPoints, i + 1 < 256, entropy[i % entropy.count] & 1 == 0 {
                // Fixed point.
                let a = order[i]
                table[a] = UInt8(a)
                i += 1
                continue
            }
            if i + 1 >= 256 {
                let a = order[i]
                table[a] = UInt8(a)
                break
            }
            let a = order[i]
            let b = order[i + 1]
            table[a] = UInt8(b)
            table[b] = UInt8(a)
            i += 2
        }
        return table
    }

    /// Deterministic fixed-point-free base reflector. The transposition 0 ↔ 1
    /// is reserved so center mode one can replace only that pair with two
    /// fixed points while preserving an involution.
    package static func fixedPointFreeReflector(from entropy: Data) -> [UInt8] {
        let order = fisherYatesOrder(count: 254, entropy: entropy).map { $0 + 2 }
        var table = [UInt8](repeating: 0, count: 256)
        table[0] = 1
        table[1] = 0
        for i in stride(from: 0, to: order.count, by: 2) {
            let a = order[i]
            let b = order[i + 1]
            table[a] = UInt8(b)
            table[b] = UInt8(a)
        }
        return table
    }

    package static func permutationAndInverse(from entropy: Data) -> (fwd: [UInt8], rev: [UInt8]) {
        let order = fisherYatesOrder(count: 256, entropy: entropy)
        var fwd = [UInt8](repeating: 0, count: 256)
        var rev = [UInt8](repeating: 0, count: 256)
        for (src, dst) in order.enumerated() {
            fwd[src] = UInt8(dst)
            rev[dst] = UInt8(src)
        }
        return (fwd, rev)
    }
}
