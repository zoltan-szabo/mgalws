// JEDEC.swift — JEDEC (JESD3) fuse-map file reader/writer

import Foundation

public struct JEDECError: Error, CustomStringConvertible {
    public let description: String
    init(_ s: String) { description = s }
}

/// A parsed JEDEC fuse file. Only the fields relevant to GAL programming are
/// modelled; unknown fields are ignored on input.
public struct JEDECFile: Equatable, Sendable {
    public var fuseCount: Int              // *QF
    public var fuses: [Bool]               // true = 1 (blown/disconnected), false = 0 (intact)
    public var declaredFuseChecksum: UInt16?   // *C, if present
    public var pinCount: Int?              // *QP, if present
    public var header: String              // free text before the first field

    public init(fuseCount: Int, fuses: [Bool], declaredFuseChecksum: UInt16? = nil,
                pinCount: Int? = nil, header: String = "") {
        self.fuseCount = fuseCount
        self.fuses = fuses
        self.declaredFuseChecksum = declaredFuseChecksum
        self.pinCount = pinCount
        self.header = header
    }

    /// JESD3 fuse checksum: fuses packed LSB-first into bytes (fuse n is bit
    /// n mod 8 of byte n / 8, missing fuses = 0), summed modulo 65536.
    public var computedFuseChecksum: UInt16 {
        var sum: UInt32 = 0
        var byte: UInt32 = 0
        for (i, f) in fuses.enumerated() {
            if f { byte |= 1 << (i % 8) }
            if i % 8 == 7 { sum &+= byte; byte = 0 }
        }
        if fuses.count % 8 != 0 { sum &+= byte }
        return UInt16(sum & 0xFFFF)
    }

    public static func parse(_ text: String) throws -> JEDECFile {
        // Strip STX/ETX framing and anything after ETX (transmission checksum).
        var body = text
        if let stx = body.firstIndex(of: "\u{02}") { body = String(body[body.index(after: stx)...]) }
        if let etx = body.firstIndex(of: "\u{03}") { body = String(body[..<etx]) }

        let fields = body.components(separatedBy: "*")
        let header = fields.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var fuseCount: Int?
        var defaultFuse = false
        var pinCount: Int?
        var checksum: UInt16?
        var fuseRows: [(Int, [Bool])] = []

        for raw in fields.dropFirst() {
            let field = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let first = field.first else { continue }
            let rest = field.dropFirst()
            switch first {
            case "Q":
                if rest.first == "F", let n = Int(rest.dropFirst().trimmingCharacters(in: .whitespaces)) {
                    fuseCount = n
                } else if rest.first == "P", let n = Int(rest.dropFirst().trimmingCharacters(in: .whitespaces)) {
                    pinCount = n
                }
            case "F":
                if rest.trimmingCharacters(in: .whitespaces) == "1" { defaultFuse = true }
            case "L":
                let payload = rest
                let addrDigits = payload.prefix(while: { $0.isNumber })
                guard let addr = Int(addrDigits) else { throw JEDECError("bad L field address: \(field.prefix(20))") }
                var bits: [Bool] = []
                for ch in payload.dropFirst(addrDigits.count) {
                    if ch == "0" { bits.append(false) }
                    else if ch == "1" { bits.append(true) }
                    else if ch.isWhitespace { continue }
                    else { throw JEDECError("bad character '\(ch)' in L field at \(addr)") }
                }
                fuseRows.append((addr, bits))
            case "C":
                checksum = UInt16(rest.trimmingCharacters(in: .whitespaces), radix: 16)
            default:
                continue  // G, D, N, QV, X vectors etc. — ignored
            }
        }

        guard let qf = fuseCount else { throw JEDECError("missing *QF field") }
        var fuses = [Bool](repeating: defaultFuse, count: qf)
        for (addr, bits) in fuseRows {
            guard addr + bits.count <= qf else { throw JEDECError("L field overruns QF at \(addr)") }
            for (i, b) in bits.enumerated() { fuses[addr + i] = b }
        }
        return JEDECFile(fuseCount: qf, fuses: fuses, declaredFuseChecksum: checksum,
                         pinCount: pinCount, header: header)
    }

    /// Serialize with 32-fuse L rows, a computed *C fuse checksum, and the
    /// full JESD3 STX/ETX framing with transmission checksum (the 16-bit sum
    /// of every byte from STX through ETX inclusive) — required by minipro
    /// and other programmer software.
    public func serialized() -> String {
        var out = "\u{02}"
        out += header.isEmpty ? "" : header + "\n"
        out += "\n"
        if let qp = pinCount { out += "*QP\(qp)\n" }
        out += "*QF\(fuseCount)\n*G0\n*F0\n"
        var addr = 0
        while addr < fuses.count {
            let row = fuses[addr ..< min(addr + 32, fuses.count)]
            out += String(format: "*L%05d ", addr) + row.map { $0 ? "1" : "0" }.joined() + "\n"
            addr += 32
        }
        out += String(format: "*C%04X\n", Int(computedFuseChecksum))
        out += "*\u{03}"
        let transmission = out.utf8.reduce(UInt32(0)) { $0 &+ UInt32($1) } & 0xFFFF
        return out + String(format: "%04X", transmission)
    }
}
