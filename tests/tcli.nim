## End-to-end tests of the nyx binary against a local skills repository.
## Run from the repository root after building bin/nyx (see tests/run).

import std/[paths, symlinks, syncio, strutils, os, dirs, files, osproc, streams,
            envvars, strtabs, tempfiles]
import ../src/[state, install]

var failures = 0   # single-threaded test program

proc fail(msg: string) =
  echo "FAIL: ", msg
  {.cast(assumeSync).}:
    inc failures

template check(cond: bool; msg: string) =
  if not cond: fail(msg)

proc mkfile(p: Path; content: string) {.raises.} =
  createDir(parentDir(p))
  writeFile($p, content)

proc git(dir: Path; args: openArray[string]) {.raises.} =
  var all = @["-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"]
  for a in args: all.add a
  let p = startProcess("git", workingDir = $dir, args = all,
    options = {poUsePath, poStdErrToStdOut})
  defer: close(p)
  close(p.inputStream)
  discard p.outputStream.readAll()
  if waitForExit(p) != 0: quit("git failed: " & all.join(" "))

proc commit(origin: Path; msg: string) {.raises.} =
  git(origin, ["add", "-A"])
  git(origin, ["commit", "-qm", msg])

type Env = object
  bin, data, origin, home, path: Path

proc nyx(e: Env; cwd: Path; args: openArray[string]; repo = ""): (int, string) {.raises.} =
  var env = newStringTable(modeCaseSensitive)
  # Detection reads the home directory, these variables and PATH: pin them all.
  for key, value in envPairs():
    if key notin ["CLAUDE_CONFIG_DIR", "CODEX_HOME", "XDG_CONFIG_HOME"]: env[key] = value
  env["HOME"] = $e.home
  env["PATH"] = $e.path
  env["NYX_HOME"] = $e.data
  env["NYX_REPO"] = if repo.len > 0: repo else: "file://" & $e.origin
  let p = startProcess($e.bin, workingDir = $cwd, args = args, env = env,
    options = {poStdErrToStdOut})
  defer: close(p)
  close(p.inputStream)
  let output = p.outputStream.readAll()
  result = (waitForExit(p), output)

proc linkedSkill(root: Path; dir, skill: string): bool =
  symlinkExists(root / path(dir) / path(skill))

proc inBoth(root: Path; skill: string): bool =
  linkedSkill(root, ".agents/skills", skill) and linkedSkill(root, ".claude/skills", skill)

