@echo off
rem Default strategy: fake + multidisorder + md5sig
setlocal
net session >nul 2>&1
if errorlevel 1 ( echo Run as Administrator & pause & exit /b 1 )
set "ROOT=%~dp0.."
set "HOSTLIST=%ROOT%\lists\discord-hosts.txt"
set "BIN=%ROOT%\bin\winws.exe"
set "ARGS=--wf-tcp=443,2053,2083,2087,2096,8443 --wf-udp=50000-50099,19294-19344"
set "ARGS=%ARGS% --filter-tcp=443 --hostlist=%HOSTLIST% --dpi-desync=fake,multidisorder --dpi-desync-split-pos=1,midsld --dpi-desync-fooling=md5sig --dpi-desync-repeats=6"
set "ARGS=%ARGS% --new --filter-tcp=2053,2083,2087,2096,8443 --hostlist=%HOSTLIST% --dpi-desync=fake,multidisorder --dpi-desync-split-pos=1,midsld --dpi-desync-fooling=md5sig --dpi-desync-repeats=6"
set "ARGS=%ARGS% --new --filter-udp=50000-50099 --filter-l7=discord,stun --dpi-desync=fake --dpi-desync-repeats=6"
set "ARGS=%ARGS% --new --filter-udp=19294-19344 --filter-l7=discord,stun --dpi-desync=fake --dpi-desync-repeats=6"
sc config zapret-discord binPath= "\"%BIN%\" %ARGS%"
net stop zapret-discord
net start zapret-discord
pause
