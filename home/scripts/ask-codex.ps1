# ============================================================
# SCRIPT: ask-codex.ps1
# VERSION: 0.1.0
# PURPOSE: Delegate a well-specified coding/edit task to the OpenAI
#          Codex CLI (gpt-5.5 agent), treated as a subagent. Codex
#          edits the working tree; this script returns a structured
#          summary + change list + last message so Claude can
#          doublecheck the diff and iterate (via -Resume) or take over.
# WHEN TO USE:
#   - Claude has a crisp, self-contained spec and a verifiable done-state
#   - Mechanical / spec-driven implementation, refactors, boilerplate
# WHEN NOT TO USE:
#   - Architecture / one-way-door decisions, ambiguous requirements
#     (those stay with Claude; see skills/ask-codex/SKILL.md)
# INPUTS (named PowerShell parameters):
#   -Intent      <string>   REQUIRED, short task label, e.g. "impl parser"
#   -Prompt      <string>   the task spec (use this OR -PromptFile)
#   -PromptFile  <path>     read spec from file (preferred for multiline)
#   -Resume      <id>       continue a prior Codex session (thread_id)
#   -ResumeLast             continue the most recent Codex session
#   -Sandbox     <string>   read-only|workspace-write|danger-full-access
#                           default: workspace-write
#   -NoNetwork              disable sandbox network access (default: ON)
#   -ProjectRoot <path>     working root passed to codex --cd (default: cwd)
#   -Model       <string>   optional model override (default: config gpt-5.6-sol)
#   -ReasoningEffort <str>  minimal|low|medium|high (+ model-specific e.g. max);
#                           overrides config model_reasoning_effort. WITHOUT this,
#                           -Model inherits the global effort (e.g. luna@high) and
#                           loses its cost benefit — always pair a cheap model with
#                           a lower effort. Passed as -c model_reasoning_effort=<v>.
#   -Profile     <string>   codex --profile <name> (route profile: model+effort combo)
#   -TimeoutSec  <int>      kill runaway runs (default: 900)
#   -NoLog                  do not write to .codex-log (privacy)
# OUTPUTS:
#   stdout:
#     ---CODEX-CALL-SUMMARY---
#     intent=.. | model=.. | sandbox=.. | status=completed | session=<id> |
#       files_changed=N | ~<in>/<out> tok | <dur>s | exit=0 | ckpt=<sha>
#     ---CODEX-DIFF-STAT---
#     <git status --short (change list; non-mutating)>
#     ---CODEX-OUTPUT---
#     <Codex last message / blockers>
#   .codex-log/<session>/calls.jsonl    one JSON line per call
#   .codex-prompts/<session>/<hash>.txt spec sidecar (skipped with -NoLog)
# DEPENDENCIES: OpenAI Codex CLI installed (resolved dynamically)
# EXIT CODES:
#   0 = completed        1 = bad/missing arg
#   2 = Codex not found  3 = codex exec errored (non-zero)
#   4 = timeout/truncated (no turn.completed) -> Claude takes over in-repo
# RELATED:
#   - skills/ask-codex/SKILL.md   (the subagent doctrine + routing)
#   - fixtures/codex-exec-sample.jsonl (real --json event shape)
#   - ask-local.ps1               (sibling: free local model, non-code)
# ============================================================