proc main() {.raises.} =
  let tmp = createTempDir("nyx-cli-", "")
  defer: removeDir(tmp)
  var e = Env(bin: path(expandFilename("bin/nyx")), data: tmp / path("data"),
              origin: tmp / path("origin"), home: tmp / path("home"), path: tmp / path("bin"))
  createDir(e.home)
  createDir(e.path)
  createSymlink(path(findExe("git")), e.path / path("git"))
  for name in ["alpha", "beta", "gamma"]:
    mkfile(e.origin / path(name) / path("SKILL.md"), "---\ndescription: " & name & "\n---\n")
  git(e.origin, ["init", "-q"])
  commit(e.origin, "one")
  let app = tmp / path("app")
  createDir(app)

  # A fresh project points to the page and fetches nothing.
  var (code, o) = nyx(e, app, [])
  check(code == 0 and "skills.html" in o, "bare in a fresh project points to the page: " & o)
  check(not dirExists($skillsDir(e.data)), "bare in a fresh project does not clone")

  # No access on first use: nothing recorded, a useful hint.
  (code, o) = nyx(e, app, ["install", "alpha"], repo = "file://" & $(tmp / path("missing")))
  check(code == 1 and "gh auth status" in o, "install without access fails: " & o)
  check(not taken(app / path(".agents")), "failed clone places nothing")

  # With no agent detected, install uses both standard directories, without
  # flags or questions.
  (code, o) = nyx(e, app, ["install", "alpha", "beta", "alpha"])
  check(code == 0 and "ready" in o, "install succeeds: " & o)
  check(inBoth(app, "alpha") and inBoth(app, "beta"), "installed into both directories")
  var st = loadState(e.data).state
  check(st.projects.len == 1 and st.projects[0].skills == @["alpha", "beta"],
        "duplicates collapse in the recorded set")

  # A subdirectory of a repository is the same project.
  createDir(app / path(".git"))
  createDir(app / path("src"))
  (code, o) = nyx(e, app / path("src"), [])
  check(code == 0 and "alpha" in o and "beta" in o, "bare shows the set from a subdirectory: " & o)
  check("gamma" notin o, "bare shows only the installed skills")

  # An unknown name changes nothing, even beside a valid one.
  (code, o) = nyx(e, app, ["install", "gamma", "../beta", "nope"])
  check(code == 1 and "nope" in o and "../beta" in o and "nothing changed" in o,
        "unknown names are rejected: " & o)
  check(inBoth(app, "alpha") and inBoth(app, "beta") and not inBoth(app, "gamma"),
        "rejected install leaves the set alone")

  # No names is not a request to clear the set.
  (code, o) = nyx(e, app, ["install"])
  check(code == 1 and "skills.html" in o and inBoth(app, "alpha"), "install with no names: " & o)

  # Exact set: alpha goes, the user's own skill stays and is not claimed.
  mkfile(app / path(".claude/skills/own/SKILL.md"), "mine")
  mkfile(app / path(".claude/skills/gamma/SKILL.md"), "my gamma")
  (code, o) = nyx(e, app, ["install", "beta", "gamma"])
  check(code == 0 and not taken(app / path(".agents/skills/alpha")) and
        not taken(app / path(".claude/skills/alpha")), "install removes what left the set: " & o)
  check(fileExists($(app / path(".claude/skills/own/SKILL.md"))), "own skill survives")
  check(readFile($(app / path(".claude/skills/gamma/SKILL.md"))) == "my gamma" and
        "exists, not nyx's" in o, "collision left alone and reported")
  check(linkedSkill(app, ".agents/skills", "gamma"), "collision does not block the other directory")

  # Update reports this project's set, not the whole catalog.
  mkfile(e.origin / path("beta/SKILL.md"), "---\ndescription: beta two\n---\n")
  mkfile(e.origin / path("alpha/SKILL.md"), "---\ndescription: alpha two\n---\n")
  mkfile(e.origin / path("delta/SKILL.md"), "---\ndescription: delta\n---\n")
  commit(e.origin, "two")
  (code, o) = nyx(e, app, ["update"])
  check(code == 0 and "1 updated, 1 current, 1 new in the catalog" in o,
        "update summary covers the set: " & o)
  check("alpha" notin o, "update does not list skills outside the set: " & o)
  check("beta two" in readFile($(app / path(".agents/skills/beta/SKILL.md"))),
        "update reaches the installed skill")

  # The bare command updates once the check is due, and not before.
  mkfile(e.origin / path("beta/SKILL.md"), "---\ndescription: beta three\n---\n")
  commit(e.origin, "three")
  (code, o) = nyx(e, app, [])
  check("beta three" notin readFile($(app / path(".agents/skills/beta/SKILL.md"))),
        "bare does not fetch before the check is due")
  st = loadState(e.data).state
  st.lastCheck = 0
  saveState(e.data, st)
  (code, o) = nyx(e, app, [])
  check(code == 0 and "beta three" in readFile($(app / path(".agents/skills/beta/SKILL.md"))),
        "bare fetches when due: " & o)

  # A skill gone upstream is flagged by name.
  git(e.origin, ["rm", "-rq", "gamma"])
  commit(e.origin, "four")
  (code, o) = nyx(e, app, ["update"])
  check(code == 0 and "no longer in the catalog" in o, "vanished skill is flagged: " & o)

  # A detected agent decides the directory; nothing else is created.
  let cline = tmp / path("cline-app")
  createDir(cline / path(".cline"))
  (code, o) = nyx(e, cline, ["install", "beta"])
  check(code == 0 and linkedSkill(cline, ".cline/skills", "beta") and
        not taken(cline / path(".agents")) and not taken(cline / path(".claude")),
        "project marker selects the agent's directory: " & o)
  # An agent detected later joins; the recorded one stays.
  createDir(cline / path(".cursor"))
  (code, o) = nyx(e, cline, ["install", "beta"])
  check(linkedSkill(cline, ".cline/skills", "beta") and
        linkedSkill(cline, ".agents/skills", "beta"), "later agent joins: " & o)
  (code, o) = nyx(e, cline, ["remove"])
  check(not taken(cline / path(".cline/skills")) and dirExists($(cline / path(".cline"))),
        "remove leaves the agent's own folder: " & o)

  # Agents found through the home directory or PATH count too.
  let other = tmp / path("other-app")
  createDir(other)
  createDir(e.home / path(".roo"))
  (code, o) = nyx(e, other, ["install", "beta"])
  check(linkedSkill(other, ".roo/skills", "beta") and not taken(other / path(".claude")),
        "home marker selects the agent's directory: " & o)
  (code, o) = nyx(e, other, ["remove"])
  removeDir(e.home / path(".roo"))

  # Old flags and commands are gone.
  for args in [@["-g"], @["setup"], @["install", "-g", "beta"]]:
    (code, o) = nyx(e, app, args)
    check(code != 0, "rejected: " & args.join(" "))

  # Remove clears the set and only that.
  (code, o) = nyx(e, app, ["remove"])
  check(code == 0 and not taken(app / path(".agents")), "remove prunes what nyx created: " & o)
  check(fileExists($(app / path(".claude/skills/own/SKILL.md"))), "remove leaves own skill")
  (code, o) = nyx(e, app, [])
  check("skills.html" in o, "removed project is fresh again")
  (code, o) = nyx(e, app, ["remove"])
  check(code == 0 and "nothing to remove" in o, "remove with no set: " & o)

  # A project and a user scope set up by nyx 0.2 stay manageable.
  let old = tmp / path("old")
  createDir(old)
  let store = skillsDir(e.data)
  let crush = old / path(".crush/skills/beta")
  createDir(parentDir(crush))
  createSymlink(store / path("beta"), crush)
  let home = tmp / path("old-home/.claude/skills/beta")
  createDir(parentDir(home))
  createSymlink(store / path("beta"), home)
  st = loadState(e.data).state
  st.projects.add Project(global: true, targets: @["claude"], skills: @["beta"],
    installs: @[Install(path: home, skill: "beta", mode: Link, source: store / path("beta"))])
  st.projects.add Project(root: path(expandFilename($old)), targets: @["crush"], skills: @["beta"],
    installs: @[Install(path: path(expandFilename($old)) / path(".crush/skills/beta"),
                        skill: "beta", mode: Link, source: store / path("beta"))],
    dirs: @[path(expandFilename($old)) / path(".crush"),
            path(expandFilename($old)) / path(".crush/skills")])
  saveState(e.data, st)
  (code, o) = nyx(e, old, [])
  check(code == 0 and "beta" in o and "skills.html" notin o, "bare reads a 0.2 project: " & o)
  (code, o) = nyx(e, old, ["install", "beta"])
  check(code == 0 and linkedSkill(old, ".crush/skills", "beta") and
        not taken(old / path(".agents")), "install keeps a 0.2 project's directories: " & o)
  (code, o) = nyx(e, old, ["remove"])
  check(code == 0 and not taken(old / path(".crush")), "remove clears a 0.2 project: " & o)
  st = loadState(e.data).state
  check(st.projects.len == 1 and st.projects[0].global and symlinkExists(home),
        "the 0.2 user scope is left alone")

try:
  main()
except ErrorCode as err:
  fail("raised " & $err)
{.cast(assumeSync).}:
  if failures > 0:
    echo failures, " failed"
    quit(1)
echo "cli tests passed"
