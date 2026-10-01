# CLI surface inventory

What `run.sh` actually exposes today, verified line by line against the code as it
stands after the v2.24 fixes in this same PR. This documents; it changes nothing.

It exists as raw material for fixing the man page standard later, so it records the
surface as it *is*, not as it was meant to be. Where the code and the help text
disagree, both are written down & the disagreement is named.

Every claim anchors on something `grep` finds in `run.sh`, such as a function, a
variable, a `case` arm or a quoted string. Until v2.43 each also carried a line number,
& the v2.24 work alone shifted about forty of them. By v2.42 the anchors near the top of
the file still held, & the ones past `log_warn` pointed at the wrong line. The numbers
are gone, & the symbols were always the anchor.

## 0. Two premises that did not survive contact with the repo

The brief that asked for this inventory assumed a `README.md` and an existing man
page, and asked which parts of the man page are redundant.

**Neither existed when this inventory was written.** A manual page does now: v2.25
embedded one in `run.sh`, reachable with `--print-man` & installable with
`--install-man`, per `docs/cli/cli-standard.md`. There is still no `README.md`, and still
no `.1` file in the tree, by design. What follows in section 5 was written against
the state before that, & is kept because it is the reasoning the standard was built
on; where it says "there is no man page", read "there was none, and here is what
`--help` duplicated on its own".

At the time of writing: `git ls-files` returns no `README.md`, no `*.1`, no `man/`
directory, and `git log --all --diff-filter=A` shows neither was ever committed. The
tracked documentation is exactly: `AGENTS.md`, `CLAUDE.md`, `DESIGN.md`,
`CHANGELOG.md`, `ROADMAP.md`, `LICENSE`.

So section 5 below answers the question that can be answered: what `--help` holds,
& what it duplicates against the docs that do exist. There is no man page to call
redundant yet. When one gets written, this inventory is the input.

## 1. Flag inventory

All parsing happens in one `case` inside `main()`, one arm per flag. There is no
getopt, no flag bundling (`-vM` is rejected as an unknown option), and no `--`
end-of-options marker.

| Short | Long | Arg | Default | Global set |
|---|---|---|---|---|
| `-v` | `--verbose` | no | `false` | `VERBOSE` |
| `-n` | `--offline` | no | `false` | `OFFLINE_MODE` |
| `-M` | `--monitor` | no | `false` | `MONITOR_ENABLED` |
| `-a` | `--analyze` | no | `false` | `AUTO_ANALYZE` |
| `-A` | `--analyze-only` | no | `false` | `analyze_only` (local) |
| `-m` | `--mozilla` | no | `false` | `MOZILLA_CHECK` |
| `-K` | `--kill-orphans` | no | `false` | `KILL_ORPHANS` |
| `-R` | `--report` | **required** DIR | `""` | `REPORT_SESSION` |
| `-c` | `--cleanup-logs` | **optional** DAYS | `7` | `CLEANUP_LOGS_FLAG`, `CLEANUP_DAYS` |
| `-P` | `--proxy` | no | `false` | `PROXY_ENABLED` |
| `-B` | `--save-baseline` | **required** DIR | `""` | `SAVE_BASELINE_SESSION` |
| (none) | `--check-deps` | no | `false` | `CHECK_DEPS` |
| `-ml` | `--mozilla-path` | **required** PATH | `${REAL_HOME}/.mozilla` | `MOZILLA_SEARCH_PATH` |
| `-f` | `--file` | **required** PATH | `""` | `TLAUNCHER_PATH` |
| (none) | `--print-man` | no | `false` | `PRINT_MAN` |
| (none) | `--install-man` | no | `false` | `INSTALL_MAN` |
| `-h` | `--help` | no | n/a | calls `usage()`, exits 0 |

Notes the table cannot hold:

- **Three options have no short form:** `--check-deps`, `--print-man`, `--install-man`.
  `DESIGN.md` principle 4 says "every flag has a short form & a long alias", so these
  are documented exceptions. The two manual-page options are deliberate: they are
  run once, by hand, and a short letter spent on them would be a letter unavailable
  to a flag used every session.
- **`-ml` is a two-letter short option.** `-ml` is not standard short-option
  grammar; a POSIX-ish parser would read it as `-m -l`. Here the `case` matches the
  literal string `-ml`, so it works, but it means `-m` and `-ml` are different
  options distinguished only by the trailing letter: the `-m|--mozilla)` arm & the
  `-ml|--mozilla-path)` arm.
