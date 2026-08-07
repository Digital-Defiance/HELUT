import Foundation

package enum Enigma256V3FixtureError: Error, Equatable, CustomStringConvertible {
    case pathExists(String)
    case missingPath(String)
    case symlink(String)
    case notRegularFile(String)
    case notDirectory(String)
    case manifestTooLarge(Int)
    case artifactTooLarge(path: String, size: Int)
    case invalidJSON(String)
    case duplicateJSONKey(path: String, key: String)
    case unknownJSONKey(path: String, key: String)
    case missingJSONKey(path: String, key: String)
    case wrongJSONShape(String)
    case nonCanonicalJSON
    case schemaMismatch(String)
    case identityMismatch(String)
    case invalidHex(field: String)
    case unsafeArtifactPath(String)
    case duplicateArtifactPath(String)
    case duplicateLogicalEncoding(String)
    case unexpectedLayout(String)
    case artifactSize(path: String, expected: Int, actual: Int)
    case artifactHash(path: String, expected: String, actual: String)
    case artifactEncoding(path: String, encoding: String)
    case duplicateArtifactMismatch(String)
    case derivationMismatch(String)
    case recurrenceMismatch(String)
    case streamMismatch(String)
    case negativeVectorMismatch(String)

    package var description: String {
        switch self {
        case let .pathExists(path): return "refusing to replace existing fixture path \(path)"
        case let .missingPath(path): return "missing fixture path \(path)"
        case let .symlink(path): return "fixture path must not be a symlink: \(path)"
        case let .notRegularFile(path): return "fixture path is not a regular file: \(path)"
        case let .notDirectory(path): return "fixture path is not a directory: \(path)"
        case let .manifestTooLarge(size): return "fixture manifest exceeds limit: \(size) bytes"
        case let .artifactTooLarge(path, size): return "fixture artifact exceeds limit: \(path) (\(size) bytes)"
        case let .invalidJSON(message): return "invalid strict fixture JSON: \(message)"
        case let .duplicateJSONKey(path, key): return "duplicate JSON key \(path).\(key)"
        case let .unknownJSONKey(path, key): return "unknown JSON key \(path).\(key)"
        case let .missingJSONKey(path, key): return "missing JSON key \(path).\(key)"
        case let .wrongJSONShape(path): return "wrong JSON shape at \(path)"
        case .nonCanonicalJSON: return "fixture manifest is not canonical sorted pretty JSON with one trailing LF"
        case let .schemaMismatch(message): return "fixture schema mismatch: \(message)"
        case let .identityMismatch(message): return "fixture identity mismatch: \(message)"
        case let .invalidHex(field): return "invalid canonical lowercase hex in \(field)"
        case let .unsafeArtifactPath(path): return "unsafe fixture artifact path \(path)"
        case let .duplicateArtifactPath(path): return "duplicate fixture artifact path \(path)"
        case let .duplicateLogicalEncoding(value): return "duplicate logical artifact encoding \(value)"
        case let .unexpectedLayout(path): return "unexpected fixture path \(path)"
        case let .artifactSize(path, expected, actual):
            return "artifact size mismatch for \(path): expected \(expected), got \(actual)"
        case let .artifactHash(path, expected, actual):
            return "artifact hash mismatch for \(path): expected \(expected), got \(actual)"
        case let .artifactEncoding(path, encoding):
            return "artifact \(path) violates \(encoding)"
        case let .duplicateArtifactMismatch(logical):
            return "duplicate artifact formats disagree for \(logical)"
        case let .derivationMismatch(field): return "fixture derivation mismatch: \(field)"
        case let .recurrenceMismatch(field): return "fixture recurrence mismatch: \(field)"
        case let .streamMismatch(field): return "fixture stream mismatch: \(field)"
        case let .negativeVectorMismatch(field): return "fixture negative-vector mismatch: \(field)"
        }
    }
}

package indirect enum Enigma256StrictJSONShape: Sendable {
    case object([String: Enigma256StrictJSONShape])
    case array(Enigma256StrictJSONShape)
    case scalar
}

