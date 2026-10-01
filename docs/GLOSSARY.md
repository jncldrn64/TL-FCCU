# GLOSSARY.md: what the words mean today

> This file says what a term means now & is corrected when it ages. Why a term changed
> lives in `docs/DECISIONS.md`, which is append-only. Each line cites its source by date &
> title, or the CHANGELOG section that brought the term when no entry did.
>
> It started on 2026-10-01 with the words the standard uses. The launcher's own words
> enter as a phase is about to use them, before code does, starting with Phases 3 & 4.
> A word that names something not built yet says so.
>
> Maintenance rule: a DECISIONS entry that introduces or refines a term writes its line
> here in the same PR.

- **baseline**: two senses, told apart by context. In the launcher, the files that
  `-B/--save-baseline` builds from a session the user trusts, which later reports compare
  against (`save_baseline`). In the standard, a prose count measured on a stated date with
  a written command, which may not rise. Source for the second: 2026-10-01 "Prose gets a
  measured floor".
- **binary archive**: the store Phase 3 plans, outside the sandbox, keeping each
  `starter-core` & `TLauncher.jar` seen, with its SHA256, date, size & source URL. Not
  built yet. Never called just "archive". Sources: CHANGELOG v2.10, & 2026-10-01 "The launcher's words enter the glossary, & archive always takes a qualifier".
- **CLI module**: `docs/cli/cli-standard.md`, what the command line must do, & its
  counterpart `docs/cli/cli-surface.md`, what it does today. Source: 2026-10-01 "The CLI
  module lives in docs/cli/".
- **decision**: an entry in `docs/DECISIONS.md` saying why something is the way it is.
  Never edited; a newer entry replaces it & names it by date & title. Source: 2026-10-01
  "Decisions get a file of their own".
- **desfase**: the gap between the latest CHANGELOG version & the version `run.sh -h`
  prints. A doc-only PR may open it on purpose; the next code PR closes it. The word stays
  in Spanish because the standard has used it that way since it was written. Source:
  CHANGELOG v2.18, & `CLAUDE.md`, "Displayed version".
- **doc-only PR**: a PR that changes no `run.sh`, `scripts/` or `tests/` file. It opens
  its own dated CHANGELOG section & never bumps `VERSION`. Source: CHANGELOG v2.18.
- **draft**: the state a PR opens in. The author marks it ready & merges it. Source:
  2026-10-01 "A PR opens as a draft".
- **Entered**: the line a Backlog item opens with, holding the date it entered & the PR
  that brought it, both from `git log -S`. Source: 2026-10-01 "A Backlog item carries the
  date & PR it entered with".
- **flat triple**: three consecutive sentences whose lengths sit within 3 words of each
  other, the unit of prose rule 8. Source: 2026-10-01 "Prose gets a measured floor".
- **home jar**: the user's own `TLauncher.jar`, the one `-f` points at or detection
  finds. Its counterpart is the **sandbox jar**, the copy `setup_sandbox` puts in
  `bin/` on every run. Sources: CHANGELOG v2.10, & 2026-10-01 "The launcher's words enter the glossary, & archive always takes a qualifier".
- **Hypothesis**: the marker for an inference made while rebuilding lost context, written
  with its basis in view. Its counterpart is **No recoverable origin**, for what can't be
  rebuilt. Source: 2026-10-01 "An inference is marked as one, & in doubt the gap is
  stated".
- **Known gap**: a dated entry in `docs/ARCHITECTURE.md`, section "Known gaps", for
  something open or not verified against real data, with the run that shows it. It's
  removed in the PR that closes it. Until 2026-10-01 the section lived in `AGENTS.md`,
  append-only, & held decisions too. Sources: 2026-10-01 "Decisions get a file of their
  own" & "Known gaps move to the description of the code, & close by removal".
- **line anchor**: a reference by line number, a file name, a colon & the number. Not
  allowed in new text, because the next edit moves it. Source: 2026-10-01 "Prose gets a
  measured floor".
- **manifest**: the append-only list Phase 3 plans for the binary archive, one line
  per artifact, deduplicated by hash. Not built yet. Sources: CHANGELOG v2.10, &
  2026-10-01 "The launcher's words enter the glossary, & archive always takes a qualifier".
- **promotion**: replacing the home jar with the sandbox jar, after showing both hashes
  & asking. Never done without asking. Planned in Phase 4, not built yet. Sources:
  CHANGELOG v2.10, & 2026-10-01 "The launcher's words enter the glossary, & archive always takes a qualifier".
- **session archive**: the `logs.tar.gz` that `cleanup_logs` packs inside a session
  directory older than the retention window, keeping `SUMMARY.txt` &
  `INCIDENT_REPORT.md` beside it. Never called just "archive". Sources: CHANGELOG v2.4,
  & 2026-10-01 "The launcher's words enter the glossary, & archive always takes a qualifier".
- **sighting**: a manifest line recording that a binary already in the binary archive
  was seen again, in place of a second copy. Not built yet. Sources: CHANGELOG v2.10, &
  2026-10-01 "The launcher's words enter the glossary, & archive always takes a qualifier".
- **starter-core**: a TLauncher component. ROADMAP Phase 4 says TLauncher's `UpdateCore`
  re-applies it on every start, because `run.sh` copies the home jar into the sandbox
  each run, & plans to stop that. TLauncher's side isn't verified here. Sources: CHANGELOG v2.10, & 2026-10-01 "The launcher's words enter the glossary, & archive always takes a qualifier".
- **temporary context**: what was observed & would be lost if nobody wrote it down, before
  anyone knows whether it's wanted. It lives in `docs/TEMPORARY-CONTEXT.md`, one line each,
  & every line is later placed or discarded. Source: 2026-10-01 "The temporary context is
  adopted".
- **type**: the word that opens a commit message or a PR title, one of `add`, `chg`,
  `fix`, `rmv` & `doc`. Source: 2026-10-01 "A PR title carries the commit type".
