# collect-diagnostics.ps1 - gather state/logs into a zip for bug reports.
$ErrorActionPreference = 'Continue'

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$logsDir = Join-Path $root 'tools\logs'
New-Item -ItemType Directory -Force -Path $logsDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$tmp = Join-Path $env:TEMP ("zapret-diag-" + $stamp)
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

function Try-Run([string]$file, [string]$cmd) {
    try { $out = & cmd.exe /c $cmd 2>&1; $out | Out-File -FilePath (Join-Path $tmp $file) -Encoding utf8 }
    catch { "ERROR: $($_.Exception.Message)" | Out-File -FilePath (Join-Path $tmp $file) -Encoding utf8 }
}

$version = 'unknown'
if (Test-Path (Join-Path $root 'VERSION')) { $version = (Get-Content (Join-Path $root 'VERSION') -Raw).Trim() }

$sys = @()
$sys += "zapret-discord diagnostics"
$sys += "version: $version"
$sys += "date: $(Get-Date -Format o)"
$sys += "os: $((Get-CimInstance Win32_OperatingSystem).Caption) $((Get-CimInstance Win32_OperatingSystem).Version)"
$sys += "user: $env:USERNAME"
$sys += "admin: " + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$sys += ''
$sys += '--- service ---'
$sys += (sc.exe qc zapret-discord 2>&1 | Out-String)
$sys += (sc.exe query zapret-discord 2>&1 | Out-String)
$sys += '--- driver ---'
$sys += (sc.exe qc windivert 2>&1 | Out-String)
$sys += '--- process ---'
$sys += (Get-Process winws -ErrorAction SilentlyContinue | Format-List Id,StartTime,CPU,WorkingSet64 | Out-String)
$sys += '--- adapters ---'
$sys += (Get-NetAdapter | Select-Object Name,Status,InterfaceDescription,LinkSpeed | Format-Table -AutoSize | Out-String)
$sys += '--- default route ---'
$sys += (Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Select-Object InterfaceAlias,NextHop,RouteMetric,ifMetric | Format-Table -AutoSize | Out-String)
$sys += '--- dns ---'
$sys += (Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object { $_.ServerAddresses } | Select-Object InterfaceAlias,ServerAddresses | Format-Table -AutoSize | Out-String)
$sys += '--- scheduled tasks ---'
$sys += (Get-ScheduledTask -TaskName 'zapret-discord-*' -ErrorAction SilentlyContinue | Select-Object TaskName,State | Format-Table -AutoSize | Out-String)
$sys += '--- service events (7d) ---'
$sys += (Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = (Get-Date).AddDays(-7) } -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -match 'zapret|winws|WinDivert' } |
    Select-Object -First 20 TimeCreated, Id, ProviderName, Message | Format-List | Out-String)
$sys | Out-File -FilePath (Join-Path $tmp 'system.txt') -Encoding utf8

$curlLines = @()
foreach ($u in @('https://discord.com/api/v9/gateway', 'https://discord.com/', 'https://cdn.discordapp.com/', 'https://gateway.discord.gg/')) {
    $r = & curl.exe -sS -o NUL -m 8 -w '%{http_code} tls=%{time_appconnect} total=%{time_total}' $u 2>&1
    $curlLines += "$u -> $($r -join ' ')"
}
$curlLines | Out-File -FilePath (Join-Path $tmp 'curl.txt') -Encoding utf8

foreach ($f in @('watchdog.log', 'watchdog.log.1', 'blockcheck-report.txt', 'last-strategy.json', 'tray.log', 'strategies-history.jsonl')) {
    $p = Join-Path $logsDir $f
    if (Test-Path $p) { Copy-Item $p (Join-Path $tmp $f) -Force }
}

$zip = Join-Path $logsDir ("diagnostics-" + $stamp + ".zip")
Compress-Archive -Path (Join-Path $tmp '*') -DestinationPath $zip -CompressionLevel Optimal
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Diagnostics saved: $zip"
Write-Host 'Review the zip before publishing it: it contains network config and logs.'
Start-Process explorer.exe $logsDir
