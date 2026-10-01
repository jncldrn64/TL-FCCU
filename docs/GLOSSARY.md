# GLOSSARY.md: what the words mean today

> This file says what a term means now & is corrected when it ages. Why a term changed
> lives in `docs/DECISIONS.md`, which is append-only. Each line cites its source by date &
> title, or the CHANGELOG section that brought the term when no entry did.
>
> It starts on 2026-10-01 with the words the standard uses. The launcher's own vocabulary
> isn't collected yet, except where one of its words collides with the standard's.
>
> Maintenance rule: a DECISIONS entry that introduces or refines a term writes its line
> here in the same PR.

- **baseline**: two senses, told apart by context. In the launcher, the files that
  `-B/--save-baseline` builds from a session the user trusts, which later reports compare
  against (`save_baseline`). In the standard, a prose count measured on a stated date with
  a written command, which may not rise. Source for the second: 2026-10-01 "Prose gets a
  measured floor".
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
- **temporary context**: what was observed & would be lost if nobody wrote it down, before
  anyone knows whether it's wanted. It lives in `docs/TEMPORARY-CONTEXT.md`, one line each,
  & every line is later placed or discarded. Source: 2026-10-01 "The temporary context is
  adopted".
- **type**: the word that opens a commit message or a PR title, one of `add`, `chg`,
  `fix`, `rmv` & `doc`. Source: 2026-10-01 "A PR title carries the commit type".