[CmdletBinding(DefaultParameterSetName="InlinePrompt")]
param(
    [Parameter(Mandatory=$true)]
    [string]$Intent,

    [Parameter(Mandatory=$true, ParameterSetName="InlinePrompt")]
    [string]$Prompt,

    [Parameter(Mandatory=$true, ParameterSetName="FilePrompt")]
    [string]$PromptFile,

    [string]$Resume,

    [switch]$ResumeLast,

    [ValidateSet("read-only","workspace-write","danger-full-access")]
    [string]$Sandbox = "workspace-write",

    [switch]$NoNetwork,

    [string]$ProjectRoot = (Get-Location).Path,

    [string]$Model,

    [string]$ReasoningEffort,

    [string]$Profile,

    [int]$TimeoutSec = 900,

    [switch]$NoLog
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

# ---- Resolve the spec text (from file if -PromptFile was used) --------------
if ($PSCmdlet.ParameterSetName -eq "FilePrompt") {
    if (-not (Test-Path $PromptFile)) {
        Write-Error "PromptFile not found: $PromptFile"
        exit 1
    }
    $Prompt = [System.IO.File]::ReadAllText($PromptFile, $Utf8NoBom)
}
if ([string]::IsNullOrWhiteSpace($Prompt)) {
    Write-Error "Empty spec. Provide -Prompt or -PromptFile with a self-contained task."
    exit 1
}

# ---- Resolve the Codex binary (survives version-hashed install dir) ---------
# Order: $env:CODEX_BIN -> PATH -> newest AppData\Local\OpenAI\Codex\bin\*\codex.exe
$Codex = $null
if ($env:CODEX_BIN -and (Test-Path $env:CODEX_BIN)) {
    $Codex = $env:CODEX_BIN
} else {
    $onPath = Get-Command codex -ErrorAction SilentlyContinue
    if ($onPath) {
        $Codex = $onPath.Source
    } else {
        $glob = Join-Path $env:LOCALAPPDATA "OpenAI\Codex\bin\*\codex.exe"
        $cand = Get-ChildItem $glob -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($cand) { $Codex = $cand.FullName }
    }
}
if (-not $Codex) {
    Write-Error "Codex CLI not found. Set `$env:CODEX_BIN, add codex to PATH, or install it under %LOCALAPPDATA%\OpenAI\Codex."
    exit 2
}

# ---- Preflight: record version (drift visibility) --------------------------
$CodexVersion = "unknown"
try { $CodexVersion = (& $Codex --version 2>$null | Select-Object -First 1).ToString().Trim() } catch {}

# ---- Session id + project root ---------------------------------------------
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$OsRoot = (Resolve-Path (Join-Path $ScriptDir "..")).Path
$ProjectRoot = (Resolve-Path $ProjectRoot).Path
$LogRoot = Join-Path $OsRoot ".codex-log"
$PromptStoreRoot = Join-Path $OsRoot ".codex-prompts"

$SessionId = $env:CLAUDE_SESSION_ID
if (-not $SessionId) { $SessionId = (Get-Date).ToString("yyyyMMdd") }

# hash(spec) for the prompt sidecar
$Sha = [System.Security.Cryptography.SHA256]::Create()
$Hash = ([System.BitConverter]::ToString($Sha.ComputeHash($Utf8NoBom.GetBytes($Prompt))) -replace "-","").ToLower().Substring(0,16)

# ---- Git checkpoint (recoverability; never auto-destroys) ------------------
$IsGitRepo = $false
$Checkpoint = "none"
try {
    Push-Location $ProjectRoot
    git rev-parse --is-inside-work-tree *> $null
    if ($LASTEXITCODE -eq 0) {
        $IsGitRepo = $true
        $Checkpoint = (git rev-parse HEAD 2>$null).Trim()
    }
} catch {} finally { Pop-Location }

# ---- Build codex arguments -------------------------------------------------
$MsgFile = [System.IO.Path]::GetTempFileName()
$IsResume = [bool]($ResumeLast -or $Resume)
$argList = @("exec")
if ($IsResume) {
    # resume continues an existing session; SESSION_ID is positional (omitted for --last)
    $argList += "resume"
    if ($ResumeLast) { $argList += "--last" } else { $argList += $Resume }
}
$argList += @("--json", "--skip-git-repo-check", "--output-last-message", $MsgFile)
# --sandbox / --cd are fresh-run only. `codex exec resume` rejects them; a resumed
# session inherits the original run's sandbox mode and working directory.
if (-not $IsResume) {
    $argList += @("--sandbox", $Sandbox, "--cd", $ProjectRoot)
}
if (-not $NoNetwork) { $argList += @("-c", "sandbox_workspace_write.network_access=true") }
$argList += @("-c", "notify=[]")          # suppress desktop notify in headless runs
if ($Profile)         { $argList += @("--profile", $Profile) }
if ($Model)           { $argList += @("-m", $Model) }
# Reasoning-effort override: without this a cheap -Model still inherits the global
# high effort (the wrapper's cost-leak bug). Passed as a config override, same
# mechanism as notify/network above; applies to fresh and resumed runs.
if ($ReasoningEffort) { $argList += @("-c", "model_reasoning_effort=$ReasoningEffort") }
$argList += "-"                            # read the spec/fix from stdin

# Manual quoting for .NET Framework ProcessStartInfo.Arguments (no ArgumentList)
function Quote-Arg([string]$a) {
    if ($a -match '[\s"]') { '"' + ($a -replace '"','\"') + '"' } else { $a }
}
$argString = ($argList | ForEach-Object { Quote-Arg $_ }) -join " "

# ---- Launch Codex: UTF-8 stdout capture + stdin + timeout ------------------
# stdout is captured with an explicit UTF-8 encoding (NOT a PowerShell `1>`
# redirect, which would mangle it to UTF-16 -- confirmed in Phase 0).
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $Codex
$psi.Arguments = $argString
# Set the process cwd to the project root. Fresh runs also pass --cd, but
# `codex exec resume` has no --cd and operates in the process working
# directory, so this is the only cwd lever the resume path respects.
$psi.WorkingDirectory = $ProjectRoot
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.StandardOutputEncoding = $Utf8NoBom
$psi.StandardErrorEncoding = $Utf8NoBom

$proc = New-Object System.Diagnostics.Process
$proc.StartInfo = $psi

$script:StdOut = New-Object System.Text.StringBuilder
$script:StdErr = New-Object System.Text.StringBuilder
$outEvt = Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -MessageData $script:StdOut -Action {
    if ($null -ne $EventArgs.Data) { [void]$Event.MessageData.AppendLine($EventArgs.Data) }
}
$errEvt = Register-ObjectEvent -InputObject $proc -EventName ErrorDataReceived -MessageData $script:StdErr -Action {
    if ($null -ne $EventArgs.Data) { [void]$Event.MessageData.AppendLine($EventArgs.Data) }
}

$StartTime = Get-Date
$TimedOut = $false
[void]$proc.Start()
$proc.BeginOutputReadLine()
$proc.BeginErrorReadLine()

# Write the spec to stdin as UTF-8 bytes (BaseStream bypasses console encoding)
$inBytes = $Utf8NoBom.GetBytes($Prompt + "`n")
$proc.StandardInput.BaseStream.Write($inBytes, 0, $inBytes.Length)
$proc.StandardInput.BaseStream.Flush()
$proc.StandardInput.Close()

if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
    $TimedOut = $true
    try { $proc.Kill() } catch {}
    $proc.WaitForExit()
}
$proc.WaitForExit()          # ensure async output handlers flush
$ExitCode = $proc.ExitCode

