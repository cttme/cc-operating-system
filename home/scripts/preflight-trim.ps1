# ============================================================
# SCRIPT: preflight-trim.ps1
# VERSION: 0.1.0
# PURPOSE: Pre-flight context trim. Summarize every eligible file in
#          a target directory via local Ollama (using ask-local.ps1
#          internally), then emit a single Markdown digest that Claude
#          can read in place of the originals.
# WHEN TO USE:
#   - Before sending Claude a large directory for exploration
#   - To produce a "what's in this codebase" cheat sheet
# WHEN NOT TO USE:
#   - Directory has < 5 files (overhead > savings)
#   - All files are binary / minified (skip rate would be ~100%)
#   - You need Claude to actually edit the files (digest is read-only)
# INPUTS (named PowerShell parameters):
#   -Path        <dir>     REQUIRED, directory to scan
#   -Filter      <glob>    optional, default *
#   -MaxFiles    <int>     optional, default 50 (runaway guard)
#   -BulletCount <int>     optional, default 3
#   -Model       <name>    optional, default gemma4-fast-e4b
#   -OutputDir   <path>    optional, default <Path>\.preflight
#   -NoCache               optional switch, passes through to ask-local
# OUTPUTS:
#   stdout: progress lines + final summary block
#   <OutputDir>\digest-<timestamp>.md   the aggregated digest
# DEPENDENCIES: ask-local.ps1 (must sit next to this file)
# EXIT CODES: 0=ok, 1=missing/bad args, 2=ask-local missing,
#             3=path not found, 4=no eligible files
# RELATED:
#   - scripts/ask-local.ps1  (the per-file worker)
#   - templates/local-prompts/summarize-file.md
# ============================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$Path,

    [string]$Filter = "*",

    [int]$MaxFiles = 50,

    [int]$BulletCount = 3,

    [string]$Model = "gemma4-fast-e4b",

    [string]$OutputDir,

    [switch]$NoCache
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AskLocal = Join-Path $ScriptDir "ask-local.ps1"

# Sanity
if (-not (Test-Path $AskLocal)) {
    Write-Error "ask-local.ps1 not found next to this script ($AskLocal)"
    exit 2
}
if (-not (Test-Path $Path)) {
    Write-Error "Path not found: $Path"
    exit 3
}
$Path = (Resolve-Path $Path).Path

if (-not $OutputDir) {
    $OutputDir = Join-Path $Path ".preflight"
}
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
}

# --- Ollama health helpers ---------------------------------------------
function Test-OllamaHealthy {
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:11434/api/version" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        return ($r.StatusCode -eq 200)
    } catch {
        return $false
    }
}

function Wait-OllamaRecovery {
    param([int]$MaxWaitSec = 30)
    $elapsed = 0
    while ($elapsed -lt $MaxWaitSec) {
        if (Test-OllamaHealthy) { return $true }
        Start-Sleep -Seconds 2
        $elapsed += 2
        Write-Output "    (waiting for Ollama... ${elapsed}s)"
    }
    return $false
}

# Pre-batch check
if (-not (Test-OllamaHealthy)) {
    Write-Error "Ollama is not reachable at http://localhost:11434. Start the service and retry."
    exit 2
}

# --- Skip rule helpers -------------------------------------------------
$BinaryExt = @(
    ".exe",".dll",".so",".dylib",".bin",".dat",".obj",".o",".a",".lib",
    ".png",".jpg",".jpeg",".gif",".bmp",".ico",".tiff",".webp",".svg",
    ".pdf",".zip",".gz",".tar",".7z",".rar",".jar",".whl",
    ".mp3",".wav",".mp4",".mkv",".avi",".mov",
    ".pyc",".class",".woff",".woff2",".ttf",".otf",".eot",
    ".db",".sqlite",".sqlite3"
)

function Should-Skip {
    param([string]$FullPath)

    $Item = Get-Item -LiteralPath $FullPath -Force

    # Symlinks: skip (loop / external risk)
    if ($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        return @{ skip = $true; reason = "symlink" }
    }

    $Ext = $Item.Extension.ToLower()
    if ($BinaryExt -contains $Ext) {
        return @{ skip = $true; reason = "binary extension $Ext" }
    }

    if ($Item.Length -eq 0) {
        return @{ skip = $true; reason = "empty" }
    }

    if ($Item.Length -gt 20480) {
        return @{ skip = $true; reason = "too large ($($Item.Length) bytes > 20 KB)" }
    }

    # Read content (UTF-8 first, fall back to default ANSI)
    try {
        $Content = [System.IO.File]::ReadAllText($FullPath, [System.Text.UTF8Encoding]::new($false, $true))
    } catch {
        try {
            $Content = [System.IO.File]::ReadAllText($FullPath, [System.Text.Encoding]::Default)
        } catch {
            return @{ skip = $true; reason = "unreadable encoding" }
        }
    }

    $LineCount = ($Content -split "`n").Count
    if ($Item.Length -lt 500 -and $LineCount -lt 20) {
        return @{ skip = $true; reason = "tiny (<500 bytes, <20 lines)" }
    }

    # Minified heuristic: one line, >5 KB
    if ($LineCount -le 2 -and $Item.Length -gt 5120) {
        return @{ skip = $true; reason = "looks minified (single line, $($Item.Length) bytes)" }
    }

    return @{ skip = $false; content = $Content; line_count = $LineCount }
}

