# CLAUDE.md: project standard

- Read AGENTS.md first (purpose, hard constraints, repo map, known gaps), then
  docs/DESIGN.md before writing code, & docs/ROADMAP.md when the work belongs to a phase.
  Last, docs/TEMPORARY-CONTEXT.md: normally empty, read anyway because one line there can
  contradict what you were about to propose. This file just pins the doc/format standard.
- Documentation: AGENTS.md, CLAUDE.md & CHANGELOG.md at the repo root; DESIGN.md,
  ROADMAP.md, DECISIONS.md, GLOSSARY.md & TEMPORARY-CONTEXT.md in docs/; the CLI module
  (cli-standard.md, cli-surface.md) in docs/cli/.
  Do NOT create a new doc file without asking me first (this already lives in AGENTS.md).
  One exception by kind: a `README.md` inside a subfolder that only explains that folder,
  such as how to run `tests/`, isn't a canonical doc & needs no separate permission.
- This repo does not describe other repos. Another repo's name may appear as historical
  provenance, where a convention came from, never as operational information. No document
  here depends on another repo to be understood or worked on.
- Decisions go in docs/DECISIONS.md, append-only, one entry each, opening with
  `## YYYY-MM-DD: <title>`. Open items go in the "Known gaps" section of AGENTS.md,
  append-only, dated. Never scatter them. A new Known gaps entry carries the command or
  the run that shows the gap, so the next reader can check it's still open.
  A pointer to a DECISIONS entry cites its date & title, never a line number or a place
  in the file ("the last entry"). One is added where a line would otherwise read as
  arbitrary or as contradicting the rest of its document.
  A DECISIONS entry that introduces or refines a term writes its line in docs/GLOSSARY.md
  in the same PR. DECISIONS keeps why a term changed; GLOSSARY keeps what it means today &
  is corrected.
- What was observed & would be lost if nobody wrote it, & isn't known yet to be wanted,
  goes in docs/TEMPORARY-CONTEXT.md: one line, the date & who noted it, written without
  asking. Each line is later placed or discarded. Its full rules live in that file.
- CHANGELOG.md: Keep a Changelog. ONE file that grows by section, never one per round.
  Newest section on TOP (descending). Every section header is
  `## vX.Y — YYYY-MM-DD`, then ### Added / ### Changed / ### Fixed / ### Removed.
- A doc-only PR opens its OWN dated CHANGELOG section. Never fold it into the section of
  an already-published version: that section is history & isn't rewritten. The new section
  carries the change's real date in ISO 8601, not an earlier version's date. A doc-only PR
  may leave the latest CHANGELOG version ahead of the version the program prints; that
  desfase is intentional & closes in the next code PR (see "Displayed version").
- Dates: ISO 8601 (YYYY-MM-DD) everywhere I author them by hand.
  A Backlog item in docs/ROADMAP.md is born with a line opening `**Entered:**`: the date
  it entered & the PR that brought it, taken from `git log -S` on the file, not memory.
- Phases: a parked item enters a phase already in progress only if leaving it out makes
  a pending increment impossible to deliver, or forces redoing work already delivered.
  Anything else waits for the next phase.
- Commits: "<type>: <short imperative summary>", type in {add, chg, fix, rmv, doc}.
  add=new capability, chg=behavior change, fix=bugfix, rmv=feature removed, doc=docs only.
  The commit BODY does NOT re-narrate the change: 1-2 lines max plus a reference to the
  CHANGELOG section. Detail lives in CHANGELOG (what) and docs/DECISIONS.md (why), not in the
  commit message. (Keep the automatic Co-Authored-By / Claude-Session trailer.)
- PR title: the same format as the commit, with the same type. The PR list then reads
  like `git log` & filters by type from either side.
- PR body: the per-file table is copied from `git diff --numstat origin/main...HEAD`, run
  as the last step before writing the body. Never from `--stat`, which folds additions &
  deletions into one number, never rebuilt from memory, & never run before a last edit.
- Prose (docs, comments): English, applying no-ai-slop-writing-rules:rossmann-voice
  and no-ai-slop-writing-rules:no-ai-slop. Keep the existing voice. The plugin alone
  catches little, so "Prose floor" below holds with it & without it.
  docs/TEMPORARY-CONTEXT.md is exempt.