Unregister-Event -SourceIdentifier $outEvt.Name -ErrorAction SilentlyContinue
Unregister-Event -SourceIdentifier $errEvt.Name -ErrorAction SilentlyContinue

$Duration = ((Get-Date) - $StartTime).TotalSeconds
$DurStr = ([math]::Round($Duration, 2)).ToString([System.Globalization.CultureInfo]::InvariantCulture)

# ---- Parse the JSONL event stream ------------------------------------------
$ThreadId = ""
$InTokens = -1; $OutTokens = -1; $CachedInTokens = -1
$SawTurnCompleted = $false
$ChangedFiles = New-Object System.Collections.Generic.HashSet[string]
foreach ($line in ($script:StdOut.ToString() -split "`r?`n")) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    try { $ev = $line | ConvertFrom-Json } catch { continue }
    switch ($ev.type) {
        "thread.started" { if ($ev.thread_id) { $ThreadId = $ev.thread_id } }
        "turn.completed" {
            $SawTurnCompleted = $true
            if ($ev.usage) {
                if ($null -ne $ev.usage.input_tokens)        { $InTokens = [int]$ev.usage.input_tokens }
                if ($null -ne $ev.usage.output_tokens)       { $OutTokens = [int]$ev.usage.output_tokens }
                if ($null -ne $ev.usage.cached_input_tokens) { $CachedInTokens = [int]$ev.usage.cached_input_tokens }
            }
        }
    }
    # file_change items (item.started or item.completed) carry the edits
    if ($ev.item -and $ev.item.type -eq "file_change" -and $ev.item.changes) {
        foreach ($ch in $ev.item.changes) { if ($ch.path) { [void]$ChangedFiles.Add($ch.path) } }
    }
}
$FilesChanged = $ChangedFiles.Count

# ---- Derive status ---------------------------------------------------------
# truncated = cut off before the terminal turn.completed (kill/limit) -> take over here
if ($TimedOut)              { $Status = "truncated"; $Rc = 4 }
elseif ($ExitCode -ne 0)    { $Status = "error";     $Rc = 3 }
elseif (-not $SawTurnCompleted) { $Status = "truncated"; $Rc = 4 }
else                        { $Status = "completed"; $Rc = 0 }

