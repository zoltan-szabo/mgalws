// VectorScript.swift — a small stimulus/expectation script for simulations
//
// Line-oriented format:
//   # comment
//   watch PHI0 PHI1 VIAACT VIA        columns of the printed trace
//   set STRB=1 A9=0 A12=1             drive input pins by signal name
//   clock 5                           n rising edges (default 1), one trace row each
//   show                              print one trace row without clocking
//   expect VIAACT=1 VIA=0             assert pin levels (0, 1 or Z); failures collected
//
// Signal names come from the compiled design's PIN declarations; active-low
// declarations refer to the pin, and levels in set/expect are PIN VOLTAGES.

public struct VectorReport: Sendable {
    public var trace: [String] = []
    public var failures: [String] = []
    public var passed: Bool { failures.isEmpty }
}

public enum VectorScript {
    public static func run(script: String, design: PLDDesign, jed: JEDECFile) throws -> VectorReport {
        guard jed.fuseCount == GAL22V10.fuseCount else {
            throw SimulationError("vector scripts currently support the GAL22V10 only")
        }
        var sim = GAL22V10Simulator(try GAL22V10.decode(jed))

        var pinOf: [String: Int] = [:]
        for pin in design.pins { pinOf[pin.name] = pin.number }

        var report = VectorReport()
        var watch: [String] = []
        var cycle = 0

        func level(named name: String) throws -> PinLevel {
            guard let pin = pinOf[name] else { throw SimulationError("unknown signal \(name)") }
            if GAL22V10.olmcPins.contains(pin) {
                return try sim.outputs()[pin]!
            }
            return (sim.inputs[pin] ?? false) ? .high : .low
        }

        func traceRow(_ tag: String) throws {
            guard !watch.isEmpty else { return }
            let cells = try watch.map { "\($0)=\(try level(named: $0).symbol)" }
            report.trace.append("[\(tag)] " + cells.joined(separator: " "))
        }

        for (index, rawLine) in script.components(separatedBy: .newlines).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(separator: " ").map(String.init)
            let lineNo = index + 1
            switch parts[0].lowercased() {
            case "watch":
                watch = Array(parts.dropFirst())
                for name in watch where pinOf[name] == nil {
                    throw SimulationError("line \(lineNo): unknown signal \(name)")
                }
            case "set":
                for assign in parts.dropFirst() {
                    let kv = assign.split(separator: "=").map(String.init)
                    guard kv.count == 2, let pin = pinOf[kv[0]], kv[1] == "0" || kv[1] == "1" else {
                        throw SimulationError("line \(lineNo): bad assignment \(assign)")
                    }
                    guard !GAL22V10.olmcPins.contains(pin) else {
                        throw SimulationError("line \(lineNo): \(kv[0]) is an output")
                    }
                    sim.inputs[pin] = kv[1] == "1"
                }
            case "clock":
                let n = parts.count > 1 ? Int(parts[1]) ?? 1 : 1
                for _ in 0 ..< n {
                    try sim.clock()
                    cycle += 1
                    try traceRow("t\(cycle)")
                }
            case "show":
                try traceRow("t\(cycle)")
            case "expect":
                for expectation in parts.dropFirst() {
                    let kv = expectation.split(separator: "=").map(String.init)
                    guard kv.count == 2 else {
                        throw SimulationError("line \(lineNo): bad expectation \(expectation)")
                    }
                    let actual = try level(named: kv[0])
                    let want: PinLevel
                    switch kv[1].uppercased() {
                    case "0": want = .low
                    case "1": want = .high
                    case "Z": want = .highZ
                    default: throw SimulationError("line \(lineNo): bad level \(kv[1])")
                    }
                    if actual != want {
                        report.failures.append(
                            "line \(lineNo), cycle \(cycle): \(kv[0]) expected \(want.symbol), got \(actual.symbol)")
                    }
                }
            default:
                throw SimulationError("line \(lineNo): unknown command \(parts[0])")
            }
        }
        return report
    }
}
