## nyx: installs coding-agent skills from the skills repository into the
## current project, and keeps them up to date.

import std/[appdirs, paths, syncio, strutils, os, dirs, smartcli]
import state, targets, catalog, repo, install, ui

const
  PageUrl = "https://verified-nim.github.io/nyx/"

type
  Ctx = object
    data: Path     ## NYX data directory
    root: Path     ## canonical project root
    st: State
    corrupt: bool  ## state.json was unreadable and set aside

# --- helpers ----------------------------------------------------------------

proc display(file: Path): string =
  ## `file` with the home directory shortened to `~`.
  let p = $file
  var home = $appdirs.getHomeDir()
  while home.len > 1 and home[^1] in {DirSep, AltSep} and
      not (home.len == 3 and home[1] == ':'):
    home.setLen(home.len - 1)
  if p == home: return "~"
  # Keep the separator in ~/child when home itself is a filesystem root.
  let n = if home.len > 0 and home[^1] in {DirSep, AltSep}: home.len - 1 else: home.len
  if home.len > 0 and p.len > home.len and p.startsWith(home) and p[n] in {DirSep, AltSep}:
    "~" & p.substr(n)
  else: p

proc rel(c: Ctx; file: Path): string =
  let p = $file
  let root = $c.root
  let n = root.len
  if n == 0 or p.len <= n or not p.startsWith(root): return p
  if root[^1] in {DirSep, AltSep}: p.substr(n)
  elif p[n] in {DirSep, AltSep}: p.substr(n + 1)
  else: p

proc ago(t: int): string =
  if t == 0: return "never"
  let hours = (now() - t) div 3600
  if hours < 1: "just now"
  elif hours < 24: $hours & "h ago"
  elif hours < 48: "1 day ago"
  else: $(hours div 24) & " days ago"

proc save(c: Ctx) =
  try:
    saveState(c.data, c.st)
  except:
    fail "cannot write " & $statePath(c.data)
    quit(1)

proc context(): Ctx =
  result = Ctx(data: dataDir())
  try:
    result.root = projectRoot(path("."))
  except:
    fail "cannot resolve the current directory"
    quit(1)
  let loaded = loadState(result.data)
  result.st = loaded.state
  result.corrupt = loaded.corrupt

proc notes(c: Ctx) =
  if c.corrupt:
    warn "state was unreadable, starting fresh" & dim("  (kept as state.json.bad)")

proc pointToPage() =
  line "  " & dim("pick your skills at ") & PageUrl
  line "  " & dim("then run the command it gives you in your project")

# --- updating ---------------------------------------------------------------

proc explain(r: GitResult; output: string; setup: bool) =
  case r
  of Done: discard
  of NoGit:
    fail "git not found" & dim("  nyx uses git to fetch skills")
  of NoAccess:
    warn "no access to the skills repository"
    if setup: line "    " & dim("check your GitHub login, e.g. gh auth status")
    else: line "    " & dim("installed skills stay; updates unavailable")
  of Offline:
    warn "offline" & dim("  installed skills stay; try again later")
  of Failed:
    fail "git failed"
    for l in output.strip().splitLines(): line "    " & dim(l)

proc refresh(c: var Ctx; changed: var seq[string]): bool =
  ## Clone or fast-forward the skills repository, then bring copied installs
  ## in every project up to date: the clone and its applied revision are
  ## shared. Reports the skills that changed. Records the check time either way.
  let store = skillsDir(c.data)
  let fresh = not dirExists($store)
  let oldRev = c.st.repoRev
  var output = ""
  var r = Done
  if fresh:
    try:
      createDir(c.data)
    except:
      fail "cannot create " & $c.data
      quit(1)
    r = repo.clone(repoUrl(), store, output)
  else:
    r = pull(store, output)
  c.st.lastCheck = now()
  if r != Done:
    explain(r, output, fresh)
    save(c)
    return false

  let newRev = head(store)
  let diff = changedSkills(store, oldRev, newRev)
  # An absent revision or unavailable diff cannot establish what was applied.
  # Recopy conservatively; an unchanged, known revision needs no work.
  let all = oldRev.len == 0 or newRev.len == 0 or
    (oldRev != newRev and diff.len == 0)
  var complete = true
  for p in mitems(c.st.projects):
    for inst in mitems(p.installs):
      if all or inst.skill in diff:
        try:
          resync(inst)
        except:
          complete = false
          warn "could not refresh " & display(inst.path)
  if complete and newRev.len > 0: c.st.repoRev = newRev
  save(c)
  if not fresh: changed = diff
  result = true

proc report(p: Project; changed: seq[string]) =
  ## What a refresh meant for this project's skills.
  var updated = 0
  for name in p.skills:
    if name in changed:
      done(name, "updated")
      inc updated
  done("skills", $updated & " updated, " & $(p.skills.len - updated) & " current")

proc showSkills(p: Project) =
  for name in p.skills: ok name
  let gone = missing(p)
  if gone > 0:
    warn $gone & " installs changed or missing" & dim("  nyx install SKILL restores them")

# --- commands ----------------------------------------------------------------

proc showChanges(c: Ctx; rep: Report) =
  for d in rep.removed:
    line "  " & Alert & "- " & Reset & c.rel(d) & "  " & dim("removed")
  for d in rep.collisions: warn c.rel(d) & dim("  exists, not nyx's; left alone")
  for d in rep.kept: warn c.rel(d) & dim("  modified; left alone")

