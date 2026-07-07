// GAL22V10Fitter.swift — fit a parsed PLD design onto a GAL22V10 fuse map
//
// Supports combinational outputs, registered outputs (.D), per-pin .OE,
// and the global .AR / .SP product terms. Registered macrocell feedback
// enters the AND array as Q-bar, independent of the pin's polarity.

public enum GAL22V10Fitter {
    struct Signal {
        let pin: Int
        let activeLow: Bool
    }

    public static func fit(_ design: PLDDesign) throws -> JEDECFile {
        // ---- signal table ----------------------------------------------
        var signals: [String: Signal] = [:]
        for pin in design.pins {
            guard (1...11).contains(pin.number) || pin.number == 13 || (14...23).contains(pin.number) else {
                throw FitError("pin \(pin.number) is not a usable GAL22V10 signal pin")
            }
            guard signals[pin.name] == nil else { throw FitError("duplicate signal name \(pin.name)") }
            signals[pin.name] = Signal(pin: pin.number, activeLow: pin.activeLow)
        }

        // ---- collect equations per OLMC pin ----------------------------
        var logicEq: [Int: LogicExpr] = [:]
        var registered: Set<Int> = []
        var oeEq: [Int: LogicExpr] = [:]
        var arEqs: [LogicExpr] = []
        var spEqs: [LogicExpr] = []
        for eq in design.equations {
            guard let sig = signals[eq.target] else {
                throw FitError("equation target \(eq.target) is not a declared pin")
            }
            guard GAL22V10.olmcPins.contains(sig.pin) else {
                throw FitError("\(eq.target) (pin \(sig.pin)) is not an output-capable pin")
            }
            switch eq.ext {
            case nil, "D":
                guard logicEq[sig.pin] == nil else {
                    throw FitError("duplicate logic/.D equation for \(eq.target)")
                }
                logicEq[sig.pin] = eq.expr
                if eq.ext == "D" { registered.insert(sig.pin) }
            case "OE":
                guard oeEq[sig.pin] == nil else { throw FitError("duplicate .OE equation for \(eq.target)") }
                oeEq[sig.pin] = eq.expr
            case "AR":
                arEqs.append(eq.expr)
            case "SP":
                spEqs.append(eq.expr)
            case let other?:
                throw FitError(".\(other) is not supported on the GAL22V10 (use .D/.OE/.AR/.SP)")
            }
        }
        guard !logicEq.isEmpty else { throw FitError("design has no output equations") }
        for pin in oeEq.keys where logicEq[pin] == nil {
            throw FitError("pin \(pin) has an .OE equation but no logic equation")
        }

        // ---- column pair lookup ----------------------------------------
        var pinPair: [Int: Int] = [:]
        var feedbackPair: [Int: Int] = [:]
        for (pair, src) in GAL22V10.columnSources.enumerated() {
            switch src {
            case .pin(let p): pinPair[p] = pair
            case .feedback(let p): feedbackPair[p] = pair
            }
        }

        // ---- fuse assembly ---------------------------------------------
        var fuses = [Bool](repeating: false, count: GAL22V10.fuseCount)

        func writeRow(_ row: Int, cube: Cube?) throws {
            let base = row * GAL22V10.columns
            guard let cube else { return }                    // unused row: never
            for c in 0 ..< GAL22V10.columns { fuses[base + c] = true }
            for (name, positive) in cube.literals {
                guard let sig = signals[name] else { throw FitError("undeclared signal \(name)") }
                let pair: Int
                let columnNegated: Bool
                if let p = pinPair[sig.pin] {
                    pair = p
                    // Column true-level is the pin voltage.
                    columnNegated = (positive == sig.activeLow)
                } else if let p = feedbackPair[sig.pin] {
                    guard logicEq[sig.pin] != nil else {
                        throw FitError("\(name) (pin \(sig.pin)) is used as input but has no equation; OLMC input pins need a driven or tri-stated macrocell")
                    }
                    pair = p
                    if registered.contains(sig.pin) {
                        // Registered feedback is Q-bar of the stored logical
                        // value; pin polarity (S0) does not affect it.
                        columnNegated = positive
                    } else {
                        // Combinatorial feedback is the pin voltage.
                        columnNegated = (positive == sig.activeLow)
                    }
                } else {
                    throw FitError("\(name) (pin \(sig.pin)) cannot reach the AND array")
                }
                fuses[base + 2 * pair + (columnNegated ? 1 : 0)] = false
            }
        }

        func singleCube(_ expr: LogicExpr, what: String) throws -> Cube? {
            let cubes = try LogicSynthesis.cubes(of: expr)
            if cubes.isEmpty { return nil }                   // constant false
            guard cubes.count == 1 else {
                throw FitError("\(what) must reduce to a single product term")
            }
            return cubes[0]
        }

        // Global AR (row 0) and SP (row 131): all declarations must agree.
        func globalTerm(_ exprs: [LogicExpr], what: String) throws -> Cube? {
            guard let first = exprs.first else { return nil }
            let cube = try singleCube(first, what: what)
            for other in exprs.dropFirst() {
                guard try singleCube(other, what: what) == cube else {
                    throw FitError("conflicting \(what) equations")
                }
            }
            return cube
        }
        try writeRow(0, cube: try globalTerm(arEqs, what: ".AR"))
        try writeRow(131, cube: try globalTerm(spEqs, what: ".SP"))

        var row = 1
        for (idx, olmcPin) in GAL22V10.olmcPins.enumerated() {
            let capacity = GAL22V10.termCounts[idx]
            let oeRow = row
            let logicBase = row + 1
            row += capacity + 1

            guard let expr = logicEq[olmcPin] else {
                // Unused OLMC: combinatorial, never enabled — a safe input pin.
                fuses[GAL22V10.sBase + 2 * idx] = true        // S0 (polarity, irrelevant)
                fuses[GAL22V10.sBase + 2 * idx + 1] = true    // S1 = combinatorial
                continue
            }
            let sig = design.pins.first { $0.number == olmcPin }!

            // OE row: default always enabled.
            if let oe = oeEq[olmcPin] {
                try writeRow(oeRow, cube: try singleCube(oe, what: "pin \(olmcPin) .OE"))
            } else {
                try writeRow(oeRow, cube: Cube())
            }

            let cubes = try LogicSynthesis.cubes(of: expr)
            guard cubes.count <= capacity else {
                throw FitError("pin \(olmcPin): \(cubes.count) product terms exceed the \(capacity) available")
            }
            for (i, cube) in cubes.enumerated() {
                try writeRow(logicBase + i, cube: cube)
            }

            fuses[GAL22V10.sBase + 2 * idx] = !sig.activeLow             // S0: 1 = active high
            fuses[GAL22V10.sBase + 2 * idx + 1] = !registered.contains(olmcPin)  // S1: 1 = combinatorial
        }

        return JEDECFile(fuseCount: GAL22V10.fuseCount, fuses: fuses,
                         pinCount: 24,
                         header: "compiled by mgalws")
    }
}
