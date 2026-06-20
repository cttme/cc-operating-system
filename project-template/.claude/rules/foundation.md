<!-- profile: core -->
# Foundation — How to Add New Code

> The "how" — checklist before adding files, endpoints, tables, or dependencies.
> Generic baseline (backported from düzhesap). Add stack-specific rules as the
> project earns them; promote recurring ones via `/retro` → BACKPORT.md.

## Before adding a new file

1. **Does it fit an existing module?** Check `<module>/index.md` first — most new
   code belongs in an existing top-level module dir.
2. **If not** — create a new module directory **with an `index.md`** (1-line
   purpose + 1-line-per-file list) in the same commit, and add it to CLAUDE.md's
   "Module indices" table.
3. Update the relevant `<module>/index.md` with the new file's 1-line purpose.

## File-size limits

- **Target: ≤ 300 lines.** Plan splits before a file crosses this.
- **Hard ceiling: 500 lines.** Beyond 300, add `# === Section: <name>` (Python)
  or `// === Section: <name>` (TS/TSX) anchors so Grep/partial-Read can navigate.
- Test files follow the same limits — split by scenario group, not by convenience.

## Adding an API endpoint

- Validate ID path params (reject ≤ 0 / non-existent before use).
- POST/mutating endpoints need a rate limit; admin endpoints need an auth guard.
- Update the API module's `index.md` with the new route.
- If it changes the API contract (new required field, removed field, auth
  change) — log it in `tasks/decisions.md`, not just the commit message.

## Adding a DB table / column

- New migration in the project's migration dir + entry in its `index.md`.
- Update the data-layer `index.md` (models, repository).
- Never silently drop or rename a column carrying historical/audit data.

## Adding a dependency

- Justify in the commit message (why this dep, not a smaller alternative or
  stdlib).
- Check install/bundle impact: backend deps via a CVE audit; heavy frontend deps
  stay behind lazy/dynamic imports.
- Dependency bumps are their own commit — don't mix with feature work.

## When in doubt

- 3+ step task → `/plan` first.
- Touching a HIGH-RISK file (CLAUDE.md, `.claude/rules/`, `.pre-commit-config.yaml`,
  migrations, auth) → `.claude/rules/change-protocol.md` (backup + `/verify`).
- Sweep ≥ 30 items or file > 300 lines to read → `/ask-local` triage first.
- One-way-door decision (schema, public API contract, framework) → extra rigor;
  see `change-protocol.md` reversibility axis.
