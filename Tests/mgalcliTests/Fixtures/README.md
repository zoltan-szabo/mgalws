# Test fixtures

Most files here are from the **DCJ11 Single Board Computer** and
**DCJ11 Multi IO card** projects by **Peter Schranz** —
https://www.5volts.ch/pages/dcj11sbc/ — included, with attribution, as
reference test vectors for mgalcli.

## SBC decoder GAL (GAL16V8)

| File | Origin |
|---|---|
| `DCJ11SBC-V1-3-2.PLD` | Original decoder source (Peter Schranz) |
| `DCJ11SBC-V1-3-2.jed` | WinCUPL 5.0a build of it — runs in real hardware |
| `DCJ11SBC-V1-3-2-IO-INPUT.PLD` | Local modification by Zoltan Szabo, hardware-verified 2026-07-08 |

`DCJ11SBC-V1-3-2-IO-INPUT.PLD` omits the `IO` output so that pin 18's
OLMC becomes a dedicated input (high impedance): the Multi IO expansion
card drives the `!IO` net instead, with schematic and PCB unchanged. The
device stays in the same simple mode as the proven original — the fuse
delta is pin 18's cleared row plus its AC1 configuration bit.

An earlier attempt achieved the same goal with `IO.OE = 'b'0`, which
forces the whole device into complex mode. That image (identical to a
GALasm build of the same design) **failed its in-circuit test** and was
removed; GAL16V8 complex mode is considered unvalidated on real silicon.
See HISTORY.md. The `.OE`/complex-mode compiler features remain covered
by inline test sources.

## Multi IO glue GAL (GAL22V10)

| File | Origin |
|---|---|
| `DCJ11SBC-W65C22S.PLD` | Original glue-logic source with SEQUENCE state machine (Peter Schranz) |
| `DCJ11SBC-W65C22S.jed` | WinCUPL build of it — runs in real hardware |
| `DCJ11SBC-W65C22S-EXPLICIT.PLD` | Same design with the SEQUENCE rewritten as explicit .D equations (derived for mgalcli testing by Zoltan Szabo) |
| `W65C22S-statemachine.vec` | Sequential golden vectors for the state machine (written for mgalcli by Zoltan Szabo) |
