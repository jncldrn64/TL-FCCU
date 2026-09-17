# CLI surface inventory

What `run.sh` actually exposes today, verified line by line against the code as it
stands after the v2.24 fixes in this same PR. This documents; it changes nothing.

It exists as raw material for fixing the man page standard later, so it records the
surface as it *is*, not as it was meant to be. Where the code and the help text
disagree, both are written down & the disagreement is named.

Every claim carries a `file:line`, re-verified against `run.sh` as of v2.25.

Line numbers are a snapshot & they rot: the v2.24 work shifted roughly forty of them
in one PR, and refreshing them by hand is not a habit that survives. Read the symbol
(the function, the variable, the `printf` whose text is quoted) as the real anchor,
& the number as a hint for finding it quickly.

## 0. Two premises that did not survive contact with the repo

The brief that asked for this inventory assumed a `README.md` and an existing man
page, and asked which parts of the man page are redundant.

**Neither existed when this inventory was written.** A manual page does now: v2.25
embedded one in `run.sh`, reachable with `--print-man` & installable with
`--install-man`, per `docs/cli-standard.md`. There is still no `README.md`, and still
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

All parsing happens in one `case` inside `main()`, `run.sh:2390-2455`. There is no
getopt, no flag bundling (`-vM` is rejected as an unknown option), and no `--`
end-of-options marker.

| Short | Long | Arg | Default | Parsed at | Global set |
|---|---|---|---|---|---|
| `-v` | `--verbose` | no | `false` | `run.sh:2391` | `VERBOSE` (`run.sh:87`) |
| `-n` | `--offline` | no | `false` | `run.sh:2392` | `OFFLINE_MODE` (`run.sh:88`) |
| `-M` | `--monitor` | no | `false` | `run.sh:2393` | `MONITOR_ENABLED` (`run.sh:89`) |
| `-a` | `--analyze` | no | `false` | `run.sh:2394` | `AUTO_ANALYZE` (`run.sh:90`) |
| `-A` | `--analyze-only` | no | `false` | `run.sh:2395` | `analyze_only` (local, `run.sh:2386`) |
| `-m` | `--mozilla` | no | `false` | `run.sh:2396` | `MOZILLA_CHECK` (`run.sh:91`) |
| `-K` | `--kill-orphans` | no | `false` | `run.sh:2397` | `KILL_ORPHANS` (`run.sh:96`) |
| `-R` | `--report` | **required** DIR | `""` | `run.sh:2398-2404` | `REPORT_SESSION` (`run.sh:97`) |
| `-c` | `--cleanup-logs` | **optional** DAYS | `7` | `run.sh:2405-2414` | `CLEANUP_LOGS_FLAG`, `CLEANUP_DAYS` (`run.sh:98-99`) |
| `-P` | `--proxy` | no | `false` | `run.sh:2415-2418` | `PROXY_ENABLED` (`run.sh:101`) |
| `-B` | `--save-baseline` | **required** DIR | `""` | `run.sh:2419-2425` | `SAVE_BASELINE_SESSION` (`run.sh:102`) |
| (none) | `--check-deps` | no | `false` | `run.sh:2426` | `CHECK_DEPS` (`run.sh:103`) |
| `-ml` | `--mozilla-path` | **required** PATH | `${REAL_HOME}/.mozilla` | `run.sh:2429-2435` | `MOZILLA_SEARCH_PATH` (`run.sh:93`) |
| `-f` | `--file` | **required** PATH | `""` | `run.sh:2436-2442` | `TLAUNCHER_PATH` (`run.sh:92`) |
| (none) | `--print-man` | no | `false` | `run.sh:2427` | `PRINT_MAN` (`run.sh:104`) |
| (none) | `--install-man` | no | `false` | `run.sh:2428` | `INSTALL_MAN` (`run.sh:105`) |
| `-h` | `--help` | no | n/a | `run.sh:2443` | calls `usage()`, exits 0 |

Notes the table cannot hold:

- **Three options have no short form:** `--check-deps`, `--print-man`, `--install-man`.
  `DESIGN.md` principle 4 says "every flag has a short form & a long alias", so these
  are documented exceptions. The two manual-page options are deliberate: they are
  run once, by hand, and a short letter spent on them would be a letter unavailable
  to a flag used every session.
- **`-ml` is a two-letter short option.** `-ml` is not standard short-option
  grammar; a POSIX-ish parser would read it as `-m -l`. Here the `case` matches the
  literal string `-ml`, so it works, but it means `-m` and `-ml` are different
  options distinguished only by the trailing letter (`run.sh:2396` vs `run.sh:1917`).
- **`-c`'s argument is optional & numeric-only.** `[[ "${2:-}" =~ ^[0-9]+$ ]]`
  (`run.sh:2408`). `-c foo` silently ignores `foo` & uses the default 7 rather than
  erroring, then `foo` is re-parsed as the next argument & dies as an unexpected
  argument (`run.sh:2450-2454`).
