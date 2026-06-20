# ============================================================
# SCRIPT: ask-local.ps1
# VERSION: 0.1.0
# PURPOSE: Send a prompt to local Ollama and return the response,
#          with intent logging, cache, and a structured summary block.
# WHEN TO USE:
#   - Single-shot summarization, classification, extraction, translation
#   - Output expected <= ~1K tokens
#   - No multi-step reasoning needed
# WHEN NOT TO USE:
#   - Code generation (use Claude)
#   - Multi-turn dialogue (use Ollama API directly with context array)
#   - Privacy-sensitive input without -NoLog flag
# INPUTS (named PowerShell parameters):
#   -Intent      <string>   REQUIRED, short purpose, e.g. "summarize git log"
#   -Prompt      <string>   prompt text (use this OR -PromptFile)
#   -PromptFile  <path>     read prompt from file (preferred for multiline/
#                           large prompts to avoid CLI arg-escaping bugs)
#   -Model       <string>   optional, default: gemma4-fast-e4b (qwen35-fast-4b = fallback)
#   -Tier        <string>   optional, T0|T1|T2, default: T1
#   -NoCache                optional switch, bypass disk cache
#   -NoLog                  optional switch, do not write to log (privacy)
# OUTPUTS:
#   stdout:
#     ---OLLAMA-CALL-SUMMARY---
#     tier=<T> | intent=<i> | model=<m> | cached=<bool> | ~<in>-><out> tok | <dur>s
#     ---OLLAMA-OUTPUT---
#     <response text>
#   .ollama-log/<session>/calls.jsonl     one JSON line per call
#   .ollama-cache/<model>-<hash>.txt      cached response (skipped with -NoCache)
# DEPENDENCIES: Ollama running on http://localhost:11434
# EXIT CODES: 0=ok, 1=missing arg, 2=ollama unreachable, 3=invalid response
# RELATED:
#   - skills/ask-local/SKILL.md
#   - templates/local-prompts/*.md
# ============================================================

[CmdletBinding(DefaultParameterSetName="InlinePrompt")]
param(
    [Parameter(Mandatory=$true)]
    [string]$Intent,

    [Parameter(Mandatory=$true, ParameterSetName="InlinePrompt")]
    [string]$Prompt,

    [Parameter(Mandatory=$true, ParameterSetName="FilePrompt")]
    [string]$PromptFile,

    [string]$Model = "gemma4-fast-e4b",

    [ValidateSet("T0","T1","T2")]
    [string]$Tier = "T1",

    [switch]$NoCache,

    [switch]$NoLog
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

# Resolve prompt content (from file if -PromptFile was used)
if ($PSCmdlet.ParameterSetName -eq "FilePrompt") {
    if (-not (Test-Path $PromptFile)) {
        Write-Error "PromptFile not found: $PromptFile"
        exit 1
    }
    $Prompt = [System.IO.File]::ReadAllText($PromptFile, [System.Text.UTF8Encoding]::new($false))
}

# Resolve project root (parent of scripts/)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Resolve-Path (Join-Path $ScriptDir "..")).Path
$LogRoot = Join-Path $ProjectRoot ".ollama-log"
$CacheRoot = Join-Path $ProjectRoot ".ollama-cache"
$PromptStoreRoot = Join-Path $ProjectRoot ".ollama-prompts"

# Session id: honor CLAUDE_SESSION_ID if injected, else fall back to date
$SessionId = $env:CLAUDE_SESSION_ID
if (-not $SessionId) {
    $SessionId = (Get-Date).ToString("yyyyMMdd")
}

# Hash the (model + prompt) for cache key
$Sha = [System.Security.Cryptography.SHA256]::Create()
$Bytes = [System.Text.Encoding]::UTF8.GetBytes($Model + "|" + $Prompt)
$HashBytes = $Sha.ComputeHash($Bytes)
$Hash = ([System.BitConverter]::ToString($HashBytes) -replace "-","").ToLower().Substring(0,16)

$CacheFile = Join-Path $CacheRoot "$Model-$Hash.txt"
$Cached = $false
$StartTime = Get-Date
$InTokens = -1
$OutTokens = -1

if ((-not $NoCache) -and (Test-Path $CacheFile)) {
    $Response = Get-Content -Raw -Encoding UTF8 $CacheFile
    $Cached = $true
} else {
    # Call Ollama API. think:false disables reasoning mode for models that have
    # one (Qwen3.5 and Gemma 4 both do); ignored by models that don't. Verified
    # honored by gemma4-fast-e4b (clean answer, no reasoning trace).
    $Body = @{
        model  = $Model
        prompt = $Prompt
        stream = $false
        think  = $false
    } | ConvertTo-Json -Compress

    try {
        $Result = Invoke-RestMethod -Uri "http://localhost:11434/api/generate" `
            -Method Post -Body $Body -ContentType "application/json" `
            -TimeoutSec 120
    } catch {
        Write-Error "Ollama unreachable or error: $($_.Exception.Message)"
        exit 2
    }

    if (-not $Result.response) {
        Write-Error "Invalid response from Ollama (no 'response' field)"
        exit 3
    }

    $Response = $Result.response
    if ($Result.prompt_eval_count) { $InTokens = [int]$Result.prompt_eval_count }
    if ($Result.eval_count)        { $OutTokens = [int]$Result.eval_count }

    # Persist to cache
    if (-not $NoCache) {
        if (-not (Test-Path $CacheRoot)) {
            New-Item -ItemType Directory -Force -Path $CacheRoot | Out-Null
        }
        $Response | Out-File -FilePath $CacheFile -Encoding utf8 -NoNewline
    }
}

$Duration = ((Get-Date) - $StartTime).TotalSeconds
# Force invariant culture so the human-readable line uses "1.23" (not "1,23")
$DurStr = ([math]::Round($Duration, 2)).ToString([System.Globalization.CultureInfo]::InvariantCulture)

# Structured log line (JSONL)
if (-not $NoLog) {
    $LogDir = Join-Path $LogRoot $SessionId
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    }
    $LogFile = Join-Path $LogDir "calls.jsonl"

    $LogEntry = @{
        ts      = (Get-Date).ToString("o")
        session = $SessionId
        tier    = $Tier
        intent  = $Intent
        model   = $Model
        cached  = $Cached
        in_tok  = $InTokens
        out_tok = $OutTokens
        dur_s   = [math]::Round($Duration, 2)
        hash    = $Hash
    } | ConvertTo-Json -Compress

    Add-Content -Path $LogFile -Value $LogEntry -Encoding utf8

    # Sidecar: store the prompt text indexed by hash, for ollama-replay.
    # Skipped when -NoLog (privacy) since the whole call goes unrecorded.
    $PromptDir = Join-Path $PromptStoreRoot $SessionId
    if (-not (Test-Path $PromptDir)) {
        New-Item -ItemType Directory -Force -Path $PromptDir | Out-Null
    }
    $PromptStoreFile = Join-Path $PromptDir "$Hash.txt"
    if (-not (Test-Path $PromptStoreFile)) {
        # Write once per unique prompt; cache hits don't overwrite
        [System.IO.File]::WriteAllText($PromptStoreFile, $Prompt, [System.Text.UTF8Encoding]::new($false))
    }
}

# Output: summary block (machine + human readable) + delimiter + response
Write-Output "---OLLAMA-CALL-SUMMARY---"
Write-Output "tier=$Tier | intent=$Intent | model=$Model | cached=$Cached | ~$InTokens->$OutTokens tok | ${DurStr}s"
Write-Output "---OLLAMA-OUTPUT---"
Write-Output $Response

exit 0
