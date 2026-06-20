# Decisions

> Append-only log of consequential, hard-to-reverse choices for this repo.

## 2026-06-20 — Extract the workflow OS into a shareable repo

**Decision:** Consolidate the Claude Code "workflow operating system" — previously
split across `~/.claude/` (global skills/scripts/templates) and a host project's
`.claude/` (rules/hooks) — into this single repo, `cttme/cc-operating-system`.

- **Drift strategy: snapshot + export.** `tools/export.sh` pulls from the live
  `~/.claude/` config into this repo (one-way copy). The live config stays the working
  source of truth; this repo is the publishable snapshot. Rejected alternative:
  repo-as-SSOT with a symlink install — it would rewire the global config every project
  depends on, for no benefit while there's a single author.
- **Visibility: private now.** The repo is private (reversible — deletable, unindexed).
  **Flipping it public is the one-way door** and is deferred until a deliberate review;
  a secrets scrub (grep battery for credentials / emails / absolute paths) runs on every
  snapshot regardless.
- **Scope:** ships PORTABLE + MIXED rules/skills and the bootstrap machinery. Excludes
  the origin project's PROJECT-specific rules (listed as labeled examples in
  `PORTABILITY.md`) and the `/audit-*` suite (possible follow-on).

**Reversibility:** two-way (build in a fresh dir, no live config touched, private remote).
**Status:** done — initial snapshot committed and pushed private.
