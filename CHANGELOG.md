# Changelog

Every notable change to the launcher (`run.sh` & its helpers). The format follows
[Keep a Changelog](https://keepachangelog.com/): one file that grows by section,
newest on top, headers `## vX.Y — YYYY-MM-DD`.

## v2.26 — 2026-09-19

One bug, in eighteen places. `tests/doc-sync.sh` had been failing about one run in
five & blaming a different, correctly documented option each time. The cause was not
in the check: it was the shape `printf '%s' "$var" | grep -q PATTERN` under
`set -o pipefail`, which returns 141 when the producer outruns what the pipe can
hold. Every site with that shape is gone.

### Fixed
- Browser-directory & JAR detection in the session summary could miss a hit that was
  really there. `printf "%s" "$new_files" | grep -qE ...` ran under `pipefail`, so a
  `SIGPIPE` in `printf` made the `if` read as "no match" & the summary printed no
  warning for a `.mozilla` directory the sandbox had actually grown. `$new_files` has
  no bound: it is one line per file created during the session. For a tool whose only
  job is to notice exactly that, this was the worst site in the repo to carry the
  race. Both conditions now read the variable with a here-string, which involves no
  pipe.
- The same shape removed from the filesystem monitor's noise filter & from the risky-
  domain match in the report. One line of `inotifywait` output & one domain name: both
  small today, neither with a declared bound. Corrected for uniformity, not because
  either was observed failing.
- Eleven further sites, found by sweeping `run.sh` rather than by report, where the
  early-exiting consumer was `head` or `grep -m` instead of `grep -q`: the HTTP table
  (`sort -u | head -60`, where `sort` buffers the whole table & is the process that
  dies), the new-process blocks, the incident report's new-files block, the timeline,
  the summary's file & IP listings, the largest-files listing, the `--check-deps`
  registry line, the orphan-PID `ps` lines & the two version banners. Under
  `set -euo pipefail` these do not silently mis-answer, they abort the function, so
  the failure mode was a report that stops halfway rather than one that lies. Both
  are bad; the first one is worse, which is why it is listed first.
- The three test suites carried the same shape: `doc-sync.sh` in six places,
  `lock-exclusion.sh` in two, `report-states.sh` in two. Where the match is a fixed
  string, they now use `case`, which spawns no process & opens no pipe at all.
- The manual page had one text line past 80 bytes in `FILES`, which `mandoc -Tlint`
  reports as `STYLE`. Split in two. The roff was valid before & after; this is
  typography, not syntax.
- `doc-sync.sh` check 5 treated any output from `mandoc` as a failure, so the page
  would have gone red over that width note the moment anyone installed a formatter.
  It now grades by severity: `ERROR`/`WARNING`/`UNSUPP`/`SYSERR` fail, `STYLE` prints
  as a note & passes. The reasoning is written at the check so the next reader can
  disagree with the line rather than guess where it is.

### Added
- `tests/run-all.sh`. Runs the three suites once, then re-runs the flakiness-sensitive
  one `REPEATS` times, default 3. One green run never disproved this bug: the first
  version of `doc-sync.sh` was green when it shipped & was already broken. The proof
  run for this release was `REPEATS=200`, 200/200 green.
- `DESIGN.md` principle 3 gains the rule this bug came from: under `pipefail`, a
  pipeline whose consumer can exit first is a race, the consumers that do it
  (`grep -q`, `grep -m N`, `head`, `sed` with `q`, `awk` with `exit`, a single
  `read`), what to write instead depending on whether the producer is a variable, a
  file, or a command, & the explicit refusal of `|| true`, `set +o pipefail`, &
  `|| [ $? -eq 141 ]` as fixes. It also records that the threshold is not portable:
  measured here on bash 5.2.21, nothing failed at 61,013 bytes in 2,000 tries & about
  a quarter of runs failed at 62,013, which is the 64 KiB pipe capacity, not the
  4 KiB figure this machine was expected to show.

### Changed
- `VERSION` 2.25 -> 2.26.

## v2.25 — 2026-09-17

Three review findings from the previous PR, & the command-line documentation
standard, applied: a manual page that ships inside the script, one exit code per
condition, & a test that keeps the two documents from drifting.

### Fixed
- Errors & warnings never reached the session log. `log_error` & `log_warn` printed
  straight to stderr with no timestamp & no file write, so reading a past session's
  `master.log` showed the run but none of the errors in it. In a tool whose claim is
  that an auditor can read it end to end (`DESIGN.md` principle 9), the hole was in
  the worst possible place. All four levels now share one writer, `_log_emit`, which
  fixes the timestamp format & the file write in one spot. Colour is decided at print
  time & only for the terminal: `master.log` received no escape sequences before this
  change & receives none after, verified with colour forced on.
- `-K` could not tell an unreadable lockfile from a live session. The probe returned
  "not free" for both, so a lockfile left owned by another user made `-K` refuse
  forever while stating that a session was running, which was false. Three states
  now: free, held, & indeterminable, the last with its own message & its own exit
  code. Verified against the real case, a root-owned `0600` lockfile read as another
  user.
- `-K` released the lock before sweeping. It took the lock, released it, closed the
  descriptor, & only then looked for orphans to kill, so a legitimate session
  starting inside that window lost its monitors, which is the failure the interlock
  exists to prevent. The lock is now held across the whole sweep. Verified: a
  concurrent `flock -n` fails while the sweep is in progress.

### Added
- A manual page, in roff, embedded in `run.sh`. `--print-man` writes it to stdout &
  exits 0; `--install-man` installs it under `${XDG_DATA_HOME}/man/man1` without
  root, prints the `MANPATH` hint when it is needed, & links the canonical command
  name into `~/.local/bin` when that directory exists & is on `PATH`. No `.1` file
  lives in the tree: the script is the single copy, which is the same reason
  `DESIGN.md` principle 9 keeps the program in one file. The page carries the four
  sections no user could see before: `EXIT STATUS`, `ENVIRONMENT`, `FILES` &
  `DIAGNOSTICS`.
- `docs/cli-standard.md`, normative. The canonical command name (`tlauncher-fccu`),
  where the manual lives, the split between it & the long `--help`, the presentation
  rules, the exit-code table, & the array naming convention.
- `tests/doc-sync.sh`. A long `--help` plus a full manual page duplicates content on
  purpose; this is what stops it duplicating maintenance. It checks that every parsed
  option appears in both documents & that neither documents an option the parser does
  not accept, that every `EX_*` code appears in `EXIT STATUS`, that both documents
  write to stdout & exit 0 with nothing on stderr, & that the manual's sections are
  present & in the fixed order. Each rule was verified to go red by breaking it.
  7/8 green with 1 honestly reported as skipped: neither `mandoc` nor `groff` is
  installed here, so the roff is NOT machine-validated & the check says so rather
  than passing by default.

### Changed
- One exit code per condition. `1` used to cover usage errors, unknown options, a
  missing dependency, an unwritable lockfile & a lost lock race, so a caller could
  not tell them apart without parsing stderr. Now `1` usage, `2` a live session holds
  the lock, `3` a missing dependency, `4` an environment error, `5` the lock state is
  indeterminable. `die()` takes an optional code. TLauncher's own status is still
  propagated unchanged.
- Regex arrays are named for their semantics: `*_PATTERNS` holds regular expressions
  & is joined raw, `*_LITERALS` holds literals & is joined with escaping. A comment
  was previously the only thing distinguishing `NOISE_PATTERNS` from the domain
  lists, which is how a literal ends up silently treated as a regex.
  `RISK_DOMAIN_PATTERNS` & `KNOWN_TELEMETRY_DOMAINS` became `RISK_DOMAIN_LITERALS` &
  `KNOWN_TELEMETRY_LITERALS`.
- `SCRIPT_DIR` resolves symlinks. A comment had claimed for months that it "survives
  being called through a symlink" & it did not: it resolved the symlink's own
  directory, so the tool invoked through `~/.local/bin` looked for the agent jars
  beside the link, found none, & ran with no capture. That had to be true before the
  `--install-man` symlink could be honest, so the code was fixed rather than the
  feature dropped.
- `docs/cli-surface.md` refreshed against this release: line references re-verified,
  the exit-code table replaced, the logging table corrected, & the two new options
  added. `VERSION` 2.24 to 2.25.

## v2.24 — 2026-09-17

Six findings from an external code review, fixed, plus one ROADMAP Phase 5 item that
the second of them turned from latent into load-bearing. Plus the first CLI surface
inventory, as input for the man page standard.

### Fixed
- The instance that LOST the lock race deleted the lockfile of the instance that held
  it. `cleanup()` ended with `rm -f "$LOCKFILE"` & `die()` calls `cleanup()`, so a
  second launch freed the path while the holder kept its lock on the now-unlinked
  inode; a third launch then created a fresh inode, locked it without contest & ran in
  parallel. Mutual exclusion was gone in exactly the case it exists for, & it fired
  every time someone launched twice by accident. The lockfile is no longer deleted:
  `flock(2)` lives on the open file description, not on the path, so unlinking never
  released anything anyway. It is zero bytes & sits under `XDG_RUNTIME_DIR`, which the
  system clears at logout. `tests/lock-exclusion.sh` is the regression net, 5/5,
  & it goes red against the old behaviour.
- `-K/--kill-orphans` killed the monitors of a LIVE session. `find_orphan_pids` matches
  any process tagged `tlauncher-mon-`, excluding only our own ancestor chain, & `-K` is
  a standalone mode that never consulted the lock. Run from a second terminal during a
  session it reaped that session's monitors while announcing them as strays "from a
  previous session", leaving the audit target running with no instrumentation & no
  warning. `-K` now takes the lock first: if a live session holds it, it refuses, names
  the holding PID & exits 2.
- `cleanup()` ran twice on the `die()` path, which calls it & then exits into the EXIT
  trap. Every step happened to be idempotent, so nothing broke; a `CLEANUP_DONE` guard
  makes it once so the first non-idempotent step added later doesn't become a bug.
- `$(ls -A)` split session filenames on whitespace during log compression. A name with
  a space became several nonexistent entries: `tar` archived the rest, `--remove-files`
  deleted those, the odd file was left unarchived, & `|| true` swallowed the error. Now
  a `nullglob`/`dotglob` glob, & a failed `tar` is reported instead of silently
  discarding the logs it was meant to preserve.
- The lockfile descriptor leaked into every child. `exec 200>"$LOCKFILE"` runs before
  the monitors & firejail are spawned, & nothing closed fd 200 in them; `flock(2)` lives
  on the open file description, which fork/exec inherits, so any monitor that outlived
  the parent went on co-holding the session lock. Recorded as a latent gap in v2.23, it
  stopped being latent the moment `-K` began consulting that lock: an orphan holding
  fd 200 would have made `-K` refuse to reap the very orphan holding it. Verified here:
  without `200>&-` the lock stays held after the parent exits; with it, the lock frees.
  Closes the second of the three ROADMAP Phase 5 items.
- The risk-domain literals are escaped before being joined into an ERE. The array holds
  substrings but is fed to `grep -E`; today's two entries carry no metacharacters, so it
  worked by luck. Adding the `tlauncher.ru` family, which AGENTS.md leaves open as the
  author's call, would have made `res.tlauncher.ru` match `resXtlauncherYru`. A false
  positive costs trust in the whole report, so the escaping happens in the code.

### Changed
- `BLOCKED_DOMAINS` is now `KNOWN_TELEMETRY_DOMAINS`, & is actually read. Twenty domains
  sat in an array called "blocked" that nothing in the script ever used: no `--dns`, no
  netfilter, no filter of any kind. The name promised a capability the sandbox does not
  have, which is the state-honesty rule's own failure mode. The list now drives a report
  line marking those hosts as contacted, labelled "observed, NOT blocked".
- `trap cleanup EXIT INT TERM` names HUP & QUIT too. Measured on bash 5.2.21 here, the
  EXIT trap still ran for an untrapped HUP or QUIT, so the orphaning this was predicted
  to cause did not reproduce; that behaviour is bash's own & version dependent, so the
  two signals are named rather than left to luck.
- `VERSION` jumped 2.21 to 2.24 to match this section, closing the desfase the two
  doc-only sections (v2.22, v2.23) opened by design.

### Added
- `docs/cli-surface.md`: an inventory of what the command line actually exposes, each
  claim carrying `file:line`. Flags & the globals they set, environment variables read,
  exit codes & where they are emitted, the logging & colour rules, the `--help` section
  order, its five examples & the real cases with none, & the report states the test
  suite covers against those it does not. It records the surface as it is, as input for
  the man page standard; it proposes no standard.

## v2.23 — 2026-07-30

Documentation only. No `run.sh`, `scripts/`, or `VERSION` change.

### Added
- ROADMAP Phase 5, "cleanup survives every death it can see": the phase that fixes the
  three defects below. It is independent of Phases 3 & 4, stated there explicitly so the
  Ordering principle isn't read as putting it behind them; the number records arrival
  order, not a dependency. Its acceptance is stub-driven & needs no TLauncher: a stub
  session killed with SIGHUP leaves no `tlauncher-mon-` process, `flock -n` succeeds
  from a second shell while a stub monitor is held alive, & `bash -n run.sh` stays clean.
- AGENTS.md Known gaps: the trap does not cover every fatal signal. `run.sh:1596` traps
  EXIT, INT & TERM, so an untrapped HUP or QUIT kills the shell without running
  `cleanup()` & orphans every monitor, `inotifywait` included, which is the 51 MB
  `files.log` failure this changelog already records.
- AGENTS.md Known gaps: the lockfile descriptor is inherited by children. `run.sh:810`
  opens fd 200 before the monitors & firejail spawn & never closes it in them, & a
  `flock(2)` lock lives on the open file description, so a surviving child co-holds it &
  the next run reports a false "TLauncher already running".
- AGENTS.md Known gaps: `first_seen_loop` (`run.sh:547`) leaks one `/tmp` file per
  monitor per session when a signal lands between the `mktemp` & the `rm` that closes
  the cycle. Cosmetic, clears on reboot.

All three are latent, not active: every session so far has ended through a trapped exit,
& the author's machine shows zero orphan monitors, zero retained inotify watches & a free
lockfile. They are recorded here, not fixed; the fix is a code PR under Phase 5. Until it
lands, the "orphan-proof cleanup" header comment in `run.sh` holds only for a death the
script can trap.

## v2.22 — 2026-07-23

Documentation only. No `run.sh`, `scripts/`, or `VERSION` change.

### Added
- `DESIGN.md` principle 9, "One program, one file". `run.sh` is one file on purpose &
  none of the eight existing principles said why, so a "should this be `lib/*.sh`?"
  question had nothing written to answer with. The reasons, each checked against the
  repo: an audit tool is read end to end, so chasing `source` across files costs the
  reader more than it saves; bash has no namespaces, so the per-area prefixes (`log_`,
  `deps_`, `kill_`) already do the isolation splitting would claim to; a `lib/` layout
  adds a missing-library-at-launch failure mode the single file doesn't have; & the
  tool is copy-and-run, not installed. Stated as a property, not a line count: the
  condition that would move a piece out is that it becomes its own separately-audited
  program, the way `scripts/` (the Java agent, `build-agent.sh`) already is. Nothing in
  the launcher's own logic currently is.

## v2.21 — 2026-07-23

ROADMAP Phase 2 closed: cut what can't work. The mitmproxy fallback is gone.

### Removed
- The mitmproxy fallback for `-P`. It set the JVM proxy props & ran an on-host
  `mitmdump`, but TLauncher's traffic goes through Apache HttpClient (4.x & 5.x), which
  ignores those props, so it captured nothing of the audit target & never ran end to end.
  Removed: `monitor_mitmproxy`, the `HTTP(S)_PROXY` env injection, the `-Dhttp.proxyHost`
  fallback java opts, `MITM_ALLOWLIST`, the report's mitmproxy branch, `_report_mitm_flow`,
  the `mitmdump` dependency entry, & `scripts/mitm_report.py`. `-P` is agent-only; the
  preflight disables it when the agent isn't built. The decision (remove vs degrade to a
  label) went to removal & is dated in AGENTS.md Known gaps.
