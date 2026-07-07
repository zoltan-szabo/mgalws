import Foundation
import Testing
@testable import mgalwsCore

// Fixture fuse maps are from Peter Schranz's DCJ11 SBC project
// (https://www.5volts.ch/pages/dcj11sbc/) — see Fixtures/README.md.
// Expected values below were verified against the original WinCUPL .PLD
// sources and by fuse-level analysis of the shipped JEDs.

func fixture(_ name: String) throws -> JEDECFile {
    let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "jed")!
    return try JEDECFile.parse(String(contentsOf: url, encoding: .utf8))
}

@Suite struct JEDECParsing {
    @Test func parsesWinCUPL16V8() throws {
        let jed = try fixture("DCJ11SBC-V1-3-2")
        #expect(jed.fuseCount == 2194)
        #expect(jed.fuses.count == 2194)
        #expect(jed.pinCount == 20)
        if let declared = jed.declaredFuseChecksum {
            #expect(jed.computedFuseChecksum == declared)
        }
    }

    @Test func parsesWinCUPL22V10() throws {
        let jed = try fixture("DCJ11SBC-W65C22S")
        #expect(jed.fuseCount == 5892)
        if let declared = jed.declaredFuseChecksum {
            #expect(jed.computedFuseChecksum == declared)
        }
    }

    @Test func serializedHasJESD3Framing() throws {
        // minipro requires STX/ETX framing with a transmission checksum.
        let text = try fixture("DCJ11SBC-V1-3-2").serialized()
        #expect(text.hasPrefix("\u{02}"))
        let etxIndex = try #require(text.firstIndex(of: "\u{03}"))
        let sumText = String(text[text.index(after: etxIndex)...])
        #expect(sumText.count == 4)
        let declared = try #require(UInt32(sumText, radix: 16))
        let covered = text[...etxIndex]
        let computed = covered.utf8.reduce(UInt32(0)) { $0 &+ UInt32($1) } & 0xFFFF
        #expect(computed == declared)
    }

    @Test func serializeRoundTrip() throws {
        for name in ["DCJ11SBC-V1-3-2", "DCJ11SBC-W65C22S"] {
            let original = try fixture(name)
            let reparsed = try JEDECFile.parse(original.serialized())
            #expect(reparsed.fuses == original.fuses, "round trip failed for \(name)")
            #expect(reparsed.declaredFuseChecksum == original.computedFuseChecksum)
        }
    }
}

@Suite struct GAL16V8Decoding {
    // Pin names from the DCJ11SBC-V1-3-2.PLD source.
    static let pinNames = [1: "LAIO3", 2: "LAIO2", 3: "LAIO1", 4: "LAIO0",
                           5: "LBS0", 6: "LBS1", 7: "nSCTL", 8: "nBUFCTL",
                           9: "A0", 11: "NXM"]

    @Test func v132IsSimpleMode() throws {
        let d = try GAL16V8.decode(try fixture("DCJ11SBC-V1-3-2"))
        #expect(d.mode == .simple)
    }

    @Test func v132PinIOEquation() throws {
        // V1-3-2 drives !IO (pin 18) for the whole I/O page: IO = LBS1 & !LBS0
        let d = try GAL16V8.decode(try fixture("DCJ11SBC-V1-3-2"))
        let namer = d.namer(pinNames: Self.pinNames)
        let io = try #require(d.olmc(pin: 18))
        #expect(io.kind == .simpleOutput)
        #expect(io.activeHigh == false)
        #expect(namer.render(io.logic) == "!LBS0 & LBS1")
    }

    @Test func v132CEEquation() throws {
        // CE = !LBS1 & !LBS0 — RAM enabled for every memory-space cycle.
        let d = try GAL16V8.decode(try fixture("DCJ11SBC-V1-3-2"))
        let namer = d.namer(pinNames: Self.pinNames)
        let ce = try #require(d.olmc(pin: 17))
        #expect(namer.render(ce.logic) == "!LBS0 & !LBS1")
    }
}

@Suite struct GAL16V8Diffing {
    @Test func winCUPLGoldenVersusCompiledIOInput() throws {
        // The WinCUPL-built V1-3-2 (runs in real hardware) against the
        // mgalws-compiled IO-INPUT variant (also hardware-verified):
        // everything equivalent except pin 18, which became an input.
        let compiled = try PLDCompiler.compile(
            try fixtureText("DCJ11SBC-V1-3-2-IO-INPUT", ext: "PLD")).jed
        let diff = try FuseDiff.gal16v8(try fixture("DCJ11SBC-V1-3-2"), compiled)
        for pin in diff.pins where pin.pin != 18 {
            #expect(pin.logicEquivalent, "pin \(pin.pin) logic should be equivalent")
            #expect(pin.oeEquivalent, "pin \(pin.pin) OE should be equivalent")
        }
        let pin18 = try #require(diff.pins.first { $0.pin == 18 })
        #expect(!pin18.oeEquivalent, "pin 18 must differ (output removed)")
        #expect(!diff.isFunctionallyEquivalent)
    }

