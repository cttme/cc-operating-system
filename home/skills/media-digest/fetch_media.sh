#!/usr/bin/env bash
# fetch_media.sh — headless source-text fetcher for the /media-digest skill.
#
# Pulls a clean transcript (video) or media-tweet text via yt-dlp, parsing
# captions WITHOUT downloading the media. Browser-backed paths (x.com text
# tweets, Copilot escalation) live in SKILL.md, not here — this script only
# does what is cheap and headless.
#
# Usage:  bash fetch_media.sh <url> [langs]
#   langs : comma yt-dlp sub-lang globs (default "en.*,tr.*")
#
# Output: clean transcript text on stdout.
# Exit codes (so SKILL.md branches deterministically, no stderr grep):
#   0  ok        — transcript printed to stdout
#   2  no-caps   — extractable but no captions; title/description printed instead
#   3  failed    — not extractable headlessly (text tweet / article / blocked)
#   4  usage     — bad invocation
set -uo pipefail

# Force UTF-8 for all python subprocesses: Windows defaults stdout to the
# locale codec (e.g. cp1254), which crashes on transcript glyphs like ♪/em-dash.
export PYTHONIOENCODING=utf-8
export PYTHONUTF8=1

URL="${1:-}"
LANGS="${2:-en.*,tr.*}"
[ -z "$URL" ] && { echo "usage: fetch_media.sh <url> [langs]" >&2; exit 4; }

# yt-dlp needs a JS runtime for YouTube; deno is absent, node v24 is present.
YTDLP=(yt-dlp --js-runtimes node --no-warnings --no-playlist)

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 1) Try to fetch subtitles (human + auto) without downloading the media.
"${YTDLP[@]}" --skip-download --write-subs --write-auto-subs \
  --sub-langs "$LANGS" --sub-format vtt \
  -o "$TMP/m.%(ext)s" "$URL" >/dev/null 2>"$TMP/err.log"
FETCH_RC=$?

VTT="$(ls "$TMP"/*.vtt 2>/dev/null | head -1)"

if [ -n "$VTT" ]; then
  # Parse VTT -> clean transcript: drop header/NOTE/timestamps, strip inline
  # tags, collapse consecutive duplicate lines (YouTube rolling captions).
  python - "$VTT" <<'PY'
import sys, re
lines = open(sys.argv[1], encoding="utf-8", errors="ignore").read().splitlines()
out, prev = [], None
for ln in lines:
    s = ln.strip()
    if s in ("WEBVTT", "") or "-->" in ln:
        continue
    if s.startswith(("NOTE", "Kind:", "Language:")):
        continue
    ln = re.sub(r"<[^>]+>", "", ln).strip()   # strip <c>/<timestamp> tags
    if ln and ln != prev:
        out.append(ln)
        prev = ln
text = " ".join(out).strip()
if not text:
    sys.exit(10)  # vtt existed but parsed empty
print(text)
PY
  [ $? -eq 0 ] && exit 0
fi

# 2) No usable captions. If yt-dlp could still see the item, return its
#    title/description as fallback context (exit 2). Otherwise it's not
#    headlessly extractable at all (exit 3).
META="$("${YTDLP[@]}" --dump-json --skip-download "$URL" 2>/dev/null \
  | python -c 'import sys,json
try:
    d=json.load(sys.stdin)
    t=(d.get("title") or "").strip()
    u=(d.get("uploader") or "").strip()
    desc=(d.get("description") or "").strip()
    print(f"TITLE: {t}\nUPLOADER: {u}\nDESCRIPTION: {desc}".strip())
except Exception:
    pass' 2>/dev/null)"

if [ -n "$META" ]; then
  echo "$META"
  exit 2
fi

echo "fetch_media: not extractable headlessly (text tweet / article / blocked) — use browser path" >&2
exit 3
