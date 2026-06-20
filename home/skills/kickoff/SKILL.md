---
name: kickoff
description: Project-zero interview for a brand-new project. Plan-mode, read-only — front-loads the expensive-to-reverse decisions into a one-page constitution + decision #0 (thesis, architecture skeleton, definition-of-done, risk register, three-tier boundaries). Run once, right after bootstrap, before writing code.
allowed-tools: Read, Glob, Grep, Write, AskUserQuestion
---

# /kickoff — Cold-Start Constitution

The first hour of a project sets decisions that are **expensive to reverse** (the
thesis, the architecture skeleton, the naming, what "done" means). `/kickoff`
front-loads them in a short interview and writes them down **once**, so project N+1
starts sharp instead of accreting structure ad-hoc.

Run **once**, right after `new-project.py` bootstrap, before real code. Read-only
interview (plan-mode mindset) — the only writes are the two output files at the end.

## Anti-theater contract

- **Max one page.** The constitution is `docs/CONSTITUTION.md` (~1 page). If it grows
  past a screen, you're over-specifying — cut.
- **Written as contract, not aspiration.** The thesis becomes the CLAUDE.md identity
  line verbatim. The Definition of Done is what `/session-end` checks progress against.
- **One-way doors only.** Don't decide reversible things here (lint config, file
  names you can rename later) — decide the things that calcify.

## Akış

### Adım 1 — Interview (read-only)
Ask the user, one cluster at a time (use `AskUserQuestion` where choices are
discrete). Keep it tight — 5 clusters:

1. **Thesis** — "In one sentence, what is this and who is it for?" (→ CLAUDE.md
   identity line). Probe until it's specific (not "a web app" but "X for Y that does Z").
2. **Architecture skeleton** — main modules + their boundaries + naming convention.
   What are the 3–6 top-level dirs and what does each own?
3. **Definition of done** — what does v1 *do*? 2–4 success metrics that
   `/session-end` can check ("scrapes N sites", "p95 < Xms", "passes audit --strict").
4. **Risk register** — "What kills this project?" 3–5 risks (technical, legal/policy,
   data-integrity, scope). The one-way doors live here.
5. **Three-tier boundaries** — ✅ always-allowed / ⚠️ ask-first / 🚫 never. Ground in
   *this* project's risks (e.g. 🚫 never delete price history; ⚠️ ask before schema
   migration; ✅ add a scraper test freely).

### Adım 2 — Reflect the skeleton back
Before writing, restate the architecture + DoD + tiers in 5 bullets and confirm.
A wrong thesis written down is worse than no thesis.

### Adım 3 — Write `docs/CONSTITUTION.md` (one page)
```markdown
# <Project> — Constitution  (kickoff YYYY-MM-DD)

## Thesis
<one paragraph — the CLAUDE.md identity line, verbatim>

## Architecture skeleton
- `<dir>/` — <what it owns>   (×3–6)
- Naming: <convention>

## Definition of Done (v1)
- [ ] <capability>
- Metrics: <metric> ≥/≤ <target>   (×2–4)

## Risk register (what kills this)
- 🟥 <risk> → <mitigation / one-way-door note>   (×3–5)

## Three-tier boundaries
- ✅ Always: <...>
- ⚠️ Ask-first: <...>
- 🚫 Never: <...>
```

### Adım 4 — Write decision #0 to `tasks/decisions.md`
Append an ADR entry (full format incl. `Reversibility`/`Status`) titled
`Decision #0 — project constitution`, capturing the thesis + the one-way doors as
`Reversibility: one-way`, `Status: Accepted`. This is the audit anchor for every
later decision.

### Adım 5 — Wire the thesis into CLAUDE.md
Replace the CLAUDE.md identity line (top paragraph) with the thesis verbatim, so the
contract loads every session. Point `/session-end` at `docs/CONSTITUTION.md`'s DoD.

### Adım 6 — Summary block
```
═══════════════════════════════════════════
   /kickoff — <project>
───────────────────────────────────────────
  Thesis:      <one line>
  Modules:     <n> top-level dirs
  DoD:         <n> capabilities, <n> metrics
  Risks:       <n> (one-way doors: <n>)
  Tiers:       ✅/⚠️/🚫 set
  Written:     docs/CONSTITUTION.md + decision #0
═══════════════════════════════════════════
```

## Kurallar

- **One page or it failed.** Constitution that needs scrolling = over-specified.
- **Interview before writing.** Don't draft the constitution from assumptions —
  the value is the user's answers, not your guesses.
- **Reflect before commit** (Adım 2) — confirm the skeleton is right.
- **One-way doors → `Reversibility: one-way`** in decision #0; later `/council`
  escalations reference it.

## İlgili

- `new-project.py --profile` — runs *before* kickoff (scaffolds files); kickoff fills
  the thinking. `bootstrap-project` skill orchestrates the scaffold.
- `tasks/decisions.md` — decision #0 destination (ADR + Reversibility/Status).
- `/session-end` — checks progress against the constitution's Definition of Done.
- `.claude/rules/change-protocol.md` — reversibility axis (the risk register uses it).
