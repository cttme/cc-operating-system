# ============================================================
# SCRIPT: test-ask-codex.ps1
# PURPOSE: Offline regression guard for ask-codex.ps1. Asserts the
#          Codex `exec --json` event contract the wrapper depends on,
#          using the recorded fixture (no API call, no tokens spent).
#          If a Codex update changes the event schema, re-capture a
#          fresh sample over the fixture and run this to see what broke.
# USAGE:   powershell -NoProfile -ExecutionPolicy Bypass -File test-ask-codex.ps1
# EXIT:    0 = all assertions pass, 1 = a contract assertion failed
# RELATED: ask-codex.ps1, fixtures/codex-exec-sample.jsonl
# ============================================================

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Fixture = Join-Path $ScriptDir "fixtures\codex-exec-sample.jsonl"
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Output "  PASS  $msg" } else { Write-Output "  FAIL  $msg"; $script:fail++ }
}

Write-Output "test-ask-codex: parsing $Fixture"
Assert (Test-Path $Fixture) "fixture exists"

# Parse with the same logic ask-codex.ps1 uses (thread_id / turn.completed / file_change)
$ThreadId = ""; $InTok = -1; $OutTok = -1; $SawTurnCompleted = $false
$Changed = New-Object System.Collections.Generic.HashSet[string]
foreach ($line in (Get-Content $Fixture)) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $ev = $line | ConvertFrom-Json
    switch ($ev.type) {
        "thread.started" { if ($ev.thread_id) { $ThreadId = $ev.thread_id } }
        "turn.completed" {
            $SawTurnCompleted = $true
            if ($ev.usage) { $InTok = [int]$ev.usage.input_tokens; $OutTok = [int]$ev.usage.output_tokens }
        }
    }
    if ($ev.item -and $ev.item.type -eq "file_change" -and $ev.item.changes) {
        foreach ($ch in $ev.item.changes) { if ($ch.path) { [void]$Changed.Add($ch.path) } }
    }
}

# Contract assertions -- these are exactly the fields the wrapper reads
Assert ($ThreadId -match '^[0-9a-f-]{16,}$') "thread.started carries a thread_id (session id) -> $ThreadId"
Assert ($SawTurnCompleted)                   "a terminal turn.completed event is present (status signal)"
Assert ($InTok -gt 0 -and $OutTok -ge 0)     "turn.completed.usage has input/output tokens -> $InTok/$OutTok"
Assert ($Changed.Count -eq 1)                "file_change items yield the changed-file list -> $($Changed.Count)"

if ($fail -eq 0) { Write-Output "test-ask-codex: OK (contract intact)"; exit 0 }
else             { Write-Output "test-ask-codex: $fail assertion(s) FAILED -- Codex event schema may have drifted"; exit 1 }