- The `[PORT]` argument on `-P/--proxy`. It only ever set the mitmproxy listen port; the
  agent uses no port, so a documented argument that did nothing is gone. `-P/--proxy` is
  now a plain flag.

### Changed
- `capture-mode` records only `agent` or `off`. The report's network-capture section
  drops to three live states (agent with data, agent empty, off) plus a legacy branch: a
  session that recorded the removed `mitmproxy` mode renders as on-disk facts, promising
  nothing. `usage()`, the config summary (`Capture: Java agent` / `Off`), `--check-deps`,
  & the header comments no longer mention mitmproxy. `DESIGN.md` & the AGENTS.md repo map
  drop their `mitm_report.py` references. `VERSION` jumped 2.16 to 2.21 to match this
  section, closing the doc-only desfase carried since v2.17.
- `tests/report-states.sh`: the `proxy-fallback` fixture became `legacy-mitm`, asserting a
  removed-mode session promises no capture. Still green, now 5/5.

## v2.20 — 2026-07-23

Documentation only. No `run.sh`, `scripts/`, or `VERSION` change.

### Removed
- The sibling-repository list & the "anchored, not deleted" policy from `CLAUDE.md`
  (added in `v2.19`). Naming other repos there implied a dependency this repo does not
  have, & the same pattern in a sibling repo produced a stale claim that had to be fixed.

