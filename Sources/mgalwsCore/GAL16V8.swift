// GAL16V8.swift — fuse-map model and decoder for the Lattice GAL16V8 / Atmel ATF16V8

public struct GAL16V8: Sendable {
    public static let fuseCount = 2194
    public static let columns = 32
    public static let pairs = 16
    public static let arrayRows = 64          // fuses 0..2047
    public static let olmcPins = [19, 18, 17, 16, 15, 14, 13, 12]  // row-group order

    // Configuration fuse offsets
    static let xorBase = 2048    // 8, pin 19 first
    static let sigBase = 2056    // 64-bit signature
    static let ac1Base = 2120    // 8, pin 19 first
    static let ptdBase = 2128    // 64 product-term disable bits
    static let synFuse = 2192
    static let ac0Fuse = 2193

    public enum Mode: String, Sendable {
        case registered   // SYN=0
        case complex      // SYN=1, AC0=1
        case simple       // SYN=1, AC0=0
    }

    public enum OutputKind: String, Sendable {
        case registeredOutput      // registered mode, AC1=0
        case combinatorialIO       // PT0 is the OE term
        case simpleOutput          // always enabled, 8 logic rows
        case input                 // OLMC pin used as input only
    }

    public struct OLMC: Sendable {
        public let pin: Int
        public let kind: OutputKind
        public let activeHigh: Bool           // XOR fuse = 1
        public let outputEnable: SumOfProducts  // .always / .never / single-term SOP
        public let logic: SumOfProducts       // OR of logic rows
    }

    public struct Decoded: Sendable {
        public let mode: Mode
        public let olmcs: [OLMC]              // in olmcPins order
        public let columnSources: [ColumnSource]
        public let signature: [Bool]

        public func olmc(pin: Int) -> OLMC? { olmcs.first { $0.pin == pin } }
        public func namer(pinNames: [Int: String] = [:]) -> SignalNamer {
            SignalNamer(sources: columnSources, pinNames: pinNames)
        }
    }

    /// Column-pair sources. Pairs 1 and 15 route pin 1 / pin 11 in simple and
    /// complex modes, and OLMC feedback of pins 19 / 12 in registered mode.
    public static func columnSources(mode: Mode) -> [ColumnSource] {
        let edge1: ColumnSource = mode == .registered ? .feedback(19) : .pin(1)
        let edge15: ColumnSource = mode == .registered ? .feedback(12) : .pin(11)
        return [
            .pin(2), edge1,
            .pin(3), .feedback(18),
            .pin(4), .feedback(17),
            .pin(5), .feedback(16),
            .pin(6), .feedback(15),
            .pin(7), .feedback(14),
            .pin(8), .feedback(13),
            .pin(9), edge15,
        ]
    }

    public static func decode(_ jed: JEDECFile) throws -> Decoded {
        guard jed.fuseCount == fuseCount else {
            throw JEDECError("not a GAL16V8 fuse map (QF\(jed.fuseCount), expected QF\(fuseCount))")
        }
        let f = jed.fuses
        let syn = f[synFuse], ac0 = f[ac0Fuse]
        let mode: Mode = !syn ? .registered : (ac0 ? .complex : .simple)

        var olmcs: [OLMC] = []
        for (idx, pin) in olmcPins.enumerated() {
            let ac1 = f[ac1Base + idx]
            let activeHigh = f[xorBase + idx]
            let rowBase = idx * 8
            var rows: [ProductTerm] = []
            for r in 0 ..< 8 {
                let start = (rowBase + r) * columns
                let term = ProductTerm.decode(row: f[start ..< start + columns])
                // A cleared PTD fuse disables the row outright.
                rows.append(f[ptdBase + rowBase + r] ? term : .never)
            }

            let kind: OutputKind
            var oe: SumOfProducts
            var logicRows: [ProductTerm]
            switch mode {
            case .simple:
                if ac1 { kind = .input; oe = SumOfProducts([.never]); logicRows = [] }
                else { kind = .simpleOutput; oe = SumOfProducts([.always]); logicRows = rows }
            case .complex:
                kind = .combinatorialIO
                oe = SumOfProducts([rows[0]])
                logicRows = Array(rows.dropFirst())
            case .registered:
                if ac1 {
                    kind = .combinatorialIO
                    oe = SumOfProducts([rows[0]])
                    logicRows = Array(rows.dropFirst())
                } else {
                    kind = .registeredOutput
                    oe = SumOfProducts([.always])   // enabled by /OE pin 11, not a term
                    logicRows = rows
                }
            }
            olmcs.append(OLMC(pin: pin, kind: kind, activeHigh: activeHigh,
                              outputEnable: oe, logic: SumOfProducts(logicRows)))
        }
        return Decoded(mode: mode, olmcs: olmcs,
                       columnSources: columnSources(mode: mode),
                       signature: Array(f[sigBase ..< sigBase + 64]))
    }
}
