# Test fixtures

The `DCJ11SBC-*.jed` fuse maps in this directory are from the
**DCJ11 Single Board Computer** and **DCJ11 Multi IO card** projects by
**Peter Schranz** — https://www.5volts.ch/pages/dcj11sbc/ — and are included
here, with attribution, solely as reference test vectors for mgalws's JEDEC
reader and GAL decoders:

| File | Device | Origin |
|---|---|---|
| `DCJ11SBC-V1-3-2.jed` | GAL16V8 (simple mode) | SBC decoder GAL, compiled with WinCUPL 5.0a |
| `DCJ11SBC-W65C22S.jed` | GAL22V10 | Multi IO card glue logic (W65C22S VIA interface), WinCUPL |
| `DCJ11SBC-V1-3-2.PLD` | CUPL source | SBC decoder, golden input for the mgalws compiler |
| `DCJ11SBC-V1-3-3-IO-HIZ.PLD` | CUPL source | Local modification, see below |
| `DCJ11SBC-W65C22S-EXPLICIT.PLD` | CUPL source | Multi IO glue with the SEQUENCE state machine rewritten as explicit .D equations (derived for mgalws testing) |
| `DCJ11SBC-W65C22S.PLD` | CUPL source | Original Multi IO glue logic, golden input for FIELD/SEQUENCE support |

`DCJ11SBC-V1-3-3-IO-HIZ.PLD` is a local modification by Zoltan Szabo
(github.com/zoltan-szabo), not part of the original 5volts.ch distribution:
it holds pin 18 (`!IO`) in permanent high impedance via `IO.OE = 'b'0` so
that an expansion card can drive the `!IO` net. It exercises the `.OE`
extension and complex-mode fitting in the compiler tests. It has not been
tested in hardware.

The V1-3-2 / V1-3-3 pair remains a useful test case: two OLMC modes,
functionally identical logic on every output except one intentionally
tri-stated pin.
