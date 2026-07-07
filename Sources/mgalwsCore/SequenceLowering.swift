// SequenceLowering.swift — expand FIELD/SEQUENCE state machines into
// registered .D equations before device fitting.
//
// For each transition `PRESENT p IF c NEXT n OUT s...`, the product
// `stateDecode(p) & c` is OR-ed into bit.D for every field bit set in n,
// and into s.D for every OUT signal. States with no matching transition
// fall to state 0 (all register D inputs low). DEFAULT clauses take the
// conjunction of the negated IF conditions of their PRESENT block.

public enum SequenceLowering {
    public static func lower(_ design: inout PLDDesign) throws {
        for seq in design.sequences {
            guard let bits = design.fields[seq.field] else {
                throw FitError("SEQUENCE \(seq.field): no such FIELD")
            }
            guard bits.count <= 16 else { throw FitError("FIELD \(seq.field) is too wide") }
            let stateLimit = 1 << bits.count

            // bits are MSB-first: bit i (from LSB) is bits[count-1-i]
            func stateDecode(_ value: Int) -> LogicExpr {
                var expr: LogicExpr? = nil
                for (i, name) in bits.enumerated() {
                    let bitIndex = bits.count - 1 - i
                    let literal: LogicExpr = (value >> bitIndex) & 1 == 1
                        ? .ref(name) : .not(.ref(name))
                    expr = expr.map { .and($0, literal) } ?? literal
                }
                return expr!
            }

            var dTerms: [String: [LogicExpr]] = [:]
            let byPresent = Dictionary(grouping: seq.transitions, by: \.present)
            for (present, transitions) in byPresent {
                guard present < stateLimit else {
                    throw FitError("SEQUENCE \(seq.field): state \(present) exceeds field width")
                }
                let ifConditions = transitions.compactMap { $0.isDefault ? nil : $0.condition }
                for t in transitions {
                    guard t.next < stateLimit else {
                        throw FitError("SEQUENCE \(seq.field): state \(t.next) exceeds field width")
                    }
                    var term = stateDecode(present)
                    if t.isDefault {
                        // DEFAULT: none of the sibling IF conditions hold.
                        for c in ifConditions { term = .and(term, .not(c)) }
                    } else if let c = t.condition {
                        term = .and(term, c)
                    }
                    for (i, name) in bits.enumerated() {
                        let bitIndex = bits.count - 1 - i
                        if (t.next >> bitIndex) & 1 == 1 {
                            dTerms[name, default: []].append(term)
                        }
                    }
                    for out in t.outs {
                        dTerms[out, default: []].append(term)
                    }
                }
            }

            for (signal, terms) in dTerms.sorted(by: { $0.key < $1.key }) {
                let expr = terms.dropFirst().reduce(terms[0]) { .or($0, $1) }
                design.equations.append(PLDEquation(target: signal, ext: "D", expr: expr))
            }
        }
        design.sequences = []
    }
}
