#!/usr/bin/env python
"""new-project.py — Claude Code project bootstrap.

Usage:
    python ~/.claude/scripts/new-project.py /path/to/new-project [options]

Options:
    --name NAME           Project name (default: dir basename)
    --description DESC    Short description (one line)
    --tech STACK          Tech stack (e.g. "python+fastapi", "nextjs", "go")
    --frontend-port N     Frontend port (default: 3000)
    --backend-port N      Backend port (default: 8000)
    --dry-run             Show what would happen, don't write
    --install-deps        Run pip/npm install (default: skip — print commands)
    --skip-git            Skip git init

What it does:
    1. Copies template files from ~/.claude/templates/project-bootstrap/
    2. Fills placeholders ({{PROJECT_NAME}}, {{TECH_STACK}}, etc.)
    3. Renames *.template → final names
    4. Optionally runs `git init` + initial commit
    5. Optionally installs dev deps

Placeholders supported:
    {{PROJECT_NAME}}, {{PROJECT_DESCRIPTION}}, {{PROJECT_PATH}}
    {{TECH_STACK}}, {{LANG}}, {{LANG_LINT}}
    {{FRONTEND_PORT}}, {{BACKEND_PORT}}
    {{RUN_COMMANDS}}, {{DEV_SERVER_CMD}}
    {{COVERAGE_SOURCES}}, {{DATE}}
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from datetime import date
from pathlib import Path

# Windows console UTF-8 fix
if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

TEMPLATE_ROOT = Path(os.path.expanduser("~/.claude/templates/project-bootstrap"))


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Claude Code project bootstrap")
    p.add_argument("target", help="Target project path")
    p.add_argument("--name", help="Project name (default: dir basename)")
    p.add_argument("--description", default="New project — Claude Code template bootstrap", help="Short description")
    p.add_argument("--tech", default="Python 3.13", help="Tech stack")
    p.add_argument("--frontend-port", default="3000", help="Frontend port")
    p.add_argument("--backend-port", default="8000", help="Backend port")
    p.add_argument("--dry-run", action="store_true", help="Show actions, don't write")
    p.add_argument("--install-deps", action="store_true", help="Run pip/npm install")
    p.add_argument("--skip-git", action="store_true", help="Skip git init")
    p.add_argument(
        "--profile",
        default="core",
        choices=["core", "web", "scraper", "library", "gamedev", "trading"],
        help="Rule profile: seed only matching .claude/rules/ (default core). "
        "Non-core profiles are additive — they also include all core rules.",
    )
    return p.parse_args()


def build_placeholders(args: argparse.Namespace, target: Path) -> dict[str, str]:
    name = args.name or target.name
    is_python = "python" in args.tech.lower()
    is_node = any(k in args.tech.lower() for k in ["next", "node", "react", "vue", "javascript"])

    lang_lint = []
    if is_python: lang_lint.append("ruff + mypy + bandit")
    if is_node: lang_lint.append("tsc + eslint")
    lang_lint_str = " + ".join(lang_lint) if lang_lint else "linting"

    run_lines = []
    if is_python:
        run_lines.append("# Backend")
        run_lines.append(f"uvicorn api.main:app --reload --port {args.backend_port}")
        run_lines.append("pytest -v")
    if is_node:
        run_lines.append("# Frontend")
        run_lines.append(f"cd frontend && npm run dev -- --port {args.frontend_port}")

    coverage_sources = '", "'.join(["api", "scripts"]) if is_python else "src"

    return {
        "{{PROJECT_NAME}}": name,
        "{{PROJECT_DESCRIPTION}}": args.description,
        "{{PROJECT_PATH}}": str(target).replace("\\", "/"),
        "{{TECH_STACK}}": args.tech,
        "{{LANG}}": "python" if is_python else "javascript",
        "{{LANG_LINT}}": lang_lint_str,
        "{{FRONTEND_PORT}}": args.frontend_port,
        "{{BACKEND_PORT}}": args.backend_port,
        "{{RUN_COMMANDS}}": "\n".join(run_lines) if run_lines else "# Add your run commands here",
        "{{DEV_SERVER_CMD}}": run_lines[1] if run_lines else "# Dev server command",
        "{{COVERAGE_SOURCES}}": coverage_sources,
        "{{DATE}}": date.today().isoformat(),
    }


def fill_placeholders(content: str, placeholders: dict[str, str]) -> str:
    for k, v in placeholders.items():
        content = content.replace(k, v)
    return content


def copy_and_fill(src: Path, dst: Path, placeholders: dict[str, str], dry_run: bool):
    """Copy src to dst, fill placeholders, strip the .template suffix."""
    # Target path without the .template suffix
    if dst.name.endswith(".template"):
        dst = dst.parent / dst.name[: -len(".template")]

    if dry_run:
        print(f"  [DRY] {dst}")
        return

    dst.parent.mkdir(parents=True, exist_ok=True)

    # Binary or text?
    if src.suffix in (".py", ".md", ".json", ".yaml", ".yml", ".toml", ".txt", ".template"):
        content = src.read_text(encoding="utf-8")
        # If .template, fill placeholders
        if src.name.endswith(".template"):
            content = fill_placeholders(content, placeholders)
        dst.write_text(content, encoding="utf-8")
    else:
        shutil.copy2(src, dst)
    print(f"  + {dst.relative_to(dst.parents[len(dst.parts) - 2])}")


def _rule_profile(src: Path) -> str:
    """Read a rule file's `<!-- profile: X -->` header (default 'core' if untagged)."""
    try:
        first = src.read_text(encoding="utf-8").lstrip().splitlines()[0]
    except Exception:
        return "core"
    if first.startswith("<!-- profile:") and "-->" in first:
        return first.split("profile:", 1)[1].split("-->", 1)[0].strip().lower()
    return "core"  # untagged rules are always seeded (fail-safe, never silently drop)


