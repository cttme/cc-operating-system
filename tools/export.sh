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
GITLEAKS_STATUS="not run"
MANIFEST_STATUS="not run"
PARITY_STATUS="not run"
STALE_COUNT=0

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

# Also copy cave/, normal/, review/ from Mantikli's local skills.
# review was converted from a flat review.md to Agent-Skill dir form
# (review/SKILL.md, R13 spillover) — prefer the dir, fall back to the
# legacy flat file so an un-migrated project still exports.
if [ -d "$SRC_MANTIKLI_SKILLS/cave" ]; then
    cp -r "$SRC_MANTIKLI_SKILLS/cave" "$DEST_SKILLS/cave"
    SKILLS_COPIED=$((SKILLS_COPIED + 1))
fi
if [ -d "$SRC_MANTIKLI_SKILLS/normal" ]; then
    cp -r "$SRC_MANTIKLI_SKILLS/normal" "$DEST_SKILLS/normal"
    SKILLS_COPIED=$((SKILLS_COPIED + 1))
fi
if [ -d "$SRC_MANTIKLI_SKILLS/review" ]; then
    cp -r "$SRC_MANTIKLI_SKILLS/review" "$DEST_SKILLS/review"
    SKILLS_COPIED=$((SKILLS_COPIED + 1))
elif [ -f "$SRC_MANTIKLI_SKILLS/review.md" ]; then
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
           "$DEST_TEMPLATE/DELEGATION_GATES.md" \
           "$DEST_TEMPLATE/STATUS.md"
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
# STATUS.md deliberately dropped — a maintainer note ABOUT copy B itself
# (freeze status, authoritative-source pointers); shipping it into
# project-template/ would tell project #2's Claude the wrong thing about
# ITS OWN authoritativeness. See STATUS.md's own text + decisions.md
# 2026-07-03 "Council — copy-B topology".

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
# g2. export manifest + post-conditions (A-P1 core + O6 + council rider 2)
# =========================================================================
# Three independent checks, in order of severity:
#   1. Manifest + post-conditions   — FAIL loud, named misses, no `|| true`.
#   2. Template-hook-diff parity    — FAIL loud (O6+SEC-P4): the template's
#      secret gate must be a superset-or-equal of the live gate.
#   3. Rider 2 — staleness WARN     — WARN-ONLY, never fails the export.
#
# All three read the DESTINATION (post-copy state), matching what a fresh
# consumer of this repo actually receives — not the source, which could
# theoretically differ from what section a/b/d actually landed.
echo "--> [g2] export manifest + post-conditions"

MANIFEST_FILE="$SCRIPT_DIR/export-manifest.txt"
MANIFEST_FAILED=0
declare -a MANIFEST_MISSING=()

# --- 1a. Expected skills (section a) -------------------------------------
declare -a EXPECTED_SKILLS=()
if [ -d "$SRC_SKILLS" ]; then
    for entry in "$SRC_SKILLS"/*; do
        [ -e "$entry" ] || continue
        base="$(basename "$entry")"
        case "$base" in
            audit-*|__pycache__|*.bak-*)
                continue
                ;;
        esac
        EXPECTED_SKILLS+=("$base")
    done
fi
for extra in cave normal; do
    if [ -d "$SRC_MANTIKLI_SKILLS/$extra" ]; then
        EXPECTED_SKILLS+=("$extra")
    fi
done
if [ -d "$SRC_MANTIKLI_SKILLS/review" ]; then
    EXPECTED_SKILLS+=("review")
elif [ -f "$SRC_MANTIKLI_SKILLS/review.md" ]; then
    EXPECTED_SKILLS+=("review.md")
fi

for name in "${EXPECTED_SKILLS[@]}"; do
    if [ ! -e "$DEST_SKILLS/$name" ]; then
        MANIFEST_MISSING+=("[a home/skills] $name")
        MANIFEST_FAILED=1
    fi
done

# --- 1b. Expected scripts (section b) -------------------------------------
declare -a EXPECTED_SCRIPTS=()
if [ -d "$SRC_SCRIPTS" ]; then
    for entry in "$SRC_SCRIPTS"/*; do
        [ -e "$entry" ] || continue
        base="$(basename "$entry")"
        case "$base" in
            __pycache__|*.bak-*)
                continue
                ;;
        esac
        EXPECTED_SCRIPTS+=("$base")
    done
fi

for name in "${EXPECTED_SCRIPTS[@]}"; do
    if [ ! -e "$DEST_SCRIPTS/$name" ]; then
        MANIFEST_MISSING+=("[b home/scripts] $name")
        MANIFEST_FAILED=1
    fi
done

# --- 1d. Expected project-template files (section d) ----------------------
declare -a EXPECTED_TEMPLATE=()
if [ -d "$SRC_TEMPLATE" ]; then
    while IFS= read -r rel; do
        case "$rel" in
            .git|.git/*|.preflight|.preflight/*|__pycache__|*/__pycache__|*/__pycache__/*)
                continue
                ;;
            *.bak-*|*/.bak-*)
                continue
                ;;
            BACKPORT.md|ENGINEERING_PATTERNS.md|DELEGATION_GATES.md|STATUS.md)
                continue
                ;;
        esac
        EXPECTED_TEMPLATE+=("$rel")
    done < <(cd "$SRC_TEMPLATE" && find . -mindepth 1 -type f | sed 's|^\./||')
