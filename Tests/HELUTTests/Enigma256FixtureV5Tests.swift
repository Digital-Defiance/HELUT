import CryptoKit
import Foundation
import XCTest
@testable import HELUTCore

final class Enigma256FixtureV5Tests: XCTestCase {
    private let profile = Enigma256V3Profile.gen0
    private let dayIKM = Data("E256-v3 fixture-v5 day IKM 0001".utf8)
    private let daySalt = Data("E256-v3 fixture-v5 day salt".utf8)
    private let messageIKM = Data("E256-v3 fixture-v5 message IKM 0001".utf8)
    private let nonce = Data((0 ..< 16).map(UInt8.init))

    private func bundle() throws -> Enigma256FixtureV5Bundle {
        try Enigma256FixtureV5Codec.makeBundle(
            profile: profile,
            dayIKM: dayIKM,
            daySalt: daySalt,
            messageIKM: messageIKM,
            nonce: nonce
        )
    }

    private func temporaryDirectory(_ suffix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("helut-e256-v3-\(suffix)-\(UUID().uuidString)")
    }

    private func withWrittenBundle<T>(
        _ body: (URL, Enigma256FixtureV5Bundle) throws -> T
    ) throws -> T {
        let directory = temporaryDirectory("fixture-v5")
        defer { try? FileManager.default.removeItem(at: directory) }
        let value = try bundle()
        try Enigma256FixtureV5Codec.write(value, to: directory)
        return try body(directory, value)
    }

