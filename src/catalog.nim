## Skill discovery: a skill is a directory holding `SKILL.md`. Its directory
## name is the installed name.

import std/[paths, strutils, parseutils, os, dirs, algorithm]

proc validName*(s: string): bool =
  ## Plain names only: no separators, no `..`, no hidden or absolute paths.
  s.len > 0 and s.len <= 64 and s[0] in Letters + Digits and
    skipUntil(s, AllChars - (Letters + Digits + {'_', '-'})) == s.len

proc discover*(dir: Path): seq[string] =
  ## Names of the skills directly under `dir`, sorted. Symlinked entries are
  ## skipped so the catalog cannot point outside its own directory.
  result = @[]
  try:
    for kind, p in walkDir(dir, relative = true):
      let name = $p
      if kind == pcDir and validName(name) and fileExists($(dir / p / path("SKILL.md"))):
        result.add name
  except:
    discard
  sort(result, proc (a, b: string): int = cmp(a, b))
