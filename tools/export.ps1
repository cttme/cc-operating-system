# untested on this run — best-effort PowerShell port of export.sh
#
# Copies + sanitizes the live Claude Code "workflow operating system" from
# ~/.claude/ (global) and D:/cc/Mantikli/.claude/ (project) into this repo's
# home/, project-template/, docs/, and PORTABILITY.md.
#
# Mirrors tools/export.sh. export.sh (Git Bash) is the canonical, verified
# version — prefer it. This port has not been executed/verified in this session.

$ErrorActionPreference = "Stop"

$HomeClaude     = if ($env:HOME_CLAUDE) { $env:HOME_CLAUDE } else { Join-Path $env:USERPROFILE ".claude" }
$MantikliClaude = if ($env:MANTIKLI_CLAUDE) { $env:MANTIKLI_CLAUDE } else { "D:/cc/Mantikli/.claude" }

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir

$DestSkills    = Join-Path $RepoRoot "home/skills"
$DestScripts   = Join-Path $RepoRoot "home/scripts"
$DestClaudeMd  = Join-Path $RepoRoot "home/CLAUDE.md.example"
$DestTemplate  = Join-Path $RepoRoot "project-template"
$DestDocs      = Join-Path $RepoRoot "docs"

$SrcSkills    = Join-Path $HomeClaude "skills"
$SrcScripts   = Join-Path $HomeClaude "scripts"
$SrcClaudeMd  = Join-Path $HomeClaude "CLAUDE.md"
$SrcTemplate  = Join-Path $HomeClaude "templates/project-bootstrap"
$SrcMantikliSkills = Join-Path $MantikliClaude "skills"

$SkillsCopied = 0
$ScriptsCopied = 0
$NestedRemoved = 0
$SedApplied = 0
$SedNotFound = 0

Write-Host "==> Exporting workflow OS snapshot into $RepoRoot"

# --- a. home/skills/ ---
Write-Host "--> [a] home/skills/"
if (Test-Path $DestSkills) { Remove-Item -Recurse -Force $DestSkills }
New-Item -ItemType Directory -Force -Path $DestSkills | Out-Null

if (Test-Path $SrcSkills) {
    Get-ChildItem $SrcSkills | ForEach-Object {
        $base = $_.Name
        if ($base -like "audit-*" -or $base -eq "__pycache__" -or $base -like "*.bak-*") { return }
        Copy-Item $_.FullName -Destination (Join-Path $DestSkills $base) -Recurse
        $SkillsCopied++
    }
}

Get-ChildItem -Path $DestSkills -Recurse -Directory -Filter "__pycache__" -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-Item -Recurse -Force $_.FullName }
Get-ChildItem -Path $DestSkills -Recurse -Filter "*.bak-*" -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-Item -Recurse -Force $_.FullName }

Get-ChildItem -Path $DestSkills -Directory | ForEach-Object {
    $name = $_.Name
    $nested = Join-Path $_.FullName $name
    if (Test-Path $nested) {
        Remove-Item -Recurse -Force $nested
        $NestedRemoved++
        Write-Host "    removed nested dir: $name/$name"
    }
}

foreach ($extra in @("cave", "normal")) {
    $src = Join-Path $SrcMantikliSkills $extra
    if (Test-Path $src) {
        Copy-Item $src -Destination (Join-Path $DestSkills $extra) -Recurse
        $SkillsCopied++
    }
}
$reviewMd = Join-Path $SrcMantikliSkills "review.md"
if (Test-Path $reviewMd) {
    Copy-Item $reviewMd -Destination (Join-Path $DestSkills "review.md")
}

# --- b. home/scripts/ ---
Write-Host "--> [b] home/scripts/"
if (Test-Path $DestScripts) { Remove-Item -Recurse -Force $DestScripts }
New-Item -ItemType Directory -Force -Path $DestScripts | Out-Null

if (Test-Path $SrcScripts) {
    Get-ChildItem $SrcScripts | ForEach-Object {
        $base = $_.Name
        if ($base -eq "__pycache__" -or $base -like "*.bak-*") { return }
        Copy-Item $_.FullName -Destination (Join-Path $DestScripts $base) -Recurse
        $ScriptsCopied++
    }
}
Get-ChildItem -Path $DestScripts -Recurse -Directory -Filter "__pycache__" -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-Item -Recurse -Force $_.FullName }
Get-ChildItem -Path $DestScripts -Recurse -Filter "*.bak-*" -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-Item -Recurse -Force $_.FullName }

# --- c. home/CLAUDE.md.example ---
Write-Host "--> [c] home/CLAUDE.md.example"
if (Test-Path $SrcClaudeMd) { Copy-Item $SrcClaudeMd -Destination $DestClaudeMd }

# --- d. project-template/ ---
Write-Host "--> [d] project-template/"
if (Test-Path $DestTemplate) { Remove-Item -Recurse -Force $DestTemplate }
New-Item -ItemType Directory -Force -Path $DestTemplate | Out-Null

