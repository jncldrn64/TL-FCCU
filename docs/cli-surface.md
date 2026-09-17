# CLI surface inventory

What `run.sh` actually exposes today, verified line by line against the code as it
stands after the v2.24 fixes in this same PR. This documents; it changes nothing.

It exists as raw material for fixing the man page standard later, so it records the
surface as it *is*, not as it was meant to be. Where the code and the help text
disagree, both are written down & the disagreement is named.

Every claim carries a `file:line`. Line numbers move; the facts were read at commit
time & re-checked after the v2.24 fixes landed.

## 0. Two premises that did not survive contact with the repo

The brief that asked for this inventory assumed a `README.md` and an existing man
page, and asked which parts of the man page are redundant.

**Neither file exists.** `git ls-files` returns no `README.md`, no `*.1`, no `man/`
directory, and `git log --all --diff-filter=A` shows neither was ever committed. The
tracked documentation is exactly: `AGENTS.md`, `CLAUDE.md`, `DESIGN.md`,
`CHANGELOG.md`, `ROADMAP.md`, `LICENSE`.

So section 5 below answers the question that can be answered: what `--help` holds,
& what it duplicates against the docs that do exist. There is no man page to call
redundant yet. When one gets written, this inventory is the input.

## 1. Flag inventory

All parsing happens in one `case` inside `main()`, `run.sh:1880-1943`. There is no
getopt, no flag bundling (`-vM` is rejected as an unknown option), and no `--`
end-of-options marker.

| Short | Long | Arg | Default | Parsed at | Global set |
|---|---|---|---|---|---|
| `-v` | `--verbose` | no | `false` | `run.sh:1881` | `VERBOSE` (`run.sh:69`) |
| `-n` | `--offline` | no | `false` | `run.sh:1882` | `OFFLINE_MODE` (`run.sh:70`) |
| `-M` | `--monitor` | no | `false` | `run.sh:1883` | `MONITOR_ENABLED` (`run.sh:71`) |
| `-a` | `--analyze` | no | `false` | `run.sh:1884` | `AUTO_ANALYZE` (`run.sh:72`) |
| `-A` | `--analyze-only` | no | `false` | `run.sh:1885` | `analyze_only` (local, `run.sh:1876`) |
| `-m` | `--mozilla` | no | `false` | `run.sh:1886` | `MOZILLA_CHECK` (`run.sh:73`) |
| `-K` | `--kill-orphans` | no | `false` | `run.sh:1887` | `KILL_ORPHANS` (`run.sh:78`) |
| `-R` | `--report` | **required** DIR | `""` | `run.sh:1888-1894` | `REPORT_SESSION` (`run.sh:79`) |
| `-c` | `--cleanup-logs` | **optional** DAYS | `7` | `run.sh:1895-1904` | `CLEANUP_LOGS_FLAG`, `CLEANUP_DAYS` (`run.sh:80-81`) |
| `-P` | `--proxy` | no | `false` | `run.sh:1905-1908` | `PROXY_ENABLED` (`run.sh:83`) |
| `-B` | `--save-baseline` | **required** DIR | `""` | `run.sh:1909-1915` | `SAVE_BASELINE_SESSION` (`run.sh:84`) |
| (none) | `--check-deps` | no | `false` | `run.sh:1916` | `CHECK_DEPS` (`run.sh:85`) |
| `-ml` | `--mozilla-path` | **required** PATH | `${REAL_HOME}/.mozilla` | `run.sh:1917-1923` | `MOZILLA_SEARCH_PATH` (`run.sh:75`) |
| `-f` | `--file` | **required** PATH | `""` | `run.sh:1924-1930` | `TLAUNCHER_PATH` (`run.sh:74`) |
| `-h` | `--help` | no | n/a | `run.sh:1931` | calls `usage()`, exits 0 |

Notes the table cannot hold:

- **`--check-deps` has no short form.** Every other option has one. `DESIGN.md`
  principle 4 says "every flag has a short form & a long alias", so this is the one
  documented exception, & `--help` lists it without flagging that.
- **`-ml` is a two-letter short option.** `-ml` is not standard short-option
  grammar; a POSIX-ish parser would read it as `-m -l`. Here the `case` matches the
  literal string `-ml`, so it works, but it means `-m` and `-ml` are different
  options distinguished only by the trailing letter (`run.sh:1886` vs `run.sh:1917`).
- **`-c`'s argument is optional & numeric-only.** `[[ "${2:-}" =~ ^[0-9]+$ ]]`
  (`run.sh:1897`). `-c foo` silently ignores `foo` & uses the default 7 rather than
  erroring, then `foo` is re-parsed as the next argument & dies as an unexpected
  argument (`run.sh:1938-1942`).
- **`-A` writes a function-local, not a global.** `analyze_only` is `local`
  (`run.sh:1876`), unlike every other flag target.

### Options in the code but not in `--help`

None. Every one of the 15 parser arms above appears in `usage()`.

### Options in `--help` that no longer do anything

