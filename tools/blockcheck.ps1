# blockcheck.ps1 - auto-select a working zapret strategy for Discord on this provider.
# Run as Administrator:  powershell -NoProfile -ExecutionPolicy Bypass -File tools\blockcheck.ps1
$ErrorActionPreference = 'Continue'

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$winws = Join-Path $root 'bin\winws.exe'
$hostlist = Join-Path $root 'lists\discord-hosts.txt'
$strategiesFile = Join-Path $root 'tools\strategies.json'
$report = Join-Path $root 'tools\blockcheck-report.txt'

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Write-Host 'Run as Administrator' -ForegroundColor Red; exit 1 }
foreach ($f in @($winws, $hostlist, $strategiesFile)) {
    if (-not (Test-Path $f)) { Write-Host "Missing: $f" -ForegroundColor Red; exit 1 }
}

$wf = '--wf-tcp=443,2053,2083,2087,2096,8443 --wf-udp=50000-50099,19294-19344'
$udpProfiles = @(
    '--new', '--filter-udp=50000-50099', '--filter-l7=discord,stun', '--dpi-desync=fake', '--dpi-desync-repeats=6',
    '--new', '--filter-udp=19294-19344', '--filter-l7=discord,stun', '--dpi-desync=fake', '--dpi-desync-repeats=6'
)

function Build-Args([string]$tls) {
    $a = @()
    $a += ($wf -split '\s+')
    $a += @('--filter-tcp=443', "--hostlist=$hostlist")
    $a += ($tls -split '\s+')
    $a += @('--new', '--filter-tcp=2053,2083,2087,2096,8443', "--hostlist=$hostlist")
    $a += ($tls -split '\s+')
    $a += $udpProfiles
    return $a
}

function Test-Http([string]$url) {
    $r = & curl.exe -sS -o NUL -m 8 -w '%{http_code}|%{size_download}' $url 2>$null
    $code = 0; $size = 0
    if ($r -match '^(\d+)\|(\d+)$') { $code = [int]$Matches[1]; $size = [int]$Matches[2] }
    return @{ ok = ($code -in @(200, 301, 302, 403, 404) -and $size -ge 0 -and $code -ne 0); code = $code }
}

function Test-Ws {
    try {
        $ws = New-Object System.Net.WebSockets.ClientWebSocket
        $cts = New-Object System.Threading.CancellationTokenSource
        $cts.CancelAfter(8000)
        $ws.ConnectAsync([Uri]'wss://gateway.discord.gg/?v=9&encoding=json', $cts.Token).Wait()
        $buf = New-Object byte[] 4096
        $seg = New-Object System.ArraySegment[byte](, $buf)
        $t = $ws.ReceiveAsync($seg, $cts.Token)
        $t.Wait() | Out-Null
        $msg = [Text.Encoding]::UTF8.GetString($buf, 0, $t.Result.Count)
        $ws.Dispose()
        return ($msg -match '"op":10')
    } catch { return $false }
}

function Run-Candidate($cand) {
    Get-Process winws* -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 400
    $argsList = Build-Args $cand.tls
    $errFile = Join-Path $root 'tools\candidate-err.txt'
    $proc = Start-Process -FilePath $winws -ArgumentList $argsList -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $root 'tools\candidate-out.txt') -RedirectStandardError $errFile
    Start-Sleep -Seconds 2
    $proc.Refresh()
    if ($proc.HasExited) {
        return @{ score = 0; details = "winws exited ($($proc.ExitCode))" }
    }
    $checks = @()
    $checks += (Test-Http 'https://discord.com/api/v9/gateway')
    $checks += (Test-Http 'https://discord.com/')
    $checks += (Test-Http 'https://cdn.discordapp.com/')
    $checks += (Test-Http 'https://gateway.discord.gg/')
    $wsOk = Test-Ws
    $score = ($checks | Where-Object { $_.ok } | Measure-Object).Count
    if ($wsOk) { $score += 2 }
    $details = ($checks | ForEach-Object { $_.code }) -join ','
    $details += " ws=" + $(if ($wsOk) { 'ok' } else { 'fail' })
    Get-Process -Id $proc.Id -ErrorAction SilentlyContinue | Stop-Process -Force
    return @{ score = $score; details = $details }
}

# --- stop production service while testing ---
Write-Host 'Stopping zapret-discord service for the test...' -ForegroundColor Yellow
sc.exe stop zapret-discord | Out-Null
Start-Sleep -Seconds 2
Get-Process winws* -ErrorAction SilentlyContinue | Stop-Process -Force

$strategies = Get-Content $strategiesFile -Raw | ConvertFrom-Json
$results = @()
"blockcheck start $(Get-Date -Format o)" | Set-Content $report -Encoding utf8

$i = 0
foreach ($s in $strategies) {
    $i++
    Write-Host ("[{0}/{1}] {2}" -f $i, $strategies.Count, $s.name) -ForegroundColor Cyan
    $res = Run-Candidate $s
    $results += [pscustomobject]@{ Index = $i; Name = $s.name; Tls = $s.tls; Score = $res.score; Details = $res.details }
    "{0} | score={1} | {2}" -f $s.name, $res.score, $res.details | Add-Content $report -Encoding utf8
    Write-Host ("        score={0}  {1}" -f $res.score, $res.details) -ForegroundColor Gray
}

Get-Process winws* -ErrorAction SilentlyContinue | Stop-Process -Force

$best = $results | Sort-Object @{ Expression = 'Score'; Descending = $true }, @{ Expression = 'Index'; Ascending = $true } | Select-Object -First 1
"`n=== SUMMARY ===" | Add-Content $report -Encoding utf8
$results | Format-Table -AutoSize | Out-String | Add-Content $report -Encoding utf8

if ($best -and $best.Score -ge 4) {
    "BEST: $($best.Name) score=$($best.Score)" | Add-Content $report -Encoding utf8
    Write-Host "`nBest strategy: $($best.Name) (score $($best.Score))" -ForegroundColor Green

    $argsList = Build-Args $best.Tls
    $binPath = '"{0}" {1}' -f $winws, ($argsList -join ' ')
    sc.exe config zapret-discord binPath= $binPath | Out-Null
    sc.exe start zapret-discord | Out-Null
    Start-Sleep -Seconds 3
    $verdict = Test-Http 'https://discord.com/api/v9/gateway'
    Write-Host ("Service restarted with best strategy. discord api HTTP {0}" -f $verdict.code) -ForegroundColor Green
    "APPLIED: $($best.Name), api_http=$($verdict.code)" | Add-Content $report -Encoding utf8
} else {
    Write-Host "`nNo strategy passed enough checks. Keeping the existing service config." -ForegroundColor Red
    "NOT APPLIED: no strategy scored >= 4" | Add-Content $report -Encoding utf8
    sc.exe start zapret-discord | Out-Null
}

Write-Host "`nReport: $report" -ForegroundColor Yellow
Write-Host 'Done.'
