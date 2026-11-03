# watchdog.ps1 - periodic self-healing check for zapret-discord.
# Run by a scheduled task every 5 minutes (install.bat installs it).
# One invocation = one check; no resident process.
$ErrorActionPreference = 'Continue'

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$logsDir = Join-Path $root 'tools\logs'
$logFile = Join-Path $logsDir 'watchdog.log'
$stateFile = Join-Path $logsDir 'watchdog-state.json'
$blockcheckLock = Join-Path $logsDir '.blockcheck.lock'
$ownLock = Join-Path $logsDir '.watchdog.lock'
$blockcheck = Join-Path $root 'tools\blockcheck.ps1'

New-Item -ItemType Directory -Force -Path $logsDir | Out-Null

function Write-Log([string]$msg) {
    $line = '[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '] ' + $msg
    if ((Test-Path $logFile) -and ((Get-Item $logFile).Length -gt 1MB)) {
        Move-Item $logFile ($logFile + '.1') -Force
    }
    Add-Content $logFile -Value $line -Encoding utf8
}

function Get-Health {
    for ($try = 1; $try -le 3; $try++) {
        $r = & curl.exe -sS -o NUL -m 8 -w '%{http_code}' 'https://discord.com/api/v9/gateway' 2>$null
        if ($r -match '^(\d+)$' -and $Matches[1] -eq '200') { return $true }
        if ($try -lt 3) { Start-Sleep -Seconds 3 }
    }
    return $false
}

$tunnelRegex = '(?i)happ|wintun|wireguard|sing-tun|sing_box|sing-box|tap-windows|openvpn|amnezia|outline|shadowsocks|v2ray|xray|\btun\b|\bvpn\b'
function Get-VpnAdapter {
    foreach ($r in (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue)) {
        $a = Get-NetAdapter -InterfaceIndex $r.ifIndex -ErrorAction SilentlyContinue
        if (-not $a -or $a.Status -ne 'Up') { continue }
        if ("$($a.Name) $($a.InterfaceDescription)" -match $tunnelRegex) { return $a }
    }
    return $null
}

# one watchdog at a time (scheduled task and manual run must not overlap)
if ((Test-Path $ownLock) -and (((Get-Date) - (Get-Item $ownLock).LastWriteTime).TotalMinutes -lt 4)) {
    exit 0
}
Set-Content $ownLock (Get-Date -Format o) -Encoding ascii

try {
    $state = [pscustomobject]@{
        consecutiveFailures = 0
        lastRecoveryAt      = $null
        lastHealthOkAt      = $null
        lastAction          = $null
    }
    if (Test-Path $stateFile) {
        try {
            $loaded = Get-Content $stateFile -Raw | ConvertFrom-Json
            foreach ($p in 'consecutiveFailures', 'lastRecoveryAt', 'lastHealthOkAt', 'lastAction') {
                if ($null -ne $loaded.$p) { $state.$p = $loaded.$p }
            }
        } catch { Write-Log 'state file is corrupted, resetting' }
    }
    function Save-State { $state | ConvertTo-Json | Set-Content $stateFile -Encoding utf8 }

    # --- VPN guard: do not count failures while traffic goes through a tunnel ---
    $vpnAdapter = Get-VpnAdapter
    if ($vpnAdapter) {
        Write-Log "skip: VPN/tunnel default route ($($vpnAdapter.Name))"
        return
    }

    $svc = Get-Service zapret-discord -ErrorAction SilentlyContinue
    if (-not $svc) { Write-Log 'ERROR: service zapret-discord is not installed'; exit 1 }

    if ($svc.Status -ne 'Running') {
        Write-Log "service is $($svc.Status), trying to start"
        try { Start-Service zapret-discord } catch { Write-Log "start failed: $($_.Exception.Message)" }
        Start-Sleep -Seconds 3
    }

    if (Get-Health) {
        if ($state.consecutiveFailures -gt 0) { Write-Log "recovered after $($state.consecutiveFailures) failures" }
        $state.consecutiveFailures = 0
        $state.lastHealthOkAt = (Get-Date -Format o)
        Save-State
        return
    }

    $state.consecutiveFailures = [int]$state.consecutiveFailures + 1
    Write-Log "health check FAILED (consecutive=$($state.consecutiveFailures))"

    # 2 failures in a row: cheap attempt - restart the service
    if ($state.consecutiveFailures -eq 2) {
        Write-Log 'restarting service (cheap attempt)'
        try {
            Restart-Service zapret-discord -Force -ErrorAction Stop
            Start-Sleep -Seconds 4
            if (Get-Health) {
                Write-Log 'service restart fixed it'
                $state.consecutiveFailures = 0
                $state.lastAction = 'service-restart'
                Save-State
                return
            }
        } catch { Write-Log "restart failed: $($_.Exception.Message)" }
    }

    if ($state.consecutiveFailures -ge 3) {
        $cooldownOk = $true
        if ($state.lastRecoveryAt) {
            try {
                $last = [datetime]::Parse($state.lastRecoveryAt)
                if (((Get-Date) - $last).TotalMinutes -lt 60) { $cooldownOk = $false }
            } catch { }
        }
        if (-not $cooldownOk) {
            Write-Log 'auto-blockcheck skipped: 60 min cooldown after last recovery'
            Save-State
            return
        }
        if ((Test-Path $blockcheckLock) -and (((Get-Date) - (Get-Item $blockcheckLock).LastWriteTime).TotalMinutes -lt 40)) {
            Write-Log 'auto-blockcheck skipped: blockcheck already running'
            Save-State
            return
        }

        Write-Log 'running auto blockcheck...'
        $p = Start-Process -FilePath 'powershell.exe' -PassThru -WindowStyle Hidden -Wait `
            -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $blockcheck, '-Auto'
        Write-Log "blockcheck exit code: $($p.ExitCode)"
        Start-Sleep -Seconds 3

        if (Get-Health) {
            Write-Log 'auto-recovery successful, Discord reachable again'
            $state.consecutiveFailures = 0
            $state.lastRecoveryAt = (Get-Date -Format o)
            $state.lastAction = 'auto-blockcheck'
        } else {
            Write-Log 'auto-recovery did not help, will retry after cooldown'
            $state.lastRecoveryAt = (Get-Date -Format o)
            $state.lastAction = 'auto-blockcheck-failed'
        }
        Save-State
    }
}
finally {
    Remove-Item $ownLock -Force -ErrorAction SilentlyContinue
}
