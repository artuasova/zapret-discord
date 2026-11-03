# blockcheck.ps1 - auto-select a working zapret strategy for Discord on this provider.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools\blockcheck.ps1 [-Auto] [-Force] [-Voice]
param(
    [switch]$Auto,
    [switch]$Force,
    [switch]$Voice
)
$ErrorActionPreference = 'Continue'

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$winws = Join-Path $root 'bin\winws.exe'
$hostlist = Join-Path $root 'lists\discord-hosts.txt'
$strategiesFile = Join-Path $root 'tools\strategies.json'
$voiceTest = Join-Path $root 'tools\voice-test.ps1'
$logsDir = Join-Path $root 'tools\logs'
$report = Join-Path $logsDir 'blockcheck-report.txt'
$history = Join-Path $logsDir 'strategies-history.jsonl'
$lockFile = Join-Path $logsDir '.blockcheck.lock'

New-Item -ItemType Directory -Force -Path $logsDir | Out-Null

function Log([string]$msg, [string]$color = 'Gray') {
    $line = '[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '] ' + $msg
    if (-not $Auto) { Write-Host $line -ForegroundColor $color }
    Add-Content $report -Value $line -Encoding utf8
}

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Write-Host 'Run as Administrator' -ForegroundColor Red; exit 1 }
foreach ($f in @($winws, $hostlist, $strategiesFile)) {
    if (-not (Test-Path $f)) { Write-Host "Missing: $f" -ForegroundColor Red; exit 1 }
}

# --- VPN / tunnel guard: testing through a tunnel gives false results ---
$tunnelRegex = '(?i)happ|wintun|wireguard|sing-tun|sing_box|sing-box|tap-windows|openvpn|amnezia|outline|shadowsocks|v2ray|xray|\btun\b|\bvpn\b'
function Get-VpnAdapter {
    foreach ($r in (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue)) {
        $a = Get-NetAdapter -InterfaceIndex $r.ifIndex -ErrorAction SilentlyContinue
        if (-not $a -or $a.Status -ne 'Up') { continue }
        if ("$($a.Name) $($a.InterfaceDescription)" -match $tunnelRegex) { return $a }
    }
    return $null
}

$vpnAdapter = Get-VpnAdapter
if ($vpnAdapter -and -not $Force) {
    "blockcheck aborted at $(Get-Date -Format o): VPN/tunnel is the default route ($($vpnAdapter.Name))" | Add-Content $report -Encoding utf8
    Write-Host "VPN/tunnel is active ($($vpnAdapter.Name)). Disable it first, or use -Force." -ForegroundColor Yellow
    exit 2
}

# --- lock: do not run two blockchecks at once ---
if (Test-Path $lockFile) {
    $age = (Get-Date) - (Get-Item $lockFile).LastWriteTime
    if ($age.TotalMinutes -lt 40) {
        "blockcheck aborted at $(Get-Date -Format o): another instance is running" | Add-Content $report -Encoding utf8
        exit 3
    }
}
Set-Content -Path $lockFile -Value (Get-Date -Format o) -Encoding ascii

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
    $r = & curl.exe -sS -o NUL -m 8 -w '%{http_code}' $url 2>$null
    $code = 0
    if ($r -match '^(\d+)$') { $code = [int]$Matches[1] }
    return @{ ok = ($code -in @(200, 301, 302, 403, 404)); code = $code }
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
    $proc = Start-Process -FilePath $winws -ArgumentList $argsList -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $logsDir 'candidate-out.txt') -RedirectStandardError (Join-Path $logsDir 'candidate-err.txt')
    Start-Sleep -Seconds 2
    $proc.Refresh()
    if ($proc.HasExited) {
        return @{ score = 0; details = "winws exited ($($proc.ExitCode))" }
    }
    $codes = @()
    $ok = 0
    foreach ($u in @('https://discord.com/api/v9/gateway', 'https://discord.com/', 'https://cdn.discordapp.com/', 'https://gateway.discord.gg/')) {
        $c = Test-Http $u
        $codes += $c.code
        if ($c.ok) { $ok++ }
    }
    $wsOk = Test-Ws
    $score = $ok
    if ($wsOk) { $score += 2 }
    $details = ($codes -join ',') + ' ws=' + $(if ($wsOk) { 'ok' } else { 'fail' })
    Get-Process -Id $proc.Id -ErrorAction SilentlyContinue | Stop-Process -Force
    return @{ score = $score; details = $details }
}