- **`-A` writes a function-local, not a global.** `analyze_only` is `local`
  (`run.sh:2386`), unlike every other flag target.

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
| `XDG_DATA_HOME` | `${REAL_HOME}/.local/share` (`run.sh:61`) | Parent of `SANDBOX_DIR` (`run.sh:71`) & both baseline files (`run.sh:109-110`) |
| `XDG_STATE_HOME` | `${REAL_HOME}/.local/state` (`run.sh:62`) | Parent of `LOG_ROOT`, every session dir (`run.sh:72`) |
| `XDG_RUNTIME_DIR` | `/run/user/${REAL_UID}`, then `/tmp` if that is not a directory (`run.sh:63-69`) | Holds `LOCKFILE` (`run.sh:73`) |
| `SUDO_USER` | `${USER:-$(id -un)}` (`run.sh:55`) | Identity used for `REAL_HOME` & the lockfile name |
| `SUDO_UID` | `$(id -u)` (`run.sh:56`) | Default `XDG_RUNTIME_DIR` path |
| `SUDO_GID` | `$(id -g)` (`run.sh:57`) | Read into `REAL_GID`; no consumer in the current code |
| `USER` | `$(id -un)` (`run.sh:55`) | Fallback identity when `SUDO_USER` is unset |
| `HOME` | `getent passwd` result wins; `$HOME` is the fallback (`run.sh:58`) | Base for `REAL_HOME` |

The `SUDO_*` reads are defensive, not an invitation: the hard constraint is zero
`sudo` (`AGENTS.md`, "Hard constraints"). They exist so that a user who ignores that
& runs under `sudo` still gets their own paths rather than root's.

`NO_COLOR` is **not** read. See section 4.

## 3. Exit codes

| Code | Meaning | Emitted at |
|---|---|---|
| `0` | Success, including every standalone mode, `--help` & `--print-man` | `EX_OK`, `run.sh:342` |
| `1` | Usage error: unknown option, missing or invalid argument | `EX_USAGE`, `run.sh:343` |
| `2` | Refusal: a live session holds the lock | `EX_LOCK_HELD`, `run.sh:344` |
| `3` | A required dependency is missing | `EX_MISSING_DEP`, `run.sh:345` |
| `4` | Environment: lockfile unwritable, jar not found, sandbox unusable | `EX_ENV`, `run.sh:346` |
| `5` | The lock state could not be determined | `EX_LOCK_UNKNOWN`, `run.sh:347` |
| TLauncher's own | The sandboxed run's exit status is propagated, not swallowed | end of `run_sandboxed` |

One code per condition, as of v2.25. Before that, `1` covered five distinct failures
(usage error, unknown option, missing dependency, unwritable lockfile, lost lock
race) & a caller had to read stderr to tell them apart. `die()` takes an optional
code, defaulting to `EX_USAGE`. `tests/doc-sync.sh` fails if an `EX_*` constant is
missing from the manual's `EXIT STATUS`.

## 4. Presentation

### Logging functions

| Function | Stream | Prefix | Also written to | Defined at |
|---|---|---|---|---|
| `log_msg` | stderr | `[YYYY-MM-DD HH:MM:SS.mmm]` | `${SESSION_DIR}/master.log` when a session dir exists | `run.sh:272-274` |
| `log_verbose` | stderr | same as `log_msg` | same as `log_msg` | `run.sh:276-283` |
| `log_error` | stderr | `[ERROR]` in red | `${SESSION_DIR}/master.log` | `run.sh:330-332` |
| `log_warn` | stderr | `[WARN]` in yellow | `${SESSION_DIR}/master.log` | `run.sh:334-336` |

All four go to stderr, all four are timestamped, and all four reach `master.log`
through one shared writer, `_log_emit`. Until v2.25 `log_error` & `log_warn` did
neither: they printed straight to stderr, so a past session's `master.log` showed the
run but none of the errors in it.

`log_verbose` ends with an explicit `return 0` (`run.sh:281`), load-bearing under
`set -e`; the comment there records the bug it fixes.

### Colour

Decided once, at `run.sh:233-238`, by `[ -t 1 ]`: colour when **stdout** is a TTY,
empty strings otherwise.

Two incoherencies, both real:

1. **The gate tests stdout; almost all coloured output goes to stderr.** `log_error`
   & `log_warn` write to stderr but take their colour from whether *stdout* is a
   terminal. `./run.sh -M > file` leaves stderr on the terminal with colour stripped;
   `./run.sh -M 2> file` writes escape codes into the file.
2. **`NO_COLOR` is not honoured.** There is no `NO_COLOR` read anywhere in the file.

Colour never reaches a log file: `log_msg` writes the raw `$*` to `master.log`
(`run.sh:268`) with no escape codes, & the colour lives in the `printf` format
strings, not in the messages.

### Silent mode & log levels

There is no `--quiet`, no `-q`, & no numeric log level. The levels are effectively:

- default: start/end lines & warnings/errors, all on stderr;
- `-v`: adds everything `log_verbose` carries, plus the configuration summary & a
  2-second countdown (`run.sh:2065`).

