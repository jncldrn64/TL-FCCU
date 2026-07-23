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
- Read `DESIGN.md` before you write any code.

## Map of the repo

- `run.sh`: the whole launcher, one bash script.
- `scripts/mitm_report.py`: turns a `-P` mitmproxy capture into Markdown.
- `DESIGN.md`: the conventions, read before coding.
- `CHANGELOG.md`: what changed & when.
- `ROADMAP.md`: the phased plan, read when the work belongs to a phase.

## Known gaps / not verified against real data

Be honest about these. Don't report any of them as working without a fresh run in
a real environment.

`-P/--proxy` has never run end to end. The proxy capture & `scripts/mitm_report.py`
passed static review & a test against a mock `mitmproxy` module, not a full
TLauncher session through a real `mitmdump` with real request bodies. Treat the
payload summary as unproven until someone runs it & reads the bodies.

Agent-side testing used stubs. The dev environment has no `firejail`, `inotifywait`,
or `ss`, so end-to-end runs were driven by fake binaries. Real-environment
confirmation is the user's job; don't claim it happened when it didn't.

`RISK_DOMAIN_PATTERNS` holds two substrings, `advancedrepository` & `securelogger`.
It doesn't cover the `tlauncher.ru` family (`res.tlauncher.ru`, `mps.tlauncher.ru`,
`stat.tlauncher.ru`). Those sit in `BLOCKED_DOMAINS` as historical reference, but
whether they deserve a hard risk flag is the author's call. Don't add them without
his confirmation.

The IP baseline flags the local sandbox address. A `10.x` source IP shows up as
"not in baseline" until the user populates the baseline from a clean run that
already includes it. That's by design, & worth knowing before reading a first
report.

The network monitor's PID-tree filter (Round 4) hasn't run against real firejail.
`monitor_network` now keeps only connections owned by the firejail sandbox tree,
matched by the `mcbox` hostname & filtered on the `pid=` field of `ss -tnp`. The
regex filter & the `pid=123` vs `pid=1234` boundary were validated with synthetic
`ss` output, not a live sandbox. Two things need a real run: that `ss -tnp` shows
a `pid=` for firejail's same-user children, & that `pgrep -f "firejail.*mcbox"`
reaches the whole tree across firejail's PID namespace. Verify with a browser open
during a session; no Google or Cloudflare IP unrelated to TLauncher should land in
`network.log`.

The deps state file records first-seen state & never overwrites. If a package was
`absent` when first checked & later gets installed, `--check-deps` shows the live
status as `present` but the registry line still reads `absent`. Delete
`tlauncher-sandbox-deps.ini` to re-inventory.

2026-07-05: closed the VERSION desfase. run.sh printed `VERSION="2.5"` while the
CHANGELOG had moved on; Round 5 is a code round, so it jumped straight to
`VERSION="2.9"`, the current CHANGELOG version. `-h` & the CHANGELOG are single-source
again (see CLAUDE.md "Displayed version").

The Java agent (Round 5) instruments the STARTER JVM only. The Minecraft JRE the
starter spawns is a separate process & is not instrumented. That's on purpose: the
telemetry (`securelogger.net`, `advancedrepository.net`, `AdvertisingStatusObserver`
POSTs, the domain checks) all come from the starter, which is the audit target.
Minecraft gameplay traffic is out of scope.

The agent matches `InternalHttpClient.execute()`. If `http-intercept.log` exists but
is empty after a `-P` session, TLauncher may route through `doExecute()` or a
HttpClient5 subclass the type filter doesn't match, so nothing fires. Check with
`grep -c . http-intercept.log`, or look at `java-processes.log` for the actual
client class. Broadening the matcher to `doExecute` is the likely follow-up.

`tl-http-agent.jar` is a build artifact, gitignored, never committed; only
`scripts/TLHttpAgent.java` & `scripts/build-agent.sh` live in the repo. Build it
once with `bash scripts/build-agent.sh`. The build pins Byte Buddy 1.14.18 by
SHA256 `52117af1696a53aa77c131353074ada25ccbdf2df511f2af33fad6704fa95104` (verified
against Maven Central's published SHA1 `0081e9b9...901c2485`; the Round 5 spec's
SHA256 was wrong). The fat JAR bundles Byte Buddy 1.14.18 (Apache-2.0); the build
adds a NOTICE for it, so the attribution rides along if the JAR is ever shared.

