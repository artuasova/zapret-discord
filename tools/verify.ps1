# verify.ps1 - quick health check for zapret-discord
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools\verify.ps1
$ErrorActionPreference = 'Continue'
$fail = 0

function Check([string]$name, [bool]$ok, [string]$detail) {
    if ($ok) { Write-Host ("[PASS] {0,-28} {1}" -f $name, $detail) -ForegroundColor Green }
    else     { Write-Host ("[FAIL] {0,-28} {1}" -f $name, $detail) -ForegroundColor Red; $script:fail++ }
}

$svc = Get-Service zapret-discord -ErrorAction SilentlyContinue
Check 'service exists' ($null -ne $svc) $(if ($svc) { $svc.Name } else { 'not installed' })
Check 'service running' ($svc -and $svc.Status -eq 'Running') $(if ($svc) { $svc.Status } else { '-' })
Check 'service autostart' ($svc -and $svc.StartType -eq 'Automatic') $(if ($svc) { $svc.StartType } else { '-' })

$winws = Get-Process winws -ErrorAction SilentlyContinue
Check 'winws process' ($null -ne $winws) $(if ($winws) { "pid $($winws.Id)" } else { 'not running' })

$checks = [ordered]@{
    'discord api' = 'https://discord.com/api/v9/gateway'
    'discord.com' = 'https://discord.com/'
    'cdn'         = 'https://cdn.discordapp.com/'
    'gateway'     = 'https://gateway.discord.gg/'
}
foreach ($k in $checks.Keys) {
    $r = & curl.exe -sS -o NUL -m 8 -w '%{http_code}|%{time_appconnect}' $checks[$k] 2>$null
    $code = '0'; $tls = '0'
    if ($r -match '^(\d+)\|([\d\.]+)$') { $code = $Matches[1]; $tls = $Matches[2] }
    Check $k ($code -ne '0') "http=$code tls=$tls"
}

$wsOk = $false
try {
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $cts = New-Object System.Threading.CancellationTokenSource
    $cts.CancelAfter(8000)
    $ws.ConnectAsync([Uri]'wss://gateway.discord.gg/?v=9&encoding=json', $cts.Token).Wait()
    $buf = New-Object byte[] 4096
    $seg = New-Object System.ArraySegment[byte](, $buf)
    $t = $ws.ReceiveAsync($seg, $cts.Token); $t.Wait() | Out-Null
    $msg = [Text.Encoding]::UTF8.GetString($buf, 0, $t.Result.Count)
    $wsOk = ($msg -match '"op":10')
    $ws.Dispose()
} catch { $wsOk = $false }
Check 'gateway websocket' $wsOk $(if ($wsOk) { 'OP_HELLO received' } else { 'no HELLO' })

Write-Host ''
if ($fail -eq 0) { Write-Host 'ALL CHECKS PASSED' -ForegroundColor Green; exit 0 }
else { Write-Host "$fail CHECK(S) FAILED - try tools\blockcheck.ps1" -ForegroundColor Red; exit 1 }
