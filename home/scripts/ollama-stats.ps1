# ============================================================
# SCRIPT: ollama-stats.ps1
# VERSION: 0.1.0
# PURPOSE: Aggregate call logs from .ollama-log/ into per-session
#          and per-intent metrics. Used at session end and for
#          long-term audit of the Ollama optimization.
# WHEN TO USE:
#   - Session close (/session-end): summarize today's local calls
#   - Manual audit: spot intent patterns, cache hit rate, drift
# WHEN NOT TO USE:
#   - Realtime alerting (no streaming; reads files in bulk)
# INPUTS:
#   -Session <id>     optional, default: all sessions
#   -Days    <int>    optional, look back N days (date-named sessions)
#   -Json             switch, machine-readable JSON output
# OUTPUTS:
#   stdout: human-readable table by default, JSON if -Json
# DEPENDENCIES: PowerShell 5.1+, no external tools
# EXIT CODES: 0=ok, 1=no log files found
# RELATED:
#   - scripts/ask-local.ps1 (writes the logs this reads)
#   - skills/double-stitch/SKILL.md (uses the cache_rate signal)
# ============================================================

[CmdletBinding()]
param(
    [string]$Session,
    [int]$Days = 0,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Resolve-Path (Join-Path $ScriptDir "..")).Path
$LogRoot = Join-Path $ProjectRoot ".ollama-log"

if (-not (Test-Path $LogRoot)) {
    Write-Error "No log directory found at $LogRoot. Run ask-local first."
    exit 1
}

# Collect JSONL files according to filters
$LogDirs = Get-ChildItem -Path $LogRoot -Directory
if ($Session) {
    $LogDirs = $LogDirs | Where-Object { $_.Name -eq $Session }
}
if ($Days -gt 0) {
    $Cutoff = (Get-Date).AddDays(-$Days).ToString("yyyyMMdd")
    $LogDirs = $LogDirs | Where-Object { $_.Name -ge $Cutoff }
}

$AllCalls = @()
foreach ($Dir in $LogDirs) {
    $File = Join-Path $Dir.FullName "calls.jsonl"
    if (-not (Test-Path $File)) { continue }
    Get-Content -Path $File -Encoding UTF8 | ForEach-Object {
        if ($_.Trim()) {
            try {
                $AllCalls += ($_ | ConvertFrom-Json)
            } catch {
                Write-Warning "Skipping malformed line in $File"
            }
        }
    }
}

if ($AllCalls.Count -eq 0) {
    Write-Error "No call records found."
    exit 1
}

# Estimated Anthropic cost saved per token (rough, output-token basis)
# Sonnet ~ $15 / 1M output tokens => $0.000015 / token
$SonnetPerTok = 0.000015

# Aggregations
$ByTier = $AllCalls | Group-Object tier | ForEach-Object {
    $calls = $_.Group
    # Wrap in @() so .Count is reliable when the filter returns 0 or 1 items
    $api_calls = @($calls | Where-Object { -not $_.cached }).Count
    $cache_hits = @($calls | Where-Object { $_.cached -eq $true }).Count
    $in_sum = ($calls | Where-Object { $_.in_tok -gt 0 } | Measure-Object -Property in_tok -Sum).Sum
    $out_sum = ($calls | Where-Object { $_.out_tok -gt 0 } | Measure-Object -Property out_tok -Sum).Sum
    $dur_sum = ($calls | Measure-Object -Property dur_s -Sum).Sum
    [PSCustomObject]@{
        tier         = $_.Name
        total_calls  = $calls.Count
        api_calls    = $api_calls
        cache_hits   = $cache_hits
        cache_rate   = if ($calls.Count) { [math]::Round(($cache_hits / $calls.Count), 2) } else { 0 }
        in_tokens    = if ($in_sum) { $in_sum } else { 0 }
        out_tokens   = if ($out_sum) { $out_sum } else { 0 }
        total_seconds = [math]::Round($dur_sum, 2)
    }
}

$ByIntent = $AllCalls | Group-Object intent | Sort-Object Count -Descending | ForEach-Object {
    $calls = $_.Group
    [PSCustomObject]@{
        intent       = $_.Name
        calls        = $calls.Count
        avg_in_tok   = if ($calls.Count) {
            [math]::Round((($calls | Where-Object { $_.in_tok -gt 0 } | Measure-Object -Property in_tok -Average).Average), 0)
        } else { 0 }
        avg_out_tok  = if ($calls.Count) {
            [math]::Round((($calls | Where-Object { $_.out_tok -gt 0 } | Measure-Object -Property out_tok -Average).Average), 0)
        } else { 0 }
    }
} | Select-Object -First 10

# Cost estimate: out_tokens that ACTUALLY went to Ollama would have cost on Sonnet
$total_out = ($AllCalls | Where-Object { $_.out_tok -gt 0 } | Measure-Object -Property out_tok -Sum).Sum
if (-not $total_out) { $total_out = 0 }
$saved_usd = [math]::Round(($total_out * $SonnetPerTok), 4)

if ($Json) {
    @{
        sessions_scanned = ($LogDirs | Measure-Object).Count
        total_calls      = $AllCalls.Count
        api_calls        = @($AllCalls | Where-Object { -not $_.cached }).Count
        cache_hits       = @($AllCalls | Where-Object { $_.cached -eq $true }).Count
        total_in_tokens  = if ($AllCalls | Where-Object { $_.in_tok -gt 0 }) {
            ($AllCalls | Where-Object { $_.in_tok -gt 0 } | Measure-Object -Property in_tok -Sum).Sum
        } else { 0 }
        total_out_tokens = $total_out
        estimated_usd_saved_vs_sonnet = $saved_usd
        by_tier  = $ByTier
        by_intent = $ByIntent
    } | ConvertTo-Json -Depth 5
} else {
    Write-Output ""
    Write-Output "=== Ollama Stats ==="
    Write-Output ("Sessions scanned: {0}" -f ($LogDirs | Measure-Object).Count)
    Write-Output ("Total calls:      {0}" -f $AllCalls.Count)
    Write-Output ("Cache hit rate:   {0}%" -f ([math]::Round((@($AllCalls | Where-Object { $_.cached -eq $true }).Count / $AllCalls.Count) * 100, 1)))
    Write-Output ("Output tokens:    {0}  (~`$$saved_usd saved vs Sonnet baseline)" -f $total_out)
    Write-Output ""
    Write-Output "By tier:"
    $ByTier | Format-Table -AutoSize | Out-String | Write-Output
    Write-Output "Top intents:"
    $ByIntent | Format-Table -AutoSize | Out-String | Write-Output
}

exit 0
