@echo off
setlocal EnableExtensions
title zapret: Discord only - installer
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

net session >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Run this file as Administrator.
  pause
  exit /b 1
)

set "SVC=zapret-discord"
set "BIN=%ROOT%\bin\winws.exe"
set "HOSTLIST=%ROOT%\lists\discord-hosts.txt"

if not exist "%BIN%" ( echo [ERROR] bin\winws.exe not found & pause & exit /b 1 )
if not exist "%HOSTLIST%" ( echo [ERROR] lists\discord-hosts.txt not found & pause & exit /b 1 )

echo [1/5] Stopping old service...
sc stop %SVC% >nul 2>&1
sc delete %SVC% >nul 2>&1
taskkill /f /im winws.exe >nul 2>&1

echo [2/5] Creating service...
set "ARGS=--wf-tcp=443,2053,2083,2087,2096,8443 --wf-udp=50000-50099,19294-19344"
set "ARGS=%ARGS% --filter-tcp=443 --hostlist=%HOSTLIST% --dpi-desync=fake,multidisorder --dpi-desync-split-pos=1,midsld --dpi-desync-fooling=md5sig --dpi-desync-repeats=6"
set "ARGS=%ARGS% --new --filter-tcp=2053,2083,2087,2096,8443 --hostlist=%HOSTLIST% --dpi-desync=fake,multidisorder --dpi-desync-split-pos=1,midsld --dpi-desync-fooling=md5sig --dpi-desync-repeats=6"
set "ARGS=%ARGS% --new --filter-udp=50000-50099 --filter-l7=discord,stun --dpi-desync=fake --dpi-desync-repeats=6"
set "ARGS=%ARGS% --new --filter-udp=19294-19344 --filter-l7=discord,stun --dpi-desync=fake --dpi-desync-repeats=6"

sc create %SVC% binPath= "\"%BIN%\" %ARGS%" DisplayName= "zapret: Discord only" start= auto
if errorlevel 1 ( echo [ERROR] Failed to create service & pause & exit /b 1 )
sc description %SVC% "Local DPI bypass for Discord only (winws + WinDivert)"
sc failure %SVC% reset= 86400 actions= restart/1000/restart/2000/restart/5000 >nul 2>&1

echo [3/5] Starting service...
sc start %SVC%
timeout /t 3 >nul

echo [4/5] Checking service state...
sc query %SVC% | findstr /i "RUNNING" >nul
if errorlevel 1 echo [WARN] Service is not RUNNING. See README troubleshooting.

echo [5/5] Testing Discord API...
curl.exe -s -o NUL -m 10 -w "  discord.com/api -> HTTP %%{http_code} (want 200)\n" https://discord.com/api/v9/gateway
curl.exe -s -o NUL -m 10 -w "  discord.com     -> HTTP %%{http_code} (want 200)\n" https://discord.com/

echo.
echo Done. Start Discord and check chat and voice.
pause
endlocal
