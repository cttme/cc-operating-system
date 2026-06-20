# ============================================================
# SCRIPT: ollama-replay.ps1
# VERSION: 0.1.0
# PURPOSE: Re-run a previously logged ask-local call from .ollama-log,
#          either to debug a suspicious response or to compare against
#          a fresh evaluation after a prompt/model change.
# WHEN TO USE:
#   - A logged call's response looks wrong; want to confirm reproducibility
#   - After editing a prompt template, see how output shifts on prior inputs
#   - Manual review of a flagged call from double-stitch
# WHEN NOT TO USE:
#   - Bulk regeneration (use preflight-trim with -NoCache instead)
#   - When you don't have the original prompt -- this script only
#     replays what's in the cache + log; if cache was cleared and the
#     prompt isn't kept elsewhere, replay is impossible.
# INPUTS (named PowerShell parameters):
#   -Hash    <prefix>    short hash (>=4 chars) matching a logged call
#                        (one of -Hash / -IntentMatch / -Last is required)
#   -IntentMatch <text>  substring match against logged intents
#   -Last                replay the most recent call in the log
#   -Compare             also run a fresh call (no cache), show diff
#   -Model   <name>      override the model used (forces fresh call)
# OUTPUTS:
#   stdout: original (from cache) + optional fresh response side-by-side
# DEPENDENCIES:
#   - .ollama-log/*/calls.jsonl  (records to look up)
#   - .ollama-cache/*.txt        (cached responses)
#   - scripts/ask-local.ps1      (only used with -Compare)
# EXIT CODES: 0=ok, 1=bad args, 2=no matching call, 3=cache miss
# ============================================================

[CmdletBinding(DefaultParameterSetName="Last")]
param(
    [Parameter(Mandatory=$true, ParameterSetName="ByHash")]
    [string]$Hash,

    [Parameter(Mandatory=$true, ParameterSetName="ByIntent")]
    [string]$IntentMatch,

    [Parameter(ParameterSetName="Last")]
    [switch]$Last,

    [switch]$Compare,

    [string]$Model
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Resolve-Path (Join-Path $ScriptDir "..")).Path
$LogRoot = Join-Path $ProjectRoot ".ollama-log"
$CacheRoot = Join-Path $ProjectRoot ".ollama-cache"
$PromptStoreRoot = Join-Path $ProjectRoot ".ollama-prompts"
$AskLocal = Join-Path $ScriptDir "ask-local.ps1"

if (-not (Test-Path $LogRoot)) {
    Write-Error "No log directory at $LogRoot. Nothing to replay."
    exit 2
}

# --- Load all log entries ----------------------------------------------
$Entries = @()
Get-ChildItem -Path $LogRoot -Directory | ForEach-Object {
    $f = Join-Path $_.FullName "calls.jsonl"
    if (Test-Path $f) {
        Get-Content -Path $f -Encoding UTF8 | ForEach-Object {
            if ($_.Trim()) {
                try { $Entries += ($_ | ConvertFrom-Json) } catch {}
            }
        }
    }
}

if ($Entries.Count -eq 0) {
    Write-Error "No log entries found."
    exit 2
}

# Sort newest first
$Entries = $Entries | Sort-Object ts -Descending

# --- Pick the target entry ---------------------------------------------
switch ($PSCmdlet.ParameterSetName) {
    "ByHash" {
        $matches = @($Entries | Where-Object { $_.hash -like "$Hash*" })
        if ($matches.Count -eq 0) {
            Write-Error "No call with hash prefix '$Hash'."
            exit 2
        }
        $Target = $matches[0]
    }
    "ByIntent" {
        $matches = @($Entries | Where-Object { $_.intent -like "*$IntentMatch*" })
        if ($matches.Count -eq 0) {
            Write-Error "No call matching intent '$IntentMatch'."
            exit 2
        }
        $Target = $matches[0]
    }
    default {
        $Target = $Entries[0]
    }
}

# --- Lookup cached response --------------------------------------------
$CacheFile = Join-Path $CacheRoot "$($Target.model)-$($Target.hash).txt"
$CachedResponse = $null
if (Test-Path $CacheFile) {
    $CachedResponse = Get-Content -Raw -Encoding UTF8 $CacheFile
}

# --- Emit original ----------------------------------------------------
Write-Output "=== REPLAY: original logged call ==="
Write-Output "ts:       $($Target.ts)"
Write-Output "session:  $($Target.session)"
Write-Output "intent:   $($Target.intent)"
Write-Output "model:    $($Target.model)"
Write-Output "tier:     $($Target.tier)"
Write-Output "hash:     $($Target.hash)"
Write-Output "tokens:   in=$($Target.in_tok) out=$($Target.out_tok) (cached=$($Target.cached))"
Write-Output "duration: $($Target.dur_s)s"
Write-Output ""
Write-Output "--- cached response (re-served, no API call) ---"
if ($CachedResponse) {
    Write-Output $CachedResponse
} else {
    Write-Output "(cache miss -- the response is not retrievable. Cache file expected at:"
    Write-Output " $CacheFile )"
}
Write-Output ""

# --- Optional: fresh comparison ----------------------------------------
if ($Compare) {
    Write-Output "=== FRESH CALL (no cache) ==="

    # Look up the prompt text from the sidecar store
    $PromptStoreFile = Join-Path $PromptStoreRoot (Join-Path $Target.session "$($Target.hash).txt")
    if (-not (Test-Path $PromptStoreFile)) {
        Write-Output "  ! prompt sidecar not found at $PromptStoreFile"
        Write-Output "    (older calls predate prompt logging; cannot re-run)"
        exit 3
    }

    $ReplayModel = if ($Model) { $Model } else { $Target.model }
    $ReplayIntent = "replay $($Target.intent)"

    $askArgs = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $AskLocal,
        "-Intent", $ReplayIntent,
        "-PromptFile", $PromptStoreFile,
        "-Model", $ReplayModel,
        "-Tier", $Target.tier,
        "-NoCache"
    )

    Write-Output ""
    $RawOutput = & powershell $askArgs 2>&1
    $OutputText = ($RawOutput | Out-String)
    Write-Output $OutputText

    # Quick equality check
    $Match = $OutputText -split "---OLLAMA-OUTPUT---", 2
    Write-Output ""
    if ($Match.Count -eq 2) {
        $Fresh = $Match[1].Trim()
        if ($CachedResponse) {
            $Old = $CachedResponse.Trim()
            if ($Fresh -eq $Old) {
                Write-Output "  > DIFF: identical to cached response."
            } else {
                Write-Output "  > DIFF: responses differ (length $($Old.Length) -> $($Fresh.Length) chars)."
            }
        } else {
            Write-Output "  > DIFF: no cached original to compare against (original call used -NoCache or cache was cleared)."
        }
    }
}

Write-Output "=== END REPLAY ==="
exit 0
