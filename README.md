# nyx

Installs coding-agent skills from a skills repository into the current project, and keeps them up to date.

Skills are cloned once into nyx's data directory. Each project gets symlinks (or copies, where symlinks are unavailable) into its agent skill directories, so one clone serves every project and updates are a fast-forward away.

## Install

Linux and macOS (installs to `~/.local/bin`):

```sh
curl -fsSL https://github.com/planetis-m/nyx/releases/latest/download/install.sh | sh
```

Windows (PowerShell; installs to `%LOCALAPPDATA%\Programs\nyx` and adds it to the user `PATH`):

```powershell
irm https://github.com/planetis-m/nyx/releases/latest/download/install.ps1 | iex
```

The scripts pick the archive for your OS and architecture, verify it against the release's `SHA256SUMS`, and install the single `nyx` binary. Set `NYX_VERSION` to a tag such as `v0.1.0` to install a specific release, or `NYX_INSTALL_DIR` to install elsewhere.

Release builds exist for Linux x86_64 and ARM64, macOS ARM64, and Windows x86_64. Nimony's native backend has no macOS x86_64 or Windows ARM64 target; on those, build from source.

## Requirements

- `git`
- access to the skills repository (default: `https://github.com/verified-nim/skills`, the subscriber catalog; set `NYX_REPO=https://github.com/planetis-m/skills` for the public community skills)
- to build: [Nimony](https://github.com/nim-lang/nimony) 0.6.3 or newer

## Build

```sh
nimony c -o:bin/nyx src/nyx.nim
```

Release binaries are built with the native backend (`nimony n -d:release -o:bin/nyx src/nyx.nim`) by `.github/workflows/release.yml` whenever a `v*` tag is pushed.

## Usage

Pick your skills on the [skill table](https://planetis-m.github.io/nyx/); it gives you the install command. Run it in your project:

```sh
nyx install nim-testing nim-style-guide  # make this project's skills exactly these
nyx                                      # show them, updating when a check is due
nyx update                               # update now
nyx remove                               # remove this project's skills
nyx -h                                   # help
```

`install` has no flags and asks no questions. Skills not in the list that nyx installed earlier are removed; an unknown name changes nothing. The project is the nearest enclosing directory holding a `.git` entry.

## Targets

`install` places skills in the directory of each agent it detects, from project markers, home markers and executables on `PATH`. With none detected, it uses `.agents/skills` and `.claude/skills`. An agent recorded for a project stays when it is reinstalled; `nyx remove` starts over.

| Skill directory | Targets |
| --- | --- |
| `.agents/skills` | Codex, Agents, Cursor, OpenCode, Antigravity, GitHub Copilot, Amp, Goose |
| `.claude/skills` | Claude Code |
| `.cline/skills` | Cline |
| `.crush/skills` | Crush |
| `.devin/skills` | Windsurf |
| `.pi/skills` | Pi |
| `.roo/skills` | Roo Code |
| `.continue/skills` | Continue |

Detection honors `CLAUDE_CONFIG_DIR`, `CODEX_HOME`, and `XDG_CONFIG_HOME` for the tools that use them.

## Upgrading from nyx 0.2

Projects set up by 0.2 keep working: `nyx` shows them, `nyx update` updates them, `nyx install` changes their skills and keeps their agents, and `nyx remove` clears them.

The wizard, `nyx setup` and user-level installs (`-g`) stay on the [`v0.2` branch](https://github.com/planetis-m/nyx/tree/v0.2). User-level skills set up by 0.2 keep updating here; to change or remove them, use a 0.2 binary (`NYX_VERSION=v0.2.4` with the install script).

## Files

State lives in the platform data directory (`~/.local/share/nyx` on Linux) or wherever `NYX_HOME` points:

- `state.json` - what nyx installed, per project. Written by temporary file plus rename; unreadable state is set aside as `state.json.bad`.
- `skills/` - the git clone of the skills repository.

## Environment

| Variable | Effect |
| --- | --- |
| `NYX_REPO` | Use another skills repository. |
| `NYX_HOME` | Use another data directory. |

## Safety

- An existing destination that nyx did not create is a collision: it is reported and never touched.
- Removal only acts on recorded installs that still look like what nyx made; skills a user edited are left alone, and copy installs are removed file by file so added files survive.
- The skills clone is only ever fast-forwarded, never reset or merged.
- Git never prompts for credentials; missing access or a network failure leaves installed skills in place.

Updates are checked at most once every 15 days when `nyx` is run. A skill renamed or removed upstream is flagged; run `nyx install` with the current names to replace it.

## Skill table page

`docs/` holds the page, served by GitHub Pages. `docs/skills.json` is generated from the catalog when skills are published.

## Tests

```sh
tests/run
```

Each test runs in a fresh temporary directory against local git repositories, so no network is needed.