proc status(c: var Ctx) =
  ## The bare command: update when due and show this project's skills.
  banner()
  notes(c)
  let idx = c.st.find(c.root)
  if idx < 0:
    pointToPage()
    line()
    return
  field "project", display(c.root)
  if isStale(c.st, now()):
    var changed: seq[string] = @[]
    if refresh(c, changed): report(c.st.projects[idx], changed)
  field "checked", ago(c.st.lastCheck)
  line()
  showSkills(c.st.projects[idx])
  line()

proc chooseTargets(c: Ctx; recorded: seq[string]): seq[string] =
  ## Targets already recorded stay, detected ones join. With nothing to go on,
  ## the two directories most agents read.
  result = recorded
  let home = appdirs.getHomeDir()
  for t in Targets:
    if t.id notin result and detect(t, c.root, home): result.add t.id
  if result.len == 0: result = @["agents", "claude"]

proc installSkills(c: var Ctx; wanted: seq[string]) =
  ## Add `wanted` to this project's skills and restore any that went missing.
  banner()
  notes(c)
  if wanted.len == 0:
    pointToPage()
    line()
    quit(1)

  let store = skillsDir(c.data)
  let fresh = not dirExists($store)
  var changed: seq[string] = @[]
  if not refresh(c, changed) and fresh:
    line()
    quit(1)

  let catalog = discover(store)
  let idx = c.st.find(c.root)
  var p = if idx >= 0: c.st.projects[idx] else: Project(root: c.root)
  # A skill gone upstream drops out; its link goes with it.
  var chosen: seq[string] = @[]
  for name in p.skills:
    if name in catalog: chosen.add name
  var unknown = false
  for name in wanted:
    if name notin catalog:
      fail name & dim("  not in the catalog")
      unknown = true
    elif name notin chosen:
      chosen.add name
  if unknown:
    line "  " & dim("nothing changed")
    pointToPage()
    line()
    quit(1)

  p.targets = chooseTargets(c, p.targets)
  let dirs = skillDirs(p.targets)
  let rep = sync(p, store, dirs, chosen)

  p.skills = @[]
  for name in chosen:
    for inst in p.installs:
      if inst.skill == name:
        p.skills.add name
        done(name, if inst.mode == Link: "linked" else: "copied")
        break
  showChanges(c, rep)
  for d in rep.failed: fail c.rel(d) & dim("  could not install")

  if p.installs.len > 0 or p.dirs.len > 0:
    if idx >= 0: c.st.projects[idx] = p
    else: c.st.projects.add p
  elif idx >= 0:
    c.st.projects.delete(idx)
  save(c)
  var places: seq[string] = @[]
  for d in dirs: places.add $d
  line()
  line "  " & Bold & "ready" & Reset &
    dim("  " & $p.skills.len & " skills in " & places.join(", "))
  line()
  if rep.failed.len > 0: quit(1)

proc update(c: var Ctx) =
  banner()
  notes(c)
  var changed: seq[string] = @[]
  let refreshed = refresh(c, changed)
  let idx = c.st.find(c.root)
  if idx < 0:
    pointToPage()
  else:
    if refreshed: report(c.st.projects[idx], changed)
    showSkills(c.st.projects[idx])
  line()

proc remove(c: var Ctx; names: seq[string]) =
  ## Take `names` out of this project's skills.
  banner()
  notes(c)
  if names.len == 0:
    fail "name the skills to remove" & dim("  nyx clear removes them all")
    line()
    quit(1)
  let idx = c.st.find(c.root)
  var p = if idx >= 0: c.st.projects[idx] else: Project(root: c.root)
  var unknown = false
  for name in names:
    if name notin p.skills:
      fail name & dim("  not installed")
      unknown = true
  if unknown:
    line "  " & dim("nothing changed")
    line()
    quit(1)
  field "project", display(c.root)
  let rep = removeSkills(p, names)
  var left: seq[string] = @[]
  for name in p.skills:
    if name notin names: left.add name
  p.skills = left
  if p.installs.len > 0: c.st.projects[idx] = p
  else: c.st.projects.delete(idx)
  save(c)
  showChanges(c, rep)
  line()
  showSkills(p)
  line()

proc clear(c: var Ctx) =
  banner()
  notes(c)
  let idx = c.st.find(c.root)
  if idx < 0:
    line "  " & dim("nothing to remove here")
    line()
    return
  field "project", display(c.root)
  var p = c.st.projects[idx]
  let names = p.skills
  let rep = removeSkills(p, names)
  c.st.projects.delete(idx)
  save(c)
  showChanges(c, rep)
  line()

proc main =
  if smartcli.paramCount() == 0:
    var c = context()
    status(c)
    return
  let opts = cliapp"""nyx - skills for your coding agents

Usage: nyx [install SKILL...|remove SKILL...|clear|update]

  Run `nyx` alone to see this project's skills; it updates them when due.

Commands:
  install SKILL...  Add skills to this project
  remove SKILL...   Remove skills from this project
  clear             Remove all of this project's skills
  update            Update skills now

Options:
  -h, --help  Show this help
"""
  var c = context()
  case opts.command
  of cmdInstall: installSkills(c, opts.skill)
  of cmdUpdate: update(c)
  of cmdRemove: remove(c, opts.skill)
  of cmdClear: clear(c)
  else: discard

when isMainModule:
  main()
