// CUPLParser.swift — lexer and parser for the CUPL subset mgalws supports
//
// Milestone 2 subset: header statements, PIN declarations (with active-low
// `!name`), and combinational equations `target[.ext] = expr;` where expr
// uses ! (not), & (and), # (or), $ (xor), parentheses, and 'b'0/'b'1
// constants. Comments are /* ... */.

import Foundation

public struct PLDParseError: Error, CustomStringConvertible {
    public let description: String
    init(_ s: String, line: Int? = nil) {
        description = line.map { "line \($0): \(s)" } ?? s
    }
}

public indirect enum LogicExpr: Equatable, Sendable {
    case constant(Bool)
    case ref(String)
    case not(LogicExpr)
    case and(LogicExpr, LogicExpr)
    case or(LogicExpr, LogicExpr)
    case xor(LogicExpr, LogicExpr)
}

public struct PLDPin: Equatable, Sendable {
    public let number: Int
    public let name: String
    public let activeLow: Bool
}

public struct PLDEquation: Equatable, Sendable {
    public let target: String
    public let ext: String?         // e.g. "OE" for target.OE
    public let expr: LogicExpr
}

public struct PLDSequence: Sendable {
    public struct Transition: Sendable {
        public let present: Int
        public let condition: LogicExpr?    // nil for unconditional / DEFAULT
        public let isDefault: Bool
        public let next: Int
        public let outs: [String]
        public init(present: Int, condition: LogicExpr?, isDefault: Bool,
                    next: Int, outs: [String]) {
            self.present = present
            self.condition = condition
            self.isDefault = isDefault
            self.next = next
            self.outs = outs
        }
    }
    public let field: String
    public let transitions: [Transition]
}

public struct PLDDesign: Sendable {
    public var header: [String: String] = [:]   // lowercased keyword -> raw value
    public var device: String? { header["device"]?.uppercased() }
    public var pins: [PLDPin] = []
    public var equations: [PLDEquation] = []
    public var fields: [String: [String]] = [:] // field name -> bit names, MSB first
    public var sequences: [PLDSequence] = []
}

// MARK: - Lexer

enum PLDToken: Equatable {
    case ident(String)
    case int(Int)
    case constant(Bool)     // 'b'0 / 'b'1 style
    case sym(Character)     // = ; . ! & # $ ( ) and any other single symbol
}

struct PLDLexer {
    private let chars: [Character]
    private var pos = 0
    private(set) var line = 1

    init(_ text: String) { chars = Array(text) }

    private mutating func advance() -> Character? {
        guard pos < chars.count else { return nil }
        let c = chars[pos]; pos += 1
        if c == "\n" { line += 1 }
        return c
    }
    private func peek(_ offset: Int = 0) -> Character? {
        pos + offset < chars.count ? chars[pos + offset] : nil
    }

    mutating func tokens() throws -> [(PLDToken, Int)] {
        var out: [(PLDToken, Int)] = []
        while let c = peek() {
            if c.isWhitespace { _ = advance(); continue }
            if c == "/" && peek(1) == "*" {           // block comment
                _ = advance(); _ = advance()
                while pos < chars.count && !(peek() == "*" && peek(1) == "/") { _ = advance() }
                guard pos < chars.count else { throw PLDParseError("unterminated comment", line: line) }
                _ = advance(); _ = advance()
                continue
            }
            let startLine = line
            if c == "'" {                              // CUPL number: 'b'0101, 'h'FF, ...
                _ = advance()
                guard let radixChar = advance(), advance() == "'" else {
                    throw PLDParseError("malformed CUPL number literal", line: startLine)
                }
                var digits = ""
                while let d = peek(), d.isHexDigit { digits.append(d); _ = advance() }
                let radix: Int
                switch radixChar.lowercased() {
                case "b": radix = 2
                case "o": radix = 8
                case "d": radix = 10
                case "h": radix = 16
                default: throw PLDParseError("unknown number radix '\(radixChar)'", line: startLine)
                }
                guard let value = Int(digits, radix: radix) else {
                    throw PLDParseError("bad digits '\(digits)' for radix \(radix)", line: startLine)
                }
                guard value == 0 || value == 1 else {
                    throw PLDParseError("multi-bit constants are not supported yet", line: startLine)
                }
                out.append((.constant(value == 1), startLine))
                continue
            }
            if c.isLetter || c == "_" {
                var s = ""
                while let d = peek(), d.isLetter || d.isNumber || d == "_" { s.append(d); _ = advance() }
                out.append((.ident(s), startLine))
                continue
            }
            if c.isNumber {
                var s = ""
                while let d = peek(), d.isNumber { s.append(d); _ = advance() }
                out.append((.int(Int(s)!), startLine))
                continue
            }
            _ = advance()
            out.append((.sym(c), startLine))
        }
        return out
    }
}

