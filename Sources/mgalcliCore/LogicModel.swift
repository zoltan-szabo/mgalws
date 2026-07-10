// LogicModel.swift — product terms, equations, rendering and evaluation

/// Where one AND-array column pair gets its signal from.
public enum ColumnSource: Equatable, Hashable, Sendable {
    case pin(Int)          // dedicated input pin
    case feedback(Int)     // OLMC feedback for the given pin (Q̄ for registered 22V10 macrocells)
}

/// One literal of a product term: a column pair, possibly negated.
public struct Literal: Equatable, Hashable, Sendable {
    public let pair: Int       // column pair index (column = 2*pair (+1 for complement))
    public let negated: Bool
    public init(pair: Int, negated: Bool) {
        self.pair = pair
        self.negated = negated
    }
}

/// One AND-array row, decoded.
public enum ProductTerm: Equatable, Hashable, Sendable {
    case always                // all fuses blown — constant true
    case never                 // both columns of some pair intact — constant false
    case product([Literal])    // AND of literals, ordered by pair index

    /// Decode one row of `pairs` column pairs. Fuse true = 1 = disconnected.
    public static func decode(row: ArraySlice<Bool>) -> ProductTerm {
        let bits = Array(row)
        precondition(bits.count % 2 == 0)
        if bits.allSatisfy({ $0 }) { return .always }
        var lits: [Literal] = []
        for p in 0 ..< bits.count / 2 {
            let t = bits[2 * p], c = bits[2 * p + 1]
            switch (t, c) {
            case (false, false): return .never       // X & !X
            case (false, true):  lits.append(Literal(pair: p, negated: false))
            case (true, false):  lits.append(Literal(pair: p, negated: true))
            case (true, true):   break               // pair unused
            }
        }
        return .product(lits)
    }

    public func evaluate(_ assignment: [Bool]) -> Bool {
        switch self {
        case .always: return true
        case .never: return false
        case .product(let lits):
            return lits.allSatisfy { assignment[$0.pair] != $0.negated }
        }
    }
}

/// A sum of products (the OR of an OLMC's active rows).
public struct SumOfProducts: Equatable, Sendable {
    public var terms: [ProductTerm]   // .never rows are dropped at construction

    public init(_ rows: [ProductTerm]) {
        if rows.contains(.always) { terms = [.always] }
        else { terms = rows.filter { $0 != .never } }
    }

    public var isConstantFalse: Bool { terms.isEmpty }
    public var isConstantTrue: Bool { terms == [.always] }

    public func evaluate(_ assignment: [Bool]) -> Bool {
        terms.contains { $0.evaluate(assignment) }
    }

    /// The set of column pairs this function actually depends on syntactically.
    public var usedPairs: Set<Int> {
        var s = Set<Int>()
        for t in terms {
            if case .product(let lits) = t { for l in lits { s.insert(l.pair) } }
        }
        return s
    }

    /// Exhaustive functional equivalence over the union of used pairs.
    public func isEquivalent(to other: SumOfProducts, pairCount: Int) -> Bool {
        let used = Array(usedPairs.union(other.usedPairs)).sorted()
        guard used.count <= 24 else { return false }  // refuse absurd blowup
        var assignment = [Bool](repeating: false, count: pairCount)
        for combo in 0 ..< (1 << used.count) {
            for (bit, pair) in used.enumerated() {
                assignment[pair] = (combo >> bit) & 1 == 1
            }
            if evaluate(assignment) != other.evaluate(assignment) { return false }
        }
        return true
    }
}

/// Renders terms/SOPs with human names for column sources.
public struct SignalNamer: Sendable {
    public let sources: [ColumnSource]        // by pair index
    public let pinNames: [Int: String]

    public init(sources: [ColumnSource], pinNames: [Int: String] = [:]) {
        self.sources = sources
        self.pinNames = pinNames
    }

    public func name(ofPair p: Int) -> String {
        switch sources[p] {
        case .pin(let n): return pinNames[n] ?? "P\(n)"
        case .feedback(let n): return "fb" + (pinNames[n] ?? "P\(n)")
        }
    }

    public func render(_ term: ProductTerm) -> String {
        switch term {
        case .always: return "TRUE"
        case .never: return "FALSE"
        case .product(let lits):
            return lits.map { ($0.negated ? "!" : "") + name(ofPair: $0.pair) }
                       .joined(separator: " & ")
        }
    }

    public func render(_ sop: SumOfProducts) -> String {
        if sop.isConstantFalse { return "FALSE" }
        return sop.terms.map(render).joined(separator: "\n  # ")
    }
}