- **`-c`'s argument is optional & numeric-only.** The `-c|--cleanup-logs)` arm tests
  `[[ "${2:-}" =~ ^[0-9]+$ ]]`. `-c foo` silently ignores `foo` & uses the default 7
  rather than erroring, then `foo` is re-parsed as the next argument & dies in the `*)`
  arm as an unexpected argument.
- **`-A` writes a function-local, not a global.** `analyze_only` is declared
  `local analyze_only=false` at the top of `main()`, unlike every other flag target.

### Options in the code but not in `--help`

None. Every one of the 17 parser arms above appears in `usage()`, & since v2.25
`tests/doc-sync.sh` fails the build if that stops being true, in either direction.

### Options in `--help` that no longer do anything

None. The `-P` help text was corrected when the mitmproxy fallback was removed
(CHANGELOG v2.21), & the ROADMAP Phase 2 sweep re-audited the rest. Re-checked here
against the parser: every documented flag still reaches a live code path.

## 2. Environment variables read

| Variable | Default when unset | Effect |
|---|---|---|
| `XDG_DATA_HOME` | `${REAL_HOME}/.local/share` | Parent of `SANDBOX_DIR` & both baseline files |
| `XDG_STATE_HOME` | `${REAL_HOME}/.local/state` | Parent of `LOG_ROOT`, every session dir |
| `XDG_RUNTIME_DIR` | `/run/user/${REAL_UID}`, then `/tmp` if that is not a directory (`if [ ! -d "$XDG_RUNTIME_DIR" ]`) | Holds `LOCKFILE` |
| `SUDO_USER` | `${USER:-$(id -un)}` | Identity used for `REAL_HOME` & the lockfile name |
| `SUDO_UID` | `$(id -u)` | Default `XDG_RUNTIME_DIR` path |
| `SUDO_GID` | `$(id -g)` | Read into `REAL_GID`; no consumer in the current code |
| `USER` | `$(id -un)` | Fallback identity when `SUDO_USER` is unset |
| `HOME` | `getent passwd` result wins; `$HOME` is the fallback | Base for `REAL_HOME` |

The `SUDO_*` reads are defensive, not an invitation: the hard constraint is zero
`sudo` (`AGENTS.md`, "Hard constraints"). They exist so that a user who ignores that
& runs under `sudo` still gets their own paths rather than root's.

`NO_COLOR` is **not** read. See section 4.

## 3. Exit codes

| Code | Meaning | Constant |
|---|---|---|
| `0` | Success, including every standalone mode, `--help` & `--print-man` | `EX_OK` |
| `1` | Usage error: unknown option, missing or invalid argument | `EX_USAGE` |
| `2` | Refusal: a live session holds the lock | `EX_LOCK_HELD` |
| `3` | A required dependency is missing | `EX_MISSING_DEP` |
| `4` | Environment: lockfile unwritable, jar not found, sandbox unusable | `EX_ENV` |
| `5` | The lock state could not be determined | `EX_LOCK_UNKNOWN` |
| TLauncher's own | The sandboxed run's exit status is propagated, not swallowed | end of `run_sandboxed` |

One code per condition, as of v2.25. Before that, `1` covered five distinct failures
(usage error, unknown option, missing dependency, unwritable lockfile, lost lock
race) & a caller had to read stderr to tell them apart. `die()` takes an optional
code, defaulting to `EX_USAGE`. `tests/doc-sync.sh` fails if an `EX_*` constant is
missing from the manual's `EXIT STATUS`.

## 4. Presentation

### Logging functions

| Function | Stream | Prefix | Also written to |
|---|---|---|---|
| `log_msg` | stderr | `[YYYY-MM-DD HH:MM:SS.mmm]` | `${SESSION_DIR}/master.log` when a session dir exists |
| `log_verbose` | stderr | same as `log_msg` | same as `log_msg` |
| `log_error` | stderr | `[ERROR]` in red | `${SESSION_DIR}/master.log` |
| `log_warn` | stderr | `[WARN]` in yellow | `${SESSION_DIR}/master.log` |

