<!-- profile: core -->
# Change Protocol — High-Risk-Change Discipline

> Agile engineering principle: minimum bureaucracy, maximum defense-in-depth.
> **Manual protocol only for high-risk work.** Automated controls suffice for low-risk changes.

---

## 🔴 High-Risk Files (manual protocol REQUIRED)

BEFORE changing any of the following:

| File / structure | Why high-risk |
|---|---|
| `CLAUDE.md` | Loaded every session — a break affects the whole project |
| `POLICY.md` | Data policy — legal / compliance impact |
| `.claude/settings.json` | Hook changes = silent breakage |
| `.pre-commit-config.yaml` | CI/local gate — wrong config = "every commit fails" or "no checks at all" |
| `pyproject.toml` (tool config) | Test/lint/coverage breakage |
| `.claudeignore` | Wrong pattern = Claude cannot see a critical file |
| `tasks/` folder structure | Bulk file moves — reference-break risk |
| `docs/ARCHITECTURE.md` | Architecture tree — referenced from many other files |
| `.claude/agents/`, `.claude/skills/` core contents | Agent/skill behavior change |
| `alembic/versions/*.py` (production) | DB schema — hard to roll back |

---

## 🔄 Second Axis — Reversibility (one-way vs two-way door)

> The file-risk table above asks *"which file?"*. This axis asks *"how hard to undo?"*.
> They are **orthogonal**: a low-risk file can hold a one-way decision (a public API
> shape), and a high-risk file can hold a two-way one (a hook you can revert). **Rigor
> scales with irreversibility, not just which file changed.**

| Door | Means | Examples | Required rigor |
|---|---|---|---|
| 🟥 **One-way** | Hard/expensive to undo; others depend on it once shipped | DB schema / data migration, public API contract, framework or DB swap, deleting persisted data, a published URL scheme | Backup + `/verify` + **`/council`** (FOR/AGAINST/third-path) + a `decisions.md` entry with `Reversibility: one-way` |
| 🟩 **Two-way** | Cheap to revert; blast radius is internal | internal refactor, UI tweak, reversible config/hook, advisory script, doc edit | Normal flow; automatic gates (pre-commit + tests) are enough |

**Reversibility decay:** a door that is two-way today can become one-way later — e.g. a
new API field is reversible until external consumers depend on it; a URL scheme is
reversible until search engines index it. When a two-way door has accumulated
dependents, treat the *next* change to it as one-way. **When unsure, classify as
one-way** (over-rigor costs minutes; an un-undoable mistake costs far more).

## ✅ Protocol for high-risk changes

```bash
# 1. BACK UP (naming pattern: <name>.bak-YYYY-MM-DD)
cp <file> <file>.bak-$(date +%Y-%m-%d)
# or for a folder:
cp -r <folder> <folder>.bak-$(date +%Y-%m-%d)

# 2. MAKE THE CHANGE

# 3. THEN run /verify
# Double-check battery — 8 checks

# 4. Result:
#    PASS → proceed, commit
#    WARN → assess (are size_guard warnings acceptable?)
#    FAIL → rollback: cp <file>.bak-* <file>

# 5. Note in tasks/decisions.md (high-risk change = architectural decision)
```

---

## 🟢 Low-Risk Files (normal flow; automated controls suffice)

| Type | Automated control |
|---|---|
| Code files (.py, .tsx, .ts) | pre-commit (ruff/mypy/eslint) + py_compile + run_tests_for_file hook |
| `tasks/lessons.md`, `decisions.md` append | size_guard rotation warning |
| `docs/<X>.md` content (not structure) | size_guard >300 lines warning |
| `<module>/index.md` minor update | size_guard >60 lines warning |
| README, internal comments | Minor — pre-commit suffices |

**No extra protocol needed for low-risk.** Pre-commit + tests are enough.

---

## 🟡 Medium-Risk (judgment call)

- API router/schema changes (can break API contract)
- New DB migration file (lands in production)
- New frontend route (SEO, navigation impact)

For these: request a review from `@scraper-reviewer` or `@architect` agent, then run `/verify` **after** the change.

---

## ⚙️ Quick Commands

```bash
# Single-file backup
cp <file> <file>.bak-$(date +%Y-%m-%d)

# Folder backup
cp -r <dir> <dir>.bak-$(date +%Y-%m-%d)

# Run verify
# In Claude Code: /verify

# Rollback (restore from backup)
cp <file>.bak-2026-MM-DD <file>

# Clean up all backup files (once the project is stable)
find . -name "*.bak-*" -type f -delete
find . -name "*.bak-*" -type d -exec rm -rf {} +
```

---

## 📐 Principle

> **"Minimum bureaucracy, maximum defense-in-depth."**
>
> Running an 8-step check on every edit contradicts agile-shop principles. Instead:
> 1. Automated controls (hooks, pre-commit) **catch everything routine**
> 2. **High-risk** files get the manual protocol (backup + verify)
> 3. **`/verify` skill** runs the whole battery on demand with one command
> 4. **`tasks/decisions.md`** is the auditable decision record

Related files:
- `~/.claude/skills/verify/SKILL.md` — `/verify` skill
- `scripts/size_guard.py` — drift guard
- `.pre-commit-config.yaml` — automated gate
- `.claude/settings.json` — hooks
