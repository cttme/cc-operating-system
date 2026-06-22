#!/usr/bin/env bash
# export.sh — re-runnable snapshot exporter.
#
# Copies + sanitizes the live Claude Code "workflow operating system" from
# ~/.claude/ (global) and D:/cc/Mantikli/.claude/ (project) into this repo's
# home/, project-template/, docs/, and PORTABILITY.md.
#
# Safe to re-run repeatedly: destination subtrees are wiped (rm -rf) before
# each copy, and the sed sanitization rules are idempotent.
#
# Must be run in Git Bash (POSIX sh) on Windows, or any POSIX shell elsewhere.

set -euo pipefail

# --- paths -------------------------------------------------------------
HOME_CLAUDE="${HOME_CLAUDE:-$HOME/.claude}"
MANTIKLI_CLAUDE="${MANTIKLI_CLAUDE:-/d/cc/Mantikli/.claude}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DEST_SKILLS="$REPO_ROOT/home/skills"
DEST_SCRIPTS="$REPO_ROOT/home/scripts"
DEST_TEMPLATE="$REPO_ROOT/project-template"
DEST_DOCS="$REPO_ROOT/docs"
DEST_PORTABILITY="$REPO_ROOT/PORTABILITY.md"

SRC_SKILLS="$HOME_CLAUDE/skills"
SRC_SCRIPTS="$HOME_CLAUDE/scripts"
SRC_TEMPLATE="$HOME_CLAUDE/templates/project-bootstrap"
SRC_MANTIKLI_SKILLS="$MANTIKLI_CLAUDE/skills"
SRC_PORTABILITY="$MANTIKLI_CLAUDE/rules/PORTABILITY.md"

# --- counters ------------------------------------------------------------
SKILLS_COPIED=0
SCRIPTS_COPIED=0
NESTED_REMOVED=0
SED_APPLIED=0
SED_NOT_FOUND=0

echo "==> Exporting workflow OS snapshot into $REPO_ROOT"

# =========================================================================
# a. home/skills/
# =========================================================================
echo "--> [a] home/skills/"
rm -rf "$DEST_SKILLS"
mkdir -p "$DEST_SKILLS"