    private func manifestURL(_ directory: URL) -> URL {
        directory.appendingPathComponent(Enigma256FixtureV5Codec.manifestName)
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func filesRecursively(_ directory: URL) throws -> [String: Data] {
        let manager = FileManager.default
        var result: [String: Data] = [:]
        for subpath in try manager.subpathsOfDirectory(atPath: directory.path) {
            let url = directory.appendingPathComponent(subpath)
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if !isDirectory.boolValue {
                result[subpath] = try Data(contentsOf: url)
            }
        }
        return result
    }

    func testFixtureV5RoundTripRederivesEverything() throws {
        try withWrittenBundle { directory, value in
            let report = try Enigma256FixtureV5Codec.verify(at: directory, profile: profile)
            XCTAssertEqual(
                report.profileSHA256,
                "0206c00e5084ebafe1f841708d2af3f4a029bcf160f7b22ed63bb5078d376e16"
            )
            XCTAssertEqual(report.compatibilityKey, profile.compatibilityKey)
            XCTAssertEqual(report.streamBytes, 1_024)
            XCTAssertEqual(report.artifactCount, 26)
            XCTAssertEqual(report.recurrenceBasisCount, 64)
            XCTAssertEqual(report.negativeVectorDeclarationCount, 13)
            XCTAssertTrue(report.reciprocalDecryptVerified)
            XCTAssertEqual(value.fixture.streamKAT.stateCheckpoints.map(\.byte), [0, 1, 2, 58, 59, 60, 64, 128, 1_024])
            XCTAssertEqual(value.fixture.recurrenceVectors.checkpoints.map(\.clock), [0, 1, 2, 58, 59, 60, 64, 128, 1_024])
        }
    }

    func testFixtureV5RegenerationIsByteDeterministic() throws {
        let first = temporaryDirectory("determinism-a")
        let second = temporaryDirectory("determinism-b")
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        try Enigma256FixtureV5Codec.write(try bundle(), to: first)
        try Enigma256FixtureV5Codec.write(try bundle(), to: second)
        let firstFiles = try filesRecursively(first)
        let secondFiles = try filesRecursively(second)
        XCTAssertEqual(firstFiles, secondFiles)
    }

    func testStrictManifestRejectsDuplicateAndUnknownKeys() throws {
        try withWrittenBundle { directory, _ in
            let url = manifestURL(directory)
            let original = try XCTUnwrap(String(data: Data(contentsOf: url), encoding: .utf8))

            let duplicate = original.replacingOccurrences(
                of: "{\n",
                with: "{\n  \"schema\" : null,\n",
                options: [],
                range: original.startIndex ..< original.index(original.startIndex, offsetBy: 2)
            )
            try Data(duplicate.utf8).write(to: url)
            XCTAssertThrowsError(try Enigma256FixtureV5Codec.verify(at: directory, profile: profile)) { error in
                guard case Enigma256V3FixtureError.duplicateJSONKey(path: "$", key: "schema") = error else {
                    return XCTFail("unexpected error: \(error)")
                }
            }

            let unknown = original.replacingOccurrences(
                of: "{\n",
                with: "{\n  \"unknown\" : 0,\n",
                options: [],
                range: original.startIndex ..< original.index(original.startIndex, offsetBy: 2)
            )
            try Data(unknown.utf8).write(to: url)
            XCTAssertThrowsError(try Enigma256FixtureV5Codec.verify(at: directory, profile: profile)) { error in
                guard case Enigma256V3FixtureError.unknownJSONKey(path: "$", key: "unknown") = error else {
                    return XCTFail("unexpected error: \(error)")
                }
            }
        }
    }

    func testStrictManifestRejectsNonCanonicalJSONAndUppercaseHex() throws {
        try withWrittenBundle { directory, _ in
            let url = manifestURL(directory)
            let original = try XCTUnwrap(String(data: Data(contentsOf: url), encoding: .utf8))

            try Data((" " + original).utf8).write(to: url)
            XCTAssertThrowsError(try Enigma256FixtureV5Codec.verify(at: directory, profile: profile)) { error in
                XCTAssertEqual(error as? Enigma256V3FixtureError, .nonCanonicalJSON)
            }

            let uppercaseNonce = original.replacingOccurrences(
                of: "000102030405060708090a0b0c0d0e0f",
                with: "000102030405060708090A0B0C0D0E0F"
            )
            XCTAssertNotEqual(uppercaseNonce, original)
            try Data(uppercaseNonce.utf8).write(to: url)
            XCTAssertThrowsError(try Enigma256FixtureV5Codec.verify(at: directory, profile: profile)) { error in
                guard case Enigma256V3FixtureError.invalidHex(field: "inputs.nonce_hex") = error else {
                    return XCTFail("unexpected error: \(error)")
                }
            }
        }
    }

    func testArtifactHashAndDuplicateFormatMismatchReject() throws {
        try withWrittenBundle { directory, _ in
            let plaintext = directory.appendingPathComponent("artifacts/plaintext.bin")
            var data = try Data(contentsOf: plaintext)
            data[0] ^= 1
            try data.write(to: plaintext)
            XCTAssertThrowsError(try Enigma256FixtureV5Codec.verify(at: directory, profile: profile)) { error in
                guard case Enigma256V3FixtureError.artifactHash(path: "artifacts/plaintext.bin", expected: _, actual: _) = error else {
                    return XCTFail("unexpected error: \(error)")
                }
            }
        }

        let directory = temporaryDirectory("duplicate-mismatch")
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = try bundle()
        let path = "artifacts/plaintext.hex"
        var changedData = try XCTUnwrap(original.artifactData[path])
        changedData[0] = changedData[0] == 0x30 ? 0x31 : 0x30
        let changedArtifacts = original.fixture.artifacts.map { descriptor in
            guard descriptor.path == path else { return descriptor }
            return Enigma256FixtureV5.Artifact(
                path: descriptor.path,
                logicalID: descriptor.logicalID,
                encoding: descriptor.encoding,
                fileBytes: changedData.count,
                decodedBytes: descriptor.decodedBytes,
                sha256: sha256Hex(changedData)
            )
        }
        let changedFixture = Enigma256FixtureV5(
            schema: original.fixture.schema,
            identity: original.fixture.identity,
            profileBinding: original.fixture.profileBinding,
            semantics: original.fixture.semantics,
            inputs: original.fixture.inputs,
            derivation: original.fixture.derivation,
            recurrenceVectors: original.fixture.recurrenceVectors,
            streamKAT: original.fixture.streamKAT,
            negativeVectors: original.fixture.negativeVectors,
            artifacts: changedArtifacts
        )
        var changedArtifactData = original.artifactData
        changedArtifactData[path] = changedData
        try Enigma256FixtureV5Codec.write(
            .init(fixture: changedFixture, artifactData: changedArtifactData),
            to: directory
        )
        XCTAssertThrowsError(try Enigma256FixtureV5Codec.verify(at: directory, profile: profile)) { error in
            XCTAssertEqual(
                error as? Enigma256V3FixtureError,
                .duplicateArtifactMismatch("plaintext")
            )
        }
    }

    func testExtraFileAndSymlinkReject() throws {
        try withWrittenBundle { directory, _ in
            let extra = directory.appendingPathComponent("artifacts/extra.txt")
            try Data("extra\n".utf8).write(to: extra)
            XCTAssertThrowsError(try Enigma256FixtureV5Codec.verify(at: directory, profile: profile)) { error in
                guard case Enigma256V3FixtureError.unexpectedLayout = error else {
                    return XCTFail("unexpected error: \(error)")
                }
            }
        }

        try withWrittenBundle { directory, _ in
            let target = directory.appendingPathComponent("artifacts/plaintext.bin")
            try FileManager.default.removeItem(at: target)
            try FileManager.default.createSymbolicLink(
                at: target,
                withDestinationURL: directory.appendingPathComponent("artifacts/plaintext.hex")
            )
            XCTAssertThrowsError(try Enigma256FixtureV5Codec.verify(at: directory, profile: profile)) { error in
                guard case Enigma256V3FixtureError.symlink = error else {
                    return XCTFail("unexpected error: \(error)")
                }
            }
        }
    }

    func testCanonicalArtifactBindingsRejectRemapAndDescriptorBackedExtra() throws {
        func replacingArtifacts(
            _ value: Enigma256FixtureV5Bundle,
            _ artifacts: [Enigma256FixtureV5.Artifact],
            artifactData: [String: Data]? = nil
        ) -> Enigma256FixtureV5Bundle {
            let fixture = Enigma256FixtureV5(
                schema: value.fixture.schema,
                identity: value.fixture.identity,
                profileBinding: value.fixture.profileBinding,
                semantics: value.fixture.semantics,
                inputs: value.fixture.inputs,
                derivation: value.fixture.derivation,
                recurrenceVectors: value.fixture.recurrenceVectors,
                streamKAT: value.fixture.streamKAT,
                negativeVectors: value.fixture.negativeVectors,
                artifacts: artifacts
            )
            return .init(fixture: fixture, artifactData: artifactData ?? value.artifactData)
        }

        let original = try bundle()
        let remappedArtifacts = original.fixture.artifacts.map { descriptor in
            let logicalID: String
            switch descriptor.path {
            case "artifacts/stream-trace.csv": logicalID = "recurrence_basis"
            case "artifacts/recurrence-basis.csv": logicalID = "stream_trace"
            default: logicalID = descriptor.logicalID
            }
            return Enigma256FixtureV5.Artifact(
                path: descriptor.path,
                logicalID: logicalID,
                encoding: descriptor.encoding,
                fileBytes: descriptor.fileBytes,
                decodedBytes: descriptor.decodedBytes,
                sha256: descriptor.sha256
            )
        }
        let remappedDirectory = temporaryDirectory("artifact-remap")
        defer { try? FileManager.default.removeItem(at: remappedDirectory) }
        try Enigma256FixtureV5Codec.write(
            replacingArtifacts(original, remappedArtifacts),
            to: remappedDirectory
        )
        XCTAssertThrowsError(
            try Enigma256FixtureV5Codec.verify(at: remappedDirectory, profile: profile)
        ) { error in
            XCTAssertEqual(
                error as? Enigma256V3FixtureError,
                .schemaMismatch("artifact bindings")
            )
        }

        let canonicalPath = "artifacts/plaintext.bin"
        let extraPath = "artifacts/descriptor-backed-extra.bin"
        let extraArtifacts = original.fixture.artifacts.map { descriptor in
            guard descriptor.path == canonicalPath else { return descriptor }
            return Enigma256FixtureV5.Artifact(
                path: extraPath,
                logicalID: descriptor.logicalID,
                encoding: descriptor.encoding,
                fileBytes: descriptor.fileBytes,
                decodedBytes: descriptor.decodedBytes,
                sha256: descriptor.sha256
            )
        }
        var extraArtifactData = original.artifactData
        extraArtifactData[extraPath] = extraArtifactData.removeValue(forKey: canonicalPath)
        let extraDirectory = temporaryDirectory("descriptor-backed-extra")
        defer { try? FileManager.default.removeItem(at: extraDirectory) }
        try Enigma256FixtureV5Codec.write(
            replacingArtifacts(
                original,
                extraArtifacts,
                artifactData: extraArtifactData
            ),
            to: extraDirectory
        )
        XCTAssertThrowsError(
            try Enigma256FixtureV5Codec.verify(at: extraDirectory, profile: profile)
        ) { error in
            XCTAssertEqual(
                error as? Enigma256V3FixtureError,
                .schemaMismatch("artifact bindings")
            )
        }
    }

    func testEmitScratchFixtureWhenRequested() throws {
        guard let output = ProcessInfo.processInfo.environment["E256_V3_FIXTURE_OUTPUT"] else {
            throw XCTSkip("set E256_V3_FIXTURE_OUTPUT to emit a fresh scratch fixture-v5 bundle")
        }
        let directory = URL(fileURLWithPath: output)
        try Enigma256FixtureV5Codec.write(try bundle(), to: directory)
        let report = try Enigma256FixtureV5Codec.verify(at: directory, profile: profile)
        XCTAssertEqual(report.profileSHA256, profile.profileHashHex)
        print("E256_V3_FIXTURE=\(directory.path)")
    }
}
