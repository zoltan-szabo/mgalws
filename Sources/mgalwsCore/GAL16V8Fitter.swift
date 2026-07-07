// GAL16V8Fitter.swift — fit a parsed PLD design onto a GAL16V8 fuse map
//
// Milestone 2 scope: combinational designs. Mode is chosen automatically:
// simple when no .OE equations exist, complex otherwise. Registered
// outputs (.D) are a later milestone.

public struct FitError: Error, CustomStringConvertible {
    public let description: String
    init(_ s: String) { description = s }
}

public struct CompiledPLD: Sendable {
    public let deviceName: String
    public let jed: JEDECFile
}

public enum PLDCompiler {
    /// Compile CUPL source text. Currently supports the GAL16V8 (G16V8*).
    public static func compile(_ source: String) throws -> CompiledPLD {
        let design = try PLDParser.parse(source)
        guard let device = design.device else { throw FitError("no Device statement") }
        guard device.hasPrefix("G16V8") else {
            throw FitError("device \(device) is not supported yet (GAL16V8 only)")
        }
        let jed = try GAL16V8Fitter.fit(design)
        return CompiledPLD(deviceName: "GAL16V8", jed: jed)
    }
}

public enum GAL16V8Fitter {
    struct Signal {
        let pin: Int
        let activeLow: Bool
    }

    public static func fit(_ design: PLDDesign) throws -> JEDECFile {
        // ---- signal table ----------------------------------------------
        var signals: [String: Signal] = [:]
        for pin in design.pins {
            guard (1...9).contains(pin.number) || pin.number == 11 || (12...19).contains(pin.number) else {
                throw FitError("pin \(pin.number) is not a usable GAL16V8 signal pin")
            }
            guard signals[pin.name] == nil else { throw FitError("duplicate signal name \(pin.name)") }
            signals[pin.name] = Signal(pin: pin.number, activeLow: pin.activeLow)
        }

        // ---- collect equations per OLMC pin ----------------------------
        var logicEq: [Int: LogicExpr] = [:]     // olmc pin -> logic expression
        var oeEq: [Int: LogicExpr] = [:]        // olmc pin -> OE expression
        for eq in design.equations {
            guard let sig = signals[eq.target] else {
                throw FitError("equation target \(eq.target) is not a declared pin")
            }
            guard GAL16V8.olmcPins.contains(sig.pin) else {
                throw FitError("\(eq.target) (pin \(sig.pin)) is not an output-capable pin")
            }
            switch eq.ext {
            case nil:
                guard logicEq[sig.pin] == nil else { throw FitError("duplicate equation for \(eq.target)") }
                logicEq[sig.pin] = eq.expr
            case "OE":
                guard oeEq[sig.pin] == nil else { throw FitError("duplicate .OE equation for \(eq.target)") }
                oeEq[sig.pin] = eq.expr
            case let other?:
                throw FitError(".\(other) is not supported yet (only .OE)")
            }
        }
        guard !logicEq.isEmpty else { throw FitError("design has no output equations") }
        for pin in oeEq.keys where logicEq[pin] == nil {
            throw FitError("pin \(pin) has an .OE equation but no logic equation")
        }

        let mode: GAL16V8.Mode = oeEq.isEmpty ? .simple : .complex
        let logicRowCapacity = mode == .simple ? 8 : 7

        // ---- column pair lookup ----------------------------------------
        let sources = GAL16V8.columnSources(mode: mode)
        var pinPair: [Int: Int] = [:]       // input pin -> pair
        var feedbackPair: [Int: Int] = [:]  // OLMC pin -> pair
        for (pair, src) in sources.enumerated() {
            switch src {
            case .pin(let p): pinPair[p] = pair
            case .feedback(let p): feedbackPair[p] = pair
            }
        }

        func pair(forSignal name: String) throws -> Int {
            guard let sig = signals[name] else { throw FitError("undeclared signal \(name)") }
            if let p = pinPair[sig.pin] { return p }
            if let p = feedbackPair[sig.pin] {
                // Simple mode: pins 15/16 are output-only with no array path.
                if mode == .simple && (sig.pin == 15 || sig.pin == 16) {
                    throw FitError("\(name) (pin \(sig.pin)) has no feedback path in simple mode")
                }
                return p
            }
            throw FitError("\(name) (pin \(sig.pin)) cannot reach the AND array in \(mode.rawValue) mode")
        }

        // ---- fuse assembly ---------------------------------------------
        var fuses = [Bool](repeating: false, count: GAL16V8.fuseCount)

        func writeRow(_ row: Int, cube: Cube?) throws {
            // nil = unused row (all intact = never); TRUE cube = all blown.
            let base = row * GAL16V8.columns
            guard let cube else { return }
            for c in 0 ..< GAL16V8.columns { fuses[base + c] = true }
            for (name, positive) in cube.literals {
                let p = try pair(forSignal: name)   // validates the name exists
                let sig = signals[name]!
                // Column true-level is the pin voltage; an active-low signal
                // inverts the mapping between logical literal and column.
                let columnNegated = (positive == sig.activeLow)
                fuses[base + 2 * p + (columnNegated ? 1 : 0)] = false
            }
        }

        for (idx, olmcPin) in GAL16V8.olmcPins.enumerated() {
            let rowBase = idx * 8
            let isOutput = logicEq[olmcPin] != nil

            // PTD: enabled for all rows (matches WinCUPL output)
            for r in 0 ..< 8 { fuses[GAL16V8.ptdBase + rowBase + r] = true }

            guard isOutput else {
                // unused OLMC: input configuration
                fuses[GAL16V8.ac1Base + idx] = true
                continue
            }

            let sig = design.pins.first { $0.number == olmcPin }!
            fuses[GAL16V8.xorBase + idx] = !sig.activeLow      // XOR=1: active high
            fuses[GAL16V8.ac1Base + idx] = (mode == .complex)  // complex I/O: AC1=1

            var rowCursor = rowBase
            if mode == .complex {
                // Row 0 is the OE term.
                if let oe = oeEq[olmcPin] {
                    let cubes = try LogicSynthesis.cubes(of: oe)
                    if cubes.isEmpty {
                        try writeRow(rowCursor, cube: nil)       // never enabled
                    } else if cubes.count == 1 {
                        try writeRow(rowCursor, cube: cubes[0])
                    } else {
                        throw FitError("pin \(olmcPin): .OE must reduce to a single product term")
                    }
                } else {
                    try writeRow(rowCursor, cube: Cube())        // always enabled
                }
                rowCursor += 1
            }

            let cubes = try LogicSynthesis.cubes(of: logicEq[olmcPin]!)
            guard cubes.count <= logicRowCapacity else {
                throw FitError("pin \(olmcPin): \(cubes.count) product terms exceed the \(logicRowCapacity) available")
            }
            for cube in cubes {
                try writeRow(rowCursor, cube: cube)
                rowCursor += 1
            }
        }

        // ---- architecture fuses ----------------------------------------
        fuses[GAL16V8.synFuse] = true                  // SYN=1: not registered
        fuses[GAL16V8.ac0Fuse] = (mode == .complex)    // AC0: 0 simple, 1 complex

        return JEDECFile(fuseCount: GAL16V8.fuseCount, fuses: fuses,
                         pinCount: 20,
                         header: "compiled by mgalws")
    }
}
