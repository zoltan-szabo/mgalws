import Foundation
import Testing
@testable import mgalwsCore

// Milestone 4 golden test: Peter Schranz's original DCJ11SBC-W65C22S.PLD —
// FIELD, SEQUENCE, .AR/.SP and all — compiles to a fuse map functionally
// equivalent to the WinCUPL JED running in real Multi IO hardware.

@Suite struct SequenceParsing {
    @Test func fieldRangeExpandsMSBFirst() throws {
        let d = try PLDParser.parse("FIELD PHI = [PHI3..0];")
        #expect(d.fields["PHI"] == ["PHI3", "PHI2", "PHI1", "PHI0"])
    }

    @Test func fieldListForm() throws {
        let d = try PLDParser.parse("FIELD S = [HI, MID, LO];")
        #expect(d.fields["S"] == ["HI", "MID", "LO"])
    }

    @Test func parsesOriginalW65C22S() throws {
        let d = try PLDParser.parse(try fixtureText("DCJ11SBC-W65C22S", ext: "PLD"))
        #expect(d.fields["PHI"] == ["PHI3", "PHI2", "PHI1", "PHI0"])
        #expect(d.sequences.count == 1)
        let seq = try #require(d.sequences.first)
        #expect(seq.field == "PHI")
        #expect(seq.transitions.count == 20)     // 10 states x 2 clauses
        let outs = seq.transitions.filter { !$0.outs.isEmpty }
        #expect(outs.count == 2)
        #expect(outs.allSatisfy { $0.outs == ["VIAACT"] })
    }
}

@Suite struct SequenceGoldenCompilation {
    @Test func originalW65C22SMatchesHardwareJED() throws {
        let compiled = try PLDCompiler.compile(
            try fixtureText("DCJ11SBC-W65C22S", ext: "PLD")).jed
        let diff = try FuseDiff.gal22v10(compiled, try fixture("DCJ11SBC-W65C22S"))
        for pin in diff.pins {
            #expect(pin.logicEquivalent, "pin \(pin.pin) logic differs from WinCUPL")
            #expect(pin.oeEquivalent, "pin \(pin.pin) OE differs from WinCUPL")
        }
        #expect(diff.isFunctionallyEquivalent)
    }

    @Test func sequenceAndExplicitFormsAgree() throws {
        // The SEQUENCE form and the hand-derived explicit .D form must
        // produce functionally identical devices.
        let a = try PLDCompiler.compile(try fixtureText("DCJ11SBC-W65C22S", ext: "PLD")).jed
        let b = try PLDCompiler.compile(try fixtureText("DCJ11SBC-W65C22S-EXPLICIT", ext: "PLD")).jed
        let diff = try FuseDiff.gal22v10(a, b)
        #expect(diff.isFunctionallyEquivalent)
    }
}

@Suite struct SequenceLoweringUnit {
    @Test func defaultClauseNegatesSiblingConditions() throws {
        // 1-bit machine: from state 0, go to 1 if GO, else stay (DEFAULT).
        let src = """
        Device G22V10;
        PIN 1 = CLK; PIN 2 = GO;
        PIN 14 = ST0;
        FIELD S = [ST0];
        SEQUENCE S {
            PRESENT 0 IF GO NEXT 1;
                      DEFAULT NEXT 0;
            PRESENT 1 NEXT 1;
        }
        """
        let jed = try PLDCompiler.compile(src).jed
        let d = try GAL22V10.decode(jed)
        let st0 = try #require(d.olmc(pin: 14))
        #expect(st0.registered)
        // ST0.d = !ST0 & GO # ST0  (registered feedback is Q-bar)
        let namer = d.namer(pinNames: [2: "GO", 14: "ST0"])
        let rendered = namer.render(st0.logic)
        #expect(rendered.contains("GO"))
        // Verify behaviour: D is true when (ST0=0 & GO) or ST0=1.
        // Column pairs: GO = pin 2 -> pair 2; fbST0 -> pair 19 (Q-bar).
        var assignment = [Bool](repeating: false, count: GAL22V10.pairs)
        assignment[19] = true    // fb = Q-bar high = ST0 logically 0
        assignment[2] = false    // GO low
        #expect(!st0.logic.evaluate(assignment))
        assignment[2] = true     // GO high
        #expect(st0.logic.evaluate(assignment))
        assignment[19] = false   // ST0 logically 1
        assignment[2] = false
        #expect(st0.logic.evaluate(assignment))
    }

    @Test func unknownFieldRejected() {
        let src = """
        Device G22V10;
        PIN 1 = CLK; PIN 14 = Q;
        SEQUENCE NOPE { PRESENT 0 NEXT 0; }
        """
        #expect(throws: FitError.self) { try PLDCompiler.compile(src) }
    }

    @Test func stateExceedingFieldWidthRejected() {
        let src = """
        Device G22V10;
        PIN 1 = CLK; PIN 14 = A0;
        FIELD S = [A0];
        SEQUENCE S { PRESENT 0 NEXT 5; }
        """
        #expect(throws: FitError.self) { try PLDCompiler.compile(src) }
    }
}
