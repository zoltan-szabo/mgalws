# History

Detailed notes per milestone. Commit messages stay short; the long story
lives here.

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

Golden tests compile Peter Schranz's DCJ11 SBC decoder sources (V1-3-2
and V1-3-3) and prove functional equivalence with the WinCUPL 5.0a and
GALasm 2.1 fuse maps that run in real hardware. The compiled V1-3-2
differs from WinCUPL's output only in signature fuses and term
minimization choices; `mgalws diff` reports every pin equivalent.

## Milestone 1 — JEDEC toolkit (2026-07-07)

`mgalws decode file.jed` and `mgalws diff a.jed b.jed`:

- JESD3 parser/serializer: `*QF/*QP/*F/*L/*C` fields, STX/ETX framing,
  CRLF tolerance, LSB-first fuse checksum verified against WinCUPL's and
  GALasm's declared values.
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