# --- Discover candidates -----------------------------------------------
Write-Output "Scanning $Path (filter: $Filter, max: $MaxFiles)..."

$Candidates = @(
    Get-ChildItem -Path $Path -Filter $Filter -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notlike "*\.preflight\*" -and
                       $_.FullName -notlike "*\.ollama-log\*" -and
                       $_.FullName -notlike "*\.ollama-cache\*" -and
                       $_.FullName -notlike "*\.git\*" } |
        Sort-Object FullName
)

if ($Candidates.Count -eq 0) {
    Write-Error "No files matched filter '$Filter' under $Path"
    exit 4
}

Write-Output "Found $($Candidates.Count) candidate files (will process at most $MaxFiles)."

# --- Process ----------------------------------------------------------
$Processed = @()
$Skipped = @()
$Errors = @()
$RawByteSum = 0
$DigestStartTime = Get-Date

$Limit = [Math]::Min($Candidates.Count, $MaxFiles)
for ($i = 0; $i -lt $Limit; $i++) {
    $File = $Candidates[$i]
    $Rel = $File.FullName.Substring($Path.Length).TrimStart('\','/')
    $Verdict = Should-Skip $File.FullName

    if ($Verdict.skip) {
        $Skipped += [PSCustomObject]@{ path = $Rel; reason = $Verdict.reason }
        Write-Output "  [skip] $Rel  --  $($Verdict.reason)"
        continue
    }

    $RawByteSum += $File.Length

    # Compose prompt from template (kept in sync with
    # templates/local-prompts/summarize-file.md)
    $Prompt = @"
You will summarize a single file. File name: $Rel ($($File.Length) bytes).

Output rules:
1. Produce EXACTLY $BulletCount bullet points. No preamble, no closing remarks.
   No meta-commentary about these rules.
2. Each bullet starts with a present-tense verb describing what the file does.
3. Mention named entities verbatim from the source: function names,
   class names, file paths, error codes, configuration keys. Do NOT
   include quantities unless the source contains an explicit numeric
   token for you to echo. Never write "N+", "around N", "approximately
   N", "over N", "more than N". If you cannot find an exact number in
   the source, omit the count entirely and list named entities only.
   Also avoid vague words: "various", "several", "many", "some",
   "utility".
4. The output is EITHER $BulletCount normal bullets OR a single UNREADABLE
   bullet -- never a mix.
5. Marker rule (apply ONLY when condition is true):
   - IF AND ONLY IF the file content contains the literal text TODO,
     FIXME, HACK, or XXX, THEN replace the first bullet with one that
     starts with "FLAG:" and quotes the marker context (under 20 words).
   - If none of those markers are present, do NOT mention markers at all.
     Never write "no markers" or "no TODO" in the output.
6. Keep each bullet under 25 words.
7. Single UNREADABLE option (use only when normal summarization is impossible):
   - Output exactly one bullet starting with "UNREADABLE: " followed by
     a short reason. Do not add any other bullets in this case.

File content:
---
$($Verdict.content)
---
"@

    Write-Output "  [trim] $Rel  ($($File.Length) bytes, $($Verdict.line_count) lines)..."

    # Write the prompt to a temp file to avoid CLI arg-escaping issues on
    # multiline / special-character content (<, >, quotes, etc.).
    $TempPrompt = [System.IO.Path]::GetTempFileName()
    $Summary = $null
    $LastError = $null
    try {
        [System.IO.File]::WriteAllText($TempPrompt, $Prompt, [System.Text.UTF8Encoding]::new($false))

        $askArgs = @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $AskLocal,
            "-Intent", "preflight summarize $Rel",
            "-PromptFile", $TempPrompt,
            "-Model", $Model,
            "-Tier", "T1"
        )
        if ($NoCache) { $askArgs += "-NoCache" }

        # Retry loop: up to 3 attempts with backoff (1s, 2s, 4s).
        # On connection-class errors, pause + try to recover Ollama.
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                $RawOutput = & powershell $askArgs 2>&1
                $OutputText = ($RawOutput | Out-String)
                $Match = $OutputText -split "---OLLAMA-OUTPUT---", 2
                if ($Match.Count -eq 2) {
                    $Summary = $Match[1].Trim()
                    break
                } else {
                    # Likely "Ollama unreachable" from ask-local -> exit 2 prints error to stderr,
                    # output has no delimiter. Treat as recoverable.
                    $LastError = "no delimiter; raw: $($OutputText.Substring(0,[Math]::Min(120,$OutputText.Length)))"
                }
            } catch {
                $LastError = $_.Exception.Message
            }

            if ($attempt -lt 3) {
                $sleepSec = [math]::Pow(2, $attempt - 1)
                Write-Output "    (attempt $attempt failed; backing off ${sleepSec}s)"
                Start-Sleep -Seconds $sleepSec
                if (-not (Test-OllamaHealthy)) {
                    Write-Output "    (Ollama down; waiting for recovery up to 30s)"
                    if (-not (Wait-OllamaRecovery -MaxWaitSec 30)) {
                        $LastError = "Ollama did not recover within 30s"
                        break
                    }
                }
            }
        }

        if ($Summary) {
            $Processed += [PSCustomObject]@{
                path     = $Rel
                size     = $File.Length
                lines    = $Verdict.line_count
                summary  = $Summary
            }
        } else {
            $Errors += [PSCustomObject]@{ path = $Rel; reason = $LastError }
            Write-Output "    ! failed after retries: $LastError"
        }
    } catch {
        $Errors += [PSCustomObject]@{ path = $Rel; reason = $_.Exception.Message }
        Write-Output "    ! exception: $($_.Exception.Message)"
    } finally {
        if (Test-Path $TempPrompt) { Remove-Item -Force $TempPrompt }
    }

    # Inter-call breathing room — prevents hammering Ollama
    Start-Sleep -Milliseconds 200
}

