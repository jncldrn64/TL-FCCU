# TEMPORARY-CONTEXT.md: what is lost if nobody writes it down

> What was observed & would be lost if nobody wrote it goes here. One line is enough.
> **The entry test is not whether it's ripe: it's whether it gets lost.**
>
> **It tends to zero.** Its measure is how fast it empties, not what it holds. A big file
> says nobody is emptying it, not that things were noted well.

## Entry: cheap

One line: what was observed, who brought it, & why it might matter. **No evidence
required, no question to formulate, no fields.** If nobody knows why it matters, write it
anyway & say so.

**The model writes here without asking for permission**, whoever implements & whoever
reviews, & also things that don't come from the author. That a file logs nothing, that
two names mix languages: none of it justifies interrupting a conversation, & all of it is
lost if there's nowhere to put it.

**Required: the date & who noted it. And sometimes one more thing.**

## The verbatim quote, & when it's required

The "who noted it" field records whose observation it was, not whose words. **Every entry
is a model's summary of what someone said.** When the author describes something wanted
but not yet nameable, the sentence is ambiguous, & that ambiguity is the real state of
the idea. A clean summary decides what was meant, & the ambiguity disappears along with
the fact that there was one.

**So when an entry comes from the author's words & those words are at hand, they go in
verbatim**, uncorrected: spelling, punctuation & language as they came. Correcting them is
the same mistake as summarizing: cleaning is deciding. The quote goes in whenever the words
exist. **It's required when the entry names a term with no line in `docs/GLOSSARY.md`**:
such an entry coins vocabulary, & coining it wrong costs a session to undo.

**A quote is never reconstructed.** If the words aren't at hand, the entry says so. An
invented quote is worse than none. **It's limited to the technical observation**: what
gets quoted is what was said about the work, not the conversation.

## Prose here is exempt

**This file does not follow the "Prose" & "Em dash" rules of `CLAUDE.md`.** It can be
ugly, telegraphic & untidy. That's declared so no reviewer flags it as a violation.

The reason: its only job is that something survives, & making entry expensive is what
guarantees nothing gets written. An ugly line that exists is worth more than a tidy one
nobody wrote.

## Exit: that's where all the discipline is

Each line is placed or discarded. Four destinations & no others:

- **A PR that acts on it right away.**
- **The Backlog of `docs/ROADMAP.md`**, with the reason the line carried. The reason
  travels with it or the emptying was useless.
- **A phase.**
- **Discard**, if it turns out duplicate or irrelevant. Deleted without a trace.

**The quote leaves with the line, & that isn't a loss.** Its job is to let whoever places
the entry check whether the summary said what the author said. Once that's done, the
destination is the record & the quote adds nothing. **With one exception, which is the
case that justifies it:** if, when the line is placed, the quote shows the summary had
read the idea the wrong way round, that correction is written at the destination.

## The boundary with the Backlog & Known gaps

**The Backlog holds what is already known to be wanted.** The next phases come out of it,
so its items have to be weighable: what blocks what, what gets built & what waits.
**Known gaps holds what isn't verified against real data.** **This file holds what isn't
known yet to be wanted.** A loose observation can't be weighed & is no use for building a
roadmap.

## When to note & when to collect

**Ask first, note second.** If scope opens up & what came before isn't written down, the
right move is to ask the author whether to give the open part shape before going on. That
sends the idea straight home without passing through here. This file is the net for when
that question isn't asked or isn't accepted. The other way round, the file becomes the
excuse for not asking & piles up.

**Note** when a scope branch is closing, incrementally, as things show up. **Collect** when
that branch closes & you're looking at what got left aside.

**Two numbers, as a safety net & not the mechanism.** Note if three prompts went by with
discussion & nothing noted. Collect if nine PRs went by with no active phase & the file
wasn't emptied. A model with a large window recognises the state condition & one with a
small window doesn't, & the rule is written for the worst reader. If the state condition
is recognised, the numbers are never used.

---

## Entries

**2026-10-01, Claude, from the author's words.** Four rules in `docs/cli-standard.md` might
hold beyond the CLI: one copy, & a test that syncs any second one; each document saying
whether it's normative or descriptive & which one wins over the code; the meaning goes in
the name, not a comment (`*_PATTERNS` & `*_LITERALS`); whatever the program exposes is
documented & tested, & logs carry no colour. Asked on 2026-10-01, the author wasn't sure,
& thinks the CLI docs may also say something about how comments are treated. The middle
of the quote is left out because it names another repo.
> "la verdad no estoy seguro"
> "hasta donde se esos CLI docs eras para el --help y el manpage de el proyecto ejecutable cli, por lo que en cierta forma entiendo que tambien habla de reglamentos en comentarios, y como tratar a los comentarios.... debemos expandir esto o buscar alternativa..."