$excludeNames = @(".git", "__pycache__", ".preflight", "BACKPORT.md", "ENGINEERING_PATTERNS.md", "DELEGATION_GATES.md")
if (Test-Path $SrcTemplate) {
    # -Force is required so hidden entries (.claude/, .claudeignore.template,
    # .pre-commit-config.yaml.template) are copied — without it Get-ChildItem skips
    # them and the rules + hooks that ARE the operating system get dropped.
    Get-ChildItem $SrcTemplate -Force | ForEach-Object {
        $base = $_.Name
        if ($excludeNames -contains $base -or $base -like "*.bak-*") { return }
        Copy-Item $_.FullName -Destination (Join-Path $DestTemplate $base) -Recurse -Force
    }
}
foreach ($n in @(".git", "__pycache__", ".preflight")) {
    Get-ChildItem -Path $DestTemplate -Recurse -Directory -Filter $n -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-Item -Recurse -Force $_.FullName }
}
Get-ChildItem -Path $DestTemplate -Recurse -Filter "*.bak-*" -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-Item -Recurse -Force $_.FullName }

# --- e. docs/ ---
Write-Host "--> [e] docs/"
New-Item -ItemType Directory -Force -Path $DestDocs | Out-Null
$ep = Join-Path $SrcTemplate "ENGINEERING_PATTERNS.md"
$dg = Join-Path $SrcTemplate "DELEGATION_GATES.md"
if (Test-Path $ep) { Copy-Item $ep -Destination (Join-Path $DestDocs "ENGINEERING_PATTERNS.md") }
if (Test-Path $dg) { Copy-Item $dg -Destination (Join-Path $DestDocs "DELEGATION_GATES.md") }
# BACKPORT.md deliberately dropped.

# --- f. PORTABILITY.md — repo-owned, NOT auto-synced ---
# Adapted by hand to document what THIS repo ships; a verbatim copy of the source
# manifest would reference project-only rules this repo does not include.
Write-Host "--> [f] PORTABILITY.md (repo-owned — skipped, not auto-synced)"

# --- g. sed sanitization (regex replace, idempotent) ---
Write-Host "--> [g] sanitization"

$verifySkill = Join-Path $DestSkills "verify/SKILL.md"
$sessionEndSkill = Join-Path $DestSkills "session-end/SKILL.md"
$askLocalSkill = Join-Path $DestSkills "ask-local/SKILL.md"

if (Test-Path $verifySkill) {
    $content = Get-Content $verifySkill -Raw
    if ($content -match "Mantikli.*``/clear``.*öncesi:") {
        $content = $content -replace ".*Mantikli.*``/clear``.*öncesi:.*", "- **Before ``/clear``:** Devir öncesi son sağlık kontrolu"
        Set-Content -Path $verifySkill -Value $content -NoNewline
        $SedApplied++
        Write-Host "    [applied] verify/SKILL.md"
    } else {
        $SedNotFound++
        Write-Host "    [NOT FOUND] verify/SKILL.md"
    }
}

if (Test-Path $sessionEndSkill) {
    $content = Get-Content $sessionEndSkill -Raw
    if ($content -match "Eski mekanizma fallback.*Mantikli'de /onboard kullanmazsa kullanıcı kopyala-yapıştır için:") {
        $content = $content -replace "Eski mekanizma fallback.*Mantikli'de /onboard kullanmazsa kullanıcı kopyala-yapıştır için:", "Fallback mechanism — if /onboard isn't used, for copy-paste:"
        Set-Content -Path $sessionEndSkill -Value $content -NoNewline
        $SedApplied++
        Write-Host "    [applied] session-end/SKILL.md"
    } else {
        $SedNotFound++
        Write-Host "    [NOT FOUND] session-end/SKILL.md"
    }
}

if (Test-Path $askLocalSkill) {
    $content = Get-Content $askLocalSkill -Raw
    $pattern = "\(Project-specific examples in düzhesap: ``matcher/fuzzy`` match\s*\r?\n\s*decisions, price & stock calls, ``POLICY\.md``\.\)"
    if ($content -match $pattern) {
        $content = $content -replace $pattern, "(Project-specific examples: record-matching decisions, money/pricing calls, your policy doc.)"
        Set-Content -Path $askLocalSkill -Value $content -NoNewline
        $SedApplied++
        Write-Host "    [applied] ask-local/SKILL.md"
    } else {
        $SedNotFound++
        Write-Host "    [NOT FOUND] ask-local/SKILL.md"
    }
}

Write-Host ""
Write-Host "==> Export summary"
Write-Host "    skills copied:        $SkillsCopied"
Write-Host "    scripts/files copied: $ScriptsCopied"
Write-Host "    nested dirs removed:  $NestedRemoved"
Write-Host "    sed replacements applied:   $SedApplied"
Write-Host "    sed replacements NOT found: $SedNotFound"
Write-Host "==> Done."