None. The `-P` help text was corrected when the mitmproxy fallback was removed
(CHANGELOG v2.21), & the ROADMAP Phase 2 sweep re-audited the rest. Re-checked here
against the parser: every documented flag still reaches a live code path.

## 2. Environment variables read

| Variable | Default when unset | Effect |
|---|---|---|
| `XDG_DATA_HOME` | `${REAL_HOME}/.local/share` (`run.sh:43`) | Parent of `SANDBOX_DIR` (`run.sh:53`) & both baseline files (`run.sh:89-90`) |
| `XDG_STATE_HOME` | `${REAL_HOME}/.local/state` (`run.sh:44`) | Parent of `LOG_ROOT`, every session dir (`run.sh:54`) |
| `XDG_RUNTIME_DIR` | `/run/user/${REAL_UID}`, then `/tmp` if that is not a directory (`run.sh:45-51`) | Holds `LOCKFILE` (`run.sh:55`) |
| `SUDO_USER` | `${USER:-$(id -un)}` (`run.sh:37`) | Identity used for `REAL_HOME` & the lockfile name |
| `SUDO_UID` | `$(id -u)` (`run.sh:38`) | Default `XDG_RUNTIME_DIR` path |
| `SUDO_GID` | `$(id -g)` (`run.sh:39`) | Read into `REAL_GID`; no consumer in the current code |
| `USER` | `$(id -un)` (`run.sh:37`) | Fallback identity when `SUDO_USER` is unset |
| `HOME` | `getent passwd` result wins; `$HOME` is the fallback (`run.sh:41`) | Base for `REAL_HOME` |

The `SUDO_*` reads are defensive, not an invitation: the hard constraint is zero
`sudo` (`AGENTS.md`, "Hard constraints"). They exist so that a user who ignores that
& runs under `sudo` still gets their own paths rather than root's.

`NO_COLOR` is **not** read. See section 4.

## 3. Exit codes

| Code | Meaning | Emitted at |
|---|---|---|
| `0` | Success, including every standalone mode & `--help` | `run.sh:1868` (`usage`), `1951`, `1957`, `1962`, `1967`, `1996` |
| `1` | Fatal error via `die()`: missing required argument, TLauncher jar not found, lockfile unwritable, lock already held | `run.sh:288` (inside `die`) |
| `1` | Unknown option, or unexpected non-option argument | `run.sh:1935`, `run.sh:1941` |
| `1` | A required dependency is missing (`check_requirements`) | `run.sh:489` |
| `1` | `--check-deps` found a missing required dependency | `check_deps` returns 1, propagated by `exit $?` at `run.sh:1972` |
| `2` | `-K` refused: a live session holds the lock | `kill_orphans` returns 2 (`run.sh:387`), propagated by `exit $?` at `run.sh:1950` |
| TLauncher's own | The sandboxed run's exit status is reported, not swallowed | end of `run_sandboxed` |

**`1` is reused for five distinct conditions.** A caller cannot tell a missing
dependency from an unknown flag from a lost lock race by status alone; it has to
read stderr. `2` is the only status with a single meaning, & it is new in v2.24.

## 4. Presentation

### Logging functions

| Function | Stream | Prefix | Also written to | Defined at |
|---|---|---|---|---|
| `log_msg` | stderr | `[YYYY-MM-DD HH:MM:SS.mmm]` | `${SESSION_DIR}/master.log` when a session dir exists | `run.sh:215-222` |
| `log_verbose` | stderr | same as `log_msg` | same as `log_msg` | `run.sh:223-230` |
| `log_error` | stderr | `[ERROR]` in red | nothing | `run.sh:277-279` |
| `log_warn` | stderr | `[WARN]` in yellow | nothing | `run.sh:281-283` |

All four go to stderr. `log_msg`/`log_verbose` are timestamped; `log_error`/`log_warn`
are not, so an error cannot be correlated in time with the surrounding run from the
terminal alone, only from `master.log` (which never receives it).

`log_verbose` ends with an explicit `return 0` (`run.sh:229`), load-bearing under
`set -e`; the comment there records the bug it fixes.

### Colour

Decided once, at `run.sh:204-209`, by `[ -t 1 ]`: colour when **stdout** is a TTY,
empty strings otherwise.

Two incoherencies, both real:

1. **The gate tests stdout; almost all coloured output goes to stderr.** `log_error`
   & `log_warn` write to stderr but take their colour from whether *stdout* is a
   terminal. `./run.sh -M > file` leaves stderr on the terminal with colour stripped;
   `./run.sh -M 2> file` writes escape codes into the file.
2. **`NO_COLOR` is not honoured.** There is no `NO_COLOR` read anywhere in the file.

Colour never reaches a log file: `log_msg` writes the raw `$*` to `master.log`
(`run.sh:219`) with no escape codes, & the colour lives in the `printf` format
strings, not in the messages.

### Silent mode & log levels

There is no `--quiet`, no `-q`, & no numeric log level. The levels are effectively:

- default: start/end lines & warnings/errors, all on stderr;
- `-v`: adds everything `log_verbose` carries, plus the configuration summary & a
  2-second countdown (`run.sh:2065`).

