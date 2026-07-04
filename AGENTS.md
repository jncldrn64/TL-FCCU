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

2026-07-04: `run.sh` still reads `VERSION="2.5"` while CHANGELOG.md assigns v2.6
(Round 3) & v2.7 (Round 4). The bump changes `-h` output, so it's out of scope for
a doc-only pass; fold it into the next code round.

Find another open item while reading `DESIGN.md` or `CHANGELOG.md` that isn't
closed with verified evidence? Add it here instead of quietly fixing it or
re-scoping it. A new documentation idea goes here too, as a note for the author.
Don't add a fourth doc file on your own.
