# Delegation Gates — What Claude May Do Unprompted

> Companion to `.claude/rules/change-protocol.md` (reversibility axis). That file says
> *how much rigor* a change needs; this file says *whether Claude needs to stop and ask*
> before doing it. The dividing line is the same: **two-way doors flow, one-way doors
> get sign-off.**

## ✅ Auto-approve (two-way doors — just do it, then report)

These are cheap to revert; asking first is friction, not safety:

- **Commit** a change you just proposed (standing permission — suggest-then-commit).
- **Run** read-only inspection: tests, linters, `git log/status/diff`, grep, builds.
- **Edit** internal code / refactors / UI tweaks / docs / comments.
- **Add** a test, a fixture, an advisory hook/script, an index.md entry.
- **Create a backup** (`.bak-YYYY-MM-DD`) before a risky edit.
- **Branch** off the default branch to start work.

## ⚠️ Ask first (judgment — surface intent, get a nod)

- **Push** to a remote (do at session boundaries; confirm the branch).
- **Bump a dependency** (its own commit; CVE/bundle-size justified).
- **Add an API endpoint / route** (contract surface; rate-limit + validation).
- **A new top-level module or dependency** (architecture footprint).
- **Delete or move** files you didn't create this session — look first; surface a
  contradiction rather than proceeding.

## 🚫 Sign-off required (one-way doors — stop, present, wait)

These are expensive-to-impossible to undo; never do them unprompted:

- **DB schema / data migration**, dropping or renaming a column with history.
- **Public / affiliate API contract** changes (removed field, changed type, auth).
- **Framework / DB / major-dependency swap.**
- **Anything in `HIGH-RISK files`** (`POLICY.md`, `.claude/settings.json`,
  `.pre-commit-config.yaml`, `api/auth/*`, production migrations) — backup + `/verify`
  + a `decisions.md` entry, and run `/council` first.
- **Sending content to an external service** (publish, deploy, post) — outward-facing,
  may be cached/indexed even if deleted.
- **Secrets / credentials** — never read, edit, or move `.env*`, `secrets/`.

---

## Principle

> Friction belongs at the irreversible boundary, nowhere else. Auto-approving two-way
> work is what makes the human's attention *available* for the one-way decisions that
> actually need it. A workflow that asks permission for everything trains the human to
> rubber-stamp — which is worse than not asking.

_Adapted from düzhesap's `feedback_auto_commit_on_suggestion` (standing commit
permission) generalized to the full action surface. Tune the lists per project; the
reversibility test is the invariant._
