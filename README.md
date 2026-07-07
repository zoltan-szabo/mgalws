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

1. **JED toolkit** — read, write, decode, and diff JEDEC fuse maps; decode
   GAL16V8/22V10 macrocell configuration and product terms back to equations
2. **Equation compiler** — boolean equations to fuse map (GALasm parity)
3. **Registered outputs** — `.d`/`.oe`/`.ar`/`.sp` extensions, GAL22V10 fitter
4. **State machines** — CUPL `FIELD` / `SEQUENCE` / `TABLE` support
5. **Verification** — exhaustive functional-equivalence checking between
   compiled output and reference fuse maps; simulation vectors

## Building

Requires Xcode 16 or the Swift 6 toolchain.

```bash
swift build
swift test
```

## License

MIT — see [LICENSE](LICENSE).
