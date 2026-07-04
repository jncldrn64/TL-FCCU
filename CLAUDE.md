# CLAUDE.md — project standard

- Read AGENTS.md first (purpose, hard constraints, repo map, known gaps), then
  DESIGN.md before writing code. This file just pins the doc/format standard.
- Documentation lives at repo root: AGENTS.md, DESIGN.md, CHANGELOG.md. Do NOT
  create a new doc file without asking me first (this already lives in AGENTS.md).
- Decisions and open items go in the "Known gaps" section of AGENTS.md — one place,
  append-only, dated. Never scatter them.
- CHANGELOG.md: Keep a Changelog. ONE file that grows by section, never one per round.
  Newest section on TOP (descending). Every section header is
  "## vX.Y — YYYY-MM-DD", then ### Added / ### Changed / ### Fixed / ### Removed.
- Dates: ISO 8601 (YYYY-MM-DD) everywhere I author them by hand.
- Commits: "<type>: <short imperative summary>", type in {add, chg, fix, rmv, doc}.
  add=new capability, chg=behavior change, fix=bugfix, rmv=feature removed, doc=docs only.
  The commit BODY does NOT re-narrate the change: 1-2 lines max plus a reference to the
  CHANGELOG section. Detail lives in CHANGELOG (what) and DESIGN/AGENTS (why), not in the
  commit message. (Keep the automatic Co-Authored-By / Claude-Session trailer.)
- Prose (docs, comments): English, applying no-ai-slop-writing-rules:rossmann-voice
  and no-ai-slop-writing-rules:no-ai-slop. Keep the existing voice.
- State honesty: never mark something "working/tested" without a real run in a real
  environment. If it wasn't verified, say so (this is already the AGENTS.md rule).