The agent build & JAR structure are verified (it compiles, the fat JAR carries the
right MANIFEST & classes), but the capture itself is NOT: no real TLauncher ran here.
Whether the agent actually logs a `securelogger.net` POST needs a live run. Verify
with `-v -M -a -P` against real TLauncher & read `http-intercept.log`.

2026-07-22: the project moved from loose rounds to numbered phases. Until now each
feature landed as its own round with no plan tying them together; from here the work
runs by phases with a written acceptance criterion each, tracked in `ROADMAP.md`. The
blueprint is the MIDI-Scale-Trainer repo, the author's other project & a separate
repository whose documentation standard this one shares, copied for its phase
discipline, not its folder structure.

2026-07-22: the agent ran against real TLauncher (session_20260721_234406, `-v -M -a
-m -P`, agent compiled) & captured zero. This supersedes the earlier "no real run"
note above: it ran, & it missed. TLauncher starts three JVMs & only the first (the
`run.sh` starter) carries `-javaagent`. That first JVM did make HTTP: `HttpServiceImpl`
did a GET to `starterUpdateV1.json` at 23:44:12.694, & the agent logged nothing.
Hypothesis to confirm: the starter jar ships HttpClient5 with the package relocated
(shaded), so the exact name `org.apache.hc.client5.http.impl.classic.InternalHttpClient`
doesn't exist in JVM 1; the `httpclient5-*.jar` on the classpath belong to JVM 3, the
embedded JRE, not JVM 1. Widening to `HttpServiceImpl` & setting `JAVA_TOOL_OPTIONS`
is ROADMAP Phase 1.

2026-07-22: two state-honesty bugs in the current report output, both tracked as
ROADMAP Phase 0, both verified against the code. `report_payload_summary` prints
"Payload capture was **disabled** ... run without `-P/--proxy`" whenever there's no
`mitm.flow`, which is exactly the agent path (mitmproxy skipped), so the report
contradicts its own agent section. And `usage()` still heads its news block
"WHAT'S NEW IN v2.5" while `VERSION="2.9"`. What did work in that session was the
regression check, which flagged `advancedrepository.net`, `securelogger.net`,
`securelogger.top`, `ruzone.securelogger.top`, & `repo.tl.vg` as a new domain; that
comes from parsing `tlauncher.log`, not from the agent.

2026-07-22: closed. Phase 0 is a code PR, so it bumped `VERSION` to 2.11 to match the
new CHANGELOG section; `-h` & the CHANGELOG are single-source again. The `usage()`
audit found every documented flag present in the parser & no behavior mismatch; the
stale "WHAT'S NEW IN v2.5" heading is gone, & the `-P` help no longer overpromises
("no matter which HTTP library") now that the shaded-class miss is known.

2026-07-22: ROADMAP Phase 1 (v2.12) built, capture still unverified. The agent now
loads into every JVM through `JAVA_TOOL_OPTIONS` & hooks `HttpServiceImpl`, so on
paper it should catch the GET to `starterUpdateV1.json` that JVM 1 made & the old
starter-only injection missed. That's the theory; no real TLauncher ran here. Phase 1
stays `in progress` until a live `-v -M -a -P` session shows the GET in the report, or
`agent-diag.log` names the class it saw instead. Don't record the capture as working
before that run. The four traps this phase had to resolve, & the call made on each:

- 2.1 Relative paths break in child JVMs. `JAVA_TOOL_OPTIONS` is inherited by JVMs
  that start in a different cwd (`/home/ct/.tlauncher/starter/`), so the old
  `bin/...`, `tmp/...` relative paths would find nothing there. Decision: absolute
  paths inside the sandbox. firejail `--private` mounts the sandbox at the real home,
  so the in-sandbox absolute paths are `${REAL_HOME}/bin/tl-http-agent.jar` &
  `${REAL_HOME}/tmp`.
- 2.2 Three JVMs writing one log interleave. Appending one `http-intercept.log` from
  three processes splits the four-line request blocks the parser needs. Decision: one
  log per process, `http-intercept-<pid>.log`, concatenated by `run.sh` on copy-out
  into the single `http-intercept.log` the report & the Phase 0 fixtures already read.
  A block is written by one process, so it stays whole; the fixtures didn't change,
  since they mirror the post-aggregation file.
