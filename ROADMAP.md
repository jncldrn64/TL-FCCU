# ROADMAP

## Ordering principle

A tool that lies about its own state corrupts everything built on top of it. The
archive this roadmap ends at exists so that months later you can say which binary
ran on which day. If the layer that reports the run lies, the archive inherits the
lie. So the order is fixed: first the report stops lying, then the agent sees what
runs, then the binaries get archived. Phases don't get reordered for convenience.

Work now moves by numbered phases, not loose rounds. Each phase carries a one-line
objective, the scope it touches, a verifiable acceptance criterion, its blockers,
& a status. The blueprint for this discipline is the MIDI-Scale-Trainer repo; this
copies its phase habit, not its folder layout.

Status values: `pending`, `in progress`, `closed (YYYY-MM-DD)`.

## Phase 0: the report stops lying

Status: `pending`

Objective: the output describes its own state with no false claims, & a regression
net proves it without launching TLauncher.

Scope:
- Fix the false proxy claim. In a `-P` run with the agent active, mitmproxy is
  skipped, so no `mitm.flow` exists, & `report_payload_summary` prints "Payload
  capture was **disabled** ... run without `-P/--proxy`" while the agent section a
  line above says it was active. Four states have to be told apart: agent active
  with data, agent active & empty, agent absent, proxy fallback used.
- Fix `usage()`. The heading reads "WHAT'S NEW IN v2.5" while `VERSION="2.9"`.
  Re-audit every `usage()` line against the real parser, the same pass done in
  Round 2.
- Regression net: synthetic session directories that cover the four states, plus a
  check that the report prints the right state for each. This is the equivalent of
  the MIDI repo's fixtures.

Acceptance: `bash -n run.sh` clean, the four states each verified against a
synthetic session, zero change to sandbox behavior. All of it checkable without
launching TLauncher.

Blocks: everything after it reads this report, so a lying report poisons Phase 1's
own verification.

## Phase 1: the agent sees

Status: `pending`

Objective: capture the HTTP traffic that is lost today.

Scope:
- Set `JAVA_TOOL_OPTIONS` in the sandbox environment so any JVM that starts loads
  the agent, JVM 2 & JVM 3 included, not only the starter.
- Hook `by.gdev.http.download.impl.HttpServiceImpl` in addition to
  `InternalHttpClient`. `HttpServiceImpl` is TLauncher's own class, named by hand in
  the logs while making the requests, so it isn't relocated the way a shaded
  HttpClient5 package would be.
- Diagnostic mode: log which candidate classes the agent actually saw, so "zero
  captures" is never ambiguous again.
- Make `run.sh` build the agent, or say precisely that a manual step is needed. The
  current message doesn't carry enough. Audit the man page in the same pass.

Acceptance: one real session captures the GET to `starterUpdateV1.json`. If it
doesn't, diagnostic mode states why.

Blocks: Phase 2.

## Phase 2: cut what can't work

Status: `pending`

Objective: take the dead ends out of the way so they stop confusing the reader.

Scope:
- The mitmproxy fallback is confirmed to miss HttpClient5. Decide between removing
  it & degrading it to a label with no ambiguity, & record the decision in
  AGENTS.md Known gaps.
- Sweep the other options against the same bar: does each do what it says.

Acceptance: no documented option promises something it doesn't do.

Blocked by: Phase 1. The fallback doesn't get pulled before the main path works.

## Phase 3: binary archive

Status: `pending`

Objective: assert, months later, which binary ran & when.

Scope:
- Save each `starter-core` & each `TLauncher.jar` seen, with its SHA256, ISO date,
  size, & source URL.
- A stable path outside the sandbox, because the sandbox gets overwritten every run.
- An append-only manifest, one line per artifact, deduplicated by hash: a binary
  already archived gets a re-sighting line, not a second copy.
- An automatic mode & a manual mode, with a default that makes sense & is justified.
- A retention policy: how much is kept, & what happens at the cap.

Acceptance: two sessions in a row produce one copy of the same binary & two
sighting entries in the manifest.

Blocks: Phase 4.

## Phase 4: promotion & binary selection

Status: `pending`

Objective: end the manual moving of jars.

Scope:
- Detect that the sandbox jar differs from the home jar, show both hashes, & ask
  before promoting. Never promote without asking.
- At the prompt, warn that promoting can change startup behavior: one version
  hardens the connection checks relative to the one before it.
- Launch a prior version from the archive. `-f` already selects a jar; evaluate
  extending it before adding a new option.
- Cut the per-session re-update. `run.sh` copies the home jar into the sandbox
  every run, so `UpdateCore` re-applies the cached `starter-core` on every start.

Acceptance: a session with no changes doesn't re-download or re-copy the same
binary.

Blocked by: Phase 3.

## Backlog

Archive rotation, hash comparison against public sources, & whatever else surfaces.
No date commitment.
