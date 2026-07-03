# Verify Before Building — A Backlog Line Is a Claim, Not a Fact

> Promoted from `tasks/lessons.md` 2026-06-24 via `/retro` §5. Documented **6×**
> across sessions (lessons.md lines 277/288/335/418 + the 06-24 entry + the 06-24
> price-timing signal bug) before promotion — recurrence ≥2 is the trigger, this
> was long past it. PORTABLE (see [[PORTABILITY]]). Companion to
> [foundation.md](foundation.md) "Before adding a new file" and the verify-first
> principle in [thinking-pipeline.md](thinking-pipeline.md).

## The rule

**Before implementing ANY backlog / brief / "approved" item, confirm it is still
pending and not already done — with a cheap grep/inspect, BEFORE writing code.**

A backlog or handoff line is a *claim about pending work* made at some earlier
point; it drifts from repo reality. Two recurring drift sources on this project:

- **Phase-spillover** — an earlier phase already shipped part of the "new" work
  (e.g. rebrand titles, canonical SSOT config were already correct).
- **Pre-built backend** — the data/endpoint already exists and the "feature" is a
  render/wiring job, not a build (e.g. `/price-timing` already returned the full
  buy/wait/overpriced verdict; only the UI was missing).

## The check (do this first, every time)

1. **Grep the named symbol / string** — is it already present?
   `grep -rE '<symbol>' --include="*.py" --include="*.tsx" --include="*.ts"`
2. **`git log --oneline -- <path>`** — was this area already touched for this purpose?
3. **Does the backend already provide the data?** — inspect the endpoint/response
   before building a frontend "feature" or a new endpoint.
4. **Inspect the foundation you're about to build ON.** If the task extends an
   existing signal/value/computation, verify *that thing is correct first*. (06-24:
   the deal-signal card badge was about to be built on a `price-timing` verdict that
   was structurally always "Tarihi En Düşük!" — inspecting the query before building
   caught a catalog-wide bug that the badge would have amplified 50×/page.)

## Why it's a rule, not a lesson

The discipline has *worked every time it was applied* (caught the drift cheaply, no
rework) — but it lived as a lesson and had to be re-remembered each session. As a
rule it's a standing reflex: the cost is one grep; the cost of skipping it is
building on a false premise and discovering it after the code exists (or after it
ships). It is the write-time twin of the doublecheck stage — verify the *premise*
before planning, not just the *output* after executing.

## Scope

- Applies to backlog items, handoff "Next Task Brief" lines, and any "we should
  build X" that assumes X doesn't exist yet.
- Does NOT mean re-litigate decided work — it means confirm the *starting state*
  the task assumes is real. One grep, then proceed.
