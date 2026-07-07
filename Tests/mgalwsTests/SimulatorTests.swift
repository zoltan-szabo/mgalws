import Foundation
import Testing
@testable import mgalwsCore

// Milestone 5: cycle-level simulation. The vector fixture drives the Multi
// IO state machine through a full stretched bus cycle and checks the
// VIAACT window, VIA select, DV handshake and console decode — against
// both the WinCUPL fuse map running in real hardware and the
// mgalws-compiled equivalent.

@Suite struct VectorGolden {
    func design() throws -> PLDDesign {
        var d = try PLDParser.parse(try fixtureText("DCJ11SBC-W65C22S", ext: "PLD"))
        try SequenceLowering.lower(&d)
        return d
    }

    func script() throws -> String {
        let url = Bundle.module.url(forResource: "Fixtures/W65C22S-statemachine", withExtension: "vec")!
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func hardwareJEDPassesVectors() throws {
        let report = try VectorScript.run(script: try script(),
                                          design: try design(),
                                          jed: try fixture("DCJ11SBC-W65C22S"))
        #expect(report.passed, "failures: \(report.failures)")
    }

    @Test func compiledJEDPassesVectors() throws {
        let compiled = try PLDCompiler.compile(try fixtureText("DCJ11SBC-W65C22S", ext: "PLD"))
        let report = try VectorScript.run(script: try script(),
                                          design: try design(),
                                          jed: compiled.jed)
        #expect(report.passed, "failures: \(report.failures)")
    }
}

@Suite struct SimulatorUnit {
    @Test func gal16v8SimulatesDecoder() throws {
        // The proven V1-3-2 image: CE asserts for memory cycles,
        // IO asserts for I/O-page cycles. Signals per the PLD:
        // pins 5=LBS0, 6=LBS1; outputs 17=!CE, 18=!IO (active low).
        var sim = try GAL16V8Simulator(try GAL16V8.decode(try fixture("DCJ11SBC-V1-3-2")))
        sim.inputs = [5: false, 6: false]           // LBS = 00: memory cycle
        var out = try sim.outputs()
        #expect(out[17] == .low)                    // !CE asserted
        #expect(out[18] == .high)                   // !IO not asserted
        sim.inputs = [5: false, 6: true]            // LBS = 10: I/O page
        out = try sim.outputs()
        #expect(out[17] == .high)
        #expect(out[18] == .low)                    // !IO asserted
    }

    @Test func ioInputVariantPin18IsHighZ() throws {
        // The hardware-verified IO-INPUT image: pin 18 must never drive.
        let compiled = try PLDCompiler.compile(
            try fixtureText("DCJ11SBC-V1-3-2-IO-INPUT", ext: "PLD"))
        var sim = try GAL16V8Simulator(try GAL16V8.decode(compiled.jed))
        for lbs in [(false, false), (true, false), (false, true), (true, true)] {
            sim.inputs = [5: lbs.0, 6: lbs.1]
            #expect(try sim.outputs()[18] == .highZ)
        }
    }

    @Test func asyncResetClearsRegisters() throws {
        let src = """
        Device G22V10;
        PIN 1 = CLK; PIN 2 = GO; PIN 3 = RST;
        PIN 14 = Q;
        Q.d = GO # Q;
        Q.ar = RST;
        """
        let compiled = try PLDCompiler.compile(src)
        var sim = GAL22V10Simulator(try GAL22V10.decode(compiled.jed))
        sim.inputs = [2: true, 3: false]
        try sim.clock()
        #expect(try sim.outputs()[14] == .high)     // latched and self-holding
        sim.inputs = [2: false, 3: true]            // async reset term true
        try sim.clock()
        #expect(try sim.outputs()[14] == .low)
    }
}