### Session dump, 2026-10-01 (audit & restructure, PRs #28 to #32)

Written at the author's request before the session's context is compressed, so the
analysis, including what was discarded, stays usable as reference & isn't redone. Each
entry still gets placed or discarded like any other.

**2026-10-01, Claude, from the author's words.** Why this dump exists: the analysis below
would be lost when the session compresses, & it serves to avoid repeating redundancies or
failures already discussed, even where it never ends up in the repo's documents.
> "por que lo podriemos seguir usando de forma referencial para evitar redundancias o fallos ya discutidos, en teoria una de las utilidadse de ese archivo .md, asi no terminen en los documentos del repo."

**2026-10-01, Claude.** Timeline. #28 (merged) rewrote CLAUDE.md as a full method & added
docs/DECISIONS.md, GLOSSARY.md, TEMPORARY-CONTEXT.md. #29 (closed) moved Known gaps into
DECISIONS on top of #28. #30 (merged) reverted #28 to the v2.26 documents. #31 (merged)
brought DECISIONS back & made AGENTS.md short, with the Known gaps history moved byte for
byte. #32 (merged) moved DESIGN & ROADMAP into docs/, added this file, VERSION 2.30. The
reverted text of #28 is still in git (commits 93d7395, e7bcfd1, a727ad5) if any of it is
wanted again.

