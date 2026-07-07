// LogicSynthesis.swift — expression tree to sum-of-products over named signals

public struct SynthesisError: Error, CustomStringConvertible {
    public let description: String
    init(_ s: String) { description = s }
}

/// One product term over named logical signals (name → positive?).
/// An empty cube is the constant TRUE.
public struct Cube: Hashable, Sendable {
    public var literals: [String: Bool]
    public init(_ literals: [String: Bool] = [:]) { self.literals = literals }

    /// AND of two cubes; nil when they contradict (x & !x).
    func merged(with other: Cube) -> Cube? {
        var out = literals
        for (name, positive) in other.literals {
            if let existing = out[name], existing != positive { return nil }
            out[name] = positive
        }
        return Cube(out)
    }

    /// True when this cube's literals are a subset of `other`'s, meaning
    /// this cube covers (absorbs) the more specific `other`.
    func absorbs(_ other: Cube) -> Bool {
        literals.allSatisfy { other.literals[$0.key] == $0.value }
    }
}

public enum LogicSynthesis {
    static let termLimit = 512

    /// Expand an expression into a simplified list of cubes (OR of ANDs).
    /// The empty list is the constant FALSE; [Cube()] is the constant TRUE.
    public static func cubes(of expr: LogicExpr, negated: Bool = false) throws -> [Cube] {
        let raw = try expand(expr, negated)
        return simplify(raw)
    }

    private static func expand(_ expr: LogicExpr, _ negated: Bool) throws -> [Cube] {
        switch expr {
        case .constant(let b):
            return b != negated ? [Cube()] : []
        case .ref(let name):
            return [Cube([name: !negated])]
        case .not(let inner):
            return try expand(inner, !negated)
        case .and(let a, let b):
            if negated {
                // !(a & b) = !a # !b
                return try expand(a, true) + expand(b, true)
            }
            return try product(expand(a, false), expand(b, false))
        case .or(let a, let b):
            if negated {
                // !(a # b) = !a & !b
                return try product(expand(a, true), expand(b, true))
            }
            return try expand(a, false) + expand(b, false)
        case .xor(let a, let b):
            // a $ b = a&!b # !a&b  (negated: equality)
            let rewritten: LogicExpr = .or(.and(a, .not(b)), .and(.not(a), b))
            return try expand(rewritten, negated)
        }
    }

    private static func product(_ a: [Cube], _ b: [Cube]) throws -> [Cube] {
        var out: [Cube] = []
        for ca in a {
            for cb in b {
                if let merged = ca.merged(with: cb) { out.append(merged) }
                guard out.count <= termLimit else {
                    throw SynthesisError("expression expands to more than \(termLimit) product terms")
                }
            }
        }
        return out
    }

    /// Deduplicate and apply single-cube absorption (A # A&B = A).
    static func simplify(_ cubes: [Cube]) -> [Cube] {
        var unique: [Cube] = []
        for c in cubes where !unique.contains(c) { unique.append(c) }
        if unique.contains(Cube()) { return [Cube()] }   // TRUE absorbs everything
        // After dedupe, mutual absorption would imply equality, so a plain
        // "someone else absorbs me" test cannot drop both of a pair.
        var kept: [Cube] = []
        for (i, c) in unique.enumerated() {
            let absorbed = unique.enumerated().contains { j, other in
                i != j && other.absorbs(c)
            }
            if !absorbed { kept.append(c) }
        }
        return kept
    }
}
