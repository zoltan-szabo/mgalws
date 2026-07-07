// FuseDiff.swift — compare two GAL fuse maps at fuse, structural, and functional level

public struct FuseDiff: Sendable {
    public struct PinReport: Sendable {
        public let pin: Int
        public let logicIdentical: Bool        // same terms, same order
        public let logicEquivalent: Bool       // same boolean function
        public let oeIdentical: Bool
        public let oeEquivalent: Bool
    }

    public let differingFuses: [Int]
    public let pins: [PinReport]

    public var isIdentical: Bool { differingFuses.isEmpty }
    public var isFunctionallyEquivalent: Bool {
        pins.allSatisfy { $0.logicEquivalent && $0.oeEquivalent }
    }

    /// Compare two GAL16V8 images (modes may differ — comparison is functional).
    public static func gal16v8(_ a: JEDECFile, _ b: JEDECFile) throws -> FuseDiff {
        let da = try GAL16V8.decode(a), db = try GAL16V8.decode(b)
        let diffs = zip(a.fuses, b.fuses).enumerated().compactMap { $1.0 != $1.1 ? $0 : nil }
        var pins: [PinReport] = []
        for (oa, ob) in zip(da.olmcs, db.olmcs) {
            pins.append(PinReport(
                pin: oa.pin,
                logicIdentical: oa.logic == ob.logic,
                logicEquivalent: oa.logic.isEquivalent(to: ob.logic, pairCount: GAL16V8.pairs),
                oeIdentical: oa.outputEnable == ob.outputEnable,
                oeEquivalent: oa.outputEnable.isEquivalent(to: ob.outputEnable, pairCount: GAL16V8.pairs)))
        }
        return FuseDiff(differingFuses: diffs, pins: pins)
    }

    /// Compare two GAL22V10 images.
    public static func gal22v10(_ a: JEDECFile, _ b: JEDECFile) throws -> FuseDiff {
        let da = try GAL22V10.decode(a), db = try GAL22V10.decode(b)
        let diffs = zip(a.fuses, b.fuses).enumerated().compactMap { $1.0 != $1.1 ? $0 : nil }
        var pins: [PinReport] = []
        for (oa, ob) in zip(da.olmcs, db.olmcs) {
            pins.append(PinReport(
                pin: oa.pin,
                logicIdentical: oa.logic == ob.logic,
                logicEquivalent: oa.logic.isEquivalent(to: ob.logic, pairCount: GAL22V10.pairs),
                oeIdentical: oa.outputEnable == ob.outputEnable,
                oeEquivalent: oa.outputEnable.isEquivalent(to: ob.outputEnable, pairCount: GAL22V10.pairs)))
        }
        return FuseDiff(differingFuses: diffs, pins: pins)
    }
}