**2026-10-01, Claude, from the author's words.** #25, #26 & #27 (2026-09-17/19) came from
the author's private CLI code after FCCU sat idle since #24 (2026-07-30); until 07-30 both
repos' standards were as close as they could be. Those three PRs did NOT touch CLAUDE.md
(0 commits between #24 & #27). They added: docs/cli-standard.md, a second normative
document from the private CLI project; docs/cli-surface.md; tests/lock-exclusion.sh,
doc-sync.sh, run-all.sh; the pipefail rule under DESIGN principle 3; the "repeat an
intermittent test N times" practice, written only in run-all.sh's header; 114 lines
appended to Known gaps, none deleted. cli-standard extends DESIGN 4-6 without
contradicting them.
> "realmente el ultimo PR es el #24, antes que dejara de lado FCCU nuevament; 25, 26 y 27 son cuando trate de retomar el proyecto, usando otro codigo que tengo en privado"

**2026-10-01, Claude.** Tag audit. Commit subjects carry a type in both repos: FCCU 58 of
59 since 2026-07-04, MIDI 114 of 117; the misses are the author's GitHub web edits. PR
titles: FCCU 15 of 27, MIDI 105 of 112. MIDI wrote the PR-title rule in its PR #54
(2026-08-09) after the same break at its #49, & has had 0 untagged titles since (#54 to
#112). FCCU never wrote it; its untagged titles are #1-#6, #11, #17, #22, #25, #26, #27.
Recount: `git log --merges --format='%b' | grep -vcE '^(add|chg|fix|rmv|doc): '`.

**2026-10-01, Claude.** Past violations found by the audit, not registered anywhere since
#28 was reverted (the author chose "register & freeze" in the audit): the 12 untagged PR
titles above; Known gaps edited after it was append-only in #9 (deleted the 2026-07-04
entry), #11 (deleted a 2026-07-22 entry) & #18 (rewrote a line); `## v2.8.1 — 2026-07-04`
published by #8 & folded into v2.9 by #9; the v2.11 header lost by #12 & restored by #13;
em dash in 5 PR titles (#12, #14, #15, #16, #22); the author's untagged web edit a0f37ca.
Watch out: a removed-line sweep with `grep '^-[^-]'` misses deleted bullet lines; use
numstat. Commit 0a40389 (#22) removed a map line, which is legitimate.

**2026-10-01, Claude.** MIDI's standard grew from 128 to 570 lines of CLAUDE.md in 24
commits after 2026-07-30, plus AGENTS.md, GLOSARIO, REQUISITOS & CONTEXTO-TEMPORAL. The
porting backlog, one rule at a time, MIDI priority: PR title carries the commit type;
numstat table in the PR body, run as the last step; `Entró:` date & PR on Backlog items;
cross-reference to DECISIONS by date & title; Honestidad (instruction conditions,
inference marked as inference); Promesas y umbrales (no rule prescribes a future
mechanism; a syntax/API claim comes with its run); measurable prose (8 rules; numbers are
MIDI's & Spanish, so FCCU needs its own baselines); "original material outranks a
summary"; glossary; requirements doc. Not applicable: ARCHITECTURE maintenance (FCCU has
no ARCHITECTURE), log verbosity, icons, colours (MIDI product rules).

**2026-10-01, Claude.** Audit decisions whose status is unclear after the #30 revert,
since they were written only in #28: PRs open as drafts & the author merges; the author's
web edits also carry a type; FCCU prose stays English; MIDI has priority on method (kept,
see DECISIONS); past violations registered & frozen; the "extended honesty" block offered
& NOT chosen; a general rule that a reference in a doc or comment must resolve, with a
mechanical check; the CLI module in docs/cli/; cli-surface.md alive & anchored to symbols;
two FCCU rules proposed to MIDI, repeat-intermittent-tests & the authorship trailer.

**2026-10-01, Claude.** Inconsistencies still in the documents after #32: CLAUDE.md says
"Detail lives in CHANGELOG (what) and DESIGN/AGENTS (why)" while the why now lives in
DECISIONS; DECISIONS headers use a colon because CLAUDE.md allows `—` only in CHANGELOG
headers (MIDI uses `—`); Known gaps' closing paragraph still sends documentation ideas
there, overlapping this file; AGENTS.md's map misses tests/ & docs/cli-*; CLAUDE.md's Write
scope calls the repo TLauncher_FCCU, GitHub calls it TL-FCCU; docs/cli-surface.md's 93
`run.sh:N` anchors are off by 3 since #27 (`-v` at 2391 in the doc, 2394 in the code).

**2026-10-01, Claude.** Discarded, with why, so it isn't proposed again. A master rules repo:
the author said it doesn't & won't exist. Renaming DESIGN.md to ARCHITECTURE.md: DESIGN
prescribes, MIDI's ARCHITECTURE describes. Dissolving DESIGN into CLAUDE: the author kept
DESIGN. "Moving old entries is deleting them": Claude's reasoning, superseded; a verbatim
move keeps every word. A "Working with me" section in CLAUDE.md: rejected; preferences
first go through this file. Persistent memory: Claude Code in the cloud has none,
`~/.claude` is wiped per session, so the repo is where context survives. A new
docs/ARCHITECTURE.md for the agent's internals was proposed & never decided after the
restart.
> "era solo un decir, realmente no existe ni existira, yo cambio de repo a repo"

**2026-10-01, Claude.** Known gaps, read entry by entry against FCCU's own original rule
("decisions and open items go in Known gaps, one place"; "Detail lives in CHANGELOG (what)
and DESIGN/AGENTS (why)"): all 35 entries fit it (open items, items later closed,
decisions with their why, verification status). An earlier claim that only 16% belonged
there measured it with MIDI's layout & was wrong. The real issue was size: one place inside
the entry file grows into the whole log.

**2026-10-01, Claude, from the author's words.** Process lessons. Read each file's first
commit, its blame & the author's own web edits before comparing repos; analyse each repo
on its own first. CLAUDE.md is also an entry point: Claude Code reads it first, & MIDI's
AGENTS.md exists for tools that look for that name. Under FCCU's original design CLAUDE.md
pointed to AGENTS.md first; MIDI's AGENTS.md text says Claude Code doesn't read it. A PR
watcher must check merged/closed state, not only CI & review threads.
> "en realidad claude es el por donde empiezo tambien, en midi  se creo por que otros modelos no leia primero claude, leian primero agents por otro estandar diferente"
> "que hayas dicho que no sabias que claude.md era lo que era, me hace pensar que no estamos en la misma sintonia de prioridades"

**2026-10-01, Claude.** Prose baselines measured on 2026-10-01 over the pre-#28 corpus
(AGENTS, CHANGELOG, DESIGN, ROADMAP, docs/cli-*), with MIDI's commands adapted to English,
for when measurable prose is ported: 18,257 words; rule 1 (very, absolutely, clearly,
simply, probably) 1 hit; rule 2 contrastive parallelism, DESIGN.md 1 per 330 words (over
the 1-per-500 ceiling); rule 3, 43 CHANGELOG bullets over 60 words; rule 4, 1 heading with a
bare parenthesis (AGENTS "Hard constraints (don't break these)"); rule 6, 102 line anchors
(93 in cli-surface); rule 7, 26 paragraphs over five sentences; rule 8, 15 flat triples of
295, 5.1%. The adapted commands live in commit e7bcfd1's CLAUDE.md.

