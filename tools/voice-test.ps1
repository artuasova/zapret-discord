# voice-test.ps1 - verify Discord voice works right now through the bypass.
# Join a voice channel first, then run this script.
# Exit codes: 0 = voice works, 1 = voice is broken, 2 = cannot test (Discord not running / not in voice)
param([switch]$Quiet)
$ErrorActionPreference = 'Continue'

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
function Say([string]$m) { if (-not $Quiet) { Write-Host $m } }

$discord = Get-Process discord -ErrorAction SilentlyContinue
if (-not $discord) { Say 'Discord is not running - start it and join a voice channel.'; exit 2 }

# 1) service config must contain the voice profiles
$cfg = (& sc.exe qc zapret-discord 2>&1 | Out-String)
$hasVoicePorts = ($cfg -match '50000-50099' -or $cfg -match '19294-19344')
$hasVoiceL7 = ($cfg -match 'discord,stun')
if (-not $hasVoicePorts -or -not $hasVoiceL7) {
    Say "FAIL: service config has no Discord voice profiles (ports=$hasVoicePorts l7=$hasVoiceL7)"
    exit 1
}

# 2) currently bound UDP endpoints of discord
$pids = $discord.Id
$udp = Get-NetUDPEndpoint -ErrorAction SilentlyContinue | Where-Object { $pids -contains $_.OwningProcess }
$voiceUdp = @($udp | Where-Object { $_.LocalPort -ge 1024 })
$voicePortsHit = @($udp | Where-Object { ($_.LocalPort -ge 50000 -and $_.LocalPort -le 50099) -or ($_.LocalPort -ge 19294 -and $_.LocalPort -le 19344) })

# 3) recent RTC connection evidence from the renderer log
$logDir = Join-Path $env:APPDATA 'discord\logs'
$rtcOk = $false
$rtcClosed = $false
$lastOk = $null
$rl = Join-Path $logDir 'renderer_js.log'
if (Test-Path $rl) {
    $lines = Get-Content $rl -Tail 4000 -ErrorAction SilentlyContinue
    foreach ($line in $lines) {
        if ($line -match 'RTC (media )?connection state: (AWAITING_ENDPOINT => )?RTC_CONNECTED' -or $line -match 'rate: RTC_CONNECTED' -or $line -match 'RTC_CONNECTED') { $rtcOk = $true; $rtcClosed = $false; $lastOk = $line }
        if ($line -match 'RTC_DISCONNECTED|Disconnected from RTC server') { $rtcClosed = $true }
    }
}
$recent = $false
if ($lastOk -and $lastOk -match '\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') {
    try {
        $ts = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd HH:mm:ss', $null)
        $recent = (((Get-Date) - $ts).TotalMinutes -lt 15)
    } catch { }
}

Say "voice ports in service config : $hasVoicePorts"
Say "voice L7 discord,stun        : $hasVoiceL7"
Say "discord UDP endpoints        : $($voiceUdp.Count) (voice-range: $($voicePortsHit.Count))"
Say "RTC connected evidence       : $rtcOk (recent=$recent, closed_later=$rtcClosed)"

if ($rtcOk -and $recent -and -not $rtcClosed -and ($voicePortsHit.Count -gt 0 -or $voiceUdp.Count -gt 0)) {
    Say 'PASS: voice is connected through the bypass.'
    exit 0
}
if ($rtcOk -and $recent -and -not $rtcClosed) {
    Say 'PARTIAL: RTC says connected, but no UDP endpoint seen; join a channel and speak, then retry.'
    exit 1
}
Say 'FAIL: no active RTC voice connection detected. Join a voice channel and retry.'
exit 1
