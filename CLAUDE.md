# CLAUDE.md: the author's standard

These are the author's rules for this repo, written whole. They hold in every session &
are read before anything is touched. Where a rule came from is recorded in
`docs/DECISIONS.md` & nowhere else, so the weight of each rule falls on the author who
wrote it.

## Reading order

1. `AGENTS.md`: purpose, hard constraints, the repo map & Known gaps.
2. `DESIGN.md`, before writing any code.
3. `ROADMAP.md`, when the work belongs to a phase.
4. `docs/DECISIONS.md`: why things are the way they are. A restriction that lives only
   there is the one a model that skips it proposes to undo.
5. `docs/TEMPORARY-CONTEXT.md`, last. It's the most volatile file & its normal state is
   empty, & it's read anyway because one line there can contradict what you were about
   to propose.

Before touching `--help`, the man page, an option or an exit code, read the CLI module
too: `docs/cli-standard.md`.

## Documentation

At the root: `AGENTS.md`, `CLAUDE.md`, `CHANGELOG.md`, `DESIGN.md`, `ROADMAP.md`.
In `docs/`: `DECISIONS.md`, `GLOSSARY.md`, `TEMPORARY-CONTEXT.md`, & the CLI module,
which is `cli-standard.md` (normative) & `cli-surface.md` (the descriptive inventory).
The CLI module applies because this repo has a terminal entry point. `DESIGN.md` &
`ROADMAP.md` are due to move to `docs/`, & the CLI module to `docs/cli/`;
`docs/DECISIONS.md` says why.

Do NOT create a new doc file without asking the author first.

This repo does not describe other repos. Another repo's name appears only in
`docs/DECISIONS.md`, as provenance, & in history that isn't rewritten. No document here
depends on another repo to be understood or worked on.

## Decisions & Known gaps

`docs/DECISIONS.md` is append-only, in the style of an ADR. An old entry is never deleted
or edited, even once it's obsolete: a new entry replaces it & names it. Each entry opens
with `## YYYY-MM-DD — <title>`. A pointer to a decision cites its date & title, never a
line number.

`AGENTS.md`, section "Known gaps", holds what isn't verified against real data, dated &
append-only. The decisions written there before 2026-10-01 stay where they are.

## CHANGELOG

`CHANGELOG.md` follows Keep a Changelog. It's ONE file that grows by section, never one
per round, with the newest section on TOP. Every section header is
`## vX.Y — YYYY-MM-DD`, then `### Added`, `### Changed`, `### Fixed` or `### Removed`.

A doc-only PR opens its OWN dated section. Never fold it into the section of an
already-published version: that section is history & isn't rewritten. The new section
carries the change's real date in ISO 8601, not an earlier version's date. A doc-only PR
may leave the latest CHANGELOG version ahead of the version the program prints; that
desfase is intentional & closes in the next code PR (see "Displayed version").

A bullet stays at 60 words or fewer: that's rule 3 of "Prose", with its command.

## Dates

ISO 8601 (`YYYY-MM-DD`) everywhere a date is written by hand.

## Commits

The message is `<type>: <short imperative summary>`, with `type` in
`{add, chg, fix, rmv, doc}`: `add` a new capability, `chg` a behaviour change, `fix` a
bugfix, `rmv` something removed, `doc` documentation only. This holds for an edit made in
the GitHub web editor too.

The body does NOT re-narrate the change: one or two lines at most, plus a reference to
the CHANGELOG section. What changed lives in the CHANGELOG & why in `docs/DECISIONS.md`.
Keep the automatic Co-Authored-By & Claude-Session trailer.

## Pull requests

- The title uses the commit format, with the same type, so the PR list reads like
  `git log` & can be filtered by type from both sides.
- The body carries the file table copied from `git diff --numstat`, run as the **last
  step** before the body is written. Never from `--stat`, which adds insertions &
  deletions into one number, & never from memory or from a run made before the last edit.
- The body pastes the real output of every acceptance check.
- A PR opens as a draft. The author marks it ready & merges it.

## Tests

An intermittent failure is not closed by one green run. The suite that showed it is run
`N` times (`REPEATS=N tests/run-all.sh`), & the tally goes in the PR.

## References