    @Test func identityDiff() throws {
        let a = try fixture("DCJ11SBC-V1-3-2")
        let diff = try FuseDiff.gal16v8(a, a)
        #expect(diff.isIdentical)
        #expect(diff.isFunctionallyEquivalent)
    }
}

@Suite struct GAL22V10Decoding {
    // Pin names from the DCJ11SBC-W65C22S.PLD source (MultiIO card glue).
    static let pinNames = [1: "CLK", 2: "STRB", 3: "A9", 4: "A10", 5: "A11",
                           6: "A12", 7: "LAIO1", 8: "LAIO2", 9: "LAIO3",
                           10: "LBS0", 11: "LBS1", 13: "LAIO0",
                           14: "PHI0", 15: "PHI1", 16: "PHI2", 17: "PHI3",
                           18: "VIAACT", 19: "DV", 20: "SLU", 21: "ROM",
                           22: "CON", 23: "VIA"]

    func decoded() throws -> GAL22V10.Decoded {
        try GAL22V10.decode(try fixture("DCJ11SBC-W65C22S"))
    }

    @Test func macrocellConfiguration() throws {
        let d = try decoded()
        // State machine outputs are registered active-high;
        // decode outputs are combinatorial (SLU/ROM/CON/VIA active-low, DV active-high).
        for pin in [14, 15, 16, 17, 18] {
            let o = try #require(d.olmc(pin: pin))
            #expect(o.registered, "pin \(pin) should be registered")
            #expect(o.activeHigh, "pin \(pin) should be active high")
        }
        for pin in [20, 21, 22, 23] {
            let o = try #require(d.olmc(pin: pin))
            #expect(!o.registered, "pin \(pin) should be combinatorial")
            #expect(!o.activeHigh, "pin \(pin) should be active low")
        }
        let dv = try #require(d.olmc(pin: 19))
        #expect(!dv.registered)
        #expect(dv.activeHigh)
    }

    @Test func arAndSpAreNever() throws {
        let d = try decoded()
        #expect(d.asyncReset.isConstantFalse)
        #expect(d.syncPreset.isConstantFalse)
    }

    @Test func conEquation() throws {
        // CON = LBS1 & !LBS0 & A12 & A11 & A10 & A9 (console select, 177xxx)
        let d = try decoded()
        let namer = d.namer(pinNames: Self.pinNames)
        let con = try #require(d.olmc(pin: 22))
        #expect(namer.render(con.logic) == "A9 & A10 & A11 & A12 & !LBS0 & LBS1")
        #expect(con.outputEnable.isConstantTrue)
    }

    @Test func romEquationHasTwoTerms() throws {
        // ROM decodes 173xxx and 165xxx.
        let d = try decoded()
        let namer = d.namer(pinNames: Self.pinNames)
        let rom = try #require(d.olmc(pin: 21))
        #expect(rom.logic.terms.count == 2)
        #expect(namer.render(rom.logic) ==
            "A9 & A10 & !A11 & A12 & !LBS0 & LBS1\n  # A9 & !A10 & A11 & !A12 & !LBS0 & LBS1")
    }

    @Test func viaUsesRegisteredFeedbackInverted() throws {
        // VIA = IOpage & 174xxx & VIAACT. Registered feedback enters the
        // array as Q̄, so VIAACT-true appears as the complement column.
        let d = try decoded()
        let namer = d.namer(pinNames: Self.pinNames)
        let via = try #require(d.olmc(pin: 23))
        #expect(namer.render(via.logic) ==
            "!A9 & !A10 & A11 & A12 & !fbVIAACT & !LBS0 & LBS1")
    }

    @Test func dvIsDeMorganExpansion() throws {
        // DV = !(VIA range) # (VIA range & VIAACT) — WinCUPL expands to 7
        // single-literal terms.
        let d = try decoded()
        let dv = try #require(d.olmc(pin: 19))
        #expect(dv.logic.terms.count == 7)
        #expect(dv.logic.terms.allSatisfy {
            if case .product(let lits) = $0 { return lits.count == 1 }
            return false
        })
    }

    @Test func termCapacityPlacement() throws {
        // The design note requires DV on a wide OLMC: pin 19 has 16 rows.
        #expect(GAL22V10.termCounts[GAL22V10.olmcPins.firstIndex(of: 19)!] == 16)
    }
}
