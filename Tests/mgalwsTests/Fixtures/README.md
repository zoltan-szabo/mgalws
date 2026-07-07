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

`DCJ11SBC-V1-3-3-IO-HIZ.PLD` and `DCJ11SBC-V1-3-2-IO-INPUT.PLD` are local
modifications by Zoltan Szabo (github.com/zoltan-szabo), not part of the
original 5volts.ch distribution. Both aim to free pin 18 (`!IO`) so an
expansion card can drive that net:

- IO-HIZ uses `IO.OE = 'b'0`, which forces the whole device into complex
  mode. **Hardware test 2026-07-08: does not work in the SBC** (the
  equivalent GALasm-built image was never hardware-tested either). Kept
  as a compiler test for `.OE`/complex-mode fitting.
- IO-INPUT simply omits the IO output, so the device stays in the proven
  simple mode and pin 18's OLMC becomes a dedicated input.
  **Hardware-verified working 2026-07-08.**

The V1-3-2 / V1-3-3 pair remains a useful test case: two OLMC modes,
functionally identical logic on every output except one intentionally
tri-stated pin.
