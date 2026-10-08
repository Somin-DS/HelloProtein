import Foundation

/// A minimal strict JSON reader that keeps numbers as their source text, so a
/// value such as `0.85` never passes through a binary double before it is
/// converted to centigrams. Supports exactly what the bundled catalog and the
/// provider responses use: objects, arrays, strings (with escapes), numbers,
/// `true`/`false`/`null`.
enum CatalogJSON {
    indirect enum Value: Equatable {
        case object([(key: String, value: Value)])
        case array([Value])
        case string(String)
        /// The number exactly as written in the document.
        case number(String)
        case bool(Bool)
        case null

        static func == (lhs: Value, rhs: Value) -> Bool {
            switch (lhs, rhs) {
            case (.object(let a), .object(let b)):
                return a.count == b.count && zip(a, b).allSatisfy { $0.key == $1.key && $0.value == $1.value }
            case (.array(let a), .array(let b)): return a == b
            case (.string(let a), .string(let b)): return a == b
            case (.number(let a), .number(let b)): return a == b
            case (.bool(let a), .bool(let b)): return a == b
            case (.null, .null): return true
            default: return false
            }
        }

        /// First value for `key` in an object; nil for other kinds.
        subscript(key: String) -> Value? {
            guard case .object(let members) = self else { return nil }
            return members.first { $0.key == key }?.value
        }

        var stringValue: String? {
            if case .string(let text) = self { return text }
            return nil
        }

        /// Number text, or a string's text (the Korean service returns numbers as strings).
        var numberText: String? {
            switch self {
            case .number(let text), .string(let text): return text
            default: return nil
            }
        }

        var arrayValue: [Value]? {
            if case .array(let items) = self { return items }
            return nil
        }
    }

    struct ParseError: Error, Equatable {
        let offset: Int
        let reason: String
    }

