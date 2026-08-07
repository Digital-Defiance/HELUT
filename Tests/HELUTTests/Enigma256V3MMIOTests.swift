import Foundation
import XCTest
@testable import HELUTCore

final class Enigma256V3MMIOTests: XCTestCase {
    private let profile = Enigma256V3Profile.gen0
    private let dayIKM = Data("E256-v3 fixture-v5 day IKM 0001".utf8)
    private let daySalt = Data("E256-v3 fixture-v5 day salt".utf8)
    private let messageIKM = Data("E256-v3 fixture-v5 message IKM 0001".utf8)
    private let nonce = Data((0 ..< 16).map(UInt8.init))

    private enum FailurePoint: Equatable, CustomStringConvertible {
        case begin
        case table(Int)
        case state
        case commit

        var description: String {
            switch self {
            case .begin: return "begin"
            case let .table(index): return "table[\(index)]"
            case .state: return "state"
            case .commit: return "commit"
            }
        }
    }

    private enum SinkError: Error, Equatable {
        case injected(FailurePoint)
        case protocolViolation
    }

    private enum Event {
        case begin(profileHash: String, centerMaskKey: Data)
        case table(slot: UInt8, address: UInt8, value: UInt8)
        case state(lfsr: UInt64, positions: [UInt8], absoluteByteCounter: UInt64)
        case commit
        case abort
    }

    private struct RecordingSink: Enigma256V3MMIOSink {
        var failurePoint: FailurePoint? = nil
        var events: [Event] = []
        var activeToken = "existing-active-configuration"
        var stagingOpen = false
        var stagedWriteCount = 0
        var tableAttempt = 0
        var abortCount = 0

        mutating func beginConfiguration(
            profileHash: String,
            centerMaskKey: Data
        ) throws {
            if failurePoint == .begin { throw SinkError.injected(.begin) }
            guard !stagingOpen else { throw SinkError.protocolViolation }
            stagingOpen = true
            events.append(.begin(
                profileHash: profileHash,
                centerMaskKey: centerMaskKey
            ))
        }

        mutating func writeTable(
            slot: Enigma256V3TableSlot,
            address: UInt8,
            value: UInt8
        ) throws {
            guard stagingOpen else { throw SinkError.protocolViolation }
            if failurePoint == .table(tableAttempt) {
                throw SinkError.injected(.table(tableAttempt))
            }
            events.append(.table(slot: slot.rawValue, address: address, value: value))
            stagedWriteCount += 1
            tableAttempt += 1
        }

        mutating func loadState(
            lfsr: UInt64,
            positions: [UInt8],
            absoluteByteCounter: UInt64
        ) throws {
            guard stagingOpen else { throw SinkError.protocolViolation }
            if failurePoint == .state { throw SinkError.injected(.state) }
            events.append(.state(
                lfsr: lfsr,
                positions: positions,
                absoluteByteCounter: absoluteByteCounter
            ))
        }

        mutating func commitConfiguration() throws {
            guard stagingOpen else { throw SinkError.protocolViolation }
            if failurePoint == .commit { throw SinkError.injected(.commit) }
            activeToken = "committed-v3-configuration"
            stagingOpen = false
            stagedWriteCount = 0
            events.append(.commit)
        }

        mutating func abortConfiguration() {
            abortCount += 1
            stagingOpen = false
            stagedWriteCount = 0
            events.append(.abort)
        }
    }

    private struct RawConfiguration {
        var declaredProfileHash: String
        var plugboard: [UInt8]
        var r1Fwd: [UInt8]
        var r1Rev: [UInt8]
        var r2Fwd: [UInt8]
        var r2Rev: [UInt8]
        var r3Fwd: [UInt8]
        var r3Rev: [UInt8]
        var r4Fwd: [UInt8]
        var r4Rev: [UInt8]
        var lfsr: UInt64
        var positions: [UInt8]
        var centerMaskKey: Data
        var absoluteByteCounter: UInt64

