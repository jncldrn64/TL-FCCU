# Changelog

Every notable change to the launcher (`run.sh` & its helpers). The format follows
[Keep a Changelog](https://keepachangelog.com/): one file that grows by section,
newest on top, headers `## vX.Y — YYYY-MM-DD`.

## v2.8 — 2026-07-04

Reconciliation with the MIDI-Scale-Trainer doc standard. Documentation only.

### Added
- Declared the `no-ai-slop-writing-rules` plugin (realrossmanngroup) as a session
  dependency for prose in `CLAUDE.md`. The `no-ai-slop`/`rossmann-voice` skills are
  installed at runtime through `/plugin`, not vendored, because upstream ships no
  LICENSE & this repo is public.

### Changed
- `CLAUDE.md`: added an em-dash format-token rule (banned in prose, allowed only in
  CHANGELOG date headers), plus "Third-party vendoring" & "Write scope" sections.

## v2.7 — 2026-07-02

Round 4.

### Added
- `--check-deps` (standalone, like `-K`/`-R`/`-c`/`-B`). It prints each dependency
  (present or missing, required or optional, & what it's for), refreshes the state
  file, & exits 0 when every required dep is present, 1 when one is missing.
- `tlauncher-sandbox-deps.ini` under `XDG_DATA_HOME`. It records each dependency
  once as `pre-existing` or `absent` with source & date, so a future uninstall
  path can tell what the script added from what was already there. First record
  wins; delete the file to re-inventory. `check_requirements` writes it too. No
  auto-install in this round; installing packages is still the user's job.

### Changed
- The network monitor filters to TLauncher's own PID tree. `monitor_network` used
  to log every established connection on the system, so a browser, Discord, or a
  system updater running in parallel dumped its IPs into `network.log` (Microsoft
  52.111/52.112/52.123, Meta 31.13.71.49, Google 142.251.x seen in real sessions).
  It now finds the firejail sandbox by its `mcbox` hostname, walks that PID tree
  every cycle to catch the JRE/Minecraft/crash_assistant children, & keeps only
  `ss -tnp` lines whose `pid=` is in the tree. Still no privileges: same-user
  sockets show their pid.
- Paths printed to a terminal show `~` instead of `/home/<user>`. usage(), the
  configuration summary, the session analysis footer, & the path-carrying log
  lines run through a new `disp_path` helper, so no home directory leaks into a
  screenshot, a paste, or a CI log. Real filesystem operations still use absolute
  paths.

## v2.6 — 2026-06-30

Round 3, documentation only.

### Added
- `CHANGELOG.md`, this file.
- `AGENTS.md`, a short cold-start entry point with an honest "Known gaps" section.
  It records that `-P` never ran end to end against a real `mitmdump`, & that the
  `tlauncher.ru` family isn't yet a hard risk pattern.
- `DESIGN.md` section 6: verbosity depends on who invokes a tool. A human-invoked
  tool never goes mute (rule 5); a hotkey, cron, or window-manager hook may fail
  in total silence.

### Fixed
- Added `tl.vg` to `MITM_ALLOWLIST`. It's a legitimate TLauncher domain seen in
  the same session as `repo.tlauncher.org`. Without it a `-P` capture would flag
  benign `tl.vg` traffic as off-allowlist. Data correction, no logic change.

## v2.5 — 2026-06-30

Round 2.

### Added
- Sandbox-only mode for a bare `./run.sh`. It prints one start line
  (`...no monitoring, use -M to enable...`) & one end line carrying TLauncher's
  exit code to stderr, & it writes nothing under `tlauncher-logs/`. Before this it
  launched fine but printed no end line, so it looked dead. That was a feedback
  gap, not a logic bug.
- Network payload summary for `-P` captures, through the new
  `scripts/mitm_report.py`. It prints one line per request
  (host, method, path, status, request bytes, response bytes) & a
  "Flagged requests" block for any off-allowlist host or any POST/PUT that carried
  a body, with the body truncated at 2048 bytes. That block answers the only
  question that matters: did it send anything.
- Domain regression check. A new baseline file,
  `tlauncher-sandbox-baseline-domains.txt`, plus `-B/--save-baseline SESSION_DIR`
  to build it from a session you trust. The report's "Regression check" section
  marks a first-seen domain with `NEW DOMAIN` & a known-risky one with
  `NEW RISKY DOMAIN`, flagging `advancedrepository` even when it's already in the
  baseline. Text comparison only, no extra network.
- `DESIGN.md`, the first written copy of the project's conventions.

### Changed
- Audited `usage()` line by line against the real parser: it now documents the
  sandbox-only mode, corrects the `-M`/`-a`/`-m` descriptions, names the
  standalone flags, & lists the baseline files.
- The payload section says "capture disabled" when there's no `mitm.flow`, so
  "nothing captured" & "nothing suspicious" stop hiding under the same silence.

## v2.4 — 2026-06-30

Round 1.

### Added
- `-K/--kill-orphans` to reap strays from earlier sessions. It excludes the
  script's own ancestor chain so it can't kill the shell that launched it.
- Filesystem noise filtering: a lossless `files.log` plus a small `signal.log`
  driven by `NOISE_PATTERNS`. One real session logged 5,346 events into
  `signal.log` against 178,756 raw MODIFY events seen in about 30 minutes.
- First-seen process & network logging instead of a full `ps`/`ss` dump every 2
  seconds, which had produced a 42 MB `java-processes.log` per session.
- `INCIDENT_REPORT.md`, one aggregated report per session, 5.7 KB on a real run.
- Log retention through `-c/--cleanup-logs [DAYS]`, default 7 days, with a 500 MB
  cap. It also runs silently at the start of every `-M` run, after the directory
  reached 2 GB on its own.
- Opt-in mitmproxy capture through `-P/--proxy [PORT]`, default port 8080, no
  sudo. It sets the JVM proxy properties, because the JVM ignores `HTTP_PROXY`
  environment variables by default, & it turns itself off cleanly when `mitmdump`
  is absent.

### Fixed
- Orphaned monitors, the critical bug. The monitor block ran inside a
  `( ... ) 200>"$LOCKFILE"` subshell, so the PIDs it appended to the global
  `MONITOR_PIDS` never reached the parent shell, & the cleanup loop ran over an
  empty array. Every `inotifywait`/`ss`/`ps` got orphaned & kept writing into old
  logs; one stray `inotifywait` grew a single `files.log` to 51 MB. The lock now
  lives on an `exec`'d descriptor in the current shell, & cleanup reaps whole
  process trees with `kill_tree`, TERM then KILL, so no reparented leaf survives.
- Three `set -e` traps. `log_verbose` now ends with `return 0`, because a bare
  call returning non-zero aborted every non-verbose run. The `grep -c ... || echo 0`
  idiom that printed `0\n0` & crashed `printf %d` got fixed. `USER` is guarded when
  unset.
