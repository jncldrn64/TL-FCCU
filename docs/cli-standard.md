# Command-line documentation standard

Normative. This says what `run.sh` **must** satisfy, not what it happens to do
today. `docs/cli-surface.md` is the descriptive counterpart: it records the surface
as it is, and it is the input this standard was written from.

Where the two disagree, this document wins and the code is wrong.
`tests/doc-sync.sh` enforces the parts that can be checked mechanically.

## 1. Canonical command name

The tool is invoked as `./run.sh` from a checkout. That name means nothing outside
the repository, so it cannot be the name in a manual page.

**Canonical name: `tlauncher-fccu`.** It appears in `NAME`, in `SYNOPSIS`, and as
the manual file name `tlauncher-fccu.1`. It is the name a user types once the tool
is on their `PATH`, and the name `man` is asked for.

`run.sh` stays the file name in the repository. Renaming the file would break every
existing invocation, every doc reference, and the `-h` examples, and would buy
nothing the canonical name does not already buy.

### The `~/.local/bin` symlink

`--install-man` also installs a symlink at `${XDG_DATA_HOME}/../bin/tlauncher-fccu`
when that directory exists and is on `PATH`, pointing at the checkout's `run.sh`.

This was not safe before this standard existed, and the reason is worth recording.
`SCRIPT_DIR` is derived with

```sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
```

which resolves the **symlink's own directory**, not the target's, despite a comment
above it claiming it "survives being called through a symlink". Invoked through
`~/.local/bin/tlauncher-fccu`, `SCRIPT_DIR` became `~/.local/bin`, so `-P` looked
for the agent jars in `~/.local/bin/scripts/` and found nothing, silently falling
back to no capture.

So the standard requires: **`SCRIPT_DIR` must resolve symlinks to the real script
directory.** With that, the symlink is safe and the tool behaves identically
however it is invoked. A rule that the code cannot support is not a rule, so the
code was fixed rather than the rule dropped.

The symlink is never installed outside `$HOME`, never with root, and never when the
target directory is absent or off `PATH`; in those cases `--install-man` says so and
installs only the manual page.

## 2. Where the manual page lives

Roff **embedded in `run.sh`**. There is no `.1` file in the repository; the script
is the single copy.

- `--print-man` writes the roff to **stdout** and exits 0.
- `--install-man` writes it to `${XDG_DATA_HOME}/man/man1/tlauncher-fccu.1`,
  creating the directory as needed, **without root**, and prints the `MANPATH` hint
  when that root is not already on the effective `MANPATH`.

Rationale: a `.1` file in the tree is a second copy that drifts. DESIGN.md
principle 9 keeps the program in one file; the manual is part of the program's
contract, so it lives there too.

## 3. Division between `--help` and the manual page

`--help` stays long. The manual page is the formal copy. This duplicates
**content**, which is accepted, and forbids duplicating **maintenance**, which
`tests/doc-sync.sh` enforces.

Manual page sections, in this order, using the canonical `man(7)` names:

```
NAME
SYNOPSIS
DESCRIPTION
OPTIONS
EXIT STATUS
ENVIRONMENT
FILES
DIAGNOSTICS
EXAMPLES
SECURITY
SEE ALSO
BUGS
```

Rules:

- `OPTIONS` and `EXAMPLES` exist in both documents and must agree in content, though
  the formatting differs.
- `EXIT STATUS`, `ENVIRONMENT`, `FILES` and `DIAGNOSTICS` are **manual-page only**.
  None of them is visible to a user today: the environment variables and the exit
  codes exist only in `docs/cli-surface.md`, which a user never reads.
- `SECURITY` carries what `--help` shows under `SECURITY CHECKS`, expanded. `--help`
  keeps the short version.
- `BUGS` points at AGENTS.md Known gaps. It does not copy them.
- The reasoning behind a design decision stays in `DESIGN.md`. The manual page
  describes behaviour; it does not justify architecture.

## 4. Presentation rules

1. `--help` and `--print-man` write to **stdout** and exit 0. `run.sh --help | less`
   must work without redirecting stderr.
2. Diagnostics go to **stderr**, always, including a success notice that accompanies
   data on stdout.
3. Log files never receive escape sequences. Colour is decided at print time, for
   the terminal stream only.
4. Every option the argument parser accepts appears in `--help` **and** in the
   manual's `OPTIONS`. No exceptions.
5. Every exit code the program can emit appears in `EXIT STATUS`.
6. Arrays joined into a regular expression follow a naming convention:
   - `*_PATTERNS` holds regular expressions and is joined raw.
   - `*_LITERALS` holds literal strings and is joined with escaping.

   Before this rule, `NOISE_PATTERNS` (genuinely regexes) and the domain lists
   (literals) had opposite semantics and only a comment told them apart. The
   convention puts it in the name, where it cannot be missed by someone skimming.

## 5. Exit codes

One code per condition. A caller must be able to tell failures apart without
parsing stderr.

| Code | Condition |
|---|---|
| 0 | Success, including `--help`, `--print-man` and the standalone modes |
| 1 | Usage error: unknown option, missing or invalid argument |
| 2 | Refusal: a live session holds the lock |
| 3 | A required dependency is missing |
| 4 | Environment error: lockfile unwritable, jar not found, sandbox unusable |
| 5 | Lock state indeterminable |

`die()` takes an optional code, defaulting to 1. TLauncher's own exit status is
propagated unchanged, and `EXIT STATUS` says so.

No deviation from the proposed table was needed: each of the five failure
conditions already existed in the code under a shared `1`, so the mapping is a
split, not a redesign.

## 6. What this standard does not cover yet

The colour gate tests stdout while nearly all coloured output goes to stderr, and
`NO_COLOR` is unread. Both are recorded in `docs/cli-surface.md` and deferred on
purpose to a later PR, not overlooked. Until then rule 3 above is the binding part:
whatever the gate decides, the log files stay clean.
