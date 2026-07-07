# History

Detailed notes per milestone. Commit messages stay short; the long story
lives here.

## Milestone 3 — registered outputs and GAL22V10 fitter (2026-07-08)

The compiler now targets the GAL22V10: combinational and registered
(.D) outputs, per-pin .OE, global .AR/.SP product terms, per-OLMC
polarity (S0) and mode (S1) bits, variable 8-16 term capacities, and
the registered-feedback-is-Q-bar column mapping. Registered GAL16V8
outputs remain unsupported (no golden reference to validate against).

Golden test: DCJ11SBC-W65C22S-EXPLICIT.PLD expresses the Multi IO
card's PHI/VIAACT state machine as explicit .D equations (extracted
from the WinCUPL fuse map with mgalws decode). Compiling it reproduces
the shipped JED functionally on all ten pins — nine are fuse-identical;
DV differs only in term minimization. This also pre-derives exactly
what milestone 4's SEQUENCE support must generate.

## Fixture corrections (2026-07-08)

DCJ11SBC-V1-3-3-IO-HIZ.PLD (previously named DCJ11SBC-V1-3-3.PLD) is a
local modification by Zoltan Szabo, not an original 5volts.ch file: it
holds pin 18 (!IO) in permanent high impedance (IO.OE = 'b'0) so an
expansion card can drive the !IO net with unchanged schematic and PCB.
The GALasm-built JED of that modification was never tested in hardware
and has been removed from the fixtures; the tests now validate the
compiled output's pin-18 behaviour and its equivalence to the
WinCUPL-built V1-3-2 golden image on all other pins.

## Milestone 2 — CUPL equation compiler (2026-07-07)

`mgalws compile file.pld [out.jed]` compiles a CUPL subset to a GAL16V8
fuse map:

- Lexer/parser: header statements, PIN declarations (active-low `!name`),
  combinational equations with `! & # $`, parentheses, `'b'0`/`'b'1`
  constants, and the `.OE` extension. `/* */` comments.
- Logic synthesis: expression tree to sum-of-products with contradiction
  removal, deduplication, and single-cube absorption.
- GAL16V8 fitter: automatic mode selection (simple without `.OE`, complex
  with), active-low signal-to-column polarity mapping, product-term
  capacity checks, XOR/AC0/AC1/PTD/SYN configuration.

Golden tests compile Peter Schranz's DCJ11 SBC decoder source (V1-3-2)
and prove functional equivalence with the WinCUPL 5.0a fuse map that
runs in real hardware; the compiled output differs only in signature
fuses and term minimization choices. The V1-3-3-IO-HIZ local
modification exercises .OE support and complex-mode fitting.

## Milestone 1 — JEDEC toolkit (2026-07-07)

`mgalws decode file.jed` and `mgalws diff a.jed b.jed`:

- JESD3 parser/serializer: `*QF/*QP/*F/*L/*C` fields, STX/ETX framing,
  CRLF tolerance, LSB-first fuse checksum verified against WinCUPL's
  declared values.
- GAL16V8 decoder: all three modes (registered/complex/simple),
  mode-dependent column routing for pins 1/11, AC1/XOR/PTD handling.
- GAL22V10 decoder: variable 8-16 term groups, AR/SP rows, per-OLMC
  (S0, S1) configuration bits. Layout was verified empirically against
  WinCUPL output, including the detail that registered macrocell feedback
  enters the AND array inverted.
- FuseDiff: three-level comparison — fuse-identical, structurally
  identical, functionally equivalent (exhaustive over used inputs).

Test fixtures are fuse maps from Peter Schranz's DCJ11 SBC project
(https://www.5volts.ch/pages/dcj11sbc/), see Tests/mgalwsTests/Fixtures.