        init(state: Enigma256V3ValidatedState, absoluteByteCounter: UInt64 = 37) {
            declaredProfileHash = state.profile.profileHashHex
            plugboard = state.wiring.plugboard
            r1Fwd = state.wiring.r1Fwd
            r1Rev = state.wiring.r1Rev
            r2Fwd = state.wiring.r2Fwd
            r2Rev = state.wiring.r2Rev
            r3Fwd = state.wiring.r3Fwd
            r3Rev = state.wiring.r3Rev
            r4Fwd = state.wiring.r4Fwd
            r4Rev = state.wiring.r4Rev
            lfsr = state.message.lfsrSeed
            positions = state.message.positions
            centerMaskKey = state.message.centerMaskKey
            self.absoluteByteCounter = absoluteByteCounter
        }

        func plan(profile: Enigma256V3Profile) throws -> Enigma256V3ConfigurationPlan {
            try Enigma256V3ConfigurationPlan(
                profile: profile,
                declaredProfileHash: declaredProfileHash,
                plugboard: plugboard,
                r1Fwd: r1Fwd, r1Rev: r1Rev,
                r2Fwd: r2Fwd, r2Rev: r2Rev,
                r3Fwd: r3Fwd, r3Rev: r3Rev,
                r4Fwd: r4Fwd, r4Rev: r4Rev,
                lfsr: lfsr,
                positions: positions,
                centerMaskKey: centerMaskKey,
                absoluteByteCounter: absoluteByteCounter
            )
        }
    }

    private func deriveState() throws -> Enigma256V3ValidatedState {
        let day = try Enigma256V3KDF.deriveDayKey(
            ikm: dayIKM,
            salt: daySalt,
            profile: profile
        )
        let message = try Enigma256V3KDF.deriveMessageKey(
            masterIKM: messageIKM,
            nonce: nonce,
            profile: profile
        )
        return try Enigma256V3ValidatedState(
            profile: profile,
            day: day,
            message: message
        )
    }