# --- Emit digest ------------------------------------------------------
$Ts = (Get-Date).ToString("yyyyMMdd-HHmmss")
$DigestPath = Join-Path $OutputDir "digest-$Ts.md"

$DigestBuilder = [System.Text.StringBuilder]::new()
[void]$DigestBuilder.AppendLine("# Pre-flight digest")
[void]$DigestBuilder.AppendLine("")
[void]$DigestBuilder.AppendLine("- **Source:** $Path")
[void]$DigestBuilder.AppendLine("- **Filter:** $Filter")
[void]$DigestBuilder.AppendLine("- **Generated:** $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))")
[void]$DigestBuilder.AppendLine("- **Model:** $Model")
[void]$DigestBuilder.AppendLine("- **Files processed:** $($Processed.Count) | skipped: $($Skipped.Count) | errors: $($Errors.Count)")
[void]$DigestBuilder.AppendLine("- **Raw input bytes (processed):** $RawByteSum")
[void]$DigestBuilder.AppendLine("")
[void]$DigestBuilder.AppendLine("---")
[void]$DigestBuilder.AppendLine("")

foreach ($p in $Processed) {
    [void]$DigestBuilder.AppendLine("## $($p.path)  ($($p.size) bytes, $($p.lines) lines)")
    [void]$DigestBuilder.AppendLine("")
    [void]$DigestBuilder.AppendLine($p.summary)
    [void]$DigestBuilder.AppendLine("")
}

if ($Skipped.Count -gt 0) {
    [void]$DigestBuilder.AppendLine("## Skipped")
    [void]$DigestBuilder.AppendLine("")
    foreach ($s in $Skipped) {
        [void]$DigestBuilder.AppendLine("- ``$($s.path)`` -- $($s.reason)")
    }
    [void]$DigestBuilder.AppendLine("")
}

if ($Errors.Count -gt 0) {
    [void]$DigestBuilder.AppendLine("## Errors")
    [void]$DigestBuilder.AppendLine("")
    foreach ($e in $Errors) {
        [void]$DigestBuilder.AppendLine("- ``$($e.path)`` -- $($e.reason)")
    }
    [void]$DigestBuilder.AppendLine("")
}

$DigestBuilder.ToString() | Out-File -FilePath $DigestPath -Encoding utf8 -NoNewline

$DigestBytes = (Get-Item $DigestPath).Length
$Reduction = if ($RawByteSum -gt 0) {
    [math]::Round((1 - ($DigestBytes / $RawByteSum)) * 100, 1)
} else { 0 }
$DurStr = ([math]::Round(((Get-Date) - $DigestStartTime).TotalSeconds, 1)).ToString([System.Globalization.CultureInfo]::InvariantCulture)

Write-Output ""
Write-Output "---PREFLIGHT-TRIM-SUMMARY---"
Write-Output "files=processed:$($Processed.Count) skipped:$($Skipped.Count) errors:$($Errors.Count)"
Write-Output "bytes=raw:$RawByteSum digest:$DigestBytes reduction:$Reduction%"
Write-Output "duration=${DurStr}s"
Write-Output "digest=$DigestPath"

exit 0
