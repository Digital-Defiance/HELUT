import Foundation

// MARK: - Scramble bijection / reciprocity sweep
//
// For a frozen machine state the byte scramble must be a permutation of 0…255
// and an involution (encrypt ≡ decrypt). NLFF retaps do not touch this path;
// this gate catches table-builder or datapath corruption (many:1 / 1:many).

package enum Enigma256Bijection {
    package enum Failure: Error, CustomStringConvertible, Sendable {
        case collision(ptA: UInt8, ptB: UInt8, ct: UInt8)
        case notSurjective(missingCT: UInt8)
        case notReciprocal(pt: UInt8, ct: UInt8, back: UInt8)
        case unexpectedFixedPointCount(centerMode: Bool, expected: Int, actual: Int)
        case streamRoundTrip(index: Int, want: UInt8, got: UInt8)

        package var description: String {
            switch self {
            case let .collision(a, b, ct):
                return String(format: "many:1 collision pt %02x and %02x → ct %02x", a, b, ct)
            case let .notSurjective(missing):
                return String(format: "1:many / not surjective — missing ct %02x", missing)
            case let .notReciprocal(pt, ct, back):
                return String(format: "not reciprocal scramble(%02x)=%02x scramble²=%02x", pt, ct, back)
            case let .unexpectedFixedPointCount(mode, expected, actual):
                return "center mode \(mode ? 1 : 0) has \(actual) frozen fixed points; expected \(expected)"
            case let .streamRoundTrip(i, want, got):
                return String(format: "stream round-trip fail @%d want %02x got %02x", i, want, got)
            }
        }
    }

    package struct StateReport: Sendable {
        package var rotorIndices: (Int, Int, Int, Int)
        package var positions: (UInt8, UInt8, UInt8, UInt8)
    }

    package struct SweepReport: Sendable {
        package var statesChecked: Int
        package var streamBytes: Int
        package var elapsedSeconds: Double
        package var failure: Failure?
        package var failedState: StateReport?
    }

    /// Injectivity + surjectivity + reciprocity of `scramble` under a frozen state.
    package static func verifyFrozenScramble(_ machine: Enigma256Machine) -> Failure? {
        var seenCT = [Int](repeating: -1, count: 256)
        var fixedPoints = 0
        for pt in 0 ..< 256 {
            let ct = Int(machine.scramble(UInt8(pt)))
            if ct == pt { fixedPoints += 1 }
            if seenCT[ct] >= 0 {
                return .collision(ptA: UInt8(seenCT[ct]), ptB: UInt8(pt), ct: UInt8(ct))
            }
            seenCT[ct] = pt
            let back = machine.scramble(UInt8(ct))
            if Int(back) != pt {
                return .notReciprocal(pt: UInt8(pt), ct: UInt8(ct), back: back)
            }
        }
        for ct in 0 ..< 256 where seenCT[ct] < 0 {
            return .notSurjective(missingCT: UInt8(ct))
        }
        let expectedFixedPoints = machine.centerMode ? 2 : 0
        if fixedPoints != expectedFixedPoints {
            return .unexpectedFixedPointCount(
                centerMode: machine.centerMode,
                expected: expectedFixedPoints,
                actual: fixedPoints
            )
        }
        return nil
    }

    /// Encrypt then decrypt `streamBytes` under identical initial message state.
    package static func verifyStreamRoundTrip(
        day: Enigma256DayKey,
        message: Enigma256MessageKey,
        streamBytes: Int,
        plaintext: [UInt8]
    ) -> Failure? {
        precondition(plaintext.count == streamBytes)
        var enc = Enigma256Machine(day: day, message: message)
        var dec = Enigma256Machine(day: day, message: message)
        let ct = enc.process(plaintext)
        let pt = dec.process(ct)
        for i in 0 ..< streamBytes where pt[i] != plaintext[i] {
            return .streamRoundTrip(index: i, want: plaintext[i], got: pt[i])
        }
        return nil
    }

    /// One day key, many random Walzenlage + Grundstellung (+ stream round-trip).
    package static func sweep(
        day: Enigma256DayKey,
        states: Int,
        streamBytes: Int = 64,
        seed: UInt64 = 0xE256_B13E,
        onProgress: ((Int) -> Void)? = nil
    ) -> SweepReport {
        precondition(states > 0)
        precondition(streamBytes >= 0)
        var rng = SplitMix64(seed: seed)
        let t0 = DispatchTime.now().uptimeNanoseconds
        var plain = [UInt8](repeating: 0, count: streamBytes)
        for i in 0 ..< streamBytes {
            plain[i] = UInt8(truncatingIfNeeded: rng.next())
        }

        for s in 0 ..< states {
            let rotors = pickFourRotors(rng: &rng)
            let positions: (UInt8, UInt8, UInt8, UInt8) = (
                UInt8(truncatingIfNeeded: rng.next()),
                UInt8(truncatingIfNeeded: rng.next()),
                UInt8(truncatingIfNeeded: rng.next()),
                UInt8(truncatingIfNeeded: rng.next())
            )
            var lfsrSeed = rng.next()
            if lfsrSeed == 0 { lfsrSeed = 1 }
            let message = Enigma256MessageKey(
                rotorIndices: rotors,
                positions: positions,
                lfsrSeed: lfsrSeed
            )
            let machine = Enigma256Machine(day: day, message: message)
            if let fail = verifyFrozenScramble(machine) {
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e9
                return SweepReport(
                    statesChecked: s + 1,
                    streamBytes: streamBytes,
                    elapsedSeconds: elapsed,
                    failure: fail,
                    failedState: StateReport(rotorIndices: rotors, positions: positions)
                )
            }
            if streamBytes > 0, let fail = verifyStreamRoundTrip(
                day: day,
                message: message,
                streamBytes: streamBytes,
                plaintext: plain
            ) {
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e9
                return SweepReport(
                    statesChecked: s + 1,
                    streamBytes: streamBytes,
                    elapsedSeconds: elapsed,
                    failure: fail,
                    failedState: StateReport(rotorIndices: rotors, positions: positions)
                )
            }
            if let onProgress, (s + 1) % 100_000 == 0 {
                onProgress(s + 1)
            }
        }

        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e9
        return SweepReport(
            statesChecked: states,
            streamBytes: streamBytes,
            elapsedSeconds: elapsed,
            failure: nil,
            failedState: nil
        )
    }

    private static func pickFourRotors(rng: inout SplitMix64) -> (Int, Int, Int, Int) {
        var available = Array(0 ..< 16)
        var picked: [Int] = []
        picked.reserveCapacity(4)
        for _ in 0 ..< 4 {
            let idx = Int(rng.next() % UInt64(available.count))
            picked.append(available.remove(at: idx))
        }
        return (picked[0], picked[1], picked[2], picked[3])
    }
}

/// Tiny deterministic RNG for reproducible sweeps (not crypto).
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0xDEAD_BEEF_CAFE_BABE : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
