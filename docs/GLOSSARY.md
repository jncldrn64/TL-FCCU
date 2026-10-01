# GLOSSARY.md: what the words mean today

> This file says what a term means now & is corrected when it ages. Why a term changed
> lives in `docs/DECISIONS.md`, which is append-only. Each line cites its source by date &
> title.
>
> It starts on 2026-10-01 with the words the standard itself uses. The launcher's own
> vocabulary is not collected yet, except where one of its words collides with the
> standard's.

- **author's standard**: the method this repo follows, written whole in `CLAUDE.md`. Each
  rule's weight falls on the author; where a rule came from is recorded only in
  `docs/DECISIONS.md`. Source: `docs/DECISIONS.md`, 2026-10-01 "The method is the author's
  standard, written whole in this repo".
- **baseline**: two senses, kept apart by context. In the launcher, the domains & IPs
  saved by `-B/--save-baseline` from a session the user trusts, which the report compares
  new sessions against (`save_baseline`). In the standard, a count measured on a stated
  date with a written command, which may not rise. Source for the second:
  `docs/DECISIONS.md`, 2026-10-01 "Past violations are registered & frozen".
- **CLI module**: the CLI standard (`docs/cli-standard.md`) & its inventory
  (`docs/cli-surface.md`). It applies to a repo with a terminal entry point. Source:
  `docs/DECISIONS.md`, 2026-10-01 "Documentation moves to docs/, & the CLI standard
  becomes a module".
- **decision**: an entry in `docs/DECISIONS.md` saying why something is the way it is.
  Never edited; a newer entry replaces it & names it by date & title. Source:
  `docs/DECISIONS.md`, 2026-10-01 "Decisions leave Known gaps for this file".
- **draft**: the state a PR opens in. The author marks it ready & merges it. Source:
  `docs/DECISIONS.md`, 2026-10-01 "A PR title carries the commit type, & a PR opens as a
  draft".
- **flat triple**: three consecutive sentences whose lengths sit within 3 words of each
  other, the unit of prose rule 8. Source: `docs/DECISIONS.md`, 2026-10-01 "Measurable
  prose, a glossary & a temporary context are adopted".
- **frozen**: said of a violation already in published work. It's registered with its
  count & command & never fixed in place, because fixing it would rewrite history. Source:
  `docs/DECISIONS.md`, 2026-10-01 "Past violations are registered & frozen".
- **Known gap**: a dated, append-only entry in `AGENTS.md`, section "Known gaps", for
  something not verified against real data or known to be open. Until 2026-10-01 that
  section held decisions & history too; that text now sits unedited in
  `docs/DECISIONS.md`. Source: `docs/DECISIONS.md`, 2026-10-01 "Known gaps up to this
  date, moved here unedited".
- **line anchor**: a reference by line number, written as a file name, a colon & the
  number. Not allowed in new text, because the next edit moves it. Source:
  `docs/DECISIONS.md`, 2026-10-01 "A reference in a document or a comment has to
  resolve".
- **reference**: text in a document or a comment that names a file, a function, a section
  or a document. It anchors on a name & has to resolve. Source: `docs/DECISIONS.md`,
  2026-10-01 "A reference in a document or a comment has to resolve".
- **temporary context**: what was observed & would be lost if nobody wrote it down. It
  lives in `docs/TEMPORARY-CONTEXT.md`, one line each, & every line is eventually placed
  or discarded. Source: `docs/DECISIONS.md`, 2026-10-01 "Measurable prose, a glossary & a
  temporary context are adopted".
- **type**: the word that opens a commit message or a PR title, one of `add`, `chg`,
  `fix`, `rmv` & `doc`. Source: `docs/DECISIONS.md`, 2026-10-01 "A PR title carries the
  commit type, & a PR opens as a draft".
