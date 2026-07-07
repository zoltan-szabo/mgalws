import Foundation
import Testing
@testable import mgalwsCore

// Golden tests: compile the V1-3-2 PLD source by Peter Schranz and prove
// functional equivalence with the WinCUPL 5.0a fuse map running in real
// DCJ11 SBC hardware. V1-3-3 is a local tri-state modification (see
// Fixtures/README.md) and is tested for its intended pin-18 behaviour.

func fixtureText(_ name: String, ext: String) throws -> String {
    let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: ext)!
    return try String(contentsOf: url, encoding: .utf8)
}

@Suite struct LogicSynthesisTests {
    func cubes(_ e: LogicExpr) throws -> [Cube] { try LogicSynthesis.cubes(of: e) }

    @Test func deMorganOnAnd() throws {
        // !(A & B) = !A # !B
        let e = LogicExpr.not(.and(.ref("A"), .ref("B")))
        #expect(try cubes(e) == [Cube(["A": false]), Cube(["B": false])])
    }

    @Test func xorExpansion() throws {
        let e = LogicExpr.xor(.ref("A"), .ref("B"))
        #expect(try cubes(e) == [Cube(["A": true, "B": false]),
                                 Cube(["A": false, "B": true])])
    }

    @Test func contradictionsDrop() throws {
        // A & !A = FALSE
        let e = LogicExpr.and(.ref("A"), .not(.ref("A")))
        #expect(try cubes(e).isEmpty)
    }

    @Test func absorption() throws {
        // A # A&B = A
        let e = LogicExpr.or(.ref("A"), .and(.ref("A"), .ref("B")))
        #expect(try cubes(e) == [Cube(["A": true])])
    }

    @Test func constants() throws {
        #expect(try cubes(.constant(false)).isEmpty)
        #expect(try cubes(.constant(true)) == [Cube()])
        // A # !A = TRUE (via absorption of the tautology? — stays two cubes,
        // which is fine for fitting; just must not be empty)
        let taut = try cubes(.or(.ref("A"), .not(.ref("A"))))
        #expect(!taut.isEmpty)
    }
}

@Suite struct PLDParserTests {
    @Test func parsesV132() throws {
        let d = try PLDParser.parse(try fixtureText("DCJ11SBC-V1-3-2", ext: "PLD"))
        #expect(d.device == "G16V8")
        #expect(d.pins.count == 18)
        #expect(d.equations.count == 8)
        let scrl = d.pins.first { $0.name == "SCTL" }
        #expect(scrl?.activeLow == true)
        #expect(scrl?.number == 7)
    }

    @Test func parsesV133WithOEExtension() throws {
        let d = try PLDParser.parse(try fixtureText("DCJ11SBC-V1-3-3-IO-HIZ", ext: "PLD"))
        #expect(d.equations.contains { $0.target == "IO" && $0.ext == "OE" })
        #expect(d.equations.contains { $0.target == "IO" && $0.ext == nil
                                       && $0.expr == .constant(false) })
    }
}

@Suite struct GoldenCompilation {
    @Test func v132MatchesWinCUPL() throws {
        // Compile the V1-3-2 source; must be functionally identical to the
        // WinCUPL-built JED that runs in the real SBC.
        let compiled = try PLDCompiler.compile(try fixtureText("DCJ11SBC-V1-3-2", ext: "PLD"))
        let golden = try fixture("DCJ11SBC-V1-3-2")

        let decoded = try GAL16V8.decode(compiled.jed)
        #expect(decoded.mode == .simple)

        let diff = try FuseDiff.gal16v8(compiled.jed, golden)
        for pin in diff.pins {
            #expect(pin.logicEquivalent, "pin \(pin.pin) logic differs from WinCUPL")
            #expect(pin.oeEquivalent, "pin \(pin.pin) OE differs from WinCUPL")
        }
        #expect(diff.isFunctionallyEquivalent)
    }