function Apply-Strategy($cand) {
    sc.exe stop zapret-discord | Out-Null
    Start-Sleep -Seconds 2
    Get-Process winws* -ErrorAction SilentlyContinue | Stop-Process -Force
    $argsList = Build-Args $cand.Tls
    $binPath = '"{0}" {1}' -f $winws, ($argsList -join ' ')
    sc.exe config zapret-discord binPath= $binPath | Out-Null
    sc.exe start zapret-discord | Out-Null
    for ($try = 1; $try -le 5; $try++) {
        Start-Sleep -Seconds 2
        $svc = Get-Service zapret-discord -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') {
            $v = Test-Http 'https://discord.com/api/v9/gateway'
            if ($v.ok) { return $v }
        }
    }
    return $null
}

function Invoke-VoiceCheck {
    if (-not (Test-Path $voiceTest)) { return 2 }
    $p = Start-Process -FilePath 'powershell.exe' -PassThru -WindowStyle Hidden -Wait `
        -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $voiceTest, '-Quiet'
    return $p.ExitCode
}

try {
    Log "blockcheck start (auto=$Auto voice=$Voice)"
    Log 'Stopping zapret-discord service for the test...'
    sc.exe stop zapret-discord | Out-Null
    Start-Sleep -Seconds 2
    Get-Process winws* -ErrorAction SilentlyContinue | Stop-Process -Force

    $strategies = Get-Content $strategiesFile -Raw | ConvertFrom-Json
    $results = @()

    $i = 0
    foreach ($s in $strategies) {
        $i++
        Log ("[{0}/{1}] {2}" -f $i, $strategies.Count, $s.name) 'Cyan'
        $res = Run-Candidate $s
        $results += [pscustomobject]@{ Index = $i; Name = $s.name; Tls = $s.tls; Score = $res.score; Details = $res.details }
        Log ("    score={0}  {1}" -f $res.score, $res.details)
    }

    Get-Process winws* -ErrorAction SilentlyContinue | Stop-Process -Force

    $best = $results | Sort-Object @{ Expression = 'Score'; Descending = $true }, @{ Expression = 'Index'; Ascending = $true } | Select-Object -First 1
    Log '=== SUMMARY ==='
    foreach ($r in $results) { Log ("  {0,-38} score={1}" -f $r.Name, $r.Score) }

    $applied = $false
    if ($best -and $best.Score -ge 4) {
        Log "BEST: $($best.Name) score=$($best.Score)" 'Green'
        $verdict = Apply-Strategy $best
        if ($verdict) {
            Log ("APPLIED: {0}, api_http={1}" -f $best.Name, $verdict.code) 'Green'
            $applied = $true
        }

        # optional live voice validation: if Discord is in a voice channel, prefer a strategy that keeps it working
        if ($applied -and $Voice) {
            $vr = Invoke-VoiceCheck
            Log "voice check exit=$vr (0=ok 1=broken 2=not testable)"
            if ($vr -eq 1) {
                $alts = $results | Where-Object { $_.Score -ge 4 -and $_.Index -ne $best.Index } |
                    Sort-Object @{ Expression = 'Score'; Descending = $true }, @{ Expression = 'Index'; Ascending = $true } |
                    Select-Object -First 2
                foreach ($alt in $alts) {
                    Log "voice broken - trying alternative: $($alt.Name)" 'Yellow'
                    $v2 = Apply-Strategy $alt
                    if ($v2) {
                        $vr2 = Invoke-VoiceCheck
                        Log "  voice check exit=$vr2"
                        if ($vr2 -ne 1) { $best = $alt; Log "voice-compatible strategy: $($alt.Name)" 'Green'; break }
                    }
                }
            }
        }
    }

    if ($applied) {
        $entry = [pscustomobject]@{ at = (Get-Date -Format o); strategy = $best.Name; score = $best.Score; auto = [bool]$Auto; voice = [bool]$Voice }
        $entry | ConvertTo-Json -Compress | Add-Content $history -Encoding utf8
        Set-Content -Path (Join-Path $logsDir 'last-strategy.json') -Value ($entry | ConvertTo-Json) -Encoding utf8
    } else {
        Log 'NOT APPLIED: no strategy scored >= 4' 'Red'
        sc.exe start zapret-discord | Out-Null
    }

    if ($applied) { exit 0 } else { exit 4 }
}
finally {
    Get-Process winws* -ErrorAction SilentlyContinue | Stop-Process -Force
    Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
}
