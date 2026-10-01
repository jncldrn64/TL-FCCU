# AGENTS.md: start here

This repo is a personal security-audit sandbox for TLauncher. It runs the launcher
under `firejail` & records what it touches: filesystem events, child processes, &
network connections. It isn't a production launcher & never tries to be. The
author doesn't trust TLauncher; one of its update endpoints, `advancedrepository.net`,
probes over plain HTTP, & he wants to watch what it does before deciding to keep
using it. Visibility & isolation come first, usability second.

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

- `run.sh`: the whole launcher, one bash script.
- `scripts/TLHttpAgent.java` & its helpers, `scripts/build-agent.sh`: the `-P` Java
  agent (built into two gitignored jars, never committed).
- `tests/`: the regression suites, run together with `bash tests/run-all.sh`, which
  repeats the ones that used to fail intermittently.
- `docs/DESIGN.md`: the conventions, read before coding.
- `CHANGELOG.md`: what changed & when.
- `docs/ROADMAP.md`: the phased plan, read when the work belongs to a phase.
- `docs/DECISIONS.md`: why things are the way they are, append-only. Its
  entry of 2026-10-01 "Known gaps up to this date, moved here unedited" holds the
  Known gaps section as it stood until then.
- `docs/GLOSSARY.md`: what the standard's words mean today, each with its source.
- `docs/TEMPORARY-CONTEXT.md`: what was observed & isn't placed yet, normally empty.
- `docs/cli/`: the CLI module. `cli-standard.md` says what the command line must do,
  `cli-surface.md` records what it does today.

## Where it continues

`CLAUDE.md` pins how docs, commits & the CHANGELOG are written. `docs/DESIGN.md` holds
the code conventions & is read before writing any code. `docs/ROADMAP.md` says what comes next,
& `docs/DECISIONS.md` says why things are the way they are. Nothing here repeats them.

## Known gaps

What isn't verified against real data, & what is known to be open. Dated &
append-only. Everything this section recorded until 2026-10-01, decisions included, sits
unedited in `docs/DECISIONS.md`, entry of 2026-10-01 "Known gaps up to this date, moved
here unedited". The items below are the ones still open from it, each checked against
the code on 2026-10-01. Don't report any of them as working without a fresh run in a
real environment.

2026-10-01: nothing here has run end to end in this repo's own test environment. It has
no `firejail`, `inotifywait` or `ss`, so the suites drive the launcher through stubs &
synthetic session directories. Real-environment confirmation is the user's job, & nobody
claims it happened when it didn't. First recorded 2026-06-30.

2026-10-01: the network monitor's filter has never run against real firejail. It keeps
the connections whose `pid=` in `ss -tnp` belongs to the process tree rooted at
`firejail .*--hostname=mcbox`, validated with synthetic `ss` output only. A real session
with a browser open has to show that `ss` prints a `pid=` for firejail's same-user
children, that the tree is reached across firejail's PID namespace, & that no IP
unrelated to TLauncher lands in `network.log`. First recorded 2026-07-02.

2026-10-01: request-body capture for a POST has never been seen in a real session. The
agent's capture is confirmed for the starter's GET (session `20260722_113644`), but the
`securelogger.net` POST wasn't exercised, so a non-repeatable body is still unseen in the
wild. First recorded 2026-07-22.

2026-10-01: `RISK_DOMAIN_LITERALS` holds two substrings, `advancedrepository` &
`securelogger`. The `tlauncher.ru` family sits in `KNOWN_TELEMETRY_LITERALS` as reference,
not as a risk flag, & whether it deserves one is the author's call. Don't add it without
the author's confirmation. First recorded 2026-06-30.

2026-10-01: the IP baseline flags the sandbox's own address. A `10.x` source IP reads as
"not in baseline" until the user saves the baseline from a clean session that already
includes it. That's by design, & worth knowing before reading a first report. First
recorded 2026-06-30.

2026-10-01: the dependency registry records the first state it sees & never overwrites
it. A package that was `absent` & got installed later shows `present` live under
`--check-deps` while its registry line still reads `absent`. Delete
`tlauncher-sandbox-deps.ini` to re-inventory. First recorded 2026-07-02.

2026-10-01: `first_seen_loop` leaks a temp file when killed mid-cycle. It creates a
`mktemp` file each cycle & removes it at the end of that cycle, so a TERM or KILL in
between leaves one small file in `/tmp`, per monitor per session. Cosmetic, cleared on
reboot, & planned in ROADMAP Phase 5. First recorded 2026-07-30.

2026-10-01: the colour gate tests stdout (`[ -t 1 ]`) while nearly all coloured output
goes to stderr, & `NO_COLOR` isn't read at all. Deferred on purpose. The log files stay
clean whatever the gate decides, because `_log_emit` writes the file from a branch that
never carries colour. First recorded 2026-09-17.

2026-10-01: the man page's roff isn't machine-validated here, because neither `mandoc`
nor `groff` is installed & `tests/doc-sync.sh` reports SKIP. It was validated by hand on
another machine with both, clean except one style note that v2.26 fixed. Re-validate if
the roff's shape changes. First recorded 2026-09-17.

2026-10-01: an unexpected argument prints the wrong program name in its hint. The `*)`
arm of `main()`'s `case` prints `Run '%s --help'` with `"$1"` where its neighbour, the
`-*)` arm, passes `"$0"`. Run here on 2026-10-01, `bash run.sh foo` printed `Run 'foo
--help' for usage` & exited 1. It was found while replacing the line anchors in
`docs/cli/cli-surface.md`, & the fix belongs in a code PR.

2026-10-01: closed in v2.44, the unexpected-argument hint above. The `*)` arm passes
`"$0"`, & `tests/doc-sync.sh` now fails if the hint echoes the argument back. Run here,
`bash run.sh foo` prints `Run 'run.sh --help' for usage`.

Find another open item while reading `docs/DESIGN.md` or `CHANGELOG.md` that isn't closed with
verified evidence? Add it here instead of quietly fixing it or re-scoping it. A decision
goes in `docs/DECISIONS.md`. A documentation idea that nobody knows is wanted yet goes in
`docs/TEMPORARY-CONTEXT.md`; don't add a doc file on your own.
