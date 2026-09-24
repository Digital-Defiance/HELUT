import Foundation
import XCTest
@testable import HELUTCore

/// Canonical Swift M4 against Fixtures/u534_corpus.json published keys.
/// Census must match `python3 Scripts/verify_horenberg_corpus.py` (U-534).
final class HorenbergCorpusTests: XCTestCase {

    private static let mismatchIDs: Set<String> = [
        "P1030659", "P1030664", "P1030675", "P1030693", "P1030695",
        "P1030699", "P1030700", "P1030701", "P1030702", "P1030705",
        "P1030706", "P1030707", "P1030708", "P1030709", "P1030710",
        "P1030711",
    ]

    func testU534PublishedKeysMatchPythonCensus() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/u534_corpus.json")
        let file = try JSONDecoder().decode(CorpusFile.self, from: Data(contentsOf: url))

        var exact = 0
        var prefix = [String]()
        var mismatch = [String]()
        var scramble = [String]()
        var skip = 0

        for message in file.messages {
            switch grade(message) {
            case .skip:
                skip += 1
            case .exact:
                exact += 1
            case .prefix:
                prefix.append(message.id)
            case .mismatch(let agree):
                mismatch.append(message.id)
                if agree < 3 { scramble.append(message.id) }
            }
        }

        XCTAssertEqual(file.messages.count, 50)
        XCTAssertEqual(exact, 31)
        XCTAssertEqual(prefix, ["P1030694"])
        XCTAssertEqual(Set(mismatch), Self.mismatchIDs)
        XCTAssertEqual(scramble, [])
        XCTAssertEqual(skip, 2)
        XCTAssertEqual(exact + prefix.count + mismatch.count + skip, 50)
    }

    func testP1030680IsNotDecrypted() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/u534_corpus.json")
        let file = try JSONDecoder().decode(CorpusFile.self, from: Data(contentsOf: url))
        let target = try XCTUnwrap(file.messages.first { $0.id == "P1030680" })
        XCTAssertEqual(grade(target), Grade.skip)
    }

    private enum Grade: Equatable {
        case skip, exact, prefix, mismatch(agree: Int)
    }

    private struct CorpusFile: Decodable {
        struct Message: Decodable {
            let id: String
            let ciphertext: String?
            let plaintext: String?
            let reflector: String?
            let greek: String?
            let wheels: String?
            let rings: String?
            let wheel_positions: String?
            let plugs: String?
            let broken: Bool?
        }
        let messages: [Message]
    }

    private func grade(_ message: CorpusFile.Message) -> Grade {
        guard message.id != "P1030680", message.broken == true,
              let ctText = message.ciphertext, let ptText = message.plaintext,
              let reflector = message.reflector, let greek = message.greek,
              let wheels = message.wheels, let rings = message.rings,
              let positions = message.wheel_positions, let plugs = message.plugs,
              rings.count == 4, positions.count == 4
        else { return .skip }

        let rotors = Array(wheels).map { EnigmaWarehouse.rotor(named: String($0)) }
        guard rotors.count == 3 else { return .skip }
        let key = EnigmaM4Key(
            greek: EnigmaM4Warehouse.greek(named: greek),
            rotors: (rotors[0], rotors[1], rotors[2]),
            rings: EnigmaM4Key.rings(fromLetters: rings),
            positions: EnigmaM4Key.positions(fromLetters: positions),
            plugboard: EnigmaKey.plugboard(pairs: plugPairs(plugs)),
            reflector: EnigmaM4Warehouse.thinReflector(named: reflector)
        )
        var machine = EnigmaM4Machine(key: key)
        let got = EnigmaAlphabet.normalize(machine.processString(ctText))
        let expect = EnigmaAlphabet.normalize(ptText)
        if got == expect { return .exact }
        if got.count >= expect.count, Array(got.prefix(expect.count)) == expect {
            return .prefix
        }
        return .mismatch(agree: prefixAgree(got, expect))
    }

    private func prefixAgree(_ got: [Int], _ expect: [Int]) -> Int {
        var n = 0
        for (a, b) in zip(got, expect) {
            if a != b { break }
            n += 1
        }
        return n
    }

    private func plugPairs(_ text: String) -> [(Character, Character)] {
        text.split(separator: " ").compactMap { token -> (Character, Character)? in
            guard token.count == 2 else { return nil }
            let letters = Array(token)
            return (letters[0], letters[1])
        }
    }
}