    private func assertRejectedBeforeMMIO(
        _ raw: RawConfiguration,
        expected: Enigma256V3Error,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var sink = RecordingSink()
        XCTAssertThrowsError(
            try {
                let plan = try raw.plan(profile: profile)
                try plan.program(into: &sink)
            }(),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? Enigma256V3Error, expected, file: file, line: line)
        }
        XCTAssertTrue(sink.events.isEmpty, "rejected ingress reached MMIO", file: file, line: line)
    }

    func testValidPlanWritesNineCompleteTablesThenAtomicallyCommitsState() throws {
        let state = try deriveState()
        let counter: UInt64 = 37
        let plan = try Enigma256V3ConfigurationPlan(
            state: state,
            absoluteByteCounter: counter
        )
        var sink = RecordingSink()

        try plan.program(into: &sink)

        let expectedTables: [(Enigma256V3TableSlot, [UInt8])] = [
            (.plugboard, state.wiring.plugboard),
            (.r1Forward, state.wiring.r1Fwd), (.r1Reverse, state.wiring.r1Rev),
            (.r2Forward, state.wiring.r2Fwd), (.r2Reverse, state.wiring.r2Rev),
            (.r3Forward, state.wiring.r3Fwd), (.r3Reverse, state.wiring.r3Rev),
            (.r4Forward, state.wiring.r4Fwd), (.r4Reverse, state.wiring.r4Rev)
        ]
        XCTAssertEqual(sink.events.count, 2_307)
        guard case let .begin(profileHash, centerMaskKey) = sink.events[0] else {
            return XCTFail("first event was not transaction begin")
        }
        XCTAssertEqual(profileHash, profile.profileHashHex)
        XCTAssertEqual(centerMaskKey, state.message.centerMaskKey)
        for (tableIndex, expected) in expectedTables.enumerated() {
            for address in 0 ..< 256 {
                let eventIndex = 1 + tableIndex * 256 + address
                guard case let .table(slot, actualAddress, value) = sink.events[eventIndex] else {
                    return XCTFail("non-table event before all writes at event \(eventIndex)")
                }
                XCTAssertEqual(slot, expected.0.rawValue, "event \(eventIndex)")
                XCTAssertEqual(actualAddress, UInt8(address), "event \(eventIndex)")
                XCTAssertEqual(value, expected.1[address], "event \(eventIndex)")
            }
        }
        guard case let .state(lfsr, positions, absoluteByteCounter) = sink.events[2_305] else {
            return XCTFail("state was not staged after all table writes")
        }
        XCTAssertEqual(lfsr, state.message.lfsrSeed)
        XCTAssertEqual(positions, state.message.positions)
        XCTAssertEqual(absoluteByteCounter, counter)
        guard case .commit = sink.events[2_306] else {
            return XCTFail("final event was not atomic commit")
        }
        XCTAssertEqual(sink.activeToken, "committed-v3-configuration")
        XCTAssertFalse(sink.stagingOpen)
        XCTAssertEqual(sink.abortCount, 0)
    }

    func testSinkFailureAbortsStagingWithoutReplacingActiveConfiguration() throws {
        let plan = try Enigma256V3ConfigurationPlan(
            state: deriveState(),
            absoluteByteCounter: 37
        )
        let failures: [FailurePoint] = [
            .begin, .table(0), .table(255), .table(256), .table(2_303),
            .state, .commit
        ]

        for failure in failures {
            var sink = RecordingSink(failurePoint: failure)
            XCTAssertThrowsError(try plan.program(into: &sink), failure.description) { error in
                XCTAssertEqual(error as? SinkError, .injected(failure), failure.description)
            }
            XCTAssertEqual(
                sink.activeToken,
                "existing-active-configuration",
                failure.description
            )
            XCTAssertFalse(sink.stagingOpen, failure.description)
            XCTAssertEqual(sink.stagedWriteCount, 0, failure.description)
            XCTAssertEqual(sink.abortCount, 1, failure.description)
            XCTAssertFalse(
                sink.events.contains { event in
                    if case .commit = event { return true }
                    return false
                },
                failure.description
            )
        }
    }

    func testEveryMalformedIngressRejectsBeforeFirstMMIOWrite() throws {
        let state = try deriveState()
        let valid = RawConfiguration(state: state)

        var wrongHash = valid
        wrongHash.declaredProfileHash = String(repeating: "0", count: 64)
        assertRejectedBeforeMMIO(
            wrongHash,
            expected: .invalidProfileHash(
                expected: profile.profileHashHex,
                actual: wrongHash.declaredProfileHash
            )
        )

        var zeroLFSR = valid
        zeroLFSR.lfsr = 0
        assertRejectedBeforeMMIO(zeroLFSR, expected: .zeroLFSRState)

        var shortTable = valid
        shortTable.r2Fwd.removeLast()
        assertRejectedBeforeMMIO(
            shortTable,
            expected: .tableLength(name: "r2_fwd", actual: 255)
        )

        var nonPermutation = valid
        nonPermutation.r1Fwd[1] = nonPermutation.r1Fwd[0]
        assertRejectedBeforeMMIO(nonPermutation, expected: .notPermutation("r1_fwd"))

        var inverseMismatch = valid
        let firstOutput = Int(inverseMismatch.r3Fwd[0])
        let secondOutput = Int(inverseMismatch.r3Fwd[1])
        inverseMismatch.r3Rev.swapAt(firstOutput, secondOutput)
        assertRejectedBeforeMMIO(
            inverseMismatch,
            expected: .rotorPairNotInverse(rotor: 3, index: 0)
        )

        var fixedPointPlugboard = valid
        fixedPointPlugboard.plugboard = (0 ... 255).map(UInt8.init)
        assertRejectedBeforeMMIO(
            fixedPointPlugboard,
            expected: .plugboardFixedPoint(index: 0)
        )

        var wrongPositions = valid
        wrongPositions.positions.removeLast()
        assertRejectedBeforeMMIO(
            wrongPositions,
            expected: .tableLength(name: "positions", actual: 3)
        )

        var wrongKeyLength = valid
        wrongKeyLength.centerMaskKey.removeLast()
        assertRejectedBeforeMMIO(
            wrongKeyLength,
            expected: .centerMaskKeyLength(actual: 31)
        )

        var exhaustedCounter = valid
        exhaustedCounter.absoluteByteCounter = UInt64.max
        assertRejectedBeforeMMIO(exhaustedCounter, expected: .counterExhausted)
    }
}
