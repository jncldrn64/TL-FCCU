# Changelog

Every notable change to the launcher (`run.sh` & its helpers). The format follows
[Keep a Changelog](https://keepachangelog.com/): one file that grows by section,
newest on top, headers `## vX.Y — YYYY-MM-DD`.

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
