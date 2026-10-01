# REQUIREMENTS.md: what has to be true, & for whom

> This file says **what has to be true** for the launcher to be right, & for whom. It
> carries no dates & no order of work: that's `docs/ROADMAP.md`. It doesn't say why one
> shape won over another: that's `docs/DECISIONS.md`, which is append-only & keeps the
> history. It cites both & repeats neither.
>
> It's a seed, started on 2026-10-01 with the text that already said these things in
> other files, moved or cited here. Section 5 lists what nobody has written yet. Why it
> exists: `docs/DECISIONS.md`, entry of 2026-10-01 "The project's purpose gets a file of
> its own".

## 1. For whom

This repo is a personal security-audit sandbox for TLauncher. It runs the launcher
under `firejail` & records what it touches: filesystem events, child processes, &
network connections. It isn't a production launcher & never tries to be. The
author doesn't trust TLauncher; one of its update endpoints, `advancedrepository.net`,
probes over plain HTTP, & the author wants to watch what it does before deciding to
keep using it. Visibility & isolation come first, usability second.

## 2. What has to be true

Two things order every phase, & `docs/ROADMAP.md`, "Ordering principle", states them:
the report of a run doesn't lie about that run, & the binary archive lets someone say
months later which binary ran on which day. In the ROADMAP's words, if the layer that
reports the run lies, the binary archive inherits the lie.

## 3. What it isn't

- A production launcher. Usability comes second, by design.

## 4. Non-functional requirements

The ones already written are conventions of the code & live in `docs/DESIGN.md`, which
is the source; this list only points:

- Zero `sudo`, ever: principle 2.
- Every path through XDG: principle 1.
- One program, one file, auditable end to end: principle 9.
- The command line, its help & its manual page: `docs/cli/cli-standard.md`, which is
  normative for them.

## 5. Not written yet

Anything past sections 1 to 4. What an audit session has to contain to count as
evidence is the obvious next part; pieces of it sit as open items in Known gaps, in
`docs/ARCHITECTURE.md`, & nobody has written them as requirements. That waits for the
author.
