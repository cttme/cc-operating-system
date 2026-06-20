@echo off
REM ============================================================
REM SCRIPT: ollama-stats.bat
REM PURPOSE: CMD wrapper around ollama-stats.ps1.
REM USAGE:
REM   ollama-stats                       (all sessions, human table)
REM   ollama-stats -Session 20260521     (one session)
REM   ollama-stats -Days 7               (last 7 daily sessions)
REM   ollama-stats -Json                 (machine-readable)
REM ============================================================

chcp 65001 >nul
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ollama-stats.ps1" %*
exit /b %ERRORLEVEL%
