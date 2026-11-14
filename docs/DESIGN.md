# Skill Table design rules

The Skill Table (`index.html`, `skills.css`, `skills.js`) follows GNOME's libadwaita style
and the GNOME HIG. Values live in `skills.css` tokens; this file records the decisions
that are easy to undo by accident, and why. `tests/ui/check.py` enforces the ones marked ✓.

## Look

- **libadwaita names and values.** Colors, radii and timing reuse libadwaita's variable
  names (`--window-bg-color`, `--card-radius`, …) so light, dark and high contrast follow.
  Look up a value in the libadwaita docs before inventing one.
- **Deliberate departures from libadwaita**, each for contrast on a web page:
  - Accent is GNOME blue 4 `#1c71d8`, not `#3584e4`: white on `#3584e4` is 3.8:1.
  - `--dim-opacity` is 70%, not 55%: 55% gives 3.2:1 for small dim text.
  - The focus ring is opaque `--accent-color`, not 50%: it must reach 3:1 against the window.
- **The language control is a GtkSwitch**, labeled “Nimony”: a 46×26 track, a white 20px
  knob, accent when on, focus ring around the track. Not a segmented toggle group; that
  was tried and rejected.
- **Tile inner layout is fixed:** number top left, symbol centered, name on two lines at the
  bottom (`grid-template-rows: 12px 1fr 24px`, `padding: 6px 7px 7px`), 88×96. Keep it.
  Fix long names with width, not by adding lines.
- **Selection never rests on color alone** ✓ (contrast): tint, 2px ring, colored symbol,
  bold name and a check badge.
- **Group colors come from the Adwaita accent palette**, by group index, so a row keeps its
  color in both views. `--c-bg` fills; `--c` is the text-safe variant.

## Layout

- **Breakpoints follow libadwaita** (550, 860px); nine fixed columns from 1024px. Content
  sits in a centered clamp.
- **No horizontal scroll from 320px up** ✓; **no name clipped** at any width ✓.
- **1024×600 (the HIG desktop minimum) shows the Nim view without scrolling** ✓. From
  860×560 the window is the page and only the table scrolls; smaller, the page scrolls
  under a sticky bottom bar.
- **Tips open above the tile** so they never cover the bottom bar ✓.

## Touch and input

- **No tap highlight** (`-webkit-tap-highlight-color: transparent`): Android paints a blue
  flash over a tile before it turns selected.
- **Hover styles only under `@media (hover: hover)`**: on touch, `:hover` sticks to the
  last tapped element.
- **44px targets under `pointer: coarse`** ✓; the switch grows its hit area, not its box.
- **Visible focus on every control** ✓, including selected tiles in dark mode.

## Text

- Every text pair at least **4.5:1**, light and dark, normal and high contrast ✓.
- HIG writing style: header capitalization for headings, buttons and status labels
  (“Context Full”, “Command Copied”); sentence case for descriptions; no trailing period
  on single sentences; typographic ’ … × –.

## Checking a change

```sh
python3 -m venv .venv && .venv/bin/pip install playwright
.venv/bin/python -m playwright install chromium   # Fedora also needs: at-spi2-atk libXcomposite libXdamage libXfixes libXrandr
.venv/bin/python tests/ui/check.py --shots /tmp/shots
```

It exits non-zero and lists each broken rule. Look at the screenshots too: the script
cannot judge whether something looks right.