### Changed
- `CLAUDE.md` now says the opposite in one bullet: this repo does not describe other
  repos. Another repo's name may appear as historical provenance, where a convention came
  from, never as operational information; no document here depends on another repo to be
  understood or worked on. `ROADMAP.md` & `AGENTS.md` are left alone: their one-clause
  mentions of MIDI-Scale-Trainer are provenance & an analogy inside a task that is
  entirely this repo's own, they say nothing about that repo's structure, & they don't go
  stale. CHANGELOG history is left alone.

## v2.19 — 2026-07-23

Documentation only. No `run.sh`, `scripts/`, or `VERSION` change.

### Changed
- `CLAUDE.md` writes down the sibling-repository anchoring policy the repo already
  follows. A reference to a sibling is anchored, not deleted: identified inline on first
  mention in each file (which is why `ROADMAP.md` & `AGENTS.md` name MIDI-Scale-Trainer
  where they first cite it, PR #18), left bare on later mentions in the same file, & left
  as-is in CHANGELOG history. The bullet names the siblings so a reader who cloned only
  this repo can place them: MIDI-Scale-Trainer, TdeA-Mimos-Website, TdeA-Mimos-API-REST.
  The two TdeA-Mimos repos already carried the written rule; this closes the split across
  the four projects that all follow it.

## v2.18 — 2026-07-23

Documentation only. No `run.sh`, `scripts/`, or `VERSION` change.

### Changed
- `CLAUDE.md` writes down the doc-only CHANGELOG rule the repo already follows: a doc-only
  PR opens its own dated section, never folded into an already-published version's section,
  & may leave the latest CHANGELOG version ahead of the printed version until the next code
  PR closes the desfase. The rule was practice (see `v2.10`, `v2.17`); now it's on paper.
  History is not renormalized.

## v2.17 — 2026-07-23

Documentation only. No `run.sh`, `scripts/`, or `VERSION` change.

### Changed
- `ROADMAP.md` & `AGENTS.md` now identify the MIDI-Scale-Trainer repo on its first
  mention in each file: the author's other project, a separate repository whose
  documentation standard this one shares. Both cited it as the blueprint for the phase
  discipline without saying what it was, so a reader who cloned only this repo had no way
  to place it. Later mentions in the same file (ROADMAP's fixtures line, the
  reconciliation note in v2.8 below) stay as they are, & the qualifier that this repo
  copies the phase habit, not the folder layout, is unchanged.

## v2.16 — 2026-07-22

ROADMAP Phase 1 closed. The agent sees.

### Fixed
- The aggregated `agent-diag.log` & `http-intercept.log` no longer mix in an earlier
  session's requests. firejail `--private` reuses the sandbox dir across runs, so the
  agent's per-PID logs (`http-intercept-<pid>.log`, `agent-diag-<pid>.log`) survive
  there, & the start-order aggregate globs by PID, so a stale block (a `01:30` line in
  an afternoon run) leaked into the report. `run.sh` now clears those per-PID logs at
  the start of every agent-active run (`reset_agent_tmp`), so a report only ever
  describes its own session.

### Added
- A cross-contamination guard in `tests/report-states.sh`. The four state checks render
  through `-R` from an already-aggregated log, so they never exercised the live
  aggregation that reads the reused sandbox tmp. The new fifth check drives the real
  `reset_agent_tmp` + `aggregate_agent_logs` on a tmp seeded with a stale previous-session
  file & a fresh one, & fails if the stale line survives or the fresh one is missing.
  5/5 checks pass. Remove the reset & it goes red.

### Changed
- ROADMAP Phase 1 is `closed (2026-07-22)`. The session `20260722_113644` (`-v -M -a -P`)
  captured the GET to `starterUpdateV1.json` in the report's table, with `agent-diag.log`
  showing `HOOKED` in all three JVMs across both HttpClient families. This is the first
  entry in this changelog to record a real capture, not a build-verified path. `VERSION`
  bumped 2.15 to 2.16.

## v2.15 — 2026-07-22

ROADMAP Phase 1, fourth pass: one Byte Buddy, not two. The v2.14 access fix bound, then
a `LinkageError` fired before instrumentation. Phase 1 stays `in progress`; the capture is
still the author's real session.

### Fixed
- `LinkageError: loader constraint violation ... AgentBuilder$Listener ... 'app' vs
  'bootstrap'`. v2.14 appended the whole fat JAR to the bootstrap search, which put a
  second copy of Byte Buddy on the bootstrap loader. `TLHttpAgent` (app loader) then called
  `.with(new DiagListener())`, but `DiagListener` resolved from bootstrap & implemented the
  bootstrap copy of `AgentBuilder$Listener`, a different `Class` from the app one the call
  expected. The agent is now two jars: `tl-http-bootstrap.jar` holds only the classes the
  inlined `Advice` bodies touch (`AgentLogger`, `HttpTap`, `Reflect`), no Byte Buddy, & is
  the only one appended to the bootstrap loader; `tl-http-agent.jar` keeps `TLHttpAgent`,
  `DiagListener`, `HttpAdvice`, `ServiceAdvice` & Byte Buddy on the app loader. Byte Buddy
  exists once, so the listener binds; the inlined bodies still reach the logger because the
  bootstrap loader is every loader's ancestor. `HttpAdvice`/`ServiceAdvice` don't need to be
  on the bootstrap: Byte Buddy only reads their bytecode at instrumentation time, it never
  loads them into the target. This closes the deferral noted in v2.14.

### Changed
- `scripts/build-agent.sh` produces both jars from one compile. `premain` locates the
  bootstrap jar next to its own & appends that (not itself); `run.sh` copies both into the
  sandbox `bin/`, so they share a directory there. The game-JVM skip still runs before the
  append, and every safety guarantee is unchanged. `VERSION` bumped 2.14 to 2.15.

## v2.14 — 2026-07-22

ROADMAP Phase 1, third pass: make the loaders agree. The v2.13 hook bound, then threw
before it logged. Phase 1 stays `in progress`; the capture is still the author's real
session.

### Fixed
- `IllegalAccessError` across the classloader boundary. v2.13 appended the agent jar to
  the bootstrap search so the inlined `Advice` bodies could reach the helpers, but
  `premain` runs in the app loader, and a class in one loader cannot touch a
  package-private member of the same-named class in another loader (they are different
  runtime packages). The real session threw `AgentLogger is in unnamed module of loader
  'bootstrap'; TLHttpAgent is in unnamed module of loader 'app'` & logged nothing. The
  helpers, & the members crossed at that boundary (`AgentLogger.init`/`diag`/`close`/
  `logBlock`, `HttpTap.clientCall`/`serviceCall`), are now public. Each helper is its own
  top-level class in its own file, so there is no nest host to resolve twice across the
  two loaders; `scripts/build-agent.sh` compiles the directory instead of one file.
- The game-JVM self-disable now runs BEFORE the bootstrap append, not after. On the Forge
  JVM the old order put Byte Buddy & its ASM on the bootstrap classpath, ahead of Forge's
  own ASM, before the agent bowed out. `premain` now reads `sun.java.command` first &, on
  a game JVM, returns without appending or loading any helper. The "skipped" diag line is
  written with a direct file append instead of `AgentLogger`, since the helper is
  deliberately not bootstrap-visible on that path.

### Changed
- `VERSION` bumped 2.13 to 2.14 to match this section.

## v2.13 — 2026-07-22

ROADMAP Phase 1, second half: make the hook bind. The first real session (v2.12) loaded
the agent into every JVM & saw both target classes, but the interception never fired.
Phase 1 stays `in progress`; the capture is the author's real-session call.

### Fixed
- The interceptors moved from `MethodDelegation` to `Advice`. In the v2.12 session the
  diagnostic log carried an `IllegalArgumentException` for both targets: none of the
  interceptor signatures could bind, because `@SuperCall` has no super method to hand
  back once the target is rewritten in place under `RETRANSFORMATION`, and its failure
  drags the whole delegation signature down with it. `Advice` injects its body inline
  instead of resolving a delegation by signature, so it binds on inherited & overloaded
  methods too. This is the case Byte Buddy's own docs point at `Advice` for. It is not
  shading: the diagnostic named both classes exactly.

### Changed
- The agent now covers both HttpClient name families, not just 5.x. The diagnostic
  showed the JVMs don't share a stack: the starter (JVMs 1 & 2) loads
  `org.apache.http.impl.client.InternalHttpClient` (HttpClient 4.x) while the launcher
  (JVM 3) loads `org.apache.hc.client5.http.impl.classic.InternalHttpClient` (5.x). The
  earlier analysis read one classpath (JVM 3's) & assumed one library. The hook now
  matches `doExecute`/`execute` on both names & reads the request reflectively across
  the two APIs (`getMethod` or the request line; `getUri`/`getURI`; `getCode` or the
  status line). It also hooks `HttpServiceImpl.getRequestByUrlAndSave(String, Path)`,
  whose URL is argument 0, which is the shortest path to a real capture.
- `run.sh` aggregates the per-PID logs in JVM start order with a `# ---- JVM pid=N ----`
  banner before each block, instead of `cat *.log`. The glob sorted lexically by PID, so
  JVM 1 (a low PID) landed after the game JVMs; now whole files are ordered by their
  first line's timestamp, so a four-line block is never split & the starter reads before
  the launcher. Empty per-PID files (a skipped or silent JVM) are dropped, so an
  all-empty capture still aggregates to an empty file & the report keeps telling
  "active, no requests" from "active, has data". `VERSION` bumped 2.12 to 2.13.

## v2.12 — 2026-07-22

ROADMAP Phase 1, first half: make the agent see. The code path is built & checkable
here; the capture itself waits on a real session (Phase 1 stays `in progress`).

### Changed
- The agent now reaches every JVM, not only the starter. `-P` used to inject
  `-javaagent` into JVM 1 alone through the java command line; JVMs 2 & 3 (the
  re-exec & the embedded JRE, where the real work happens) ran clean. Injection
  moved to `JAVA_TOOL_OPTIONS` in the sandbox env, which every child JVM inherits.
  The paths in it are absolute inside the sandbox (`${REAL_HOME}/bin/tl-http-agent.jar`,
  `${REAL_HOME}/tmp`), because a child JVM starts with a different cwd
  (`/home/ct/.tlauncher/starter/`) & the old relative paths would have missed the
  JAR & disabled the agent in silence.
- `scripts/TLHttpAgent.java` hooks `by.gdev.http.download.impl.HttpServiceImpl`
  besides `InternalHttpClient`. That's TLauncher's own download class, named by hand
  in the logs while it did the GET to `starterUpdateV1.json` the agent missed, so it
  isn't relocated the way a shaded HttpClient5 package can be. Its signature isn't
  `execute`'s, so the interceptor has its own extraction path: it scans the argument
  list for the URL (direct string, or via `getUrl`/`getUri`) & logs the call as a GET.
- The agent self-disables on the Minecraft JVM. `JAVA_TOOL_OPTIONS` would otherwise
  instrument gameplay, drowning the audit in asset & skin traffic. `premain` reads
  `sun.java.command` & returns silently when it names a game process
  (`bootstraplauncher`, `net.minecraft`, `--gameDir`, `--assetIndex`, Forge/FML,
  `crash_assistant`). The audit target is the starter & launcher only.
- The log is now one file per process (`http-intercept-<pid>.log`), because three
  JVMs appending one file would interleave lines & split the four-line request blocks
  the report parser depends on. `run.sh` concatenates them on copy-out into a single
  `http-intercept.log`, so each block stays whole & the Phase 0 fixtures & report
  read the same aggregate as before.
- `-P` without the agent JAR still falls back to mitmproxy; the build hint now names
  the exact command & where to run it (`bash scripts/build-agent.sh` from the repo
  root, the directory holding `run.sh`), since the old message didn't say the cwd
  mattered. `VERSION` bumped 2.11 to 2.12 to match this section.

### Added
- Diagnostic mode in the agent, so "zero captures" is never ambiguous again. A Byte
  Buddy `AgentBuilder.Listener` records every candidate class the agent saw
  (`SAW <type>`), every one it hooked (`HOOKED`), & any transform error (`ERROR`) to
  a per-process `agent-diag-<pid>.log`, aggregated to `agent-diag.log` on copy-out.
  If the HTTP log is empty, the diag log names the actual (possibly shaded) class the
  JVM loaded, which is the evidence the shading hypothesis needs.

## v2.11 — 2026-07-22

ROADMAP Phase 0: the report stops lying.

### Fixed
- The report no longer claims capture was off during an active `-P` session. It used
  to infer the mode from the absence of `mitm.flow`; with the agent active mitmproxy
  is skipped, so no flow exists, & the old code printed "Payload capture was
  **disabled** ... run without `-P/--proxy`" one line after saying the agent was
  active. The capture mode is now a recorded datum (`SESSION_DIR/capture-mode`,
  written by `run_sandboxed`), & one `report_network_capture` section reads it &
  prints exactly one of four states: agent with data, agent empty, mitmproxy
  fallback, or no capture. No section claims anything about an option the user did
  use; missing data says so.
- `usage()` no longer heads its news block "WHAT'S NEW IN v2.5" while VERSION had
  moved on. It points at the CHANGELOG instead, so it can't go stale on a bump. The
  `-P` help stopped promising capture "no matter which HTTP library" now that the
  shaded-class miss is documented.

### Added
- `tests/`: a regression net (`report-states.sh` plus four synthetic session
  fixtures) that drives the real report through `run.sh -R` for each capture state &
  checks the state's phrase is present while the other three are absent. That second
  half is what would have caught the lying report. 4/4 states pass. No network, no
  sudo, no TLauncher.

### Changed
- `VERSION` bumped 2.9 to 2.11 to match this section; the desfase noted 2026-07-22 in
  AGENTS.md Known gaps is closed.

## v2.10 — 2026-07-22

Documentation only. No `run.sh` or `scripts/` change.

### Added
- `ROADMAP.md`, a fourth canonical doc: a phased plan (Phase 0 through 4 plus a
  backlog) with a one-line objective, scope, verifiable acceptance criterion,
  blockers, & status per phase. The ordering principle is that a tool that lies
  about its own state corrupts everything built on top, so the report stops lying
  (Phase 0) before the agent is made to see (Phase 1) before binaries get archived.

### Changed
- `CLAUDE.md` now lists four canonical docs (adds `ROADMAP.md`) & extends the reading
  order: `AGENTS.md`, then `DESIGN.md`, then `ROADMAP.md` for phase work.
- `AGENTS.md` Known gaps records, dated, the shift from loose rounds to phases, the
  real-session finding that the agent captured zero (JVM 1 made HTTP the agent didn't
  see; shading hypothesis), & two verified state-honesty bugs now tracked as Phase 0.

## v2.9 — 2026-07-05

Java agent for HTTP interception.

### Added
- `scripts/TLHttpAgent.java`, a `java.lang.instrument` agent that logs TLauncher's
  outbound HTTP. mitmproxy captured zero because Apache HttpClient5 ignores
  `-Dhttp.proxyHost` & the `HTTP_PROXY` env vars. The agent instruments
  `InternalHttpClient.execute()` in-process, after TLS decrypt, where the payload is
  plain text, & reads every request/response through reflection so it compiles
  against Byte Buddy alone. It never modifies a request or a response, & any
  instrumentation error is swallowed so TLauncher runs unchanged.
- `scripts/build-agent.sh`, which builds the fat JAR `scripts/tl-http-agent.jar`
  with no sudo, Maven, or Gradle: javac plus a Byte Buddy 1.14.18 download pinned by
  SHA256. `tl-http-agent.jar` is a build artifact, gitignored, never committed; only
  the `.java` & the build script live in the repo, so nothing is written to any
  other repository. The build bundles Byte Buddy (Apache-2.0) & adds a NOTICE for it
  to the JAR.
- `-P` now injects the agent into the starter JVM when the JAR is present, & writes
  `http-intercept.log` to the session dir (the agent writes it inside the sandbox;
  run.sh copies it out, since firejail `--private` walls the JVM off from the log dir).
  A "Network payload (Java agent capture)" section in `INCIDENT_REPORT.md` shows a
  per-request table & flags POST/PUT with a body. `--check-deps` now lists `javac` &
  `wget` (optional, for the one-time build).

### Changed
- `-P` without the agent JAR falls back to the previous mitmproxy path, with a clear
  warning that it misses HttpClient5. The proxy preflight keeps `-P` enabled when the
  agent JAR is present even if mitmdump is absent.
- `VERSION` jumped from 2.5 to 2.9 to match this CHANGELOG. `-h` & the CHANGELOG are
  single-source again; the old desfase noted in AGENTS.md Known gaps is closed.

### Fixed
- `CLAUDE.md` broke its own em-dash rule: em dashes sat in plain prose (the title &
  the Known-gaps bullet). Rewrote those to a colon & a comma, & wrapped the
  remaining format-token em dashes in backticks. Every em dash left in the file now
  sits inside backticks.

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