    static func parse(_ data: Data) throws -> Value {
        var parser = Parser(bytes: [UInt8](data))
        parser.skipWhitespace()
        let value = try parser.parseValue()
        parser.skipWhitespace()
        guard parser.index == parser.bytes.count else { throw parser.error("trailing characters") }
        return value
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0

        init(bytes: [UInt8]) { self.bytes = bytes }

        func error(_ reason: String) -> ParseError { ParseError(offset: index, reason: reason) }

        mutating func skipWhitespace() {
            while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
        }

        mutating func parseValue() throws -> Value {
            guard index < bytes.count else { throw error("unexpected end") }
            switch bytes[index] {
            case UInt8(ascii: "{"): return try parseObject()
            case UInt8(ascii: "["): return try parseArray()
            case UInt8(ascii: "\""): return .string(try parseString())
            case UInt8(ascii: "t"): try expect("true"); return .bool(true)
            case UInt8(ascii: "f"): try expect("false"); return .bool(false)
            case UInt8(ascii: "n"): try expect("null"); return .null
            default: return .number(try parseNumber())
            }
        }

        mutating func expect(_ literal: String) throws {
            let expected = Array(literal.utf8)
            guard index + expected.count <= bytes.count, Array(bytes[index..<index + expected.count]) == expected else {
                throw error("invalid literal")
            }
            index += expected.count
        }

        mutating func parseObject() throws -> Value {
            index += 1
            var members: [(key: String, value: Value)] = []
            skipWhitespace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "}") { index += 1; return .object(members) }
            while true {
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw error("expected key") }
                let key = try parseString()
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { throw error("expected ':'") }
                index += 1
                skipWhitespace()
                members.append((key: key, value: try parseValue()))
                skipWhitespace()
                guard index < bytes.count else { throw error("unterminated object") }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "}") { index += 1; return .object(members) }
                throw error("expected ',' or '}'")
            }
        }

        mutating func parseArray() throws -> Value {
            index += 1
            var items: [Value] = []
            skipWhitespace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
            while true {
                skipWhitespace()
                items.append(try parseValue())
                skipWhitespace()
                guard index < bytes.count else { throw error("unterminated array") }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
                throw error("expected ',' or ']'")
            }
        }

        mutating func parseString() throws -> String {
            index += 1
            var scalars = String.UnicodeScalarView()
            var utf8Buffer: [UInt8] = []
            func flush() throws {
                guard !utf8Buffer.isEmpty else { return }
                guard let text = String(bytes: utf8Buffer, encoding: .utf8) else { throw ParseError(offset: 0, reason: "invalid UTF-8") }
                scalars.append(contentsOf: text.unicodeScalars)
                utf8Buffer.removeAll()
            }
            while index < bytes.count {
                let byte = bytes[index]
                if byte == UInt8(ascii: "\"") {
                    index += 1
                    try flush()
                    return String(scalars)
                }
                if byte == UInt8(ascii: "\\") {
                    try flush()
                    index += 1
                    guard index < bytes.count else { throw error("unterminated escape") }
                    let escape = bytes[index]
                    index += 1
                    switch escape {
                    case UInt8(ascii: "\""): scalars.append("\"")
                    case UInt8(ascii: "\\"): scalars.append("\\")
                    case UInt8(ascii: "/"): scalars.append("/")
                    case UInt8(ascii: "b"): scalars.append("\u{08}")
                    case UInt8(ascii: "f"): scalars.append("\u{0C}")
                    case UInt8(ascii: "n"): scalars.append("\n")
                    case UInt8(ascii: "r"): scalars.append("\r")
                    case UInt8(ascii: "t"): scalars.append("\t")
                    case UInt8(ascii: "u"):
                        var code = try parseHex4()
                        if (0xD800...0xDBFF).contains(code) {
                            // Surrogate pair: a second \uXXXX must follow.
                            guard index + 1 < bytes.count, bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u") else {
                                throw error("lone high surrogate")
                            }
                            index += 2
                            let low = try parseHex4()
                            guard (0xDC00...0xDFFF).contains(low) else { throw error("invalid low surrogate") }
                            code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                        }
                        guard let scalar = Unicode.Scalar(code) else { throw error("invalid code point") }
                        scalars.append(scalar)
                    default: throw error("invalid escape")
                    }
                    continue
                }
                guard byte >= 0x20 else { throw error("control character in string") }
                utf8Buffer.append(byte)
                index += 1
            }
            throw error("unterminated string")
        }

        mutating func parseHex4() throws -> UInt32 {
            guard index + 4 <= bytes.count else { throw error("short \\u escape") }
            var value: UInt32 = 0
            for _ in 0..<4 {
                let byte = bytes[index]
                let digit: UInt32
                switch byte {
                case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = UInt32(byte - UInt8(ascii: "0"))
                case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = UInt32(byte - UInt8(ascii: "a") + 10)
                case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = UInt32(byte - UInt8(ascii: "A") + 10)
                default: throw error("invalid hex digit")
                }
                value = value * 16 + digit
                index += 1
            }
            return value
        }

        /// JSON number grammar, returned as text. Exponents are accepted here
        /// and rejected later by the gram conversion, so the row is reported
        /// as unusable rather than the whole file as corrupt.
        mutating func parseNumber() throws -> String {
            let start = index
            if index < bytes.count, bytes[index] == UInt8(ascii: "-") { index += 1 }
            guard index < bytes.count, isDigit(bytes[index]) else { throw error("expected number") }
            if bytes[index] == UInt8(ascii: "0") {
                index += 1
            } else {
                while index < bytes.count, isDigit(bytes[index]) { index += 1 }
            }
            if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
                index += 1
                guard index < bytes.count, isDigit(bytes[index]) else { throw error("expected fraction digits") }
                while index < bytes.count, isDigit(bytes[index]) { index += 1 }
            }
            if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
                index += 1
                if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") { index += 1 }
                guard index < bytes.count, isDigit(bytes[index]) else { throw error("expected exponent digits") }
                while index < bytes.count, isDigit(bytes[index]) { index += 1 }
            }
            return String(decoding: bytes[start..<index], as: UTF8.self)
        }

        func isDigit(_ byte: UInt8) -> Bool { byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") }
    }
}
