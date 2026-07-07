# mgalws — Mac GAL WorkShop

A native macOS toolchain for GAL programmable logic devices (GAL16V8, GAL22V10),
written in Swift. Compiles CUPL `.PLD` sources to JEDEC fuse maps — no Wine, no
Windows VM, no abandonware IDE.

Sibling project of [m11asm](https://github.com/zoltan-szabo/m11asm) and
[J11Terminal](https://github.com/zoltan-szabo/j11-terminal); built for bare-metal
DCJ-11 / PDP-11 hardware development on the
[DCJ11 SBC](https://www.5volts.ch/pages/dcj11sbc/) by Peter Schranz.

## Status

Early development. Roadmap:

1. **JED toolkit** (done) — read, write, decode, and diff JEDEC fuse maps;
   decode GAL16V8/22V10 macrocell configuration back to equations
2. **Equation compiler** (done) — CUPL-subset combinational equations to
   GAL16V8 fuse map, golden-tested against WinCUPL output. Note: GAL16V8
   simple mode is hardware-verified; complex mode (.OE) compiles to
   GALasm-equivalent fuse maps but failed its first in-circuit test and
   is considered unvalidated on real silicon
3. **Registered outputs** (done) — `.d`/`.oe`/`.ar`/`.sp` extensions and a
   GAL22V10 fitter, golden-tested against the Multi IO card's WinCUPL image
4. **State machines** (done) — CUPL `FIELD` and `SEQUENCE` (with IF/NEXT/
   OUT/DEFAULT); Peter Schranz's original Multi IO glue PLD compiles
   unmodified to a fuse map equivalent to the hardware image. `TABLE`
   deferred until a design needs it
5. **Verification** (done) — functional-equivalence diffing (part of the
   JED toolkit) plus cycle-level simulation: `mgalws sim design.pld
   script.vec` drives a design through clocked vector scripts with
   watch/set/clock/expect commands, covering registered state machines,
   output enables and polarities before any chip is programmed

## Building

Requires Xcode 16 or the Swift 6 toolchain.

```bash
swift build
swift test
```

## License

MIT — see [LICENSE](LICENSE).
