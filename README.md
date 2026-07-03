# cc-operating-system

A reusable **workflow operating system** for [Claude Code](https://claude.com/claude-code) —
a thinking pipeline, a reversibility-based rigor selector, model-routing discipline, a
memory protocol, and one-command project bootstrap. Distilled from many sessions on a
real production project and packaged so you can drop it onto a new one.

> **Thesis:** most agent mistakes are not coding mistakes — they are *scope* and
> *judgment* mistakes made before any code is written, and *unverified* claims made
> after. This system front-loads framing and back-loads verification, and spends
> expensive rigor only where a decision is hard to undo.

---

## The core ideas

**1. A per-task lifecycle.** Every non-trivial task flows through explicit stages, each
with a tool:

```
onboard → frame → plan → decide → execute → verify + doublecheck → commit → reflect
```

| Stage | Tool | Purpose |
|---|---|---|
| onboard | `/onboard` | load state, surface the next task |
| **frame** | `/triz` | state the real contradiction; don't accept a trade-off you can dissolve |
| plan | `/plan`, `/spec` | step plan; every claim cites evidence (`file:line`, command output) |
| decide | `/hats`, `/council` | evaluate from roles / adversarial decide |
| execute | (model-routed) | do the work at the right model tier |
| verify + **doublecheck** | `/verify` | mechanical battery + gap-hunt against done-gates |
| commit | (pre-commit gate) | gated; closing a task updates the todo list in the *same* commit |
| reflect | `/retro` | write lessons back into the rules |

`frame` and `doublecheck` are the two stages most workflows skip — and where most
wrong-problem and missed-scope errors get caught.

**2. Rigor scales with reversibility, not file size.** Classify each change as a
**one-way door** (hard to undo: schema, public API, data migration, a published URL
scheme) or a **two-way door** (refactor, UI tweak, reversible config). Two-way work
flows fast; one-way work gets the expensive ceremony (spec, `/council`, a decision
record). When unsure, treat it as one-way — over-rigor costs minutes, an un-undoable
mistake doesn't.

| Situation | Pipeline | Model tier |
|---|---|---|
| trivial / two-way | skip — just do it | cheap model / local |
| meaningful / two-way | lightweight inline (`/triz` + `/hats`, single pass) | mid model (top model only for algo / data-integrity) |
| one-way door or major bet | full pipeline (`/triz` + `/hats` + `/council` + decision record) | top model |

**3. Model routing.** Mechanical work (renames, sweeps, scaffolding, dep bumps) is
*dispatched to a cheaper-model subagent* rather than run on the top model — and you
*dispatch, don't switch*, to keep the main session's prompt cache and context intact. An
advisory hook nudges you when a task looks mechanical.

**4. Memory + lessons.** Corrections become lessons; recurring lessons get promoted to
durable rules in `.claude/rules/`. A per-project memory directory holds facts that
outlive a single session.

---

## What's in the box

```
cc-operating-system/
├── home/                  → installs into ~/.claude/ (global, all projects)
│   ├── skills/            the pipeline tools: triz, hats, council, verify, retro,
│   │                      spec, onboard, session-end, bootstrap-project, kickoff,
│   │                      ask-local, double-stitch, cave, normal (+ commit/plan/review)
│   ├── scripts/           new-project.py (bootstrap engine) + local-model tooling
│   └── CLAUDE.md.example  example global preferences — edit to taste
├── project-template/      → scaffolded into each project
│   ├── .claude/rules/     thinking-pipeline, change-protocol, foundation, + pitfall packs
│   ├── .claude/settings.json.template   hooks (model-routing, one-way-door, guards)
│   ├── scripts/           the hook scripts (size_guard, model_routing_hint, …)
│   └── tasks/ docs/       handoff / todo / lessons / decisions templates
├── install/               install.sh / install.ps1 — set up an adopter machine
├── tools/                 export.sh / export.ps1 — re-sync the snapshot from live config
├── docs/                  ARCHITECTURE.md + cross-project playbooks
└── PORTABILITY.md         what's PORTABLE vs MIXED vs PROJECT
```

The system lives in **two homes**: global tools in `~/.claude/` (shared by every
project) and per-project rules/hooks/tasks in each project's `.claude/`. The installer
reconstructs both. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

---

## Install

```bash
# Preview what will be written — touches nothing:
bash install/install.sh --dry-run --target /path/to/your/project

# Install the global layer + scaffold a project:
bash install/install.sh --target /path/to/your/project
```

`install.sh` backs up any existing `~/.claude/skills`, `~/.claude/scripts`, and
`~/.claude/templates/project-bootstrap` before writing (or pass `--force`). On Windows
without Git Bash, use `install/install.ps1`.

Then, in a new Claude Code session inside your project:

```
/kickoff     # project-zero interview → a one-page constitution + decision #0
/onboard     # load state and surface the first task
```

---

## Maintaining the snapshot (for the author)

This repo is a **best-effort snapshot** of a live system, exported via `tools/export.sh` —
the live machine (`~/.claude/` + the source project's `.claude/`) is authoritative, not
this repo. To refresh it after changing your live skills/rules/scripts:

```bash
bash tools/export.sh
```

`export.sh` is re-runnable: it wipes and recopies each destination subtree, drops stale
nested-skill cruft, strips `.git`/`__pycache__`/backups, and re-applies sanitization. It
does **not** touch your live config (one-way copy), and it leaves the repo-owned docs
(`README.md`, `docs/ARCHITECTURE.md`, `PORTABILITY.md`, `LICENSE`) alone.

---

## Origin & license

Built and battle-tested on **düzhesap**, a Turkish e-commerce price-comparison platform,
then generalized. Worked examples in the docs reference that project — they illustrate
the pattern; adapt them to yours. See [PORTABILITY.md](PORTABILITY.md) for what's generic
vs. project-specific.

MIT — see [LICENSE](LICENSE).