private indirect enum Enigma256StrictJSONNode {
    case object([String: Enigma256StrictJSONNode])
    case array([Enigma256StrictJSONNode])
    case scalar
}

/// A bounded structural preflight used before JSONDecoder. Foundation's JSON
/// object APIs do not preserve duplicate keys, so duplicate and unknown fields
/// must be rejected while the original token stream is still available.
package enum Enigma256StrictJSON {
    package static func validate(
        _ data: Data,
        shape: Enigma256StrictJSONShape
    ) throws {
        var parser = Parser(bytes: Array(data))
        let node = try parser.parse()
        try validate(node: node, shape: shape, path: "$", depth: 0)
    }

    private static func validate(
        node: Enigma256StrictJSONNode,
        shape: Enigma256StrictJSONShape,
        path: String,
        depth: Int
    ) throws {
        guard depth <= 64 else {
            throw Enigma256V3FixtureError.invalidJSON("nesting depth exceeds 64")
        }
        switch (node, shape) {
        case let (.object(values), .object(fields)):
            for key in values.keys where fields[key] == nil {
                throw Enigma256V3FixtureError.unknownJSONKey(path: path, key: key)
            }
            for key in fields.keys where values[key] == nil {
                throw Enigma256V3FixtureError.missingJSONKey(path: path, key: key)
            }
            for (key, childShape) in fields {
                guard let child = values[key] else { continue }
                try validate(
                    node: child,
                    shape: childShape,
                    path: "\(path).\(key)",
                    depth: depth + 1
                )
            }
        case let (.array(values), .array(elementShape)):
            for (index, child) in values.enumerated() {
                try validate(
                    node: child,
                    shape: elementShape,
                    path: "\(path)[\(index)]",
                    depth: depth + 1
                )
            }
        case (.scalar, .scalar):
            break
        default:
            throw Enigma256V3FixtureError.wrongJSONShape(path)
        }
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0
        var nodeCount = 0

        mutating func parse() throws -> Enigma256StrictJSONNode {
            skipWhitespace()
            let value = try parseValue(path: "$", depth: 0)
            skipWhitespace()
            guard index == bytes.count else { throw invalid("trailing bytes") }
            return value
        }

        mutating func parseValue(path: String, depth: Int) throws -> Enigma256StrictJSONNode {
            guard depth <= 64 else { throw invalid("nesting depth exceeds 64") }
            nodeCount += 1
            guard nodeCount <= 200_000 else { throw invalid("node count exceeds 200000") }
            skipWhitespace()
            guard index < bytes.count else { throw invalid("unexpected end of input") }
            switch bytes[index] {
            case 0x7B: return try parseObject(path: path, depth: depth)
            case 0x5B: return try parseArray(path: path, depth: depth)
            case 0x22:
                _ = try parseString()
                return .scalar
            case 0x74:
                try consumeKeyword("true")
                return .scalar
            case 0x66:
                try consumeKeyword("false")
                return .scalar
            case 0x6E:
                try consumeKeyword("null")
                return .scalar
            case 0x2D, 0x30 ... 0x39:
                try parseNumber()
                return .scalar
            default:
                throw invalid("unexpected token at byte \(index)")
            }
        }

        mutating func parseObject(path: String, depth: Int) throws -> Enigma256StrictJSONNode {
            try consume(0x7B)
            skipWhitespace()
            var values: [String: Enigma256StrictJSONNode] = [:]
            if consumeIf(0x7D) { return .object(values) }
            while true {
                skipWhitespace()
                guard peek() == 0x22 else { throw invalid("object key is not a string") }
                let key = try parseString()
                guard values[key] == nil else {
                    throw Enigma256V3FixtureError.duplicateJSONKey(path: path, key: key)
                }
                skipWhitespace()
                try consume(0x3A)
                let childPath = "\(path).\(key)"
                values[key] = try parseValue(path: childPath, depth: depth + 1)
                skipWhitespace()
                if consumeIf(0x7D) { break }
                try consume(0x2C)
            }
            return .object(values)
        }

        mutating func parseArray(path: String, depth: Int) throws -> Enigma256StrictJSONNode {
            try consume(0x5B)
            skipWhitespace()
            var values: [Enigma256StrictJSONNode] = []
            if consumeIf(0x5D) { return .array(values) }
            while true {
                values.append(try parseValue(
                    path: "\(path)[\(values.count)]",
                    depth: depth + 1
                ))
                skipWhitespace()
                if consumeIf(0x5D) { break }
                try consume(0x2C)
            }
            return .array(values)
        }

        mutating func parseString() throws -> String {
            let start = index
            try consume(0x22)
            var escaped = false
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                if escaped {
                    if byte == 0x75 {
                        guard index + 4 <= bytes.count else { throw invalid("short unicode escape") }
                        for digit in bytes[index ..< index + 4] where !Self.isHex(digit) {
                            _ = digit
                            throw invalid("invalid unicode escape")
                        }
                        index += 4
                    } else if ![0x22, 0x5C, 0x2F, 0x62, 0x66, 0x6E, 0x72, 0x74].contains(byte) {
                        throw invalid("invalid string escape")
                    }
                    escaped = false
                } else if byte == 0x5C {
                    escaped = true
                } else if byte == 0x22 {
                    let raw = Data(bytes[start ..< index])
                    var wrapped = Data([0x5B])
                    wrapped.append(raw)
                    wrapped.append(0x5D)
                    do {
                        guard let decoded = try JSONSerialization.jsonObject(with: wrapped) as? [String],
                              decoded.count == 1 else {
                            throw invalid("cannot decode JSON string")
                        }
                        return decoded[0]
                    } catch let error as Enigma256V3FixtureError {
                        throw error
                    } catch {
                        throw invalid("cannot decode JSON string: \(error)")
                    }
                } else if byte < 0x20 {
                    throw invalid("unescaped control byte in string")
                }
            }
            throw invalid("unterminated string")
        }

        mutating func parseNumber() throws {
            let start = index
            if consumeIf(0x2D), index == bytes.count { throw invalid("short number") }
            if consumeIf(0x30) {
                if let next = peek(), (0x30 ... 0x39).contains(next) {
                    throw invalid("number has a leading zero")
                }
            } else {
                guard let first = peek(), (0x31 ... 0x39).contains(first) else {
                    throw invalid("invalid number")
                }
                while let next = peek(), (0x30 ... 0x39).contains(next) { index += 1 }
            }
            if consumeIf(0x2E) {
                guard let first = peek(), (0x30 ... 0x39).contains(first) else {
                    throw invalid("fraction has no digits")
                }
                while let next = peek(), (0x30 ... 0x39).contains(next) { index += 1 }
            }
            if let next = peek(), next == 0x65 || next == 0x45 {
                index += 1
                if let sign = peek(), sign == 0x2B || sign == 0x2D { index += 1 }
                guard let first = peek(), (0x30 ... 0x39).contains(first) else {
                    throw invalid("exponent has no digits")
                }
                while let digit = peek(), (0x30 ... 0x39).contains(digit) { index += 1 }
            }
            guard index > start else { throw invalid("empty number") }
        }

        mutating func consumeKeyword(_ keyword: String) throws {
            let expected = Array(keyword.utf8)
            guard index + expected.count <= bytes.count,
                  Array(bytes[index ..< index + expected.count]) == expected else {
                throw invalid("invalid keyword")
            }
            index += expected.count
        }

        mutating func skipWhitespace() {
            while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) {
                index += 1
            }
        }

        mutating func consume(_ expected: UInt8) throws {
            guard consumeIf(expected) else {
                throw invalid(String(format: "expected byte 0x%02x at %d", expected, index))
            }
        }

        mutating func consumeIf(_ expected: UInt8) -> Bool {
            guard index < bytes.count, bytes[index] == expected else { return false }
            index += 1
            return true
        }

        func peek() -> UInt8? {
            index < bytes.count ? bytes[index] : nil
        }

        func invalid(_ message: String) -> Enigma256V3FixtureError {
            .invalidJSON(message)
        }

        static func isHex(_ byte: UInt8) -> Bool {
            (0x30 ... 0x39).contains(byte)
                || (0x41 ... 0x46).contains(byte)
                || (0x61 ... 0x66).contains(byte)
        }
    }
}