# Copy from ~/.claude/skills/ excluding audit-*, __pycache__, *.bak-*
if [ -d "$SRC_SKILLS" ]; then
    for entry in "$SRC_SKILLS"/*; do
        [ -e "$entry" ] || continue
        base="$(basename "$entry")"
        case "$base" in
            audit-*|__pycache__|*.bak-*)
                continue
                ;;
        esac
        if [ -d "$entry" ]; then
            cp -r "$entry" "$DEST_SKILLS/$base"
            SKILLS_COPIED=$((SKILLS_COPIED + 1))
        elif [ -f "$entry" ]; then
            cp "$entry" "$DEST_SKILLS/$base"
        fi
    done
fi

# Clean any __pycache__ / *.bak-* that came along inside copied skill dirs
find "$DEST_SKILLS" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find "$DEST_SKILLS" -name "*.bak-*" -exec rm -rf {} + 2>/dev/null || true

# Critical dedupe: remove nested <name>/<name>/ subdirs (stale cruft)
for d in "$DEST_SKILLS"/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    nested="$d$name"
    if [ -d "$nested" ]; then
        rm -rf "$nested"
        NESTED_REMOVED=$((NESTED_REMOVED + 1))
        echo "    removed nested dir: $name/$name"
    fi
done

# Also copy cave/, normal/, review.md from Mantikli's local skills
if [ -d "$SRC_MANTIKLI_SKILLS/cave" ]; then
    cp -r "$SRC_MANTIKLI_SKILLS/cave" "$DEST_SKILLS/cave"
    SKILLS_COPIED=$((SKILLS_COPIED + 1))
fi
if [ -d "$SRC_MANTIKLI_SKILLS/normal" ]; then
    cp -r "$SRC_MANTIKLI_SKILLS/normal" "$DEST_SKILLS/normal"
    SKILLS_COPIED=$((SKILLS_COPIED + 1))
fi
if [ -f "$SRC_MANTIKLI_SKILLS/review.md" ]; then
    cp "$SRC_MANTIKLI_SKILLS/review.md" "$DEST_SKILLS/review.md"
fi

# =========================================================================
# b. home/scripts/
# =========================================================================
echo "--> [b] home/scripts/"
rm -rf "$DEST_SCRIPTS"
mkdir -p "$DEST_SCRIPTS"

if [ -d "$SRC_SCRIPTS" ]; then
    for entry in "$SRC_SCRIPTS"/*; do
        [ -e "$entry" ] || continue
        base="$(basename "$entry")"
        case "$base" in
            __pycache__|*.bak-*)
                continue
                ;;
        esac
        if [ -d "$entry" ]; then
            cp -r "$entry" "$DEST_SCRIPTS/$base"
        else
            cp "$entry" "$DEST_SCRIPTS/$base"
        fi
        SCRIPTS_COPIED=$((SCRIPTS_COPIED + 1))
    done
fi

# Clean stray __pycache__ / *.bak-* inside copied scripts subtree
find "$DEST_SCRIPTS" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find "$DEST_SCRIPTS" -name "*.bak-*" -exec rm -rf {} + 2>/dev/null || true

# =========================================================================
# c. home/CLAUDE.md.example — repo-owned, NOT auto-synced.
# =========================================================================
# The repo's CLAUDE.md.example is a deliberately GENERICIZED English template
# (titled EXAMPLE, with install.sh notes). $SRC_CLAUDE_MD is the maintainer's
# raw personal ~/.claude/CLAUDE.md (language-specific, contains private prefs),
# so a verbatim copy would (a) revert the genericization and (b) leak personal
# config into the repo. Edit CLAUDE.md.example by hand — same as PORTABILITY.md.
echo "--> [c] home/CLAUDE.md.example (repo-owned — skipped, not auto-synced)"

# =========================================================================
# d. project-template/
# =========================================================================
echo "--> [d] project-template/"
rm -rf "$DEST_TEMPLATE"
mkdir -p "$DEST_TEMPLATE"

if [ -d "$SRC_TEMPLATE" ]; then
    # Copy ALL contents including dotfiles/dotdirs (.claude/, .claudeignore.template,
    # .pre-commit-config.yaml.template) — a plain `$SRC/*` glob silently skips hidden
    # entries, which would drop the rules + hooks that ARE the operating system.
    cp -r "$SRC_TEMPLATE/." "$DEST_TEMPLATE/"
    # Then remove the excluded items from the destination.
    rm -rf "$DEST_TEMPLATE/.git" \
           "$DEST_TEMPLATE/.preflight" \
           "$DEST_TEMPLATE/BACKPORT.md" \
           "$DEST_TEMPLATE/ENGINEERING_PATTERNS.md" \
           "$DEST_TEMPLATE/DELEGATION_GATES.md"
fi

# Clean any nested .git / __pycache__ / *.bak-* / .preflight that came along
find "$DEST_TEMPLATE" -type d -name ".git" -exec rm -rf {} + 2>/dev/null || true
find "$DEST_TEMPLATE" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find "$DEST_TEMPLATE" -type d -name ".preflight" -exec rm -rf {} + 2>/dev/null || true
find "$DEST_TEMPLATE" -name "*.bak-*" -exec rm -rf {} + 2>/dev/null || true

# =========================================================================
# e. docs/
# =========================================================================
echo "--> [e] docs/"
mkdir -p "$DEST_DOCS"
if [ -f "$SRC_TEMPLATE/ENGINEERING_PATTERNS.md" ]; then
    cp "$SRC_TEMPLATE/ENGINEERING_PATTERNS.md" "$DEST_DOCS/ENGINEERING_PATTERNS.md"
fi
if [ -f "$SRC_TEMPLATE/DELEGATION_GATES.md" ]; then
    cp "$SRC_TEMPLATE/DELEGATION_GATES.md" "$DEST_DOCS/DELEGATION_GATES.md"
fi
# BACKPORT.md deliberately dropped — Mantikli-internal, never copied anywhere.

# =========================================================================
# f. PORTABILITY.md — repo-owned, NOT auto-synced.
# =========================================================================
# The repo's PORTABILITY.md is adapted (it documents what THIS repo ships +
# keeps the source project's rows as labeled examples). The source manifest at
# $SRC_PORTABILITY lists project-only rules that this repo does not ship, so a
# verbatim copy would reference missing files. Edit PORTABILITY.md by hand.
echo "--> [f] PORTABILITY.md (repo-owned — skipped, not auto-synced)"

# =========================================================================
# g. sed sanitization (idempotent — applied to COPIED files only)
# =========================================================================
echo "--> [g] sed sanitization"

VERIFY_SKILL="$DEST_SKILLS/verify/SKILL.md"
SESSION_END_SKILL="$DEST_SKILLS/session-end/SKILL.md"
ASK_LOCAL_SKILL="$DEST_SKILLS/ask-local/SKILL.md"

# g1. verify/SKILL.md — "Mantikli `/clear` öncesi:" line → "Before `/clear`:"
if [ -f "$VERIFY_SKILL" ] && grep -q 'Mantikli.*`/clear`.*öncesi:' "$VERIFY_SKILL"; then
    sed -i -E 's/.*Mantikli.*`\/clear`.*öncesi:.*/- **Before `\/clear`:** Devir öncesi son sağlık kontrolu/' "$VERIFY_SKILL"
    SED_APPLIED=$((SED_APPLIED + 1))
    echo "    [applied] verify/SKILL.md: Mantikli /clear line"