Text that names a file, a function, a section or a document is a reference, whether it
sits in a document or in a comment. It anchors on a name, never on a line number, & it has
to resolve. A mechanical check is meant to enforce this. Until it exists (see `AGENTS.md`
Known gaps), it is checked by hand before a PR closes.

## Prose

Docs & comments in English, in the author's voice, applying two skills:
`no-ai-slop-writing-rules:no-ai-slop` & `no-ai-slop-writing-rules:rossmann-voice`. Both
come from the external plugin `no-ai-slop-writing-rules` (realrossmanngroup,
https://github.com/realrossmanngroup/no_ai_slop_writing_rules), installed per session with
`/plugin marketplace add realrossmanngroup/no_ai_slop_writing_rules` then
`/plugin install no-ai-slop-writing-rules`. Upstream ships no LICENSE, so this repo
references it at runtime instead of copying it (see "Third-party vendoring").

What follows is the floor that holds when the plugin isn't installed, & it holds with the
plugin too. Each number is this repo's baseline, measured on 2026-10-01, & comes with the
command that recounts it. **No baseline may rise.** A PR that raises one has added a
violation.

1. Before delivering, search for "very", "absolutely", "clearly", "simply" & "probably".
   With the plugin installed, its full lists apply. Baseline: one hit in running prose,
   "the very orphan" in a published `CHANGELOG.md` section, where "very" isn't an
   intensifier. The hits in `docs/DECISIONS.md` are this list, quoted, & are discounted.
2. Contrastive parallelism ("not X, but Y", "X, not Y") at most once every 500 words per
   file. Baseline: `DESIGN.md` at one every 330 words, over the ceiling; every other
   file under it, the closest `docs/cli-surface.md` at one every 533.
3. A CHANGELOG bullet stays at 60 words or fewer; if the change doesn't fit, it's two
   bullets. Baseline: **43 bullets over the ceiling**, frozen in published sections.
4. A heading carries a parenthesis only when it holds data, such as a verification state
   or a number. Baseline: 0.
5. Saying "not verified" about the code is required (see "State honesty"). Narrating
   what was searched for & not found while writing is not.
6. A claim about the code anchors on something that survives a refactor, a function name
   or a greppable quote, never a line number (see "References"). Baseline: 102 anchors.
   The 93 in `docs/cli-surface.md` & the 3 in `ROADMAP.md` are due to be replaced; the 6
   in history that isn't edited stay, 3 in `CHANGELOG.md` & 3 in Known gaps.
7. A paragraph of running prose has at most five sentences; if it doesn't fit, it's two
   paragraphs. Lists, tables & glossary lines are out of scope. Baseline: 26 paragraphs
   over the ceiling, `AGENTS.md` 19, `DESIGN.md` 5 & `ROADMAP.md` 2. Most of the 19 sit
   in append-only Known gaps.
8. Three consecutive sentences of similar length are the sign that the text is going
   flat, & rule 7 doesn't catch it. The measure is the share of consecutive sentence
   triples whose lengths sit within 3 words of each other. Baseline: **4.9%**, 16 flat
   triples of 329.

The corpus is every tracked `.md` file except two. `CLAUDE.md` is the standard itself, &
editing it would move the numbers it declares. `docs/TEMPORARY-CONTEXT.md` is exempt by
design (see "Temporary context"). The commands, from the repo root:

```sh
C=$(git ls-files '*.md' ':!:CLAUDE.md' ':!:*TEMPORARY-CONTEXT.md')

# Words in the corpus.
wc -w $C | tail -1

# Rule 1, the word list.
grep -niwE "very|absolutely|clearly|simply|probably" $C

# Rule 2, per file: words, then hits. Divide the first by the second.
for f in $C; do printf '%s %s %s\n' "$f" "$(wc -w < "$f")" "$(grep -ciE \
  "\b(is|are|was|were)(n't| not) [^,.;]{2,45}[,;] (it's|it is|they're|they are|but)\b|\b[a-z]+, not (a|an|the|of|by|to|with|in|on|for) [a-z]" \
  "$f")"; done

# Rule 3, CHANGELOG bullets over 60 words, continuation lines included.
awk '/^- /{if(b)print w; b=1; w=NF; next} /^  [^ ]/ && b{w+=NF; next}
     {if(b)print w; b=0} END{if(b)print w}' CHANGELOG.md | awk '$1>60' | wc -l

# Rule 4, headings with a parenthesis, per file.
grep -cE "^#{1,4} .*\(.*\)" $C

# Rule 6, line-number anchors, per file.
grep -oE "\b[A-Za-z_./-]+\.(sh|java|md|py):[0-9]+" $C | cut -d: -f1 | sort | uniq -c

# Rules 7 & 8, one extractor. It drops code blocks, tables, headings, quotes, bullets &
# their indented continuation lines, & keeps paragraphs of more than 15 words.
python3 - $C <<'EOF'
import io,re,sys
P,tot=[],0
for f in sys.argv[1:]:
    out,inc=[],False
    for l in io.open(f,encoding='utf-8').read().split('\n'):
        if l.strip().startswith('```'): inc=not inc; out.append(''); continue
        if inc or re.match(r'^\s*[|#>]',l) or re.match(r'^\s*[-*+] ',l) \
           or re.match(r'^\s{2,}\S',l) or re.match(r'^\s*\d+\. ',l):
            out.append(''); continue
        out.append(l)
    ps=[p for p in re.split(r'\n\s*\n','\n'.join(out)) if len(p.split())>15]
    for p in ps:
        o=[len(x.split()) for x in re.split(r'(?<=[.:;!?])\s+',p) if x.strip()]
        if len(o)>5: tot+=1; print(f"rule 7: {f}: {len(o)} sentences")
        if len(o)>=3: P.append(o)
t=sum(len(o)-2 for o in P)
pl=sum(1 for o in P for i in range(len(o)-2) if max(o[i:i+3])-min(o[i:i+3])<=3)
print(f"rule 7: {tot} paragraphs over five sentences")
print(f"rule 8: {pl} flat of {t} triples = {100*pl/t:.1f}%")
EOF
```

The rule 2 count depends on its regular expression: changing it changes the number &
breaks the comparison with the baseline. If it needs tuning, recount every file at once
& rewrite the baseline with its new date.

## Em dash

Em dash (`—`): banned in all prose (no-ai-slop rule 1). Allowed only as a format token in
CHANGELOG date headers (`## vX.Y — YYYY-MM-DD`) & `docs/DECISIONS.md` headers
(`## YYYY-MM-DD — <title>`). History is not normalized. `docs/TEMPORARY-CONTEXT.md` is
exempt.

## State honesty

Never mark something "working" or "tested" without a real run in a real environment. If
it wasn't verified, say so in those words.

## Glossary

`docs/GLOSSARY.md` says what a term means today & is corrected when it ages, unlike
`docs/DECISIONS.md`, which says why it changed & is append-only. A decision entry that
introduces or refines a term writes that term's glossary line in the same PR. Each line
cites its source by date & title.

## Temporary context

`docs/TEMPORARY-CONTEXT.md` holds what was observed & would be lost if nobody wrote it
down. The entry test is "is it lost if I don't write it?", not "is it ripe?". One line,
with the date & who noted it, & the author's own words, raw, when the entry comes from
them; no evidence required. Anyone writes there without asking. Its prose is exempt from
"Prose" & "Em dash" on purpose, because making entry expensive is what guarantees nothing
gets written.

The discipline is on the way out. Each line is placed or discarded: a PR that acts on it,
the `ROADMAP.md` Backlog, a phase, or deleted if it's duplicate or irrelevant. The reason
a line carried travels with it. The file tends to zero, & a big one means nobody is
emptying it.

Ask first, note second. If scope opens up, ask the author whether to give it shape now,
which sends it straight home. The file is the net for when that question isn't asked or
isn't accepted. Known gaps holds what is proven missing, & the Backlog holds what is known
to be wanted; this file holds what isn't known yet to be wanted.

## Third-party vendoring

When copying a skill, template, or any third-party code into this repo, copy its LICENSE
& attribution alongside it, in the same folder. This repo is public: nothing is
redistributed without its license notice. If the source lacks it, stop & flag it before
committing.

## Write scope

This repo (TL-FCCU) is the only write target. Any other repository cloned into the
session is read-only context: copy FROM it, never write INTO it. A rule enters this repo
as the author's standard, written whole here, never as a pointer to another repo. If
unsure which repo you're writing to, stop & ask.

## Displayed version

The version the program prints (`run.sh -h`) is single-source with the CHANGELOG: always
the latest CHANGELOG version. Bumped in the same PR as the code change that warrants it,
never in a doc-only PR.
