# DECISIONS.md: why this repo is the way it is

> Append-only. An entry is never edited or deleted, even once it's obsolete: a newer
> entry replaces it and names it by date & title. Each entry opens with
> `## YYYY-MM-DD — <title>`.
>
> This file starts on 2026-10-01. Decisions made before that date live in `AGENTS.md`,
> section "Known gaps", & stay there: moving them would mean deleting them from where
> they were written.

## 2026-10-01 — Decisions leave Known gaps for this file

**Context.** Until today one section of `AGENTS.md`, "Known gaps", held two different
things: decisions, & items not verified against real data. The rule that made it
append-only lived only in `CLAUDE.md`, & the section itself never said so. It was broken
three times after the rule existed: PR #9 deleted the entry dated 2026-07-04, PR #11
deleted an entry dated 2026-07-22, & PR #18 rewrote a line of an older one.

**Decision.** From 2026-10-01 a decision is written here. Known gaps keeps only what isn't
verified against real data, & it stays append-only too. The closing paragraph of Known
gaps, which sends new documentation ideas there, is superseded: those go to
`docs/TEMPORARY-CONTEXT.md`.

The three edits are recounted with this command, which lists every commit that removed a
line from `AGENTS.md`:

```sh
git log --format='@%h %ad %s' --date=short --numstat -- AGENTS.md |
  awk '/^@/{c=$0; next} NF==3 && $2>0 {print "-"$2" "c}'
```

On 2026-10-01 it prints five commits. `3d3079b` predates the rule. `0a40389`, from PR #22,
removed a line of the repo map, which is editable. The other three are the edits.

**Status:** in force.

## 2026-10-01 — The method is the author's standard, written whole in this repo

**Context.** Up to 2026-07-23 this repo's method was reconciled by hand with the author's
other project, the MIDI-Scale-Trainer repository. A rule against carrying another repo's
conventions had been written on 2026-07-04, & one against describing another repo
followed on 2026-07-23. From that date the two froze apart.

The other repo kept refining its method: the PR title, the file table in a PR body,
measurable prose, a glossary, a temporary context. None of it reached this one.

**Decision.** `CLAUDE.md` states the method as the author's standard, complete, with no
pointer to another repository. The weight of every rule falls on the author who wrote
it, never on another repo. Where a rule came from is recorded only in this file, & this
entry is that record: the rules adopted today were ported from MIDI-Scale-Trainer's
standard as of its commit `66acbf3`, an exception the author authorized for this audit.
Prose here stays in English.

Two rules this repo had & the other did not are written into the standard as well, so
they belong to the author too: an intermittent failure isn't closed by one green run, &
every commit keeps its authorship trailer.

The `CLAUDE.md` sentence "Do not carry another repo's conventions into this one" is
replaced. A rule enters here as the author's standard, written whole, never as a
reference to somewhere else.

**Status:** in force.

## 2026-10-01 — A PR title carries the commit type, & a PR opens as a draft

**Context.** Commits followed `<type>: <summary>` from the day it was written: 58 of the
59 non-merge commits since then carry a type, & the one that doesn't is a web edit by
the author. PR titles had no written rule. Of 27 merged PRs, 15 carry a type, & the last
three, #25 to #27, carry none.

**Decision.** A PR title uses the commit format & type, so the PR list reads like
`git log`. Its body carries the file table copied from `git diff --numstat`, run as the
last step before the body is written, plus the real output of every acceptance check.
A PR opens as a draft, & the author marks it ready & merges it. An edit the author makes
in the GitHub web editor carries a type as well.

Recount of untagged PR titles:

```sh
git log --merges --format='%b' | grep -vcE '^(add|chg|fix|rmv|doc): '
```

**Status:** in force.

## 2026-10-01 — Past violations are registered & frozen

**Context.** The audit of 2026-10-01 found rules broken in work that is already merged.
Rewriting published history would break the rule that protects it.

**Decision.** Nothing published is edited. Each count below is registered with its
command, & the number may not rise. A PR that raises one has added a new violation.

- 12 merged PR titles without a type: #1 to #6, #11, #17, #22, #25, #26, #27.
- 3 edits to Known gaps after it was append-only, listed in the first entry of this file.
- `## v2.8.1 — 2026-07-04` was published by PR #8 & folded into v2.9 by PR #9, so its
  bullet now carries the date 2026-07-05. The rule against folding came later, on
  2026-07-23.
- 10 commits without a type. Nine predate the rule of 2026-07-04. The one after it is
  the author's web edit `a0f37ca`, "Update CLAUDE.md".
- 43 CHANGELOG bullets over 60 words, & the prose baselines in `CLAUDE.md`, "Prose".
- 6 line-number anchors in history that can't be edited: 3 in `CHANGELOG.md`, 3 in Known
  gaps.

**Status:** in force.

## 2026-10-01 — Documentation moves to docs/, & the CLI standard becomes a module

**Context.** `CLAUDE.md` said all documentation lives at the repo root, in four files.
`docs/cli-surface.md` & `docs/cli-standard.md` have existed since PRs #25 & #26, both
requested by name in the author's briefs, & no list was updated. `ROADMAP.md` says this
repo copies "the phase habit, not the folder layout", a qualifier that came in with that
file on 2026-07-22 with no reason written anywhere.

The cost of moving was measured on 2026-10-01. Nothing reads a document at runtime. About
37 lines outside the CHANGELOG name a file that would move, & 3 of them are visible to a
user, in the man page's SEE ALSO. The 17 CHANGELOG mentions keep their old paths, because
history isn't rewritten.

**Decision.** `CLAUDE.md`, `AGENTS.md` & `CHANGELOG.md` stay at the root. `DESIGN.md` &
`ROADMAP.md` move to `docs/`, & the two CLI files move to `docs/cli/`. The move is its own
PR, typed `chg` because the man page text changes, & it bumps `VERSION`.

The CLI standard is a module: it applies to a repo with a terminal entry point. It was
born from the author's normalization work on another project of theirs that is a CLI.
Its inventory stays alive, anchored to symbols instead of line numbers.

**Status:** in force. The move itself is pending.

## 2026-10-01 — A reference in a document or a comment has to resolve

**Context.** A comment in `run.sh` claimed for months that `SCRIPT_DIR` survives symlinks,
& it was false until v2.25. `docs/cli-surface.md` carries 93 `run.sh:N` anchors. They
were right at v2.25, & PR #27 shifted them by three lines without anyone noticing: the
inventory puts `-v` at line 2391, the code has it at 2394.

**Decision.** Text that names a file, a function, a section or a document is a
reference, whether it sits in a document or in a comment. It anchors on a name, never a
line number, & it has to resolve. A mechanical check enforces it. This rule is general &
holds with or without a CLI.

**Status:** in force. The check doesn't exist yet. Until it does, the rule is applied by
hand, & `AGENTS.md` Known gaps carries it as an open item.

## 2026-10-01 — Measurable prose, a glossary & a temporary context are adopted

**Context.** On 2026-10-01 four blocks of rules were offered to the author for adoption.

**Decision.** Three are adopted: the PR title & body rules above, the measurable prose
floor, & the glossary with the temporary context. The fourth, an extended honesty block,
was offered & not chosen. It covered marking an inference as one, forbidding a rule from
prescribing a future mechanism, & letting original material outrank a summary. It is
written here so its absence reads as a choice.

The prose floor's first rule needs a word list in English. The minimal one is "very",
"absolutely", "clearly", "simply" & "probably", & the full lists of the prose plugin apply
whenever it is installed.

**Status:** in force.
