# CLAUDE.md: project standard

- Read AGENTS.md first (purpose, hard constraints, repo map, known gaps), then
  DESIGN.md before writing code, & ROADMAP.md when the work belongs to a phase.
  This file just pins the doc/format standard.
- Documentation lives at repo root: AGENTS.md, DESIGN.md, CHANGELOG.md, ROADMAP.md.
  Do NOT create a new doc file without asking me first (this already lives in AGENTS.md).
- Decisions and open items go in the "Known gaps" section of AGENTS.md, one place,
  append-only, dated. Never scatter them.
- CHANGELOG.md: Keep a Changelog. ONE file that grows by section, never one per round.
  Newest section on TOP (descending). Every section header is
  `## vX.Y — YYYY-MM-DD`, then ### Added / ### Changed / ### Fixed / ### Removed.
- Dates: ISO 8601 (YYYY-MM-DD) everywhere I author them by hand.
- Commits: "<type>: <short imperative summary>", type in {add, chg, fix, rmv, doc}.
  add=new capability, chg=behavior change, fix=bugfix, rmv=feature removed, doc=docs only.
  The commit BODY does NOT re-narrate the change: 1-2 lines max plus a reference to the
  CHANGELOG section. Detail lives in CHANGELOG (what) and DESIGN/AGENTS (why), not in the
  commit message. (Keep the automatic Co-Authored-By / Claude-Session trailer.)
- Prose (docs, comments): English, applying no-ai-slop-writing-rules:rossmann-voice
  and no-ai-slop-writing-rules:no-ai-slop. Keep the existing voice.
- Prose-skill dependency: those two skills are NOT vendored here. They come from the
  external plugin `no-ai-slop-writing-rules` (realrossmanngroup,
  https://github.com/realrossmanngroup/no_ai_slop_writing_rules), installed per session
  with `/plugin marketplace add realrossmanngroup/no_ai_slop_writing_rules` then
  `/plugin install no-ai-slop-writing-rules`. Upstream ships no LICENSE, so this repo
  references it at runtime instead of copying it (see Write scope, Third-party vendoring).
- Em dash (`—`): banned in all prose (no-ai-slop rule 1). Allowed only as a format token
  in CHANGELOG date headers (`## vX.Y — YYYY-MM-DD`). History is not normalized.
- State honesty: never mark something "working/tested" without a real run in a real
  environment. If it wasn't verified, say so (this is already the AGENTS.md rule).

## Third-party vendoring

When copying a skill, template, or any third-party code into this repo, copy its
LICENSE and attribution alongside it, in the same folder. This repo is public: nothing
is redistributed without its license notice. If the source lacks it, stop and flag
before committing.

## Write scope

This repo (TLauncher_FCCU) is the only write target. Any other repository cloned into
the session is read-only context: copy FROM it, never write INTO it. Do not carry
another repo's conventions into this one (language, DECISIONS vs Known gaps, format).
If unsure which repo you're writing to, stop and ask.

## Displayed version

The version the program prints (`run.sh -h`) is single-source with the CHANGELOG: always
the latest CHANGELOG version. Bumped in the same PR as the code change that warrants it,
never in a doc-only PR.
