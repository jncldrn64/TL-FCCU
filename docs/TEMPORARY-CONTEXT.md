# TEMPORARY-CONTEXT.md: what is lost if nobody writes it down

> What was observed & would be lost if nobody wrote it. One line is enough. **The entry
> test is not whether it's ripe: it's whether it gets lost.**
>
> **It tends to zero.** Its measure is how fast it empties, not what it holds. A big file
> says nobody is emptying it.

## Entry: cheap

One line: what was observed, who brought it, & why it might matter. **No evidence
required, no question to formulate, no fields.** If nobody knows why it matters, write it
anyway & say so. The model writes here without asking, whoever implements & whoever
reviews, & also things that don't come from the author.

**Required: the date & who noted it.** And when an entry comes from the author's words &
those words are at hand, they go in raw: spelling, punctuation & language as they came.
Every entry is a model's summary, & a clean summary decides what an ambiguous sentence
meant; the raw words keep the ambiguity, which is the real state of the idea. A quote is
never reconstructed. If the words aren't at hand, the entry says so.

## Prose here is exempt

This file does not follow the "Prose" or "Em dash" rules of `CLAUDE.md`. It can be ugly &
telegraphic, & that's declared so no reviewer flags it. An ugly line that exists is worth
more than a tidy one nobody wrote.

## Exit: that's where the discipline is

Each line is placed or discarded, & there are four destinations: a PR that acts on it, the
`ROADMAP.md` Backlog with the reason the line carried, a phase, or deletion if it's
duplicate or irrelevant. The quote leaves with the line. It stays only when it shows the
summary had read the idea the wrong way round, & then that correction is written at the
destination.

## When to note & when to collect

Ask first, note second: if scope opens up, ask the author whether to give it shape now.
Note when a scope branch is closing, as things show up. Collect when the branch closes &
you're looking at what got left aside.

Two safety numbers, for a reader who doesn't notice the branch closing: note if three
prompts went by with discussion & nothing noted, & collect if nine PRs went by with no
active phase & the file wasn't emptied.

---

## Entries

**2026-10-01, Claude, from the author's words.** Four rules in `docs/cli-standard.md`
might hold beyond the CLI: one copy, & a test that syncs any second one; each document
saying whether it's normative or descriptive & which one wins over the code (the CLI
standard says it wins & "the code is wrong", & no document here says which wins in
general); the meaning goes in the name, not a comment (`*_PATTERNS` & `*_LITERALS`);
whatever the program exposes is documented & tested, & logs carry no colour. Asked on
2026-10-01, the author wasn't sure. The reference rule adopted that day covers part of
the comment question; the rest is open. The middle of the quote is left out because it
names another repo.
> "la verdad no estoy seguro"
> "hasta donde se esos CLI docs eras para el --help y el manpage de el proyecto ejecutable cli, por lo que en cierta forma entiendo que tambien habla de reglamentos en comentarios, y como tratar a los comentarios.... debemos expandir esto o buscar alternativa..."
