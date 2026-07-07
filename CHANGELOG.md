# Changelog — cc-operating-system

Version history for the workflow OS kernel. The canonical version lives in `VERSION`
(repo root); exported projects can record which version they were installed from to
detect drift. Bumps follow semver applied to the **workflow contract**, not any one
project that runs on it.

## Semver policy (what a bump means)

| Bump | Meaning | Examples |
|---|---|---|
| **MAJOR** `x.0.0` | Breaking change to the workflow contract — the lifecycle, output contract, export contract, or a gate everything depends on. Operators must change a habit. | Restructure the `onboard→…→reflect` pipeline; change the `decisions.md` ADR schema; break the export manifest contract. |
| **MINOR** `0.x.0` | New capability, backward-compatible. Operators learn something new but nothing breaks. | A new rule / skill / gate; a new tool under `tools/`; a promoted lesson. |
| **PATCH** `0.0.x` | Fix or clarification to existing rules/tooling; no new capability. | A support-script bug fix; rule wording correction; dead-reference purge. |

Rule of thumb: does an operator have to **change a habit** (MAJOR), **learn something
new** (MINOR), or does something just **work better** (PATCH)?

---

## 0.1.1 — 2026-07-07

**PATCH — support-script bug fix.**

- **`project-template/scripts/cost_breakdown.py` now reads subagent transcripts.** The
  script globbed only top-level session transcripts
  (`~/.claude/projects/*/[0-9a-f]*.jsonl`), so all delegated subagent spend — which
  lives in `<session>/subagents/agent-*.jsonl` — was invisible. It reported the cheap
  tier at near-zero despite heavy Sonnet/Haiku delegation, systematically over-reporting
  the Opus share and making the `/retro` model-mix verdict uncertifiable. Fix: also glob
  `*/*/subagents/*.jsonl` and dedup entries by `uuid` (defensive against a future inlined
  sidechain). Verified downstream: a project's 14-day Sonnet share went 0% → 4% once the
  nested files were read. Surfaced by a project `/retro` as its headline finding.

## 0.1.0 — baseline (initial snapshot, retroactively numbered)

The kernel as of the initial public snapshot (`67bb4be`) through the export/security
hardening series (`d75484f`). The `0.1.0` line was already implied by the per-script
`# VERSION: 0.1.0` markers under `home/scripts/`; this file makes the whole-OS version
explicit. Comprised the thinking pipeline + reversibility selector, the rules
(`.claude/rules/`), the skills (`.claude/skills/` + `home/`), the export contract
(`tools/export.*` + manifest, security parity, staleness WARN), and one-command install
(`install/`).
