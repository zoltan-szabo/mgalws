// Simulator.swift — cycle-level simulation of decoded GAL fuse maps
//
// FuseDiff proves two images compute the same functions; the simulator
// shows what a fuse map DOES over time — registered state machines,
// output enables, pin polarities — before any chip is programmed.

public struct SimulationError: Error, CustomStringConvertible {
    public let description: String
    init(_ s: String) { description = s }
}

/// Pin level: driven high/low, or high impedance (output disabled).
public enum PinLevel: Equatable, Sendable {
    case low, high, highZ

    var symbol: String {
        switch self {
        case .low: return "0"
        case .high: return "1"
        case .highZ: return "Z"
        }
    }
}

/// Simulates a decoded GAL22V10: combinational OLMCs settle by fixed-point
/// iteration; registered OLMCs latch on `clock()`. Register power-up state
/// is cleared (Q = 0), matching the device's power-on reset.
public struct GAL22V10Simulator: Sendable {
    public let decoded: GAL22V10.Decoded
    public private(set) var q: [Int: Bool] = [:]        // registered OLMC pin -> Q
    public var inputs: [Int: Bool] = [:]                // input pin -> level

    public init(_ decoded: GAL22V10.Decoded) {
        self.decoded = decoded
        for olmc in decoded.olmcs where olmc.registered { q[olmc.pin] = false }
    }

    /// Solve combinational outputs for the current inputs and register state.
    /// Returns logical OLMC values (before polarity), keyed by pin.
    func solve() throws -> (logic: [Int: Bool], assignment: [Bool]) {
        var logic: [Int: Bool] = [:]
        for olmc in decoded.olmcs {
            logic[olmc.pin] = olmc.registered ? q[olmc.pin]! : false
        }
        var assignment = [Bool](repeating: false, count: GAL22V10.pairs)
        // Fixed point for combinational feedback chains (rare, but legal).
        for _ in 0 ..< 8 {
            for (pair, source) in decoded.columnSources.enumerated() {
                switch source {
                case .pin(let p):
                    assignment[pair] = inputs[p] ?? false
                case .feedback(let p):
                    let olmc = decoded.olmc(pin: p)!
                    if olmc.registered {
                        assignment[pair] = !q[p]!            // Q-bar
                    } else {
                        // Combinational feedback is the pin voltage.
                        let value = logic[p]!
                        assignment[pair] = olmc.activeHigh ? value : !value
                    }
                }
            }
            var changed = false
            for olmc in decoded.olmcs where !olmc.registered {
                let value = olmc.logic.evaluate(assignment)
                if logic[olmc.pin] != value { logic[olmc.pin] = value; changed = true }
            }
            if !changed { return (logic, assignment) }
        }
        throw SimulationError("combinational feedback did not settle")
    }

    /// Current pin levels for all OLMC pins.
    public func outputs() throws -> [Int: PinLevel] {
        let (logic, assignment) = try solve()
        var out: [Int: PinLevel] = [:]
        for olmc in decoded.olmcs {
            guard olmc.outputEnable.evaluate(assignment) else {
                out[olmc.pin] = .highZ
                continue
            }
            let value = olmc.registered ? q[olmc.pin]! : logic[olmc.pin]!
            let level = olmc.activeHigh ? value : !value
            out[olmc.pin] = level ? .high : .low
        }
        return out
    }

    /// One rising clock edge: registered OLMCs latch their D inputs
    /// (computed from the pre-edge state), honouring AR and SP.
    public mutating func clock() throws {
        let (_, assignment) = try solve()
        if decoded.asyncReset.evaluate(assignment) {
            for pin in q.keys { q[pin] = false }
            return
        }
        var next: [Int: Bool] = [:]
        let preset = decoded.syncPreset.evaluate(assignment)
        for olmc in decoded.olmcs where olmc.registered {
            next[olmc.pin] = preset ? true : olmc.logic.evaluate(assignment)
        }
        q = next
    }
}

/// Simulates a decoded GAL16V8 in simple or complex mode (combinational
/// only — registered mode is unsupported, matching the compiler).
public struct GAL16V8Simulator: Sendable {
    public let decoded: GAL16V8.Decoded
    public var inputs: [Int: Bool] = [:]

    public init(_ decoded: GAL16V8.Decoded) throws {
        guard decoded.mode != .registered else {
            throw SimulationError("registered GAL16V8 simulation is not supported")
        }
        self.decoded = decoded
    }

    public func outputs() throws -> [Int: PinLevel] {
        var logic: [Int: Bool] = [:]
        for olmc in decoded.olmcs { logic[olmc.pin] = false }
        var assignment = [Bool](repeating: false, count: GAL16V8.pairs)
        for _ in 0 ..< 8 {
            for (pair, source) in decoded.columnSources.enumerated() {
                switch source {
                case .pin(let p):
                    assignment[pair] = inputs[p] ?? false
                case .feedback(let p):
                    guard let olmc = decoded.olmc(pin: p) else { continue }
                    if olmc.kind == .input {
                        assignment[pair] = inputs[p] ?? false
                    } else {
                        let value = logic[p]!
                        assignment[pair] = olmc.activeHigh ? value : !value
                    }
                }
            }
            var changed = false
            for olmc in decoded.olmcs where olmc.kind != .input {
                let value = olmc.logic.evaluate(assignment)
                if logic[olmc.pin] != value { logic[olmc.pin] = value; changed = true }
            }
            if !changed { break }
        }
        var out: [Int: PinLevel] = [:]
        for olmc in decoded.olmcs {
            if olmc.kind == .input { out[olmc.pin] = .highZ; continue }
            guard olmc.outputEnable.evaluate(assignment) else {
                out[olmc.pin] = .highZ
                continue
            }
            let level = olmc.activeHigh ? logic[olmc.pin]! : !logic[olmc.pin]!
            out[olmc.pin] = level ? .high : .low
        }
        return out
    }
}