fi

for rel in "${EXPECTED_TEMPLATE[@]}"; do
    if [ ! -f "$DEST_TEMPLATE/$rel" ]; then
        MANIFEST_MISSING+=("[d project-template] $rel")
        MANIFEST_FAILED=1
    fi
done

# --- 1e. Expected docs (section e) ----------------------------------------
declare -a EXPECTED_DOCS=()
if [ -f "$SRC_TEMPLATE/ENGINEERING_PATTERNS.md" ]; then
    EXPECTED_DOCS+=("ENGINEERING_PATTERNS.md")
fi
if [ -f "$SRC_TEMPLATE/DELEGATION_GATES.md" ]; then
    EXPECTED_DOCS+=("DELEGATION_GATES.md")
fi

for name in "${EXPECTED_DOCS[@]}"; do
    if [ ! -f "$DEST_DOCS/$name" ]; then
        MANIFEST_MISSING+=("[e docs] $name")
        MANIFEST_FAILED=1
    fi
done

# --- 1r. Regression check: did a previously-expected SOURCE item vanish? --
# The checks above only catch "source has it, destination doesn't." They
# CANNOT catch "source itself lost a file" (e.g. an accidental rename) —
# the freshly-derived expected list simply shrinks and nothing looks wrong.
# Guard against that by diffing EVERY section's source-derived list against
# that section's entries in the PREVIOUS run's committed manifest (read
# before we overwrite it below). Anything the last run considered expected
# that this run's SOURCE walk no longer produces is a source-side
# regression — fail loud, name it. Covers ALL sections, not just d: the
# 2026-07-01 review-skill silent drop was a section-a source-shape change,
# so a d-only guard would miss the very incident class that motivated this.
if [ -f "$MANIFEST_FILE" ]; then
    check_source_regression() {
        # $1 = exact manifest section header, $2 = label, $3 = name of the
        # current source-derived expected array (bash nameref)
        local header="$1" label="$2"
        local -n _cur="$3"
        local prev cur found
        while IFS= read -r prev; do
            found=0
            for cur in "${_cur[@]}"; do
                if [ "$cur" = "$prev" ]; then
                    found=1
                    break
                fi
            done
            if [ "$found" -eq 0 ]; then
                MANIFEST_MISSING+=("[$label SOURCE REGRESSION] $prev (in previous manifest, no longer derivable from source — accidental rename/delete? If the removal is INTENTIONAL, delete that line from tools/export-manifest.txt and re-run)")
                MANIFEST_FAILED=1
            fi
        done < <(awk -v h="$header" '$0==h{flag=1;next}/^## /{flag=0}flag && NF' "$MANIFEST_FILE")
    }
    check_source_regression "## a. home/skills/"      "a home/skills"      EXPECTED_SKILLS
    check_source_regression "## b. home/scripts/"     "b home/scripts"     EXPECTED_SCRIPTS
    check_source_regression "## d. project-template/" "d project-template" EXPECTED_TEMPLATE
    check_source_regression "## e. docs/"             "e docs"             EXPECTED_DOCS
fi