- 2.3 The game JVM would also load the agent. `JAVA_TOOL_OPTIONS` reaches Minecraft
  too, which would instrument gameplay. Decision: the agent self-disables. `premain`
  reads `sun.java.command` & returns silently when it names a game process
  (`bootstraplauncher`, `net.minecraft`, `--gameDir`, `--assetIndex`, Forge/FML,
  `crash_assistant`). This is a heuristic on the command line, not a guarantee; if a
  future TLauncher launches the game by some other signature it would slip through, &
  the fix is to widen the list. Audit target stays the starter & launcher.
- 2.4 `JAVA_TOOL_OPTIONS` prints `Picked up JAVA_TOOL_OPTIONS: ...` to stderr from
  every JVM. Decision: accept it, don't filter. Filtering means parsing & rewriting
  the child stderr stream, which risks dropping a real line; the noise is harmless &
  its presence is a cheap confirmation that the env var reached the JVM. It stays in
  the session logs as-is.

2026-07-22: Phase 1 second half (v2.13). The first real session (v2.12) proved the
injection worked & the hook did not: the agent loaded into all three JVMs & the
diagnostic logged `SAW` for both target classes, then an `IllegalArgumentException`
binding failure for each, eight milliseconds before the GET to `starterUpdateV1.json`
went out unlogged. Two findings changed the work:

- `MethodDelegation` can't bind under `RedefinitionStrategy.RETRANSFORMATION`, because
  `@SuperCall` has no super method to call once the target is rewritten in place, and
  its failure invalidates the whole delegation signature. Fixed by moving both hooks to
  `Advice` (inline bytecode, no signature delegation). Not shading: both classes showed
  their exact names.
- The JVMs run two different HttpClient libraries. The starter (JVMs 1 & 2) loads
  `org.apache.http.impl.client.InternalHttpClient` (HttpClient 4.x); the launcher (JVM 3)
  loads `org.apache.hc.client5.http.impl.classic.InternalHttpClient` (5.x). The v2.12
  agent knew only the 5.x name, so JVMs 1 & 2 were never even attempted. Both name
  families are matched now, & the request is read reflectively across both APIs.

The two `Advice` traps from the spec (section 5) & the calls made:

- 5.1 Class visibility from inlined `Advice`. An `Advice` body is copied into the target
  class, so any class it names must be visible to that class's loader; TLauncher loads
  the targets from its own jars, through loaders that need not be children of the
  agent's, so a naive reference to `AgentLogger` would throw `NoClassDefFoundError` at
  runtime inside TLauncher. Decision: `appendToBootstrapClassLoaderSearch(own jar)` in
  `premain`, before the first reference to any helper, so parent-first delegation defines
  the helpers once in the bootstrap loader (the ancestor of every loader) & `premain` &
  the inlined bodies see the same class. NOT verified against real TLauncher: this fault
  only appears at runtime, & no launcher ran here. The reasoning is sound (bootstrap is
  every loader's ancestor; ordering the append before the first helper use keeps a single
  class identity), but the proof is the author's session. If a `NoClassDefFoundError`
  appears in the launch output, the append is the first suspect.
- 5.2 `Advice` exceptions propagate into the target. Unlike the `try/catch (Throwable)`
  that wrapped `MethodDelegation`, a throw inside an `Advice` body rises into TLauncher's
  own code. Decision, non-negotiable: every `Advice` method carries
  `suppress = Throwable.class`, so an interception fault is swallowed & TLauncher runs
  unchanged. The read-only guarantees also hold: only repeatable bodies are read (no
  streams, no buffering wrap that would modify the request), and the return value is
  read but never altered.

The agent-log aggregation format changed: `run.sh` now orders per-PID files by start
time with a `# ---- JVM pid=N ----` banner per block, & drops empty per-PID files so an
all-empty capture stays empty. The report parser ignores any line that isn't a request or
`STATUS`/`BODY` line, so banners pass through; the `agent-data` fixture carries banners to
keep the regression net honest to the real shape.

