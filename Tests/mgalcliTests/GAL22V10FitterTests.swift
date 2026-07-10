import Foundation
import Testing
@testable import mgalcliCore

// Milestone 3 golden test: DCJ11SBC-W65C22S-EXPLICIT.PLD carries the state
// machine of Peter Schranz's Multi IO glue logic as explicit .D equations
// (extracted from the WinCUPL fuse map). Compiling it must produce a fuse
// map functionally identical to the JED running in real hardware.

@Suite struct GAL22V10GoldenCompilation {
    func compiled() throws -> JEDECFile {
        try PLDCompiler.compile(try fixtureText("DCJ11SBC-W65C22S-EXPLICIT", ext: "PLD")).jed
    }

    @Test func matchesWinCUPLOnEveryPin() throws {
        let diff = try FuseDiff.gal22v10(try compiled(), try fixture("DCJ11SBC-W65C22S"))
        for pin in diff.pins {
            #expect(pin.logicEquivalent, "pin \(pin.pin) logic differs from WinCUPL")
            #expect(pin.oeEquivalent, "pin \(pin.pin) OE differs from WinCUPL")
        }
        #expect(diff.isFunctionallyEquivalent)
    }

    @Test func macrocellConfigurationMatchesGolden() throws {
        let mine = try GAL22V10.decode(try compiled())
        let golden = try GAL22V10.decode(try fixture("DCJ11SBC-W65C22S"))
        for (a, b) in zip(mine.olmcs, golden.olmcs) {
            #expect(a.registered == b.registered, "pin \(a.pin) registered flag")
            #expect(a.activeHigh == b.activeHigh, "pin \(a.pin) polarity")
        }
    }

    @Test func arAndSpMatchGolden() throws {
        let mine = try GAL22V10.decode(try compiled())
        #expect(mine.asyncReset.isConstantFalse)
        #expect(mine.syncPreset.isConstantFalse)
    }
}

@Suite struct GAL22V10FitterUnit {
    @Test func registeredFeedbackIsQBar() throws {
        // Y = Q where Q is registered: the logical positive literal must
        // land on the complement column of Q's feedback pair (fb = Q-bar).
        let src = """
        Device G22V10;
        PIN 1 = CLK; PIN 2 = A;
        PIN 14 = Q; PIN 23 = Y;
        Q.d = A;
        Y = Q;
        """
        let jed = try PLDCompiler.compile(src).jed
        let d = try GAL22V10.decode(jed)
        let q = try #require(d.olmc(pin: 14))
        #expect(q.registered)
        let y = try #require(d.olmc(pin: 23))
        #expect(!y.registered)
        let namer = d.namer(pinNames: [14: "Q"])
        #expect(namer.render(y.logic) == "!fbQ")
    }

    @Test func combinatorialFeedbackIsPinVoltage() throws {
        // Y = X where X is a combinatorial active-low output: logical X-true
        // means pin low, so the literal lands on the complement column too —
        // but via the polarity rule, not the register rule.
        let src = """
        Device G22V10;
        PIN 2 = A;
        PIN 14 = !X; PIN 23 = Y;
        X = A;
        Y = X;
        """
        let jed = try PLDCompiler.compile(src).jed
        let d = try GAL22V10.decode(jed)
        let namer = d.namer(pinNames: [14: "X"])
        let y = try #require(d.olmc(pin: 23))
        #expect(namer.render(y.logic) == "!fbX")
    }

    @Test func polarityBitsFollowDeclaration() throws {
        let src = """
        Device G22V10;
        PIN 2 = A;
        PIN 14 = !LO; PIN 15 = HI;
        LO = A;
        HI = A;
        """
        let d = try GAL22V10.decode(try PLDCompiler.compile(src).jed)
        #expect(try #require(d.olmc(pin: 14)).activeHigh == false)
        #expect(try #require(d.olmc(pin: 15)).activeHigh == true)
    }

    @Test func globalARMustAgree() {
        let src = """
        Device G22V10;
        PIN 1 = CLK; PIN 2 = A; PIN 3 = B;
        PIN 14 = Q; PIN 15 = R;
        Q.d = A; Q.ar = A;
        R.d = B; R.ar = B;
        """
        #expect(throws: FitError.self) { try PLDCompiler.compile(src) }
    }

    @Test func termCapacityEnforced() {
        // Pin 14 has 8 terms; an 9-term XOR chain of 4 variables (8 minterms
        // for odd parity) fits exactly, 5 variables (16 minterms) must not.
        let src = """
        Device G22V10;
        PIN 2 = A; PIN 3 = B; PIN 4 = C; PIN 5 = D; PIN 6 = E;
        PIN 14 = Q;
        Q = A $ B $ C $ D $ E;
        """
        #expect(throws: FitError.self) { try PLDCompiler.compile(src) }
    }

    @Test func registered16V8Rejected() {
        let src = "Device G16V8; PIN 1 = CLK; PIN 2 = A; PIN 14 = Q; Q.d = A;"
        #expect(throws: FitError.self) { try PLDCompiler.compile(src) }
    }
}
