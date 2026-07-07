// GAL22V10.swift — fuse-map model and decoder for the Lattice GAL22V10 / Atmel ATF22V10
//
// Layout verified against WinCUPL-produced fuse maps:
//   row 0:            async reset (AR) product term
//   rows 1..130:      10 OLMC groups, each: 1 OE row + N logic rows,
//                     N = 8,10,12,14,16,16,14,12,10,8 for pins 23..14
//   row 131:          sync preset (SP) product term
//   fuses 5808..5827: per-OLMC (S0, S1) — S0: 1 = active high; S1: 1 = combinatorial
//   fuses 5828..5891: 64-bit signature
//
// Registered macrocell feedback enters the AND array inverted (Q̄).

public struct GAL22V10: Sendable {
    public static let fuseCount = 5892
    public static let columns = 44
    public static let pairs = 22
    public static let olmcPins = [23, 22, 21, 20, 19, 18, 17, 16, 15, 14]
    public static let termCounts = [8, 10, 12, 14, 16, 16, 14, 12, 10, 8]

    static let sBase = 5808
    static let sigBase = 5828

    public struct OLMC: Sendable {
        public let pin: Int
        public let registered: Bool           // S1 = 0
        public let activeHigh: Bool           // S0 = 1
        public let outputEnable: SumOfProducts
        public let logic: SumOfProducts
    }

    public struct Decoded: Sendable {
        public let olmcs: [OLMC]              // in olmcPins order (23..14)
        public let asyncReset: SumOfProducts
        public let syncPreset: SumOfProducts
        public let columnSources: [ColumnSource]
        public let signature: [Bool]

        public func olmc(pin: Int) -> OLMC? { olmcs.first { $0.pin == pin } }
        public func namer(pinNames: [Int: String] = [:]) -> SignalNamer {
            SignalNamer(sources: columnSources, pinNames: pinNames)
        }
    }

    /// Input pins 1..11 and 13 interleaved with OLMC feedback, pin 1 first.
    public static let columnSources: [ColumnSource] = [
        .pin(1), .feedback(23),
        .pin(2), .feedback(22),
        .pin(3), .feedback(21),
        .pin(4), .feedback(20),
        .pin(5), .feedback(19),
        .pin(6), .feedback(18),
        .pin(7), .feedback(17),
        .pin(8), .feedback(16),
        .pin(9), .feedback(15),
        .pin(10), .feedback(14),
        .pin(11), .pin(13),
    ]

    public static func decode(_ jed: JEDECFile) throws -> Decoded {
        guard jed.fuseCount == fuseCount else {
            throw JEDECError("not a GAL22V10 fuse map (QF\(jed.fuseCount), expected QF\(fuseCount))")
        }
        let f = jed.fuses
        func rowTerm(_ row: Int) -> ProductTerm {
            let start = row * columns
            return ProductTerm.decode(row: f[start ..< start + columns])
        }

        let ar = SumOfProducts([rowTerm(0)])
        var row = 1
        var olmcs: [OLMC] = []
        for (idx, pin) in olmcPins.enumerated() {
            let oe = SumOfProducts([rowTerm(row)])
            var logicRows: [ProductTerm] = []
            for r in 1 ... termCounts[idx] { logicRows.append(rowTerm(row + r)) }
            row += termCounts[idx] + 1
            let s0 = f[sBase + 2 * idx]
            let s1 = f[sBase + 2 * idx + 1]
            olmcs.append(OLMC(pin: pin, registered: !s1, activeHigh: s0,
                              outputEnable: oe, logic: SumOfProducts(logicRows)))
        }
        let sp = SumOfProducts([rowTerm(row)])

        return Decoded(olmcs: olmcs, asyncReset: ar, syncPreset: sp,
                       columnSources: columnSources,
                       signature: Array(f[sigBase ..< sigBase + 64]))
    }
}