- Prose-skill dependency: those two skills are NOT vendored here. They come from the
  external plugin `no-ai-slop-writing-rules` (realrossmanngroup,
  https://github.com/realrossmanngroup/no_ai_slop_writing_rules), installed per session
  with `/plugin marketplace add realrossmanngroup/no_ai_slop_writing_rules` then
  `/plugin install no-ai-slop-writing-rules`. Upstream ships no LICENSE, so this repo
  references it at runtime instead of copying it (see Write scope, Third-party vendoring).
- Em dash (`—`): banned in all prose (no-ai-slop rule 1). Allowed only as a format token
  in CHANGELOG date headers (`## vX.Y — YYYY-MM-DD`). History is not normalized.
  docs/TEMPORARY-CONTEXT.md is exempt.
- State honesty: never mark something "working/tested" without a real run in a real
  environment. If it wasn't verified, say so (this is already the AGENTS.md rule).
  An instruction to verify something carries its conditions, not only its steps: what has
  to be true for the steps to work goes in writing next to them.
  When lost context is rebuilt, an inference is written as one, opening `**Hypothesis:**`
  with its basis in view, never as fact. In doubt between inferring & stating the gap,
  state the gap: `**No recoverable origin.**`
- Promises: no rule here prescribes a future mechanism. A threshold, an acceptance
  criterion or a method rule may force a decision; it can't make that decision in advance.
  Any sentence that names a concrete syntax, protocol or API goes with its run, the command
  & what it printed or a pointer to where they're written, wherever the sentence sits.
  When a threshold fires, the decision it opens answers three things before anything is
  planned: what is getting hard, with the number that shows it; the options & what each
  costs; the run that rules out the ones that don't work.
  An idea is dropped when its complexity outweighs a benefit someone can measure, never
  because it sounds risky. Before dropping it, check what its proposer meant: dropping
  the wrong reading of a word rejects some other idea.
- Workflow: work goes through a pull request. If `push`, creating a branch or opening
  the PR returns `403`, stop & say that write permission is missing. Never work around
  it by uploading loose files by hand.
- Tests: a suite that has ever failed intermittently runs N times, not once, because
  one green run proves nothing about a failure that shows up one run in five. It's
  listed in `REPEATED` in `tests/run-all.sh` & stays there after the fix, so the bug
  can't come back unseen. N is `REPEATS`, 3 by default; raise it for proof.

## Prose floor

Eight rules, each with this repo's baseline, measured on 2026-10-01, & the command that
recounts it. **No baseline may rise.** A PR that raises one added a violation. History
that isn't rewritten keeps its count, so a baseline only falls when live text is fixed.

**If the plugin's original text is in reach during a session, it's read & it outranks
this floor.** Installed or attached to the conversation, the trigger is having it, not
how it arrived: before writing prose, check whether it's there, & if it is, open it. The
floor below is a summary of it, & a summary is what's left when the original isn't.
Measured against the original on 2026-10-01, the floor & the rest of this file cover 3 of
its 24 rules in full & 5 in part; `docs/DECISIONS.md` has the count & what it found.

1. Before delivering, grep for the seven intensifiers in the rule 1 command below. With
   the plugin installed, its full lists apply too. Baseline: 11 hits, 8 in history that
   isn't edited (5 in `CHANGELOG.md`, 3 in `docs/DECISIONS.md`) & 3 live, one each in
   `docs/DESIGN.md`, `docs/ROADMAP.md` & `docs/cli/cli-surface.md`.
2. Contrastive parallelism ("not X, but Y", "X, not Y") at most once every 500 words per
   file. Baseline: `docs/DESIGN.md` at one every 330 words, over the ceiling; every other
   file under it, the closest `docs/cli/cli-surface.md` at one every 533.
3. A CHANGELOG bullet stays at 60 words or fewer; if the change doesn't fit, it's two
   bullets. Baseline: **43 bullets over the ceiling**, all in published sections.
4. A heading carries a parenthesis only when it holds data, such as a verification state
   or a number. Baseline: 1, `AGENTS.md`'s "Hard constraints (don't break these)".
5. Saying "not verified" about the code is required (see "State honesty"). Narrating
   what was searched for & not found while writing is not.
6. A claim about the code anchors on something that survives a refactor, a function name
   or a greppable quote, never a line number. Baseline: 6 anchors, all in history that
   isn't edited, 3 in `CHANGELOG.md` & 3 in `docs/DECISIONS.md`. The 96 in live text
   were replaced on 2026-10-01. A number that describes the code, such as a count of
   lines, arms or functions, goes with the command that recounts it, or it doesn't go.
   Writing the command isn't running it: a PR that changes what a number counts reruns
   its command before it closes.
7. A paragraph of running prose has at most five sentences; if it doesn't fit, it's two
   paragraphs. Lists, tables & glossary lines are out of scope. Baseline: 27 paragraphs
   over the ceiling: `docs/DECISIONS.md` 19, all in append-only entries, `docs/DESIGN.md`
   5, `docs/ROADMAP.md` 2 & `AGENTS.md` 1.
8. Three consecutive sentences of similar length are the sign that the text is going
   flat, & rule 7 doesn't catch it. The measure is the share of consecutive sentence
   triples whose lengths sit within 3 words of each other. Baseline: **4.6%**, 18 flat
   triples of 389.

The corpus is every tracked `.md` file except two. `CLAUDE.md` is the standard itself, &
editing it would move the numbers it declares. `docs/TEMPORARY-CONTEXT.md` is exempt by
design. The commands, from the repo root:

```sh
C=$(git ls-files '*.md' ':!:CLAUDE.md' ':!:*TEMPORARY-CONTEXT.md')

# Words in the corpus.
wc -w $C | tail -1

# Rule 1, the word list.
grep -niwE "very|absolutely|clearly|simply|probably|actually|really" $C

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

## Third-party vendoring

When copying a skill, template, or any third-party code into this repo, copy its
LICENSE and attribution alongside it, in the same folder. This repo is public: nothing
is redistributed without its license notice. If the source lacks it, stop and flag
before committing.

## Write scope

This repo (TL-FCCU on GitHub, TLauncher_FCCU before it was renamed) is the only write
target. Any other repository cloned into the session is read-only context: copy FROM it,
never write INTO it. Do not carry another repo's conventions into this one (language,
format).
If unsure which repo you're writing to, stop and ask.

## Displayed version

The version the program prints (`run.sh -h`) is single-source with the CHANGELOG: always
the latest CHANGELOG version. Bumped in the same PR as the code change that warrants it,
never in a doc-only PR.
