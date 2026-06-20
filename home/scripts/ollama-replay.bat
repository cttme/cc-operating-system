@echo off
REM ============================================================
REM SCRIPT: ollama-replay.bat
REM PURPOSE: Thin CMD wrapper around ollama-replay.ps1.
REM USAGE:
REM   ollama-replay -Last
REM   ollama-replay -Hash 03e915
REM   ollama-replay -IntentMatch "summarize"
REM   ollama-replay -Last -Compare
REM   ollama-replay -Hash 03e915 -Compare -Model qwen35-fast
REM ============================================================

chcp 65001 >nul
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ollama-replay.ps1" %*
exit /b %ERRORLEVEL%
