@echo off
REM ============================================================
REM SCRIPT: preflight-trim.bat
REM PURPOSE: Thin CMD wrapper around preflight-trim.ps1.
REM USAGE:
REM   preflight-trim -Path D:\path\to\dir
REM   preflight-trim -Path D:\repo -Filter *.py -MaxFiles 30 -BulletCount 3
REM   preflight-trim -Path D:\repo -Model qwen35-fast -NoCache
REM ============================================================

chcp 65001 >nul
setlocal

if "%~1"=="" (
  echo Usage: preflight-trim -Path ^"D:\path\to\dir^"
  echo Optional: -Filter ^"*.py^" ^| -MaxFiles 50 ^| -BulletCount 3 ^| -Model gemma4-fast-e4b ^| -NoCache
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0preflight-trim.ps1" %*
exit /b %ERRORLEVEL%
