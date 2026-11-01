## Terminal look, matching the skill table page: the terminal's own ink and
## muted text with soft status colors, so light and dark themes both work.

import std/[syncio, strutils, terminal]

const
  Logo = slurp("../assets/logo.ans")
  Reset* = ansiResetCode

let
  Bold* = ansiStyleCode(styleBright)
  Muted = ansiStyleCode(styleDim)
  Good = ansiForegroundColorCode(fgGreen)
  Caution = ansiForegroundColorCode(fgYellow)
  Alert* = ansiForegroundColorCode(fgRed)

proc interactive*(): bool =
  ## False when stdout is not a terminal: no animation, no redraws.
  terminal.isatty(stdout)

proc put*(s: string) =
  stdout.write s
  flushFile stdout

proc line*(s = "") =
  put s & Reset & "\n"

proc banner*() =
  ## Header for every command on a terminal: the N, Y and X tiles and a tagline.
  if not interactive(): return
  line()
  put Logo & Reset
  line()

# --- output helpers -------------------------------------------------------

proc field*(label, value: string) =
  line "  " & Muted & alignLeft(label, 9) & Reset & value

proc ok*(s: string) =
  line "  " & Good & "+ " & Reset & s

proc warn*(s: string) =
  line "  " & Caution & "! " & Reset & s

proc fail*(s: string) =
  line "  " & Alert & "x " & Reset & s

proc dim*(s: string): string = Muted & s & Reset

proc done*(label, detail: string) =
  line "  " & Good & "+ " & Reset & alignLeft(label, 25) & "  " & dim(detail)
