@echo off
setlocal
title zapret: Discord only - uninstaller
set "QUIET=0"
if /i "%~1"=="/quiet" set "QUIET=1"
net session >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Run this file as Administrator.
  if "%QUIET%"=="0" pause
  exit /b 1
)

echo [1/5] Removing scheduled tasks...
if exist "%~dp0tools\remove-tasks.ps1" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\remove-tasks.ps1"
timeout /t 1 >nul

echo [2/5] Stopping service...
sc stop zapret-discord >nul 2>&1
sc delete zapret-discord >nul 2>&1
taskkill /f /im winws.exe >nul 2>&1
timeout /t 2 >nul

echo [3/5] Removing WinDivert driver...
sc stop windivert >nul 2>&1
sc delete windivert >nul 2>&1
timeout /t 2 >nul

echo [4/5] Checking leftovers...
sc query zapret-discord >nul 2>&1
if not errorlevel 1 echo [WARN] Service zapret-discord still present. Reboot required.
sc query windivert >nul 2>&1
if not errorlevel 1 echo [WARN] Driver windivert still present. Reboot required.

echo [5/5] Done. Discord bypass removed, normal internet untouched.
if "%QUIET%"=="0" pause
endlocal