    @Test func v133TriStatesPin18() throws {
        // V1-3-3 uses IO.OE = 'b'0 — must select complex mode and hold
        // pin 18 permanently high impedance.
        let compiled = try PLDCompiler.compile(try fixtureText("DCJ11SBC-V1-3-3-IO-HIZ", ext: "PLD"))
        let decoded = try GAL16V8.decode(compiled.jed)
        #expect(decoded.mode == .complex)
        let io = try #require(decoded.olmc(pin: 18))
        #expect(io.outputEnable.isConstantFalse)
        #expect(io.logic.isConstantFalse)
    }

    @Test func compiledJEDRoundTrips() throws {
        let compiled = try PLDCompiler.compile(try fixtureText("DCJ11SBC-V1-3-2", ext: "PLD"))
        let reparsed = try JEDECFile.parse(compiled.jed.serialized())
        #expect(reparsed.fuses == compiled.jed.fuses)
    }

    @Test func crossVersionEquivalence() throws {
        // Compile BOTH sources and diff them against each other: everything
        // equivalent except pin 18 (logic and OE).
        let a = try PLDCompiler.compile(try fixtureText("DCJ11SBC-V1-3-2", ext: "PLD")).jed
        let b = try PLDCompiler.compile(try fixtureText("DCJ11SBC-V1-3-3-IO-HIZ", ext: "PLD")).jed
        let diff = try FuseDiff.gal16v8(a, b)
        for pin in diff.pins where pin.pin != 18 {
            #expect(pin.logicEquivalent && pin.oeEquivalent, "pin \(pin.pin)")
        }
        let pin18 = try #require(diff.pins.first { $0.pin == 18 })
        #expect(!pin18.oeEquivalent)
    }
}

@Suite struct IOInputVariant {
    @Test func pin18BecomesInput() throws {
        // Hardware-verified 2026-07-08: simple mode, pin 18 as input.
        let compiled = try PLDCompiler.compile(
            try fixtureText("DCJ11SBC-V1-3-2-IO-INPUT", ext: "PLD"))
        let d = try GAL16V8.decode(compiled.jed)
        #expect(d.mode == .simple)
        let io = try #require(d.olmc(pin: 18))
        #expect(io.kind == .input)
        // All other pins equivalent to the proven WinCUPL image.
        let diff = try FuseDiff.gal16v8(compiled.jed, try fixture("DCJ11SBC-V1-3-2"))
        for pin in diff.pins where pin.pin != 18 {
            #expect(pin.logicEquivalent && pin.oeEquivalent, "pin \(pin.pin)")
        }
    }
}

@Suite struct FitterErrors {
    @Test func rejectsUnknownDevice() {
        let src = "Device G20V8; PIN 2 = A; PIN 19 = Q; Q = A;"
        #expect(throws: FitError.self) { try PLDCompiler.compile(src) }
    }

    @Test func rejectsUndeclaredSignal() {
        let src = "Device G16V8; PIN 2 = A; PIN 19 = Q; Q = A & GHOST;"
        #expect(throws: FitError.self) { try PLDCompiler.compile(src) }
    }

    @Test func rejectsEquationOnInputPin() {
        let src = "Device G16V8; PIN 2 = A; PIN 3 = B; B = A;"
        #expect(throws: FitError.self) { try PLDCompiler.compile(src) }
    }

    @Test func rejectsMultiTermOE() {
        let src = "Device G16V8; PIN 2 = A; PIN 3 = B; PIN 19 = Q; Q = A; Q.OE = A # B;"
        #expect(throws: FitError.self) { try PLDCompiler.compile(src) }
    }

    @Test func minimalDesignCompiles() throws {
        let src = "Device G16V8; PIN 2 = A; PIN 3 = B; PIN 19 = Q; Q = A & !B # !A & B;"
        let compiled = try PLDCompiler.compile(src)
        let d = try GAL16V8.decode(compiled.jed)
        let q = try #require(d.olmc(pin: 19))
        #expect(q.activeHigh)
        #expect(q.logic.terms.count == 2)
    }
}
