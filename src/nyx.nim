## nyx: installs coding-agent skills from the skills repository into the
## current project, and keeps them up to date.

import std/[appdirs, paths, syncio, strutils, os, dirs, smartcli]
import state, targets, catalog, repo, links, ui

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
    warn "state was unreadable, starting fresh" & dim("  kept as state.json.bad")

proc page() =
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

proc installed(st: State): seq[string] =
  ## Every skill nyx placed, in any project: they share one clone, so an
  ## update reaches them all.
  result = @[]
  for p in st.projects:
    for name in p.skills:
      if name notin result: result.add name

proc report(c: Ctx; fresh: bool; diff: seq[string]) =
  ## What a refresh did to the skills nyx installed, wherever they are.
  let store = skillsDir(c.data)
  if fresh:
    field "skills", $discover(store).len & " available"
    return
  let all = installed(c.st)
  if all.len == 0:
    field "skills", "none installed"
    return
  var updated: seq[string] = @[]
  var vanished: seq[string] = @[]
  for name in all:
    if name notin diff: discard
    elif dirExists($(store / path(name))): updated.add name
    else: vanished.add name
  var counts: seq[string] = @[]
  if updated.len > 0: counts.add $updated.len & " updated"
  if vanished.len > 0: counts.add $vanished.len & " removed upstream"
  counts.add $(all.len - updated.len - vanished.len) & " current"
  field "skills", counts.join(", ")
  for name in updated: done(name, "updated")
  for name in vanished: gone(name, "removed upstream")

proc refresh(c: var Ctx): bool =
  ## Clone or fast-forward the skills repository, then bring copied installs
  ## in every project up to date: the clone and its applied revision are
  ## shared. Reports the outcome. Records the check time either way.
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
  let diff = touched(store, oldRev, newRev)
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
  report(c, fresh, diff)
  result = true

# --- the project view ---------------------------------------------------------

proc header(c: Ctx; p: Project) =
  field "project", display(c.root)
  var dirs: seq[string] = @[]
  for d in skillDirs(p.targets): dirs.add $d
  field "dirs", dirs.join(", ")

proc how(p: Project; name: string): string =
  result = "linked"
  for inst in p.installs:
    if inst.skill == name and inst.mode == Copy: return "copied"

proc list(c: Ctx; p: Project; added, restored: seq[string] = @[]) =
  ## This project's skills, one line each: what just happened to it, or
  ## what needs attention.
  let store = skillsDir(c.data)
  let known = dirExists($store)
  for name in p.skills:
    if name in added: done(name, how(p, name))
    elif name in restored: done(name, "restored")
    elif known and not dirExists($(store / path(name))):
      warn(name, "removed upstream; nyx install drops it")
    elif not intact(p, name):
      warn(name, "changed or missing; nyx install " & name & " restores it")
    else: item name

proc problems(c: Ctx; rep: Report) =
  ## Destinations an operation had to leave alone or could not create.
  for d in rep.collisions: warn(c.rel(d), "exists, not nyx's; left alone")
  for d in rep.kept: warn(c.rel(d), "modified; left alone")
  for d in rep.failed: fail c.rel(d) & dim("  could not install")

# --- commands ----------------------------------------------------------------

proc status(c: var Ctx) =
  ## The bare command: update when due and show this project's skills.
  banner()
  notes(c)
  let idx = c.st.find(c.root)
  if idx < 0:
    page()
    line()
    return
  let due = isStale(c.st, now())
  if due:
    discard refresh(c)
    line()
  header(c, c.st.projects[idx])
  if not due: field "checked", ago(c.st.lastCheck)
  line()
  list(c, c.st.projects[idx])
  line()

proc pick(c: Ctx; recorded: seq[string]): seq[string] =
  ## Targets already recorded stay, detected ones join. With nothing to go on,
  ## the two directories most agents read.
  result = recorded
  let home = appdirs.getHomeDir()
  for t in Targets:
    if t.id notin result and detect(t, c.root, home): result.add t.id
  if result.len == 0: result = @["agents", "claude"]

proc install(c: var Ctx; wanted: seq[string]) =
  ## Add `wanted` to this project's skills and restore any that went missing.
  banner()
  notes(c)
  if wanted.len == 0:
    page()
    line()
    quit(1)

  let store = skillsDir(c.data)
  let fresh = not dirExists($store)
  let fetched = refresh(c)
  line()
  if not fetched and fresh: quit(1)

  let catalog = discover(store)
  let idx = c.st.find(c.root)
  var p = if idx >= 0: c.st.projects[idx] else: Project(root: c.root)
  # A skill gone upstream drops out; its link goes with it.
  var before: seq[string] = @[]
  var vanished: seq[string] = @[]
  for name in p.skills:
    if name in catalog: before.add name
    else: vanished.add name
  var chosen = before
  var unknown = false
  for name in wanted:
    if name notin catalog:
      fail name & dim("  not in the catalog")
      unknown = true
    elif name notin chosen:
      chosen.add name
  if unknown:
    line "  " & dim("nothing changed")
    page()
    line()
    quit(1)

  p.targets = pick(c, p.targets)
  let rep = sync(p, store, skillDirs(p.targets), chosen)
  var added: seq[string] = @[]
  var restored: seq[string] = @[]
  p.skills = @[]
  for name in chosen:
    var present = false
    var placed = false
    for inst in p.installs:
      if inst.skill == name:
        present = true
        if inst.path in rep.placed: placed = true
    if present:
      p.skills.add name
      if name notin before: added.add name
      elif placed: restored.add name

  if p.installs.len > 0 or p.dirs.len > 0:
    if idx >= 0: c.st.projects[idx] = p
    else: c.st.projects.add p
  elif idx >= 0:
    c.st.projects.delete(idx)
  save(c)
  header(c, p)
  line()
  for name in vanished: gone(name, "removed upstream")
  list(c, p, added, restored)
  problems(c, rep)
  line()
  if rep.failed.len > 0: quit(1)

proc update(c: var Ctx) =
  ## Update every skill nyx installed, wherever it was run from.
  banner()
  notes(c)
  discard refresh(c)
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
  let rep = drop(p, names)
  var left: seq[string] = @[]
  for name in p.skills:
    if name notin names: left.add name
  p.skills = left
  if p.installs.len > 0: c.st.projects[idx] = p
  else: c.st.projects.delete(idx)
  save(c)
  header(c, p)
  line()
  for name in names: gone(name, "removed")
  list(c, p)
  problems(c, rep)
  line()

proc clear(c: var Ctx) =
  banner()
  notes(c)
  let idx = c.st.find(c.root)
  if idx < 0:
    line "  " & dim("nothing to remove here")
    line()
    return
  var p = c.st.projects[idx]
  let names = p.skills
  let rep = drop(p, names)
  c.st.projects.delete(idx)
  save(c)
  header(c, p)
  line()
  for name in names: gone(name, "removed")
  problems(c, rep)
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
  of cmdInstall: install(c, opts.skill)
  of cmdUpdate: update(c)
  of cmdRemove: remove(c, opts.skill)
  of cmdClear: clear(c)
  else: discard

when isMainModule:
  main()
