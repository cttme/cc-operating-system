@echo off
REM ============================================================
REM SCRIPT: ask-codex.bat
REM PURPOSE: Thin CMD wrapper around ask-codex.ps1. Forwards all
REM          named PowerShell parameters and exit code.
REM USAGE:
REM   ask-codex -Intent "impl parser" -PromptFile C:\path\to\spec.txt
REM   ask-codex -Intent "refactor auth" -Prompt "the self-contained spec"
REM   ask-codex -Intent "fix review notes" -Resume 019f... -PromptFile fixes.txt
REM   ask-codex -Intent "analyze module" -Sandbox read-only -Prompt "..."
REM Use -PromptFile for multiline / special-character specs (<, >, quotes)
REM to avoid CLI argument-escaping issues.
REM EXIT CODES: 0=completed 1=bad arg 2=codex not found 3=exec error
REM             4=timeout/truncated (Claude takes over in-repo)
REM ============================================================

chcp 65001 >nul
setlocal

if "%~1"=="" (
  echo Usage: ask-codex -Intent ^"task label^" -PromptFile path\to\spec.txt
  echo    or: ask-codex -Intent ^"task label^" -Prompt ^"the self-contained spec^"
  echo Optional: -Resume ^<id^> ^| -ResumeLast ^| -Sandbox read-only^|workspace-write ^| -NoNetwork ^| -Model ^<m^> ^| -TimeoutSec ^<n^> ^| -NoLog
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ask-codex.ps1" %*
exit /b %ERRORLEVEL%
