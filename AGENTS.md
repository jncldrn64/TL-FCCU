# AGENTS.md: start here

This repo is a personal security-audit sandbox for TLauncher. It runs the launcher
under `firejail` & records what it touches: filesystem events, child processes, &
network connections. It isn't a production launcher & never tries to be. The
author doesn't trust TLauncher; one of its update endpoints, `advancedrepository.net`,
probes over plain HTTP, & he wants to watch what it does before deciding to keep
using it. Visibility & isolation come first, usability second.

## Hard constraints

- Zero `sudo`, in any file, any flag, present or future. An optional dependency
  gets a `command -v` probe & a manual install hint, never an auto-install.
- Always XDG paths (`XDG_DATA_HOME`/`XDG_STATE_HOME`/`XDG_RUNTIME_DIR`), never a
  hardcoded `~/.something`.
- Never wrap shared state in a `( ... )` subshell. That exact bug orphaned the
  monitors & grew one `files.log` to 51 MB. Hold locks with `exec N>FILE` plus
  `flock` in the same scope, & track background jobs by `$!`.
- Read `DESIGN.md` before you write any code.

## Map of the repo

- `run.sh`: the whole launcher, one bash script.
- `scripts/TLHttpAgent.java` & its helpers, `scripts/build-agent.sh`: the `-P` Java
  agent (built into two gitignored jars, never committed).
- `tests/`: the suites, run together by `tests/run-all.sh`, with no network, sudo or
  TLauncher.
- `CLAUDE.md`: the author's standard, how work is written, measured & delivered.
- `DESIGN.md`: the conventions, read before coding.
- `CHANGELOG.md`: what changed & when.
- `ROADMAP.md`: the phased plan, read when the work belongs to a phase.
- `docs/DECISIONS.md`: why things are the way they are, append-only, from 2026-10-01.
- `docs/GLOSSARY.md`: what the standard's words mean today.
- `docs/TEMPORARY-CONTEXT.md`: what was observed & isn't placed yet, normally empty.
- `docs/cli-standard.md` & `docs/cli-surface.md`: the CLI module, normative &
  descriptive.
