# TLauncher Sandbox: Design Conventions

This file is the style guide. `run.sh` reads like a standard Unix program, &
every change keeps it that way. A new feature that breaks these conventions gets
rejected, whether a human or an agent wrote it. When you're unsure, copy the
shape of the code already in the file instead of inventing a new idiom.

## 1. XDG Base Directory, always

No hardcoded `~/.something`. Every path resolves through an XDG variable with a
fallback:

```sh
XDG_DATA_HOME="${XDG_DATA_HOME:-${REAL_HOME}/.local/share}"
XDG_STATE_HOME="${XDG_STATE_HOME:-${REAL_HOME}/.local/state}"
XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/${REAL_UID}}"   # falls back to /tmp
```

Everything derives from those three:

- Sandbox HOME: `$XDG_DATA_HOME/tlauncher-sandbox`
- Session logs: `$XDG_STATE_HOME/tlauncher-logs/session_<ts>/`
- Lockfile: `$XDG_RUNTIME_DIR/tlauncher-<user>.lock`
- Baselines: `$XDG_DATA_HOME/tlauncher-sandbox-baseline-{ips,domains}.txt`

The two baseline files added in Round 2 already follow this. Keep it that way for
any new file the script reads or writes.

## 2. Zero `sudo`, ever

The script never calls `sudo`, never asks for a password, & never needs a
capability beyond what `firejail` drops on its own. An optional dependency like
`javac` (for the one-time agent build) gets probed with `command -v` & degraded
with a one-line manual install hint. A printed line that reads `apt install
default-jdk` is an instruction for the user to run by hand; that's allowed. The
script running it is not.

## 3. Race conditions get designed out, not patched later

Hold a lock with `flock` over a file descriptor opened by `exec N>FILE`, in the
same shell scope that uses the resource:

```sh
exec 200>"$LOCKFILE"
flock -n 200 || die "already running"
```

Round 1 paid for this rule. The monitor block used to live inside a `( ... )`
subshell, so the PIDs the monitors appended to `MONITOR_PIDS` died with the
subshell & never reached the parent. The cleanup loop then ran over an empty
array, every `inotifywait`/`ss`/`ps` got orphaned, & one stray `inotifywait`
wrote a single session's `files.log` up to 51 MB. Never wrap shared state in
`( ... )` when that state has to outlive the subshell.

Track every background job by its real PID, captured from `$!` the line after you
launch it (see `spawn_monitor`). The `pgrep`/argv-tag matching in
`find_orphan_pids` (the `tlauncher-mon-<session>` tag) is a backstop, not the
handle. Cleanup reaps whole process trees with `kill_tree`, TERM then KILL, so no
reparented leaf keeps writing.

## 4. Standard CLI grammar

- Every flag has a short form & a long alias: `-v/--verbose`, `-M/--monitor`.
- `-h/--help` prints usage & exits 0.
- An unknown option prints to stderr, points at `--help`, & exits 1.
- Flags stay combinable unless they genuinely conflict, & a no-op combination
  warns instead of failing silently. `-a` without `-M` prints a warning & turns
  itself off rather than dying.
- The standalone modes (`-K`, `-R`, `-c`, `-B`, `-A`) do their one job & exit
  without launching TLauncher.
- `usage()` is part of the contract. It describes what the current parser
  actually does, so audit it the moment a flag changes.

## 5. Silent by default, verbose by request, never mute

Silent doesn't mean no sign of life. The split:

- A start line & an end line print in every mode, including the no-argument
  sandbox-only run, through `log_msg`, which always writes to stderr.
- The configuration summary, the 2-second countdown, & per-monitor detail print
  only with `-v` or when a logging session is active.
- `log_verbose` ends with `return 0`. A bare call that returns non-zero aborts the
  whole script under `set -e`, & that bug used to kill every non-verbose run.

## 6. Verbosity is a function of who invokes you, not an absolute

Rule 5 isn't universal. It's correct for this tool because of how the tool gets
launched, & the right verbosity depends on who pulls the trigger.

A human watching a terminal launches `run.sh`, so it never goes mute: a person is
waiting on the result, & a silent failure there is worse than noise. Print a start
& end line, send errors to stderr, exit with a real code. A keyboard-shortcut
helper or a cron job runs with nobody watching, so the opposite is correct on
purpose; those should fail in total silence with chained `|| exit 0`, because an
error message no one reads only interrupts. Silence is the feature there.

A sibling utility that swallows every error without a word isn't breaking rule 5.
It's a different rule for a different context. Before you add or judge a script,
ask who launches it & whether anyone is looking, then pick the verbosity from the
answer. Don't copy code from those other tools into this repo; take the principle
only.

## 7. Idempotence & cleanup

Every resource the script creates has a written teardown or regeneration path, &
`usage()` tells the user about it:

| Resource          | Created by           | Reset / regenerate                          |
|-------------------|----------------------|---------------------------------------------|
| Lockfile          | `run_sandboxed`      | Removed by `cleanup` (EXIT/INT/TERM trap)   |
| Sandbox dir       | `setup_sandbox`      | Safe to `rm -rf`; rebuilt next run          |
| Session dirs      | `-M` / `-P` runs     | `-c/--cleanup-logs` compresses & prunes them|
| Baseline files    | `-B/--save-baseline` | Delete to reset; re-run `-B` to recreate    |
| Orphaned monitors | (shouldn't happen)   | `-K/--kill-orphans` reaps strays            |

## 8. Report size discipline

`INCIDENT_REPORT.md` stays in the KB range. A real audited session's report ran
5.7 KB; a `files.log` from the same family of sessions reached 51 MB & 178,756
MODIFY events in about 30 minutes. The report never carries that weight. It
summarizes: one line per item, bodies truncated at 2048 bytes, lists capped by
`head`. A report section degrades to a one-line Markdown note instead of crashing
when its input is missing: the network-capture section states on-disk facts &
claims no cause rather than guessing when a session's log is empty or its mode is
one no longer supported.

## 9. One program, one file

`run.sh` is one file (near 2,000 lines, 47 prefixed functions today) & it stays that
way on purpose. The reasons, not a line count:

- A security audit tool gets read end to end by whoever audits it. That is the point
  of it. Chasing a `source` across `lib/*.sh` costs the reader more than the
  navigation saves; the whole thing has to be held in one head, so it lives in one
  file.
- Bash has no namespaces. Splitting buys navigation, not isolation. The per-area
  function prefixes (`log_`, `deps_`, `kill_`, `monitor_`, `report_`) already do the
  isolation a reader needs, in one file, found with `grep`.
- Splitting adds a failure mode that does not exist today. The script resolves its own
  `SCRIPT_DIR` only to find the `scripts/` helpers; a `lib/` layout would make it load
  libraries that can be missing, moved, or stale, & fail at launch on a machine where
  the copy came over incomplete.
- Distribution is copy-and-run, not install. `run.sh` lands on a machine & runs; no
  package manager places its parts.

This is a property, not a tolerance: end-to-end auditability does not degrade at N
lines, so a threshold would be decoration. What the boundary tracks is whether a piece
is its own program. The Java agent & `build-agent.sh` live in `scripts/` because each
is a separate program, built & audited on its own terms, not a slice of the launcher
carved out for navigation. So the condition that would move something out of `run.sh`
is that: it becomes a program in its own right, audited separately, the way `scripts/`
already is. Nothing in the launcher's own logic currently is.