def include_rule(src: Path, profile: str) -> bool:
    """Filter for `.claude/rules/*.md`. Core rules always load; a non-core profile
    additively includes its own rules. Non-rule files are never filtered here."""
    parts = src.parts
    if ".claude" not in parts or "rules" not in parts or src.suffix != ".md":
        return True
    tier = _rule_profile(src)
    return tier == "core" or tier == profile


def walk_template(src_root: Path, dst_root: Path, placeholders: dict[str, str],
                  dry_run: bool, profile: str = "core"):
    """Walk the template directory and copy each file to dst, honoring the rule profile."""
    skipped = 0
    for src in src_root.rglob("*"):
        if src.is_dir():
            continue
        if not include_rule(src, profile):
            print(f"  - skip (profile={profile}): {src.relative_to(src_root)}")
            skipped += 1
            continue
        rel = src.relative_to(src_root)
        dst = dst_root / rel
        copy_and_fill(src, dst, placeholders, dry_run)
    if skipped:
        print(f"  ({skipped} rule(s) skipped for profile '{profile}')")


def maybe_git_init(target: Path, dry_run: bool):
    if (target / ".git").exists():
        print("  ✓ Git already initialized, skipping")
        return
    if dry_run:
        print("  [DRY] git init + initial commit")
        return
    try:
        subprocess.run(["git", "init"], cwd=target, check=True, capture_output=True)
        subprocess.run(["git", "add", "."], cwd=target, check=True, capture_output=True)
        subprocess.run(
            ["git", "commit", "-m", "chore: bootstrap Claude Code project template"],
            cwd=target, check=True, capture_output=True,
        )
        print("  ✓ Git init + initial commit")
    except subprocess.CalledProcessError as e:
        print(f"  ⚠ Git init failed: {e}")


def maybe_install_deps(target: Path, args: argparse.Namespace, dry_run: bool):
    has_requirements = (target / "requirements-dev.txt").exists()
    has_package_json = (target / "package.json").exists()

    print("\n── External tools ──")
    print("  pip install -r requirements-dev.txt  # Python dev tools")
    print("  pre-commit install                    # activate git hooks")
    print("  npm install -g ccusage ccstatusline   # monitoring")
    print("  npm install -g context-mode repomix   # token optimization")

    if not args.install_deps:
        print("\n  ℹ --install-deps not given; skipping. Run the commands above manually.")
        return

    if has_requirements and not dry_run:
        print("\n  running pip install -r requirements-dev.txt...")
        subprocess.run(["pip", "install", "-r", "requirements-dev.txt"], cwd=target)


def main() -> int:
    args = parse_args()
    target = Path(args.target).resolve()

    if not TEMPLATE_ROOT.exists():
        print(f"ERR: Template root missing: {TEMPLATE_ROOT}", file=sys.stderr)
        return 1

    if target.exists() and any(target.iterdir()):
        # Warn if not empty
        files = list(target.iterdir())
        if any(f.name == "CLAUDE.md" for f in files):
            print(f"⚠ {target} already looks like a Claude Code project (CLAUDE.md exists).")
            ans = input("Overwrite? (yes/no): ").strip().lower()
            if ans != "yes":
                print("Cancelled.")
                return 0

    target.mkdir(parents=True, exist_ok=True)
    placeholders = build_placeholders(args, target)

    print(f"═══════════════════════════════════════════════════════")
    print(f"   Bootstrap: {target.name}")
    print(f"═══════════════════════════════════════════════════════")
    print(f"  Target:      {target}")
    print(f"  Tech:        {args.tech}")
    print(f"  Ports:       FE={args.frontend_port}, BE={args.backend_port}")
    print(f"  Profile:     {args.profile}  (rule tier)")
    print(f"  Dry-run:     {args.dry_run}")
    print(f"")
    print(f"── Copying template ──")

    walk_template(TEMPLATE_ROOT, target, placeholders, args.dry_run, args.profile)

    print(f"")
    print(f"── Git ──")
    if not args.skip_git:
        maybe_git_init(target, args.dry_run)
    else:
        print("  (--skip-git)")

    maybe_install_deps(target, args, args.dry_run)

    print(f"")
    print(f"═══════════════════════════════════════════════════════")
    print(f"   Bootstrap COMPLETE")
    print(f"═══════════════════════════════════════════════════════")
    print(f"  Next:")
    print(f"    1. cd {target}")
    print(f"    2. pip install -r requirements-dev.txt")
    print(f"    3. pre-commit install")
    print(f"    4. Update CLAUDE.md with project details")
    print(f"    5. In Claude Code: /onboard")
    print(f"═══════════════════════════════════════════════════════")

    return 0


if __name__ == "__main__":
    sys.exit(main())
