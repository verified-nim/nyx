## Terminal look: colors, logo, and results.

import std/[syncio, strutils, terminal, colors, os]

const
  Logo = slurp("../assets/logo.ans")
  Reset* = ansiResetCode
  # Fire gradient of the NYX wordmark, top row to bottom row.
  MarkColors = [(255, 226, 52), (255, 161, 23), (245, 103, 10), (226, 52, 14)]

let
  Bold* = ansiStyleCode(styleBright)
  White* = ansiForegroundColorCode(rgb(238, 238, 232))
  Ash* = ansiForegroundColorCode(rgb(120, 118, 114))
  Gold* = ansiForegroundColorCode(rgb(230, 184, 40))
  Ember* = ansiForegroundColorCode(rgb(255, 128, 8))
  Blood* = ansiForegroundColorCode(rgb(226, 52, 14))

proc interactive*(): bool =
  ## False when stdout is not a terminal: no animation, no redraws.
  terminal.isatty(stdout)

proc put*(s: string) =
  stdout.write s
  flushFile stdout

proc line*(s = "") =
  put s & Reset & "\n"

proc markColor(c: (int, int, int); k: float): string =
  ## Bold `c` scaled to brightness `k` (0..1).
  Bold & ansiForegroundColorCode(rgb(int(float(c[0]) * k), int(float(c[1]) * k),
                                     int(float(c[2]) * k)))

proc stripAnsi(s: string): string =
  result = ""
  var i = 0
  while i < s.len:
    if s[i] == '\x1b':
      while i < s.len and s[i] != 'm': inc i
    else:
      result.add s[i]
    inc i

proc indentOf(s: string): int =
  s.len - s.strip(trailing = false).len

proc wordmark(): seq[string] =
  ## The logo rows with their common left indent removed.
  result = @[]
  var rows: seq[string] = @[]
  for l in Logo.strip(leading = false).split('\n'): rows.add stripAnsi(l)
  var indent = high(int)
  for l in rows: indent = min(indent, indentOf(l))
  for l in rows: result.add l.substr(indent)

proc ignite(mark: seq[string]; ms: int) =
  ## Fade the wordmark up from ember to full fire.
  const steps = 10
  for s in 1 .. steps:
    if s > 1:  # back to the start of the wordmark's first line
      cursorUp(stdout, mark.len)
      setCursorXPos(stdout, 0)
    let k = (float(s) / float(steps)) * (float(s) / float(steps))
    for i in 0 ..< mark.len:
      put "  " & markColor(MarkColors[min(i, MarkColors.high)], k) & mark[i] & Reset & "\n"
    os.sleep(ms div steps)

proc banner*() =
  ## Header for every command on a terminal: just the burning wordmark.
  if not interactive(): return
  hideCursor(stdout)
  line()
  ignite(wordmark(), 250)
  showCursor(stdout)
  line()

# --- output helpers -------------------------------------------------------

proc field*(label, value: string) =
  line "  " & Ash & alignLeft(label, 9) & Reset & value

proc ok*(s: string) =
  line "  " & Gold & "+ " & Reset & s

proc warn*(s: string) =
  line "  " & Ember & "! " & Reset & s

proc fail*(s: string) =
  line "  " & Blood & "x " & Reset & s

proc dim*(s: string): string = Ash & s & Reset

proc done*(label, detail: string) =
  line "  " & Gold & "+ " & Reset & alignLeft(label, 25) & "  " & dim(detail)
