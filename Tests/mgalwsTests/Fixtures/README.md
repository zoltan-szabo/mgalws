# Test fixtures

The `DCJ11SBC-*.jed` fuse maps in this directory are from the
**DCJ11 Single Board Computer** and **DCJ11 Multi IO card** projects by
**Peter Schranz** — https://www.5volts.ch/pages/dcj11sbc/ — and are included
here, with attribution, solely as reference test vectors for mgalws's JEDEC
reader and GAL decoders:

| File | Device | Origin |
|---|---|---|
| `DCJ11SBC-V1-3-2.jed` | GAL16V8 (simple mode) | SBC decoder GAL, compiled with WinCUPL 5.0a |
| `DCJ11SBC-V1-3-3-galasm.jed` | GAL16V8 (complex mode) | Same logic with `!IO` tri-stated, built with GALasm 2.1 |
| `DCJ11SBC-W65C22S.jed` | GAL22V10 | Multi IO card glue logic (W65C22S VIA interface), WinCUPL |
| `DCJ11SBC-V1-3-2.PLD` | CUPL source | SBC decoder, golden input for the mgalws compiler |
| `DCJ11SBC-V1-3-3.PLD` | CUPL source | Same with `IO.OE = 'b'0` tri-state fix |

The V1-3-2 / V1-3-3 pair is a valuable test case: two different compilers,
two different OLMC modes, functionally identical logic on every output except
one intentionally tri-stated pin.
