# Portability Manifest — What Ships, What You Rewrite

> This repo packages a **workflow operating system** for Claude Code. Not every
> piece is domain-agnostic. This manifest tags each rule and skill **PORTABLE**,
> **MIXED**, or **PROJECT** so you know what to copy as-is vs. rewrite for your
> own project.
>
> This file is **repo-owned** (hand-maintained) — `tools/export.sh` does not
> overwrite it. Update it whenever a rule or skill is added or removed.

## Legend

- **PORTABLE** — domain-agnostic; ships in this repo, use as-is.
- **MIXED** — the *principle* is portable but the concrete content (paths,
  thresholds, module names) is project-specific; ships as a starting point,
  rewrite the specifics.
- **PROJECT** — specific to the origin project (düzhesap, a Turkish
  e-commerce price-comparison platform that served as the testbed). **These do
  NOT ship here** — they are listed as *worked examples* of the classification
  so you can see what "write your own" looks like.

## Rules (`project-template/.claude/rules/`)

| Rule | Tag | Ships? | Notes |
|---|---|---|---|
| `thinking-pipeline.md` | **PORTABLE** | ✅ | Lifecycle + reversibility selector + shared output contract. The spine. |
| `change-protocol.md` | **PORTABLE** | ✅ | Reversibility axis (one-way/two-way door) + high-risk-file protocol. The file list is project-tunable; the doc says so. |
| `foundation.md` | **MIXED** | ✅ | "Which checker when", lifecycle stages, twin-gate scope-confirm are portable; the module-directory list is an example — replace with yours. |
| `frontend-safety.md` | **MIXED** | ✅ | Generic web-frontend safety seed (JSON-LD, auth-token handling, modal a11y); trim to your stack. |
| `webapp-pitfalls.md` | **MIXED** | ✅ | Profile pack — common web-app traps. Seeded by `--profile web`. |
| `gamedev-pitfalls.md` | **MIXED** | ✅ | Profile pack — game-dev traps. |
| `trading-pitfalls.md` | **MIXED** | ✅ | Profile pack — trading/quant traps. |
| `data-integrity.md` | PROJECT | ❌ example | Fuzzy-matcher thresholds, barcode/name matching priority — domain internals. |
| `scraper-safety.md` | PROJECT | ❌ example | Site-specific scraping rules (anti-bot, Playwright requirements). |
| `review-sources.md` | PROJECT | ❌ example | Specific review-site scraping quirks. |
| `numeric-safety.md` | PROJECT | ❌ example | Price/forecast numeric rules for that domain. |

## Skills (`home/skills/`)

| Skill | Tag | Role |
|---|---|---|
| `triz/` | **PORTABLE** | **frame** — surface the real contradiction before planning. |
| `hats/` | **PORTABLE** | **decide** — evaluate a plan from multiple role perspectives. |
| `council/` | **PORTABLE** | **decide** — adversarial review for one-way doors. |
| `verify/` | **PORTABLE** | **verify** — mechanical health battery. |
| `retro/` | **PORTABLE** | **reflect** — work-style meta-review; lessons → rules. |
| `spec/` | **PORTABLE** | spec-first ritual for one-way-door features. |
| `onboard/` · `session-end/` | **PORTABLE** | session bookkeeping (load state / write handoff). |
| `bootstrap-project/` · `kickoff/` | **PORTABLE** | new-project setup + project-zero interview. |
| `ask-local/` · `double-stitch/` | **PORTABLE** | route work to a local model + validate its output. |
| `cave/` · `normal/` | **PORTABLE** | output-verbosity modes. |
| `commit.md` · `plan.md` · `review.md` | **PORTABLE** | commit / plan / review helpers. |

## Other portable infrastructure

- **Reversibility axis** (one-way vs two-way door) — `change-protocol.md`.
- **Verify-first / twin-gate** (scope-confirm before, done-gate check after) — `foundation.md`.
- **Model-routing advisory hook** (`scripts/model_routing_hint.py` — detect the active
  model, nudge mechanical work to a cheaper tier). Regex list is project-tunable.
- **One-way-door hint hook** (`scripts/one_way_door_hint.py` — warn before editing
  irreversible surfaces).
- **Cross-project playbooks** — `docs/ENGINEERING_PATTERNS.md` (universal habits incl.
  the `EXCEPTION WHEN OTHERS` / no-silent-failure discipline) and `docs/DELEGATION_GATES.md`
  (what Claude may do unprompted).
- **Memory protocol** — `~/.claude/projects/<project>/memory/` + a `MEMORY.md` index
  + `[[wikilink]]` cross-refs.

## When extracting to your project

1. **Copy PORTABLE** rules/skills verbatim — they need no edits.
2. **For MIXED**, copy then replace the project-specific bits (paths, thresholds, module
   lists) with your equivalents.
3. **Skip PROJECT** entries — write your own once you understand *your* domain's risks.
   Don't cargo-cult another project's matcher/scraper rules onto an unrelated codebase.
4. **Re-run `/retro`** after a few milestones to confirm the pipeline is actually earning
   its keep on your project — portability does not imply value.

> **Firewall (SEC-P7):** `~/.claude/memory/`, `~/.claude/plans/`, session transcripts
> (`~/.claude/projects/`), and live `tasks/` state are **never** export sources for this
> repo — they carry PII, business data, and session content. See `tools/export.sh` header.