# --- Fail FIRST, before touching the manifest file on disk ---------------
# The manifest on disk is the regression baseline the NEXT run reads (see
# the 1r check above). If a failing run were allowed to overwrite it, the
# bad/incomplete state would become the new "previous manifest" and poison
# every subsequent run's regression check. So: check-and-abort happens
# BEFORE the write, and a failing run leaves the last KNOWN-GOOD manifest
# on disk untouched.
if [ "$MANIFEST_FAILED" -eq 1 ]; then
    MANIFEST_STATUS="FAIL"
    echo ""
    echo "============================================================"
    echo "EXPORT ABORTED — manifest post-condition failed"
    echo "  The following expected files/dirs are MISSING from the"
    echo "  destination after copy:"
    for m in "${MANIFEST_MISSING[@]}"; do
        echo "    - $m"
    done
    echo "  (tools/export-manifest.txt left UNCHANGED — still reflects the"
    echo "  last known-good export, so re-running after a fix compares"
    echo "  against the correct baseline.)"
    echo "============================================================"
    exit 1
fi

# NOTE: the manifest file itself is NOT written here. It's deferred until
# after ALL g2 hard-fail gates (this post-condition check AND the security
# parity check below) have passed — see the write block just before section
# h. Writing it here would persist a manifest reflecting a run that still
# goes on to fail security parity, corrupting the NEXT run's regression
# baseline (see the 1r comment above — this was caught empirically while
# proving the done-gates: a parity-test artifact leaked into the manifest
# because the write used to happen before the parity check).
echo "    manifest post-conditions OK: ${#EXPECTED_SKILLS[@]} skills, ${#EXPECTED_SCRIPTS[@]} home scripts, ${#EXPECTED_TEMPLATE[@]} template files, ${#EXPECTED_DOCS[@]} docs"
MANIFEST_STATUS="PASS"

# --- 2. Template-hook-diff, security parity = HARD FAIL (O6+SEC-P4) -------
# The template's secret gate must be a SUPERSET-OR-EQUAL of the live gate.
# Concretely: if pretooluse_edit_guard.py (the live secret-gate script) is
# wired in live Mantikli settings.json, it must ALSO be wired in the
# post-copy template's settings.json.template — same matcher family
# (PreToolUse Edit|Write). A template that dropped or never wired this
# script would ship project #2 an editor with no secret-path block.
echo "--> [g2] template-hook-diff (security parity)"

LIVE_SETTINGS="$MANTIKLI_CLAUDE/settings.json"
DEST_SETTINGS_TEMPLATE="$DEST_TEMPLATE/.claude/settings.json.template"

SECRET_GATE_SCRIPT="pretooluse_edit_guard.py"

if [ -f "$LIVE_SETTINGS" ]; then
    LIVE_HAS_GATE="$(grep -c "scripts/${SECRET_GATE_SCRIPT}" "$LIVE_SETTINGS" || true)"
else
    LIVE_HAS_GATE=0
fi

if [ -f "$DEST_SETTINGS_TEMPLATE" ]; then
    TEMPLATE_HAS_GATE="$(grep -c "scripts/${SECRET_GATE_SCRIPT}" "$DEST_SETTINGS_TEMPLATE" || true)"
else
    TEMPLATE_HAS_GATE=0
fi

if [ "${LIVE_HAS_GATE:-0}" -gt 0 ] && [ "${TEMPLATE_HAS_GATE:-0}" -eq 0 ]; then
    PARITY_STATUS="FAIL"
    echo ""
    echo "============================================================"
    echo "EXPORT ABORTED — security parity FAILED (O6 + SEC-P4)"
    echo "  Live $LIVE_SETTINGS wires $SECRET_GATE_SCRIPT (the secret-path"
    echo "  block gate) but the exported"
    echo "  $DEST_SETTINGS_TEMPLATE does NOT wire it."
    echo "  The template's secret gate must be a superset-or-equal of the"
    echo "  live gate — project #2 must never ship with a weaker guard"
    echo "  than the source project. Fix the template wiring, then re-run."
    echo "============================================================"
    exit 1
fi

