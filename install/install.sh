#!/usr/bin/env bash
# install.sh — reconstruct the two-home layout (~/.claude/{skills,scripts,
# templates/project-bootstrap}) on an adopter machine from this repo's
# home/ and project-template/ snapshot.
#
# Usage:
#   install.sh [--dry-run] [--force] [--target <projectdir>]
#
#   --dry-run          Print every planned copy/mkdir/backup action.
#                       Touches NOTHING on disk.
#   --force            Skip the collision refusal and overwrite existing
#                       ~/.claude/{skills,scripts,templates/project-bootstrap}
#                       (a backup is still taken first).
#   --target <dir>     Also copy project-template/'s project-level files
#                       (.claude/, scripts/, tasks/, docs/, config templates)
#                       into <dir> (an existing or new project directory).
#
# Collision safety: before overwriting any of the three ~/.claude targets
# that already exist, this script backs them up to <path>.bak-<YYYY-MM-DD>.
# If such a path already exists and --force was NOT passed, it refuses
# (prints an error, exits nonzero) instead of overwriting blind.

set -euo pipefail

DRY_RUN=0
FORCE=0
TARGET=""

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --force) FORCE=1; shift ;;
        --target)
            TARGET="$2"; shift 2 ;;
        --target=*)
            TARGET="${1#--target=}"; shift ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

HOME_CLAUDE="${HOME_CLAUDE:-$HOME/.claude}"
DATE_SUFFIX="$(date +%Y-%m-%d)"

SRC_SKILLS="$REPO_ROOT/home/skills"
SRC_SCRIPTS="$REPO_ROOT/home/scripts"
SRC_CLAUDE_MD="$REPO_ROOT/home/CLAUDE.md.example"
SRC_TEMPLATE="$REPO_ROOT/project-template"

DEST_SKILLS="$HOME_CLAUDE/skills"
DEST_SCRIPTS="$HOME_CLAUDE/scripts"
DEST_CLAUDE_MD="$HOME_CLAUDE/CLAUDE.md"
DEST_TEMPLATE="$HOME_CLAUDE/templates/project-bootstrap"

log() { echo "$@"; }

plan_or_do_mkdir() {
    local dir="$1"
    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] mkdir -p $dir"
    else
        mkdir -p "$dir"
    fi
}

plan_or_do_copy() {
    local src="$1" dst="$2"
    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] cp -r $src -> $dst"
    else
        cp -r "$src" "$dst"
    fi
}

plan_or_do_backup() {
    local path="$1"
    local backup="${path}.bak-${DATE_SUFFIX}"
    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] backup: cp -r $path -> $backup"
    else
        cp -r "$path" "$backup"
        log "    backed up: $path -> $backup"
    fi
}

# Guard + backup-or-refuse for a single collision-prone target.
# Returns 0 if it is safe to proceed with the copy, 1 if it should be skipped.
guard_target() {
    local path="$1" label="$2"
    if [ -e "$path" ]; then
        local backup="${path}.bak-${DATE_SUFFIX}"
        if [ -e "$backup" ] && [ "$FORCE" -ne 1 ]; then
            echo "ERROR: $label already exists at $path AND a backup $backup already exists." >&2
            echo "       Refusing to overwrite without --force." >&2
            return 1
        fi
        plan_or_do_backup "$path"
        if [ "$DRY_RUN" -eq 0 ]; then
            rm -rf "$path"
        else
            log "[dry-run] rm -rf $path"
        fi
    fi
    return 0
}

log "==> Installing workflow OS from $REPO_ROOT"
[ "$DRY_RUN" -eq 1 ] && log "    (DRY RUN — no changes will be made)"

REFUSED=0

# --- skills ---
log "--> ~/.claude/skills/"
if guard_target "$DEST_SKILLS" "~/.claude/skills"; then
    plan_or_do_mkdir "$(dirname "$DEST_SKILLS")"
    plan_or_do_copy "$SRC_SKILLS" "$DEST_SKILLS"
else
    REFUSED=1
fi

# --- scripts ---
log "--> ~/.claude/scripts/"
if guard_target "$DEST_SCRIPTS" "~/.claude/scripts"; then
    plan_or_do_mkdir "$(dirname "$DEST_SCRIPTS")"
    plan_or_do_copy "$SRC_SCRIPTS" "$DEST_SCRIPTS"
else
    REFUSED=1
fi

# --- CLAUDE.md.example -> ~/.claude/CLAUDE.md (personal file; same collision guard) ---
log "--> ~/.claude/CLAUDE.md (from CLAUDE.md.example)"
if [ -f "$SRC_CLAUDE_MD" ]; then
    if guard_target "$DEST_CLAUDE_MD" "~/.claude/CLAUDE.md"; then
        plan_or_do_mkdir "$(dirname "$DEST_CLAUDE_MD")"
        plan_or_do_copy "$SRC_CLAUDE_MD" "$DEST_CLAUDE_MD"
    else
        REFUSED=1
    fi
else
    log "    (skip: $SRC_CLAUDE_MD not found)"
fi

# --- project-template -> ~/.claude/templates/project-bootstrap/ ---
log "--> ~/.claude/templates/project-bootstrap/"
if guard_target "$DEST_TEMPLATE" "~/.claude/templates/project-bootstrap"; then
    plan_or_do_mkdir "$(dirname "$DEST_TEMPLATE")"
    plan_or_do_copy "$SRC_TEMPLATE" "$DEST_TEMPLATE"
else
    REFUSED=1
fi

# --- optional: also copy project-template's project-level files into --target ---
if [ -n "$TARGET" ]; then
    log "--> project files into target: $TARGET"
    plan_or_do_mkdir "$TARGET"
    # dotglob so hidden entries (.claude/ with the RULES, .claudeignore.template,
    # .pre-commit-config.yaml.template) are scaffolded too — a plain `*` glob skips
    # them and the adopter's project would get no rules/hooks. nullglob avoids a
    # literal '*' when empty.
    shopt -s dotglob nullglob
    for item in "$SRC_TEMPLATE"/*; do
        [ -e "$item" ] || continue
        base="$(basename "$item")"
        dest_item="$TARGET/$base"
        if [ -e "$dest_item" ] && [ "$FORCE" -ne 1 ]; then
            echo "ERROR: $dest_item already exists. Refusing to overwrite without --force." >&2
            REFUSED=1
            continue
        fi
        if [ -e "$dest_item" ]; then
            plan_or_do_backup "$dest_item"
            if [ "$DRY_RUN" -eq 0 ]; then
                rm -rf "$dest_item"
            else
                log "[dry-run] rm -rf $dest_item"
            fi
        fi
        plan_or_do_copy "$item" "$dest_item"
    done
    shopt -u dotglob nullglob
fi

if [ "$REFUSED" -eq 1 ]; then
    echo "" >&2
    echo "One or more targets were refused due to existing backups. Re-run with --force to override." >&2
    exit 1
fi

log ""
log "==> Install complete."
[ "$DRY_RUN" -eq 1 ] && log "    (this was a dry run — nothing was written)"
exit 0
