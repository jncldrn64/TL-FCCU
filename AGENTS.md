# AGENTS.md: start here

> **Role:** door, for tools that look for this name. It wins over nothing & nothing depends
> on it. **Regime:** corrected. **Origin:** 2026-06-30; an island since 2026-10-01, "Known
> gaps move to the description of the code, & close by removal".

A personal security-audit sandbox for TLauncher: it runs the launcher under `firejail`
& records what it touches. `docs/REQUIREMENTS.md` says who it's for & what it isn't.

## Hard constraints (don't break these)

- Zero `sudo`, in any file, any flag, present or future. An optional dependency
  gets a `command -v` probe & a manual install hint, never an auto-install.
- Always XDG paths (`XDG_DATA_HOME`/`XDG_STATE_HOME`/`XDG_RUNTIME_DIR`), never a
  hardcoded `~/.something`.
- Never wrap shared state in a `( ... )` subshell. That exact bug orphaned the
  monitors & grew one `files.log` to 51 MB. Hold locks with `exec N>FILE` plus
  `flock` in the same scope, & track background jobs by `$!`.
- Read `docs/DESIGN.md` before you write any code.

## Map of the repo

- `docs/REQUIREMENTS.md`: what has to be true for the launcher to be right, & for whom.
- `docs/ARCHITECTURE.md`: what the code is today, checked against it, & the open gaps.
- `run.sh`: the whole launcher, one bash script.
- `scripts/TLHttpAgent.java` & its helpers, `scripts/build-agent.sh`: the `-P` Java
  agent (built into two gitignored jars, never committed).
- `tests/`: the regression suites, run together with `bash tests/run-all.sh`, which
  repeats the ones that used to fail intermittently.
- `docs/DESIGN.md`: the conventions, read before coding.
- `CHANGELOG.md`: what changed & when.
- `docs/ROADMAP.md`: the phased plan, read when the work belongs to a phase.
- `docs/DECISIONS.md`: why things are the way they are, append-only.
- `docs/GLOSSARY.md`: what the standard's & the launcher's words mean today, each with its
  source.
- `docs/TEMPORARY-CONTEXT.md`: what was observed & isn't placed yet, normally empty.
- `docs/cli/`: the CLI module. `cli-standard.md` says what the command line must do,
  `cli-surface.md` records what it does today.

## Where it continues

`CLAUDE.md` holds the working method, how docs, commits & PRs are written, & the order
in which the documents are read. Nothing here repeats it.