`DESIGN.md` principle 5 ("Silent by default, verbose by request, never mute") is the
written rule; the code matches it.

### Stream split, audited

`usage()` writes to **stdout** & exits 0 (`run.sh:1868`), which is right for `--help`.
Report generators write Markdown to stdout, which is how `-R` redirects into a file.

One inconsistency worth naming: the `-R` **success** line goes to stderr
(`run.sh:1956`), while the report body it announces goes to stdout. Defensible (it
keeps the success notice out of a redirected report) but it means a success message
is on the error stream.

## 5. `--help` against the rest of the documentation

`usage()` spans `run.sh:1751-1869`, 119 lines. Sections, in order:

1. `PURPOSE` (`run.sh:1758`)
2. `USAGE` (`run.sh:1762`)
3. `BASIC OPTIONS` (`run.sh:1768`)
4. `MONITORING OPTIONS` (`run.sh:1774`)
5. `MAINTENANCE / REPORTING` (`run.sh:1786`)
6. `NETWORK CAPTURE (opt-in, no sudo)` (`run.sh:1804`)
7. `SECURITY CHECKS` (`run.sh:1822`)
8. `BASELINES & REGRESSION (text-only, no extra network)` (`run.sh:1828`)
9. `COMMON USAGE PATTERNS` (`run.sh:1837`)
10. `WHAT'S NEW` (`run.sh:1857`)
11. `OUTPUT LOCATION` (`run.sh:1861`)

### What is duplicated, and between which documents

There is no man page & no README, so the duplication that exists is between
`--help` and the four root docs. It is small & mostly deliberate:

- **`WHAT'S NEW` deliberately refuses to duplicate.** `run.sh:1857-1859` reads:

  > `See CHANGELOG.md for what changed and when. The CHANGELOG is the single`
  > `source, so this heading no longer pins a version that goes stale on each bump.`

  This is the anti-duplication decision already taken (CHANGELOG v2.11, after the
  heading had gone stale at "WHAT'S NEW IN v2.5" while `VERSION` was 2.9). A future
  man page should inherit it rather than re-open it.

- **The `-P` help restates the agent architecture.** `run.sh:1805-1821` describes
  `JAVA_TOOL_OPTIONS`, the per-JVM logs, the self-disable on the Minecraft JVM, & the
  build command. `AGENTS.md` Known gaps carries the same architecture at far greater
  length across the Phase 1 entries. The overlap is the mechanism; the help text is a
  summary, not a copy, & no sentence appears verbatim in both.

- **The no-sudo claim appears three times.** `--help` says it twice, once in a
  section heading, `NETWORK CAPTURE (opt-in, no sudo)` (`run.sh:1804`), & once in the
  closing banner:

  > `Uses only standard Linux tools - no special permissions needed!` (`run.sh:1865`)

  `AGENTS.md` states it as a hard constraint, & `DESIGN.md` principle 2 is titled
  "Zero `sudo`, ever". Three statements of one rule, in three registers.

- **`OUTPUT LOCATION` restates paths the code already derives.** `run.sh:1861-1865`
  names the session-dir layout that `run.sh:53-55` & `89-90` compute. A path printed
  in help can drift from the path in code; today they agree.

Nothing else is duplicated. The docs are unusually clean on this: `AGENTS.md`
(purpose, constraints, gaps), `DESIGN.md` (conventions), `ROADMAP.md` (phases) &
`CHANGELOG.md` (history) do not restate each other's content, & `--help` does not
restate theirs beyond the four items above.

## 6. Examples in `--help`

`COMMON USAGE PATTERNS` (`run.sh:1837-1855`) carries **five** examples. Each is a
command line plus a `→` line saying what it produces:

| # | Command | Stated outcome | Line |
|---|---|---|---|
| 1 | `run.sh` | Start/end lines on stderr, no session dir | `run.sh:1838-1841` |
| 2 | `run.sh -v -M -a -m` | Full monitoring with immediate analysis | `run.sh:1842-1845` |
| 3 | `run.sh -M -a -P` | Adds payload summary + regression check | `run.sh:1846-1849` |
| 4 | `run.sh -B logs/session_XXXX`, `run.sh -K`, `run.sh -c 7` | (three maintenance commands on one line) | `run.sh:1850-1852` |
| 5 | `run.sh -A` | Analyze logs without running TLauncher | `run.sh:1853-1855` |

The shape is what makes this help good: every example states its *effect*, not just
its syntax. Example 1 is the strongest, because it documents that the no-argument
run is a real mode rather than a missing-argument error.

### Real cases with no example

- **`-R DIR`.** Regenerating a report for an existing session has no example,
  although it is the natural follow-up to every audited run & the only way to re-read
  a session after the tool has moved on.
- **`-n/--offline`.** No example anywhere, despite being the flag that answers "does
  TLauncher do anything without a network".
- **`-f/--file`.** Appears only in the unexpected-argument error (`run.sh:1940`), so
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

The report's own `case` has four arms (`run.sh:1204`, `1229`, `1235`, `1240`): `agent`
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
