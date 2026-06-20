@echo off
REM ============================================================
REM SCRIPT: ask-local.bat
REM PURPOSE: Thin CMD wrapper around ask-local.ps1. Forwards all
REM          named PowerShell parameters and exit code.
REM USAGE:
REM   ask-local -Intent "summarize log" -Prompt "the prompt text"
REM   ask-local -Intent "classify commit" -Prompt "fix auth retry" -Model gemma4-fast-e4b -Tier T1
REM   ask-local -Intent "summarize file" -PromptFile C:\path\to\prompt.txt
REM   ask-local -Intent "private analysis" -Prompt "..." -NoLog
REM Use -PromptFile for multiline or special-character content (<, >, quotes)
REM to avoid CLI argument-escaping issues.
REM NOTE: Run "chcp 65001" before this script if your CMD shows
REM       garbled non-ASCII characters; this wrapper also calls it.
REM ============================================================

chcp 65001 >nul
setlocal

if "%~1"=="" (
  echo Usage: ask-local -Intent ^"purpose^" -Prompt ^"the prompt^"
  echo    or: ask-local -Intent ^"purpose^" -PromptFile path\to\prompt.txt
  echo Optional: -Model gemma4-fast-e4b ^| -Tier T0^|T1^|T2 ^| -NoCache ^| -NoLog
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ask-local.ps1" %*
exit /b %ERRORLEVEL%