// MARK: - Parser

public struct PLDParser {
    private var tokens: [(PLDToken, Int)]
    private var pos = 0

    static let headerKeywords: Set<String> = [
        "name", "partno", "date", "rev", "revision", "designer",
        "company", "assembly", "location", "device", "format",
    ]

    public static func parse(_ source: String) throws -> PLDDesign {
        var lexer = PLDLexer(source)
        var parser = PLDParser(tokens: try lexer.tokens())
        return try parser.parseDesign()
    }

    private var current: PLDToken? { pos < tokens.count ? tokens[pos].0 : nil }
    private var currentLine: Int { pos < tokens.count ? tokens[pos].1 : tokens.last?.1 ?? 0 }
    private mutating func advance() -> PLDToken? {
        guard pos < tokens.count else { return nil }
        defer { pos += 1 }
        return tokens[pos].0
    }
    private mutating func expectSym(_ c: Character) throws {
        guard case .sym(c) = current else {
            throw PLDParseError("expected '\(c)'", line: currentLine)
        }
        pos += 1
    }

    private mutating func parseDesign() throws -> PLDDesign {
        var design = PLDDesign()
        while let tok = current {
            guard case .ident(let word) = tok else {
                throw PLDParseError("unexpected token", line: currentLine)
            }
            let lower = word.lowercased()
            if lower == "pin" {
                pos += 1
                try parsePin(into: &design)
            } else if lower == "field", !nextIsEquationIntro() {
                pos += 1
                try parseField(into: &design)
            } else if lower == "sequence", !nextIsEquationIntro() {
                pos += 1
                try parseSequence(into: &design)
            } else if Self.headerKeywords.contains(lower), !nextIsEquationIntro() {
                pos += 1
                design.header[lower] = try rawValueUntilSemicolon()
            } else {
                try parseEquation(into: &design)
            }
        }
        return design
    }

    /// True when the token after the current identifier starts an equation
    /// (`=` or `.ext =`), so header keywords can double as signal names.
    private func nextIsEquationIntro() -> Bool {
        guard pos + 1 < tokens.count else { return false }
        if case .sym("=") = tokens[pos + 1].0 { return true }
        if case .sym(".") = tokens[pos + 1].0 { return true }
        return false
    }

    private mutating func rawValueUntilSemicolon() throws -> String {
        var parts: [String] = []
        while let tok = advance() {
            switch tok {
            case .sym(";"): return parts.joined(separator: " ")
            case .ident(let s): parts.append(s)
            case .int(let n): parts.append(String(n))
            case .constant(let b): parts.append(b ? "1" : "0")
            case .sym(let c): parts.append(String(c))
            }
        }
        throw PLDParseError("missing ';' after header statement", line: currentLine)
    }

    private mutating func parsePin(into design: inout PLDDesign) throws {
        guard case .int(let number)? = advance() else {
            throw PLDParseError("expected pin number", line: currentLine)
        }
        try expectSym("=")
        var activeLow = false
        if case .sym("!") = current { activeLow = true; pos += 1 }
        guard case .ident(let name)? = advance() else {
            throw PLDParseError("expected pin name", line: currentLine)
        }
        try expectSym(";")
        design.pins.append(PLDPin(number: number, name: name, activeLow: activeLow))
    }

    /// FIELD name = [A..B] or [A, B, C]; ranges expand MSB-first.
    private mutating func parseField(into design: inout PLDDesign) throws {
        guard case .ident(let name)? = advance() else {
            throw PLDParseError("expected field name", line: currentLine)
        }
        try expectSym("=")
        try expectSym("[")
        var bits: [String] = []
        while true {
            guard case .ident(let start)? = advance() else {
                throw PLDParseError("expected signal name in field", line: currentLine)
            }
            if case .sym(".") = current, case .sym(".") = tokens[pos + 1].0 {
                pos += 2
                let endIndex: Int
                switch advance() {
                case .int(let n): endIndex = n
                case .ident(let endName):
                    let digits = endName.reversed().prefix(while: \.isNumber).reversed()
                    guard let n = Int(String(digits)) else {
                        throw PLDParseError("bad field range end \(endName)", line: currentLine)
                    }
                    endIndex = n
                default:
                    throw PLDParseError("expected field range end", line: currentLine)
                }
                let digits = String(start.reversed().prefix(while: \.isNumber).reversed())
                guard let startIndex = Int(digits) else {
                    throw PLDParseError("field range start \(start) has no index", line: currentLine)
                }
                let base = String(start.dropLast(digits.count))
                let step = startIndex <= endIndex ? 1 : -1
                var i = startIndex
                while true {
                    bits.append("\(base)\(i)")
                    if i == endIndex { break }
                    i += step
                }
            } else {
                bits.append(start)
            }
            if case .sym(",") = current { pos += 1; continue }
            break
        }
        try expectSym("]")
        try expectSym(";")
        design.fields[name] = bits
    }