`DESIGN.md` principle 5 ("Silent by default, verbose by request, never mute") is the
written rule; the code matches it.

### Stream split, audited

`usage()` writes to **stdout** & exits 0 (`run.sh:2275`), which is right for `--help`.
Report generators write Markdown to stdout, which is how `-R` redirects into a file.

One inconsistency worth naming: the `-R` **success** line goes to stderr
(`run.sh:2481`), while the report body it announces goes to stdout. Defensible (it
keeps the success notice out of a redirected report) but it means a success message
is on the error stream.

## 5. `--help` against the rest of the documentation

`usage()` spans `run.sh:2254-2384`, 119 lines. Sections, in order:

1. `PURPOSE` (`run.sh:2261`)
2. `USAGE` (`run.sh:2265`)
3. `BASIC OPTIONS` (`run.sh:2271`)
4. `MONITORING OPTIONS` (`run.sh:2277`)
5. `MAINTENANCE / REPORTING` (`run.sh:2289`)
6. `NETWORK CAPTURE (opt-in, no sudo)` (`run.sh:2314`)
7. `SECURITY CHECKS` (`run.sh:2332`)
8. `BASELINES & REGRESSION (text-only, no extra network)` (`run.sh:2343`)
9. `COMMON USAGE PATTERNS` (`run.sh:2352`)
10. `WHAT'S NEW` (`run.sh:2372`)
11. `OUTPUT LOCATION` (`run.sh:2376`)

### What is duplicated, and between which documents

There is no man page & no README, so the duplication that exists is between
`--help` and the four root docs. It is small & mostly deliberate:

- **`WHAT'S NEW` deliberately refuses to duplicate.** `run.sh:2372-2374` reads:

  > `See CHANGELOG.md for what changed and when. The CHANGELOG is the single`
  > `source, so this heading no longer pins a version that goes stale on each bump.`

  This is the anti-duplication decision already taken (CHANGELOG v2.11, after the
  heading had gone stale at "WHAT'S NEW IN v2.5" while `VERSION` was 2.9). A future
  man page should inherit it rather than re-open it.

- **The `-P` help restates the agent architecture.** `run.sh:2314-2336` describes
  `JAVA_TOOL_OPTIONS`, the per-JVM logs, the self-disable on the Minecraft JVM, & the
  build command. `AGENTS.md` Known gaps carries the same architecture at far greater
  length across the Phase 1 entries. The overlap is the mechanism; the help text is a
  summary, not a copy, & no sentence appears verbatim in both.

- **The no-sudo claim appears three times.** `--help` says it twice, once in a
  section heading, `NETWORK CAPTURE (opt-in, no sudo)` (`run.sh:2314`), & once in the
  closing banner:

  > `Uses only standard Linux tools - no special permissions needed!` (`run.sh:2375`)

  `AGENTS.md` states it as a hard constraint, & `DESIGN.md` principle 2 is titled
  "Zero `sudo`, ever". Three statements of one rule, in three registers.

- **`OUTPUT LOCATION` restates paths the code already derives.** `run.sh:2376-2380`
  names the session-dir layout that `run.sh:71-73` & `89-90` compute. A path printed
  in help can drift from the path in code; today they agree.

Nothing else is duplicated. The docs are unusually clean on this: `AGENTS.md`
(purpose, constraints, gaps), `DESIGN.md` (conventions), `ROADMAP.md` (phases) &
`CHANGELOG.md` (history) do not restate each other's content, & `--help` does not
restate theirs beyond the four items above.

## 6. Examples in `--help`

`COMMON USAGE PATTERNS` (`run.sh:2352-2370`) carries **five** examples. Each is a
command line plus a `→` line saying what it produces:

| # | Command | Stated outcome | Line |
|---|---|---|---|
| 1 | `run.sh` | Start/end lines on stderr, no session dir | `run.sh:2353-2356` |
| 2 | `run.sh -v -M -a -m` | Full monitoring with immediate analysis | `run.sh:2357-2360` |
| 3 | `run.sh -M -a -P` | Adds payload summary + regression check | `run.sh:2361-2364` |
| 4 | `run.sh -B logs/session_XXXX`, `run.sh -K`, `run.sh -c 7` | (three maintenance commands on one line) | `run.sh:2365-2367` |
| 5 | `run.sh -A` | Analyze logs without running TLauncher | `run.sh:2368-2370` |

The shape is what makes this help good: every example states its *effect*, not just
its syntax. Example 1 is the strongest, because it documents that the no-argument
run is a real mode rather than a missing-argument error.

### Real cases with no example

- **`-R DIR`.** Regenerating a report for an existing session has no example,
  although it is the natural follow-up to every audited run & the only way to re-read
  a session after the tool has moved on.
- **`-n/--offline`.** No example anywhere, despite being the flag that answers "does
  TLauncher do anything without a network".
- **`-f/--file`.** Appears only in the unexpected-argument error (`run.sh:2452`), so
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

The report's own `case` has four arms (`run.sh:1330`, `1229`, `1235`, `1240`): `agent`
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
