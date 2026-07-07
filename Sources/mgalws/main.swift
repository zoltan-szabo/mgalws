// mgalws — Mac GAL WorkShop CLI

import Foundation
import mgalwsCore

func usage() -> Never {
    print("""
    mgalws — Mac GAL WorkShop

    USAGE:
      mgalws compile <file.pld> [out.jed] Compile CUPL equations to a JEDEC fuse map
      mgalws decode <file.jed>            Decode a GAL16V8/22V10 fuse map to equations
      mgalws diff <a.jed> <b.jed>         Compare two fuse maps (fuse + functional level)

    Device is detected from the fuse count (QF2194 = GAL16V8, QF5892 = GAL22V10).
    """)
    exit(2)
}

func load(_ path: String) -> JEDECFile {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        print("error: cannot read \(path)"); exit(1)
    }
    do { return try JEDECFile.parse(text) }
    catch { print("error: \(path): \(error)"); exit(1) }
}

func decodeCommand(_ path: String) {
    let jed = load(path)
    print("\(path): QF\(jed.fuseCount), fuse checksum \(String(format: "%04X", jed.computedFuseChecksum))"
          + (jed.declaredFuseChecksum.map { $0 == jed.computedFuseChecksum ? " (matches declared)" : " (DECLARED \(String(format: "%04X", $0)) MISMATCH)" } ?? ""))
    switch jed.fuseCount {
    case GAL16V8.fuseCount:
        guard let d = try? GAL16V8.decode(jed) else { print("decode failed"); exit(1) }
        let namer = d.namer()
        print("device GAL16V8, mode: \(d.mode.rawValue)")
        for o in d.olmcs {
            print("\npin \(o.pin) [\(o.kind.rawValue), active \(o.activeHigh ? "high" : "low")]")
            if o.kind == .input { continue }
            if !o.outputEnable.isConstantTrue { print("  OE = \(namer.render(o.outputEnable))") }
            print("  = \(namer.render(o.logic))")
        }
    case GAL22V10.fuseCount:
        guard let d = try? GAL22V10.decode(jed) else { print("decode failed"); exit(1) }
        let namer = d.namer()
        print("device GAL22V10")
        if !d.asyncReset.isConstantFalse { print("AR = \(namer.render(d.asyncReset))") }
        if !d.syncPreset.isConstantFalse { print("SP = \(namer.render(d.syncPreset))") }
        for o in d.olmcs {
            print("\npin \(o.pin) [\(o.registered ? "registered" : "combinatorial"), active \(o.activeHigh ? "high" : "low")]")
            if !o.outputEnable.isConstantTrue { print("  OE = \(namer.render(o.outputEnable))") }
            print("  = \(namer.render(o.logic))")
        }
    default:
        print("unsupported device: QF\(jed.fuseCount)"); exit(1)
    }
}

func diffCommand(_ pathA: String, _ pathB: String) {
    let a = load(pathA), b = load(pathB)
    guard a.fuseCount == b.fuseCount else {
        print("different devices: QF\(a.fuseCount) vs QF\(b.fuseCount)"); exit(1)
    }
    let diff: FuseDiff
    do {
        switch a.fuseCount {
        case GAL16V8.fuseCount: diff = try FuseDiff.gal16v8(a, b)
        case GAL22V10.fuseCount: diff = try FuseDiff.gal22v10(a, b)
        default: print("unsupported device: QF\(a.fuseCount)"); exit(1)
        }
    } catch { print("error: \(error)"); exit(1) }
    print("\(diff.differingFuses.count) fuse(s) differ")
    for p in diff.pins {
        let logic = p.logicIdentical ? "identical" : (p.logicEquivalent ? "equivalent" : "DIFFERENT")
        let oe = p.oeIdentical ? "identical" : (p.oeEquivalent ? "equivalent" : "DIFFERENT")
        print("  pin \(p.pin): logic \(logic), OE \(oe)")
    }
    exit(diff.isFunctionallyEquivalent ? 0 : 1)
}

func compileCommand(_ path: String, output: String?) {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        print("error: cannot read \(path)"); exit(1)
    }
    do {
        let compiled = try PLDCompiler.compile(text)
        let outPath = output ?? path.replacingOccurrences(
            of: "\\.[pP][lL][dD]$", with: "", options: .regularExpression) + ".jed"
        try compiled.jed.serialized().write(toFile: outPath, atomically: true, encoding: .utf8)
        print("\(compiled.deviceName): \(outPath)  (fuse checksum \(String(format: "%04X", compiled.jed.computedFuseChecksum)))")
    } catch {
        print("error: \(error)"); exit(1)
    }
}

let args = Array(CommandLine.arguments.dropFirst())
switch (args.first, args.count) {
case ("compile", 2): compileCommand(args[1], output: nil)
case ("compile", 3): compileCommand(args[1], output: args[2])
case ("decode", 2): decodeCommand(args[1])
case ("diff", 3): diffCommand(args[1], args[2])
default: usage()
}