All four go to stderr, all four are timestamped, and all four reach `master.log`
through one shared writer, `_log_emit`. Until v2.25 `log_error` & `log_warn` did
neither: they printed straight to stderr, so a past session's `master.log` showed the
run but none of the errors in it.

`log_verbose` ends with an explicit `return 0`, load-bearing under
`set -e`; the comment there records the bug it fixes.

### Colour

Decided once, in the `if [ -t 1 ]` block near the top of the file: colour when
**stdout** is a TTY,
empty strings otherwise.

Two incoherencies, both real:

1. **The gate tests stdout; almost all coloured output goes to stderr.** `log_error`
   & `log_warn` write to stderr but take their colour from whether *stdout* is a
   terminal. `./run.sh -M > file` leaves stderr on the terminal with colour stripped;
   `./run.sh -M 2> file` writes escape codes into the file.
2. **`NO_COLOR` is not honoured.** There is no `NO_COLOR` read anywhere in the file.

Colour never reaches a log file: `_log_emit`, the writer behind all four, appends the
raw `$*` to `master.log` with no escape codes, & the colour lives in the `printf` format
strings, not in the messages.

### Silent mode & log levels

There is no `--quiet`, no `-q`, & no numeric log level. The levels are effectively:

- default: start/end lines & warnings/errors, all on stderr;
- `-v`: adds everything `log_verbose` carries, plus the configuration summary & a
  2-second countdown, the `Starting in 2 seconds...` line & its `sleep 2`.

`DESIGN.md` principle 5 ("Silent by default, verbose by request, never mute") is the
written rule; the code matches it.

### Stream split, audited

`usage()` writes to **stdout** & ends in `exit 0`, which is right for `--help`.
Report generators write Markdown to stdout, which is how `-R` redirects into a file.

One inconsistency worth naming: the `-R` **success** line, `✓ Report: …`, goes to
stderr, while the report body it announces goes to stdout. Defensible (it
keeps the success notice out of a redirected report) but it means a success message
is on the error stream.

## 5. `--help` against the rest of the documentation

`usage()` is 126 lines, counted from `usage() {` to its closing brace on 2026-10-01.
Sections, in order, each a `printf "${YELLOW}NAME${NC}"` line:

1. `PURPOSE`
2. `USAGE`
3. `BASIC OPTIONS`
4. `MONITORING OPTIONS`
5. `MAINTENANCE / REPORTING`
6. `NETWORK CAPTURE (opt-in, no sudo)`
7. `SECURITY CHECKS`
8. `BASELINES & REGRESSION (text-only, no extra network)`
9. `COMMON USAGE PATTERNS`
10. `WHAT'S NEW`
11. `OUTPUT LOCATION`

### What is duplicated, and between which documents

There is no man page & no README, so the duplication that exists is between
`--help` and the four root docs. It is small & mostly deliberate:

- **`WHAT'S NEW` deliberately refuses to duplicate.** Its body reads:

  > `See CHANGELOG.md for what changed and when. The CHANGELOG is the single`
  > `source, so this heading no longer pins a version that goes stale on each bump.`

  This is the anti-duplication decision already taken (CHANGELOG v2.11, after the
  heading had gone stale at "WHAT'S NEW IN v2.5" while `VERSION` was 2.9). A future
  man page should inherit it rather than re-open it.

- **The `-P` help restates the agent architecture.** The `-P, --proxy` entry under
  `NETWORK CAPTURE` describes `JAVA_TOOL_OPTIONS`, the per-JVM logs, the self-disable
  on the Minecraft JVM, & the build command. The Known gaps history carries the same
  architecture at far greater length across the Phase 1 entries; since 2026-10-01 it
  sits in `docs/DECISIONS.md`, entry "Known gaps up to this date, moved here
  unedited". The overlap is the mechanism; the help text is a
  summary, not a copy, & no sentence appears verbatim in both.

- **The no-sudo claim appears three times.** `--help` says it twice, once in a
  section heading, `NETWORK CAPTURE (opt-in, no sudo)`, & once in the
  closing banner:

  > `Uses only standard Linux tools - no special permissions needed!`

  `AGENTS.md` states it as a hard constraint, & `DESIGN.md` principle 2 is titled
  "Zero `sudo`, ever". Three statements of one rule, in three registers.