else
    SED_NOT_FOUND=$((SED_NOT_FOUND + 1))
    echo "    [NOT FOUND] verify/SKILL.md: Mantikli /clear line"
fi

# g2. session-end/SKILL.md — "Eski mekanizma fallback — Mantikli'de /onboard..." line
if [ -f "$SESSION_END_SKILL" ] && grep -q "Eski mekanizma fallback.*Mantikli'de /onboard kullanmazsa kullanıcı kopyala-yapıştır için:" "$SESSION_END_SKILL"; then
    sed -i "s/Eski mekanizma fallback.*Mantikli'de \/onboard kullanmazsa kullanıcı kopyala-yapıştır için:/Fallback mechanism — if \/onboard isn't used, for copy-paste:/" "$SESSION_END_SKILL"
    SED_APPLIED=$((SED_APPLIED + 1))
    echo "    [applied] session-end/SKILL.md: fallback line"
else
    SED_NOT_FOUND=$((SED_NOT_FOUND + 1))
    echo "    [NOT FOUND] session-end/SKILL.md: fallback line"
fi

# g3. ask-local/SKILL.md — düzhesap parenthetical (spans two lines in source)
if [ -f "$ASK_LOCAL_SKILL" ] && grep -q 'düzhesap' "$ASK_LOCAL_SKILL"; then
    # Collapse the two-line parenthetical into the sanitized single replacement.
    # Source pattern (across 2 lines):
    #   ... (Project-specific examples in düzhesap: `matcher/fuzzy` match
    #   decisions, price & stock calls, `POLICY.md`.) A YELLOW ...
    perl -0pi -e "s/\(Project-specific examples in düzhesap: \`matcher\/fuzzy\` match\s*\n\s*decisions, price & stock calls, \`POLICY\.md\`\.\)/(Project-specific examples: record-matching decisions, money\/pricing calls, your policy doc.)/" "$ASK_LOCAL_SKILL" 2>/dev/null \
        && SED_APPLIED=$((SED_APPLIED + 1)) \
        && echo "    [applied] ask-local/SKILL.md: düzhesap parenthetical" \
        || { SED_NOT_FOUND=$((SED_NOT_FOUND + 1)); echo "    [NOT FOUND] ask-local/SKILL.md: düzhesap parenthetical"; }
else
    SED_NOT_FOUND=$((SED_NOT_FOUND + 1))
    echo "    [NOT FOUND] ask-local/SKILL.md: düzhesap parenthetical"
fi

# =========================================================================
# Summary
# =========================================================================
echo ""
echo "==> Export summary"
echo "    skills copied:        $SKILLS_COPIED"
echo "    scripts/files copied: $SCRIPTS_COPIED"
echo "    nested dirs removed:  $NESTED_REMOVED"
echo "    sed replacements applied:   $SED_APPLIED"
echo "    sed replacements NOT found: $SED_NOT_FOUND"
echo "==> Done."