    /// SEQUENCE field { PRESENT n [IF expr|DEFAULT] NEXT n [OUT sig]... ; ... }
    private mutating func parseSequence(into design: inout PLDDesign) throws {
        guard case .ident(let fieldName)? = advance() else {
            throw PLDParseError("expected field name after SEQUENCE", line: currentLine)
        }
        try expectSym("{")
        var transitions: [PLDSequence.Transition] = []
        var present: Int? = nil
        while true {
            switch current {
            case .sym("}"):
                pos += 1
                design.sequences.append(PLDSequence(field: fieldName, transitions: transitions))
                return
            case .ident(let word) where word.lowercased() == "present":
                pos += 1
                guard case .int(let state)? = advance() else {
                    throw PLDParseError("expected state number after PRESENT", line: currentLine)
                }
                present = state
            case .ident(let word) where ["if", "next", "default"].contains(word.lowercased()):
                guard let from = present else {
                    throw PLDParseError("transition before any PRESENT", line: currentLine)
                }
                var condition: LogicExpr? = nil
                var isDefault = false
                if word.lowercased() == "if" {
                    pos += 1
                    condition = try parseOr()
                } else if word.lowercased() == "default" {
                    pos += 1
                    isDefault = true
                }
                guard case .ident(let kw)? = advance(), kw.lowercased() == "next" else {
                    throw PLDParseError("expected NEXT", line: currentLine)
                }
                guard case .int(let next)? = advance() else {
                    throw PLDParseError("expected state number after NEXT", line: currentLine)
                }
                var outs: [String] = []
                while case .ident(let o) = current, o.lowercased() == "out" {
                    pos += 1
                    guard case .ident(let sig)? = advance() else {
                        throw PLDParseError("expected signal after OUT", line: currentLine)
                    }
                    outs.append(sig)
                }
                try expectSym(";")
                transitions.append(PLDSequence.Transition(
                    present: from, condition: condition, isDefault: isDefault,
                    next: next, outs: outs))
            default:
                throw PLDParseError("unexpected token in SEQUENCE block", line: currentLine)
            }
        }
    }

    private mutating func parseEquation(into design: inout PLDDesign) throws {
        guard case .ident(let target)? = advance() else {
            throw PLDParseError("expected equation target", line: currentLine)
        }
        var ext: String? = nil
        if case .sym(".") = current {
            pos += 1
            guard case .ident(let e)? = advance() else {
                throw PLDParseError("expected extension after '.'", line: currentLine)
            }
            ext = e.uppercased()
        }
        try expectSym("=")
        let expr = try parseOr()
        try expectSym(";")
        design.equations.append(PLDEquation(target: target, ext: ext, expr: expr))
    }

    // expr: xorExpr { '#' xorExpr }
    private mutating func parseOr() throws -> LogicExpr {
        var lhs = try parseXor()
        while case .sym("#") = current {
            pos += 1
            lhs = .or(lhs, try parseXor())
        }
        return lhs
    }

    // xorExpr: andExpr { '$' andExpr }
    private mutating func parseXor() throws -> LogicExpr {
        var lhs = try parseAnd()
        while case .sym("$") = current {
            pos += 1
            lhs = .xor(lhs, try parseAnd())
        }
        return lhs
    }

    // andExpr: factor { '&' factor }
    private mutating func parseAnd() throws -> LogicExpr {
        var lhs = try parseFactor()
        while case .sym("&") = current {
            pos += 1
            lhs = .and(lhs, try parseFactor())
        }
        return lhs
    }

    private mutating func parseFactor() throws -> LogicExpr {
        switch current {
        case .sym("!"):
            pos += 1
            return .not(try parseFactor())
        case .sym("("):
            pos += 1
            let inner = try parseOr()
            try expectSym(")")
            return inner
        case .ident(let name):
            pos += 1
            return .ref(name)
        case .constant(let b):
            pos += 1
            return .constant(b)
        case .int(let n) where n == 0 || n == 1:
            pos += 1
            return .constant(n == 1)
        default:
            throw PLDParseError("expected expression factor", line: currentLine)
        }
    }
}
