# History

Detailed notes per milestone. Commit messages stay short; the long story
lives here.

## Milestone 5 — cycle-level simulation (2026-07-08)

`mgalws sim design.pld script.vec` simulates a compiled design against a
line-oriented vector script (watch / set / clock / show / expect; levels
are pin voltages, expectations accept 0/1/Z). The simulator executes
decoded fuse maps directly: GAL22V10 with registered OLMCs (Q-bar
feedback, AR/SP, power-up clear) and combinational fixed-point settling;
GAL16V8 in simple/complex modes. This is the layer between "fuse maps
are equivalent" and "works in circuit" that the complex-mode episode
showed was missing — state machines can now be exercised cycle by cycle
before a chip is programmed.

Golden vectors: W65C22S-statemachine.vec drives the Multi IO glue
through a full stretched bus cycle (count 0-9, park 8/9, STRB reset,
VIAACT window at states 4-5, VIA select, DV falling edge, console
decode) and passes against both the WinCUPL fuse map running in real
hardware and the mgalws-compiled equivalent.

## Fixture cleanup (2026-07-08)

The SBC decoder fixtures are reduced to the two files that matter: the
original V1-3-2 (source + WinCUPL build, runs in hardware) and the
hardware-verified IO-INPUT modification (pin 18 as input, high
impedance, driven externally by the Multi IO card). The falsified
complex-mode IO-HIZ design was removed; .OE and complex-mode compiler
features are now covered by inline test sources instead of a fixture
that reads like a recommended design.

## Hardware falsification: complex-mode tri-state (2026-07-08)

First silicon test of the complex-mode pin-18 tri-state image
(IO.OE = 'b'0): a fresh GAL16V8D programmed with it does not work in
the SBC, although the fuse map is equivalent to the (also never
tested) GALasm build of the same design. Lesson: the complex-mode
model was only ever validated against GALasm output, i.e. circularly.
Complex-mode support is therefore flagged hardware-unvalidated.

The replacement approach works and is hardware-verified: stay in
simple mode and omit the IO output entirely, making pin 18's OLMC a
dedicated input (one AC1 fuse plus a cleared row versus the proven
WinCUPL image). Fixture: DCJ11SBC-V1-3-2-IO-INPUT.PLD.

## JED framing fix (2026-07-08)

First real-world programming attempt: minipro rejected mgalws output
with "JED file format error!". Cause: serialized files lacked the JESD3
STX/ETX envelope and transmission checksum (16-bit sum of all bytes
from STX through ETX inclusive) that WinCUPL and GALasm emit and
minipro requires. serialized() now produces the full framing.

## Milestone 4 — FIELD and SEQUENCE state machines (2026-07-08)

The parser accepts CUPL FIELD declarations ([PHI3..0] range and list
forms, MSB first) and SEQUENCE blocks (PRESENT / IF / NEXT / OUT /
DEFAULT). A lowering pass expands each transition into registered .D
product terms: stateDecode(present) & condition, OR-ed into every field
bit set in the next state and into every OUT signal. Unspecified states
fall to state 0; DEFAULT takes the negated conjunction of its siblings'
IF conditions. TABLE remains unimplemented until a design needs it.

Golden test: Peter Schranz's original DCJ11SBC-W65C22S.PLD compiles
unmodified and is functionally equivalent to the WinCUPL fuse map
running in the Multi IO card on all ten pins (combinatorial pins
fuse-identical, registered pins equivalent modulo term minimization).
The SEQUENCE form and milestone 3's explicit .D form also agree.

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