- **`OUTPUT LOCATION` restates paths the code already derives.** It prints
  `$LOG_ROOT/session_YYYYMMDD_HHMMSS/`, the layout the code builds from `LOG_ROOT` &
  `SESSION_ID`. A path printed
  in help can drift from the path in code; today they agree.

Nothing else is duplicated. The docs are unusually clean on this: `AGENTS.md`
(purpose, constraints, gaps), `DESIGN.md` (conventions), `ROADMAP.md` (phases) &
`CHANGELOG.md` (history) do not restate each other's content, & `--help` does not
restate theirs beyond the four items above.

## 6. Examples in `--help`

`COMMON USAGE PATTERNS` carries **five** examples. Each is a
command line plus a `→` line saying what it produces:

| # | Command | Stated outcome |
|---|---|---|
| 1 | `run.sh` | Start/end lines on stderr, no session dir |
| 2 | `run.sh -v -M -a -m` | Full monitoring with immediate analysis |
| 3 | `run.sh -M -a -P` | Adds payload summary + regression check |
| 4 | `run.sh -B logs/session_XXXX`, `run.sh -K`, `run.sh -c 7` | (three maintenance commands on one line) |
| 5 | `run.sh -A` | Analyze logs without running TLauncher |

The shape is what makes this help good: every example states its *effect*, not just
its syntax. Example 1 is the strongest, because it documents that the no-argument
run is a real mode rather than a missing-argument error.

### Real cases with no example

- **`-R DIR`.** Regenerating a report for an existing session has no example,
  although it is the natural follow-up to every audited run & the only way to re-read
  a session after the tool has moved on.
- **`-n/--offline`.** No example anywhere, despite being the flag that answers "does
  TLauncher do anything without a network".
- **`-f/--file`.** Appears only in the unexpected-argument error, the `*)` arm, so
  a user learns it exists by making a mistake.
- **`--check-deps`.** Documented as an option, never shown, although it is the
  natural first command on a new machine.
- **Example 4 shows three unrelated commands on one line** with a single combined
  description, so none of the three gets its own stated outcome. It is the one
  example that describes rather than teaches.
- **`-ml/--mozilla-path`.** No example, & given the odd `-ml` spelling it is the flag
  most likely to be mistyped.

## 7. Report states

`tests/report-states.sh` drives `run.sh -R` against fixtures & asserts each state
prints its own phrase & none of the others. It reports **5/5**: four capture states
plus one contamination guard.

| State | Fixture | What distinguishes it in the output |
|---|---|---|
| `agent-data` | `tests/fixtures/agent-data/` | `Mode: Java agent, in-process after TLS decrypt` + the request table |
| `agent-empty` | `tests/fixtures/agent-empty/` | `Java agent active, but it logged no HTTP requests` + the diag pointer |
| `off` | `tests/fixtures/off/` | `no HTTP capture ran this session` |
| `legacy-mitm` | `tests/fixtures/legacy-mitm/` | `no longer supported`, on-disk facts only, promises nothing |
| cross-contamination | built in-test, no fixture | Not a report state: drives `reset_agent_tmp` + `aggregate_agent_logs` & fails if a previous session's line survives |

The report's own `case "$mode"`, in `report_network_capture`, has three arms: `agent`
(splitting into with-data & empty), `off`, & `*`.

### Reachable states the test does not cover

- **Empty `capture-mode` file, or none at all.** The `*)` arm is reached by two
  distinct inputs: a mode string that is no longer supported (`mitmproxy`, which the
  `legacy-mitm` fixture covers) & a session with no `capture-mode` file at all, which
  predates v2.10. Both print the same "not recorded or no longer supported" text, so
  the fixture exercises the arm but only one of its two entry paths.
- **`agent` mode with a malformed `http-intercept.log`.** The with-data branch is
  chosen by `[ -s "$ilog" ]` (non-empty) alone, so a file containing only banner lines
  & no request lines takes the data path & renders an empty table. `run.sh` avoids
  producing that (`aggregate_agent_logs` drops empty per-PID files, CHANGELOG v2.13),
  but no test pins the behaviour.
- **The new `-K` refusal path (exit 2)** is covered by neither suite; it was verified
  by hand in the v2.24 work, not by a test.

`tests/lock-exclusion.sh` is a separate suite, **5/5**, covering the lockfile
protocol rather than report states.
