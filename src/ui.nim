## Terminal look, matching the skill table page: the terminal's own ink and
## muted text with soft status colors, so light and dark themes both work.

import std/[syncio, strutils, terminal]

const
  Logo = slurp("../assets/logo.ans")
  Reset = ansiResetCode

let
  Muted = ansiStyleCode(styleDim)
  Good = ansiForegroundColorCode(fgGreen)
  Caution = ansiForegroundColorCode(fgYellow)
  Alert = ansiForegroundColorCode(fgRed)

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
# Facts are `field`s. A skill gets one line: `done` (+) for a change, `gone` (-)
# for a removal, `item` for as it was. `warn` (!) and `fail` (x) need attention.

proc field*(label, value: string) =
  line "  " & Muted & alignLeft(label, 9) & Reset & value

proc warn*(s: string) =
  line "  " & Caution & "! " & Reset & s

proc fail*(s: string) =
  line "  " & Alert & "x " & Reset & s

proc dim*(s: string): string = Muted & s & Reset

proc mark(sign, label, detail: string) =
  line "  " & sign & Reset & alignLeft(label, 25) & "  " & dim(detail)

proc done*(label, detail: string) = mark(Good & "+ ", label, detail)

proc warn*(label, detail: string) = mark(Caution & "! ", label, detail)

proc gone*(label, detail: string) = mark(Alert & "- ", label, detail)

proc item*(label: string) = line "    " & label