2026-07-22: Phase 1 third pass (v2.14). The v2.13 hook bound but threw before logging:
`IllegalAccessError: AgentLogger is in unnamed module of loader 'bootstrap'; TLHttpAgent
is in unnamed module of loader 'app'`. Cause: the helpers were package-private, & the
bootstrap append (5.1) put them in the bootstrap loader while `premain` stayed in the app
loader, so the same-named classes are different runtime packages & package-private access
across them is denied. Fix: the helper classes & every member crossed at that boundary
are public, & each helper is its own top-level file (no nested nest host to resolve twice
across two loaders). Also reordered `premain` so the game-JVM self-disable runs before the
bootstrap append, so the Forge JVM never gets Byte Buddy & its ASM on its bootstrap
classpath ahead of Forge's own; the "skipped" line is written with a direct file append,
not the helper. `bash scripts/build-agent.sh` compiles the whole `scripts/*.java` set now.
Still NOT verified against real TLauncher: whether the public helpers actually log a
request. The author's `-v -M -a -P` session is the proof; nothing here is captured until
it runs.

2026-07-22: open item, not fixed, deliberately deferred. Appending the entire fat JAR to
the bootstrap classpath (the 5.1 fix) drags Byte Buddy & its ASM onto the bootstrap loader
too, and puts the JVM's Class-Data Sharing (CDS) archive out of use for the run, since the
bootstrap classpath no longer matches the one CDS was dumped against. It works, but it is
heavier than it needs to be. The clean alternative is a small separate bootstrap JAR
carrying only the logger (and whatever the `Advice` bodies call), appended in place of the
fat JAR, leaving Byte Buddy on the agent's own loader. Not done in v2.14 to keep the change
to the access fix; noted here so the next agent-side pass can pick it up.

2026-07-22: Phase 1 fourth pass (v2.15) closes the deferred bootstrap-JAR item above. The
v2.14 access fix bound, then a `LinkageError: loader constraint violation ...
AgentBuilder$Listener ... 'app' vs 'bootstrap'` fired: appending the whole fat JAR to the
bootstrap search duplicated Byte Buddy on both loaders, so `.with(new DiagListener())`
matched two different `AgentBuilder$Listener` classes. Now split into two jars, as the
v2.14 note said would be the clean fix: `tl-http-bootstrap.jar` (only `AgentLogger`,
`HttpTap`, `Reflect`; no Byte Buddy) is the only one appended to the bootstrap loader, &
`tl-http-agent.jar` (`TLHttpAgent`, `DiagListener`, `HttpAdvice`, `ServiceAdvice` + Byte
Buddy) stays on the app loader. Byte Buddy exists once, so the listener binds; the inlined
`Advice` bodies still reach the logger because bootstrap is every loader's ancestor.
`build-agent.sh` builds both from one compile; `run.sh` copies both into the sandbox; and
this supersedes the "only `TLHttpAgent.java` & `build-agent.sh` live in the repo" line
above, since the agent is now several `.java` files (one public top-level class each) plus
`build-agent.sh`. CDS is no longer knocked out by a fat bootstrap classpath, since only the
small logger jar lands there. Still NOT verified against real TLauncher: whether the split
agent logs a request. The author's `-v -M -a -P` session is the proof.

2026-07-22: the agent captured, for real. Session `20260722_113644` (`-v -M -a -P`, the
split v2.15 agent) logged the GET to `starterUpdateV1.json` in the report's table, &
`agent-diag.log` showed `HOOKED` in all three JVMs across both HttpClient families. This
supersedes every "capture NOT verified / needs a live run" note above (the JAR-structure
note & the earlier Phase 1 passes): the capture is now confirmed, not just the build.
ROADMAP Phase 1 is closed. What remains unproven is narrower & lives in later phases: the
POST bodies (`securelogger.net`) weren't exercised in that session, only the starter GET,
so request-body capture for a non-repeatable POST is still unseen in the wild.

2026-07-22 (v2.16): fixed a cross-run contamination bug found in that same session. The
aggregated `agent-diag.log` carried `01:30` lines, from an earlier run: firejail
`--private` reuses the sandbox dir, so the agent's per-PID logs survive there & the
PID-globbing aggregate mixed old sessions into the report. `run.sh` now clears the per-PID
logs at the start of every agent-active run (`reset_agent_tmp`). A fifth check in
`tests/report-states.sh` guards it: it drives the real reset + aggregate on a tmp seeded
with a stale file & a fresh one, & fails if the stale line survives. Runner is at 5/5.

Find another open item while reading `DESIGN.md` or `CHANGELOG.md` that isn't
closed with verified evidence? Add it here instead of quietly fixing it or
re-scoping it. A new documentation idea goes here too, as a note for the author.
Don't add a fourth doc file on your own.
