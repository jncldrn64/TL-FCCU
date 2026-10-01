# TEMPORARY-CONTEXT.md: what is lost if nobody writes it down

> **Role:** transit: what was observed & isn't known yet to be wanted. It never wins.
> **Regime:** tends to zero. **Origin:** 2026-10-01, "The temporary context is adopted".
>
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

**2026-10-01, Claude, from the author's words.** Four rules in `docs/cli/cli-standard.md` might
hold beyond the CLI: one copy, & a test that syncs any second one; each document saying
whether it's normative or descriptive & which one wins over the code; the meaning goes in
the name, not a comment (`*_PATTERNS` & `*_LITERALS`); whatever the program exposes is
documented & tested, & logs carry no colour. Asked on 2026-10-01, the author wasn't sure,
& thinks the CLI docs may also say something about how comments are treated. The middle
of the quote is left out because it names another repo. Placed 2026-10-01, the second
rule only: each document's type & which one wins is `CLAUDE.md`, "Document types & which
one wins". The other three are still open.
> "la verdad no estoy seguro"
> "hasta donde se esos CLI docs eras para el --help y el manpage de el proyecto ejecutable cli, por lo que en cierta forma entiendo que tambien habla de reglamentos en comentarios, y como tratar a los comentarios.... debemos expandir esto o buscar alternativa..."

**2026-10-01, Claude.** Sentence-length spread is flatter than the voice profile: sd 10.3 here vs 15.3 in the profile, means close (17.3 vs 18.3), cut at .!? only. Also only ~10.6% of sentences over 30 words vs the profile's p90 at 36. Rule 8 only sees 3-in-a-row. Unknown whether a spread rule is worth it or whether the corpus being technical docs makes the profile the wrong yardstick. Mine from today: sd 10.0, mean 16.7, so I didn't fix it either.

**2026-10-01, Claude.** ROADMAP Phase 4's first scope item ("Detect that the sandbox jar differs from the home jar") may rest on a premise the code rules out: `build_firejail_params` mounts `bin/` with `--read-only` & `setup_sandbox` re-copies the home jar every run, so TLauncher can't change the sandbox jar from inside. Read from the code only, never seen in a run. Either TLauncher's self-update writes somewhere else, & the item should watch that place, or the item never fires. The next real session can answer it: where does TLauncher write when it updates itself (`snapshot-before.txt` vs `snapshot-after.txt` of a `-M` run that updates). The author said the run waits.
