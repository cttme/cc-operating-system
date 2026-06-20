# Architecture — How the Operating System Fits Together

This document maps the parts and the two places they live. For the *why* (the
philosophy) see the [README](../README.md); for *what's portable* see
[PORTABILITY.md](../PORTABILITY.md).

## The two-home model

Claude Code reads configuration from two locations, and this system uses both:

```
~/.claude/                         ← GLOBAL: shared by every project on the machine
├── skills/                        slash-command skills (/triz, /verify, /onboard, …)
├── scripts/                       global tooling (new-project.py, ask-local, …)
├── CLAUDE.md                      your personal preferences (loaded every session)
└── templates/project-bootstrap/   the project scaffold new-project.py copies from

<your-project>/                    ← PER-PROJECT: scoped to one repo
├── .claude/
│   ├── rules/                     auto-loaded rules (thinking-pipeline, change-protocol, …)
│   └── settings.json              hooks (SessionStart, model-routing, guards)
├── scripts/                       the hook scripts the rules/hooks invoke
├── tasks/                         handoff, todo, lessons, decisions (the project's memory)
└── docs/                          PRODUCT / ARCHITECTURE for that project
```

**Why split?** Skills and personal preferences are the same everywhere, so they belong
in the global home. Rules, hooks, and task-state are project-scoped — a scraping project
and a game need different pitfall rules — so they belong in the repo. This repo mirrors
the split: `home/` → `~/.claude/`, `project-template/` → a project (and into
`~/.claude/templates/project-bootstrap/` so the bootstrap engine can reuse it).

## Component map

| Component | Lives in | Role |
|---|---|---|
| **Thinking-pipeline skills** | `home/skills/` | the lifecycle tools (frame/decide/verify/reflect) |
| **Lifecycle skills** | `home/skills/` | `onboard` / `session-end` — load & persist session state |
| **Bootstrap skills** | `home/skills/` | `bootstrap-project` (scaffold) + `kickoff` (project-zero interview) |
| **Local-model skills** | `home/skills/` | `ask-local` (route to Ollama) + `double-stitch` (validate its output) |
| **Rules** | `project-template/.claude/rules/` | auto-loaded judgment: lifecycle, reversibility, foundation, pitfall packs |
| **Hooks** | `project-template/.claude/settings.json.template` | SessionStart status, model-routing nudge, one-way-door warning, write/bash guards |
| **Hook scripts** | `project-template/scripts/` | `size_guard`, `model_routing_hint`, `one_way_door_hint`, `check_*`, `cost_breakdown`, … |
| **Bootstrap engine** | `home/scripts/new-project.py` | copies the template, fills placeholders, seeds the right rule profile |
| **Task state** | `project-template/tasks/` | handoff (next-task brief), todo, lessons, decisions |
| **Memory** | `~/.claude/projects/<project>/memory/` | durable facts + `MEMORY.md` index (documented; created at runtime) |

## The lifecycle, mapped to tools

```
onboard ─▶ frame ─▶ plan ─▶ decide ─▶ execute ─▶ verify+doublecheck ─▶ commit ─▶ reflect
/onboard   /triz    /plan    /hats     (model-    /verify               (gate)    /retro
                    /spec    /council   routed)
```

The selector in `thinking-pipeline.md` decides *how much* of the pipeline a task gets,
keyed on **reversibility × stakes** (see the README's selector table). Trivial two-way
work skips the pipeline; one-way doors run all of it plus a `decisions.md` record.

## How `install.sh` reconstructs the layout

```
home/skills/        ─▶ ~/.claude/skills/
home/scripts/       ─▶ ~/.claude/scripts/
home/CLAUDE.md.example ─▶ ~/.claude/CLAUDE.md         (backed up if present)
project-template/   ─▶ ~/.claude/templates/project-bootstrap/   (so new-project.py works)
project-template/   ─▶ <--target>/                   (scaffold the actual project)
```

Restoring `project-template/` to `~/.claude/templates/project-bootstrap/` is what lets
the shipped `new-project.py` run **unmodified** — it reads from exactly that path. The
installer backs up existing global dirs (or refuses without `--force`), because it writes
into the *adopter's* global config — the same care the system applies to its own.

## How `export.sh` keeps the snapshot fresh (author only)

`export.sh` is a one-way copy **from** live config **into** this repo. It is re-runnable
and self-cleaning:

- copies `~/.claude/skills`, `~/.claude/scripts`, `~/.claude/CLAUDE.md`, and
  `~/.claude/templates/project-bootstrap/` into `home/` and `project-template/`;
- **drops stale nested `<skill>/<skill>/` dirs** (an artifact of how some skills were
  saved — only the outer `SKILL.md` is loaded by Claude Code);
- strips `.git`, `__pycache__`, `*.bak-*`, `.preflight`;
- **re-applies sanitization every run** (the live source still contains origin-project
  references, so a one-time clean would not survive the next export);
- leaves repo-owned docs (`README.md`, `docs/ARCHITECTURE.md`, `PORTABILITY.md`,
  `LICENSE`) untouched.

It never writes to the live config — the snapshot strategy keeps `~/.claude/` as the
working source of truth and this repo as the publishable copy.
