## Coding agents NYX can install skills for.
##
## `nyx install` uses the targets it detects. Detection only reads; a skill
## directory appears only when skills are installed into it.
##
## Detection checks project markers, home markers, and executables on PATH.
## Each target's paths and markers are defined in `Targets` below.
## Targets sharing `.agents/skills` install each skill once.

import std/[paths, os, envvars, strutils]

type
  Target* = object
    id*: string             ## stable key, stored in state
    skillDir*: Path         ## project-relative skill directory
    markers: seq[Path]      ## project-relative paths that mean "in use"
    homeMarkers: seq[Path]  ## home-relative paths that mean "installed"
    homeEnv: string         ## environment override for the config directory
    envDir: Path            ## tool directory within a shared config root
    exe: string             ## executable that means "installed"

let Targets* = @[
  Target(id: "claude", skillDir: path(".claude/skills"),
    markers: @[path(".claude"), path("CLAUDE.md")],
    homeMarkers: @[path(".claude")], homeEnv: "CLAUDE_CONFIG_DIR", exe: "claude"),
  Target(id: "codex", skillDir: path(".agents/skills"),
    markers: @[path(".codex")],
    homeMarkers: @[path(".codex")], homeEnv: "CODEX_HOME", exe: "codex"),
  Target(id: "agents", skillDir: path(".agents/skills"),
    markers: @[path(".agents")]),
  Target(id: "crush", skillDir: path(".crush/skills"),
    markers: @[path(".crush"), path("CRUSH.md")],
    homeMarkers: @[path(".config/crush")], homeEnv: "XDG_CONFIG_HOME", envDir: path("crush"),
    exe: "crush"),
  Target(id: "pi", skillDir: path(".pi/skills"),
    markers: @[path(".pi")],
    homeMarkers: @[path(".pi")], exe: "pi"),
  Target(id: "cursor", skillDir: path(".agents/skills"),
    markers: @[path(".cursor")],
    homeMarkers: @[path(".cursor")], exe: "cursor"),
  Target(id: "opencode", skillDir: path(".agents/skills"),
    markers: @[path(".opencode"), path("opencode.json"), path("opencode.jsonc")],
    homeMarkers: @[path(".config/opencode")], homeEnv: "XDG_CONFIG_HOME",
      envDir: path("opencode"), exe: "opencode"),
  Target(id: "agy", skillDir: path(".agents/skills"),
    markers: @[path(".gemini"), path("GEMINI.md")],
    homeMarkers: @[path(".gemini")], exe: "agy"),
  Target(id: "copilot", skillDir: path(".agents/skills"),
    markers: @[path(".github/skills"),
      path(".github/copilot-instructions.md")],
    homeMarkers: @[path(".copilot")], exe: "copilot"),
  Target(id: "windsurf", skillDir: path(".devin/skills"),
    markers: @[path(".devin"), path(".windsurf"), path(".windsurfrules")],
    homeMarkers: @[path(".codeium/windsurf"), path(".config/devin")], exe: "windsurf"),
  Target(id: "roo", skillDir: path(".roo/skills"),
    markers: @[path(".roo"), path(".roomodes")],
    homeMarkers: @[path(".roo")]),
  Target(id: "continue", skillDir: path(".continue/skills"),
    markers: @[path(".continue")],
    homeMarkers: @[path(".continue")], exe: "cn"),
  Target(id: "goose", skillDir: path(".agents/skills"),
    markers: @[path(".goose"), path(".goosehints")],
    homeMarkers: @[path(".config/goose")], homeEnv: "XDG_CONFIG_HOME", envDir: path("goose"),
    exe: "goose"),
  Target(id: "amp", skillDir: path(".agents/skills"),
    markers: @[path(".amp")],
    homeMarkers: @[path(".config/amp")], exe: "amp"),
  Target(id: "cline", skillDir: path(".cline/skills"),
    markers: @[path(".cline"), path(".clinerules")],
    homeMarkers: @[path(".cline")], exe: "cline")]

proc exists(p: Path): bool = dirExists($p) or fileExists($p)

proc detect*(t: Target; root, home: Path): bool =
  ## Is this agent in use in `root`, or installed for the user at `home`?
  for m in t.markers:
    if exists(root / m): return true
  let config = if t.homeEnv.len > 0: getEnv(t.homeEnv) else: ""
  if not config.isEmptyOrWhitespace:
    if exists(path(config.strip()) / t.envDir): return true
  elif home != path(""):
    for m in t.homeMarkers:
      if exists(home / m): return true
  result = t.exe.len > 0 and findExe(t.exe).len > 0

proc byId*(id: string): int =
  ## Index into `Targets`, or -1.
  result = -1
  for i in 0 ..< Targets.len:
    if Targets[i].id == id: return i

proc skillDirs*(ids: seq[string]): seq[Path] =
  ## Distinct project skill directories for the selected target ids.
  result = @[]
  for id in ids:
    let i = byId(id)
    if i >= 0 and Targets[i].skillDir notin result: result.add Targets[i].skillDir