# Content parity: wiring parity alone would still PASS while shipping a
# STALE copy of the gate script — an older gate with fewer patterns is
# exactly SEC-F4's "weakest historical gate" failure shape. Byte-equality
# against the live script is the cheap superset-or-equal proxy; if the
# template copy ever needs to deliberately diverge (e.g. genericization),
# that divergence must come THROUGH this check as an explained change, not
# around it.
LIVE_GATE_SCRIPT="${MANTIKLI_CLAUDE%/.claude}/scripts/${SECRET_GATE_SCRIPT}"
DEST_GATE_SCRIPT="$DEST_TEMPLATE/scripts/${SECRET_GATE_SCRIPT}"
if [ "${LIVE_HAS_GATE:-0}" -gt 0 ] && [ -f "$LIVE_GATE_SCRIPT" ]; then
    if ! cmp -s "$LIVE_GATE_SCRIPT" "$DEST_GATE_SCRIPT"; then
        PARITY_STATUS="FAIL"
        echo ""
        echo "============================================================"
        echo "EXPORT ABORTED — security parity FAILED (O6 + SEC-P4)"
        echo "  Exported $DEST_GATE_SCRIPT"
        echo "  is missing or differs from the live gate"
        echo "  $LIVE_GATE_SCRIPT."
        echo "  The template must never ship a stale/weaker secret gate."
        echo "  Fix: refresh copy B's scripts/$SECRET_GATE_SCRIPT from the"
        echo "  live version, then re-run."
        echo "============================================================"
        exit 1
    fi
fi

if [ "${LIVE_HAS_GATE:-0}" -gt 0 ]; then
    echo "    security parity: PASS ($SECRET_GATE_SCRIPT wired live AND in template, gate script byte-identical to live)"
else
    echo "    security parity: PASS (live does not wire $SECRET_GATE_SCRIPT — nothing to enforce)"
fi
PARITY_STATUS="PASS"

# --- Write the manifest now — BOTH hard-fail g2 gates have passed --------
# (post-conditions check above + security parity above). Sorted, stable
# ordering so re-runs with no source changes produce byte-identical files.
{
    echo "# export-manifest.txt — expected export contents, derived from SOURCE."
    echo "# Regenerated by tools/export.sh on every run. Sorted for stable diffs."
    echo "## a. home/skills/"
    printf '%s\n' "${EXPECTED_SKILLS[@]}" | sort
    echo "## b. home/scripts/"
    printf '%s\n' "${EXPECTED_SCRIPTS[@]}" | sort
    echo "## d. project-template/"
    printf '%s\n' "${EXPECTED_TEMPLATE[@]}" | sort
    echo "## e. docs/"
    printf '%s\n' "${EXPECTED_DOCS[@]}" | sort
} > "$MANIFEST_FILE"
echo "    manifest written: $MANIFEST_FILE"

# --- 3. Rider 2 — copy-B staleness WARN (WARN-ONLY, never fails) ----------
# Diffs copy B's scripts/*.py set against the LIVE-WIRED script set (parsed
# from live Mantikli settings.json, not copy B's own settings.json.template
# — the wiring is the source of truth for "this script matters enough to
# run every session"). Any live-wired script not present in copy B's
# scripts/ prints a WARN line. This is expected to fire for Wave-1-born
# scripts (posttooluse_qa_guard.py, hook_latch.py, sessionstart_recovery.py,
# etc.) that are deliberately not backfilled yet — that is CORRECT, this is
# the detector the council adopted instead of a forced sync.
echo "--> [g2] rider 2: copy-B staleness (WARN-only)"

declare -a LIVE_WIRED_SCRIPTS=()
if [ -f "$LIVE_SETTINGS" ]; then
    while IFS= read -r name; do
        LIVE_WIRED_SCRIPTS+=("$name")
    done < <(grep -oE 'scripts/[A-Za-z0-9_]+\.py' "$LIVE_SETTINGS" | sed 's|scripts/||' | sort -u)
fi

declare -a STALE_MISSING=()
for name in "${LIVE_WIRED_SCRIPTS[@]}"; do
    if [ ! -f "$SRC_TEMPLATE/scripts/$name" ]; then
        STALE_MISSING+=("$name")
    fi
done

STALE_COUNT="${#STALE_MISSING[@]}"
if [ "$STALE_COUNT" -gt 0 ]; then
    stale_csv="$(printf '%s, ' "${STALE_MISSING[@]}")"
    stale_csv="${stale_csv%, }"
    echo "    WARN: copy-B is missing live-wired scripts: $stale_csv"