# ---- Last agent message (Codex writes it UTF-8; fallback to stderr) ---------
$LastMessage = ""
if (Test-Path $MsgFile) {
    $LastMessage = [System.IO.File]::ReadAllText($MsgFile, $Utf8NoBom).Trim()
    Remove-Item $MsgFile -ErrorAction SilentlyContinue
}
if ([string]::IsNullOrWhiteSpace($LastMessage) -and $Status -ne "completed") {
    $LastMessage = ($script:StdErr.ToString()).Trim()
}

# ---- Non-mutating change list for the review surface -----------------------
$DiffStat = ""
if ($IsGitRepo) {
    try {
        Push-Location $ProjectRoot
        $DiffStat = (git status --short 2>$null | Out-String).TrimEnd()
    } catch {} finally { Pop-Location }
}
if ([string]::IsNullOrWhiteSpace($DiffStat)) {
    $DiffStat = ($ChangedFiles | ForEach-Object { " ? $_" }) -join "`n"
}

# ---- Structured log line (JSONL) -------------------------------------------
if (-not $NoLog) {
    $LogDir = Join-Path $LogRoot $SessionId
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
    $LogEntry = @{
        ts            = (Get-Date).ToString("o")
        session       = $SessionId
        intent        = $Intent
        model         = if ($Model) { $Model } else { "config" }
        reasoning     = if ($ReasoningEffort) { $ReasoningEffort } else { "config" }
        profile       = if ($Profile) { $Profile } else { "" }
        sandbox       = $Sandbox
        status        = $Status
        thread_id     = $ThreadId
        files_changed = $FilesChanged
        in_tok        = $InTokens
        out_tok       = $OutTokens
        cached_in_tok = $CachedInTokens
        dur_s         = [math]::Round($Duration, 2)
        exit          = $ExitCode
        ckpt          = $Checkpoint
        codex_version = $CodexVersion
        resumed       = [bool]($Resume -or $ResumeLast)
        hash          = $Hash
    } | ConvertTo-Json -Compress
    Add-Content -Path (Join-Path $LogDir "calls.jsonl") -Value $LogEntry -Encoding utf8

    $PromptDir = Join-Path $PromptStoreRoot $SessionId
    if (-not (Test-Path $PromptDir)) { New-Item -ItemType Directory -Force -Path $PromptDir | Out-Null }
    $PromptStoreFile = Join-Path $PromptDir "$Hash.txt"
    if (-not (Test-Path $PromptStoreFile)) {
        [System.IO.File]::WriteAllText($PromptStoreFile, $Prompt, $Utf8NoBom)
    }
}

# ---- Output contract (mirrors ask-local's ---SECTION--- style) -------------
$ModelLabel = if ($Model) { $Model } else { "(config default)" }
$EffortLabel = if ($ReasoningEffort) { $ReasoningEffort } elseif ($Profile) { "profile:$Profile" } else { "(config)" }
Write-Output "---CODEX-CALL-SUMMARY---"
Write-Output ("intent={0} | model={1} | effort={2} | sandbox={3} | status={4} | session={5} | files_changed={6} | ~{7}/{8} tok | {9}s | exit={10} | ckpt={11}" -f `
    $Intent, $ModelLabel, $EffortLabel, $Sandbox, $Status, $ThreadId, $FilesChanged, $InTokens, $OutTokens, $DurStr, $ExitCode, $Checkpoint)
Write-Output "---CODEX-DIFF-STAT---"
Write-Output $DiffStat
Write-Output "---CODEX-OUTPUT---"
Write-Output $LastMessage

# Recovery hint on any non-clean outcome (never auto-runs)
if ($Status -ne "completed" -and $IsGitRepo -and $Checkpoint -ne "none") {
    Write-Output ""
    Write-Output "---CODEX-RECOVERY---"
    Write-Output ("status={0}. To resume Codex on this task:  ask-codex -Intent `"{1} (fix)`" -Resume {2} -PromptFile <fixes>" -f $Status, $Intent, $ThreadId)
    Write-Output ("To DISCARD Codex's edits (destructive):  git -C `"{0}`" reset --hard {1}; git -C `"{0}`" clean -fd" -f $ProjectRoot, $Checkpoint)
    Write-Output "Otherwise: Claude reviews the change list above and finishes in-repo."
}

exit $Rc
