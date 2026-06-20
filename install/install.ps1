# untested on this run — best-effort PowerShell port of install.sh
#
# Reconstructs the two-home layout (~/.claude/{skills,scripts,
# templates/project-bootstrap}) on an adopter machine from this repo's
# home/ and project-template/ snapshot.
#
# Usage:
#   install.ps1 [-DryRun] [-Force] [-TargetDir <projectdir>]
#
# install.sh (Git Bash) is the canonical, verified version — prefer it.
# This port has not been executed/verified in this session.

param(
    [switch]$DryRun,
    [switch]$Force,
    [string]$TargetDir = ""
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir

$HomeClaude = Join-Path $env:USERPROFILE ".claude"
$DateSuffix = Get-Date -Format "yyyy-MM-dd"

$SrcSkills   = Join-Path $RepoRoot "home/skills"
$SrcScripts  = Join-Path $RepoRoot "home/scripts"
$SrcClaudeMd = Join-Path $RepoRoot "home/CLAUDE.md.example"
$SrcTemplate = Join-Path $RepoRoot "project-template"

$DestSkills   = Join-Path $HomeClaude "skills"
$DestScripts  = Join-Path $HomeClaude "scripts"
$DestClaudeMd = Join-Path $HomeClaude "CLAUDE.md"
$DestTemplate = Join-Path $HomeClaude "templates/project-bootstrap"

$Refused = $false

function Plan-Or-Mkdir($dir) {
    if ($DryRun) { Write-Host "[dry-run] mkdir -p $dir" }
    else { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
}

function Plan-Or-Copy($src, $dst) {
    if ($DryRun) { Write-Host "[dry-run] copy $src -> $dst" }
    else { Copy-Item $src -Destination $dst -Recurse }
}

function Plan-Or-Backup($path) {
    $backup = "$path.bak-$DateSuffix"
    if ($DryRun) { Write-Host "[dry-run] backup: $path -> $backup" }
    else {
        Copy-Item $path -Destination $backup -Recurse
        Write-Host "    backed up: $path -> $backup"
    }
}

function Guard-Target($path, $label) {
    if (Test-Path $path) {
        $backup = "$path.bak-$DateSuffix"
        if ((Test-Path $backup) -and (-not $Force)) {
            Write-Error "$label already exists at $path AND a backup $backup already exists. Refusing to overwrite without -Force."
            return $false
        }
        Plan-Or-Backup $path
        if (-not $DryRun) { Remove-Item -Recurse -Force $path }
        else { Write-Host "[dry-run] remove $path" }
    }
    return $true
}

Write-Host "==> Installing workflow OS from $RepoRoot"
if ($DryRun) { Write-Host "    (DRY RUN — no changes will be made)" }

# --- skills ---
Write-Host "--> ~/.claude/skills/"
if (Guard-Target $DestSkills "~/.claude/skills") {
    Plan-Or-Mkdir (Split-Path $DestSkills -Parent)
    Plan-Or-Copy $SrcSkills $DestSkills
} else { $Refused = $true }

# --- scripts ---
Write-Host "--> ~/.claude/scripts/"
if (Guard-Target $DestScripts "~/.claude/scripts") {
    Plan-Or-Mkdir (Split-Path $DestScripts -Parent)
    Plan-Or-Copy $SrcScripts $DestScripts
} else { $Refused = $true }

# --- CLAUDE.md.example -> ~/.claude/CLAUDE.md ---
Write-Host "--> ~/.claude/CLAUDE.md (from CLAUDE.md.example)"
if (Test-Path $SrcClaudeMd) {
    if (Guard-Target $DestClaudeMd "~/.claude/CLAUDE.md") {
        Plan-Or-Mkdir (Split-Path $DestClaudeMd -Parent)
        Plan-Or-Copy $SrcClaudeMd $DestClaudeMd
    } else { $Refused = $true }
} else {
    Write-Host "    (skip: $SrcClaudeMd not found)"
}

# --- project-template -> ~/.claude/templates/project-bootstrap/ ---
Write-Host "--> ~/.claude/templates/project-bootstrap/"
if (Guard-Target $DestTemplate "~/.claude/templates/project-bootstrap") {
    Plan-Or-Mkdir (Split-Path $DestTemplate -Parent)
    Plan-Or-Copy $SrcTemplate $DestTemplate
} else { $Refused = $true }

# --- optional: project-template's project-level files into -TargetDir ---
if ($TargetDir -ne "") {
    Write-Host "--> project files into target: $TargetDir"
    Plan-Or-Mkdir $TargetDir
    # -Force so hidden entries (.claude/ with the RULES, .claudeignore.template,
    # .pre-commit-config.yaml.template) are scaffolded — without it the adopter's
    # project gets no rules/hooks.
    Get-ChildItem $SrcTemplate -Force | ForEach-Object {
        $destItem = Join-Path $TargetDir $_.Name
        if ((Test-Path $destItem) -and (-not $Force)) {
            Write-Error "$destItem already exists. Refusing to overwrite without -Force."
            $Refused = $true
            return
        }
        if (Test-Path $destItem) {
            Plan-Or-Backup $destItem
            if (-not $DryRun) { Remove-Item -Recurse -Force $destItem }
            else { Write-Host "[dry-run] remove $destItem" }
        }
        Plan-Or-Copy $_.FullName $destItem
    }
}

if ($Refused) {
    Write-Host ""
    Write-Error "One or more targets were refused due to existing backups. Re-run with -Force to override."
    exit 1
}

Write-Host ""
Write-Host "==> Install complete."
if ($DryRun) { Write-Host "    (this was a dry run — nothing was written)" }
exit 0