else
    echo "    rider 2: copy-B has every live-wired script — no staleness"
fi

# =========================================================================
# h. gitleaks secret scan (fail-closed gate)
# =========================================================================
# Scans the exported WORKING TREE (this repo's uncommitted files, right after
# the copy/sanitize steps above) for secrets before the export is allowed to
# be considered successful. Fail-closed: if gitleaks can't be found or run,
# the export ABORTS — a missing scanner must never silently skip the scan.
echo "--> [h] gitleaks secret scan"

WINGET_GITLEAKS="$HOME/AppData/Local/Microsoft/WinGet/Packages/Gitleaks.Gitleaks_Microsoft.Winget.Source_8wekyb3d8bbwe/gitleaks.exe"

resolve_gitleaks() {
    # 1. Explicit override via $GITLEAKS_BIN. If the caller set it, honor it
    #    strictly — do NOT fall through to PATH/WinGet on failure. An explicit
    #    override that's wrong should fail loudly, not be silently substituted.
    if [ -n "${GITLEAKS_BIN:-}" ]; then
        if [ -x "$GITLEAKS_BIN" ] || command -v "$GITLEAKS_BIN" >/dev/null 2>&1; then
            printf '%s\n' "$GITLEAKS_BIN"
            return 0
        fi
        return 2
    fi
    # 2. PATH lookup.
    if command -v gitleaks >/dev/null 2>&1; then
        command -v gitleaks
        return 0
    fi
    # 3. Fallback: known WinGet install path.
    if [ -x "$WINGET_GITLEAKS" ]; then
        printf '%s\n' "$WINGET_GITLEAKS"
        return 0
    fi
    return 1
}

GITLEAKS_RC=0
GITLEAKS_CMD="$(resolve_gitleaks)" || GITLEAKS_RC=$?

if [ "$GITLEAKS_RC" -eq 2 ]; then
    echo ""
    echo "============================================================"
    echo "EXPORT ABORTED — gitleaks not found"
    echo "  \$GITLEAKS_BIN was explicitly set to '$GITLEAKS_BIN' but is"
    echo "  not executable / not resolvable. An explicit override that"
    echo "  is broken is treated as a hard error, not silently ignored."
    echo "  The export gate is fail-closed."
    echo "  Install hint: winget install Gitleaks.Gitleaks"
    echo "============================================================"
    exit 1
elif [ "$GITLEAKS_RC" -ne 0 ] || [ -z "$GITLEAKS_CMD" ]; then
    echo ""
    echo "============================================================"
    echo "EXPORT ABORTED — gitleaks not found; the export gate is"
    echo "  fail-closed. A missing scanner must never silently skip"
    echo "  the secret scan."
    echo "  Install hint: winget install Gitleaks.Gitleaks"
    echo "============================================================"
    exit 1
fi

echo "    using gitleaks: $GITLEAKS_CMD"

# --no-git treats the repo as a plain directory (verified empirically: it
# scans only the working-tree files, NOT .git/ internals — a run against
# this repo scanned exactly the working-tree byte count, not
# working-tree + .git object-store bytes, so no exclusion flag is needed).
set +e
GITLEAKS_OUTPUT="$("$GITLEAKS_CMD" detect --no-git --source "$REPO_ROOT" --redact 2>&1)"
GITLEAKS_SCAN_RC=$?
set -e

if [ "$GITLEAKS_SCAN_RC" -ne 0 ]; then
    GITLEAKS_STATUS="FAIL ($GITLEAKS_SCAN_RC findings/error)"
    echo ""
    echo "============================================================"
    echo "EXPORT ABORTED — potential secret detected in export tree"
    echo "============================================================"
    echo "$GITLEAKS_OUTPUT"
    echo "============================================================"
    echo "Fix the finding (or confirm it's a false positive) before"
    echo "re-running the export. The export gate is fail-closed."
    echo "============================================================"
    exit 1
fi

GITLEAKS_STATUS="PASS"
echo "    gitleaks: no leaks found — PASS"

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
echo "    manifest post-conditions:   $MANIFEST_STATUS"
echo "    hook-diff security parity:  $PARITY_STATUS"
echo "    copy-B staleness WARNs:     $STALE_COUNT"
echo "    gitleaks secret scan:       $GITLEAKS_STATUS"
echo "==> Done."
