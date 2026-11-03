# check-update.ps1 - compare local VERSION with the latest GitHub release.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools\check-update.ps1 [-Open]
param([switch]$Open)
$ErrorActionPreference = 'Continue'

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$versionFile = Join-Path $root 'VERSION'
$local = '0.0.0'
if (Test-Path $versionFile) { $local = (Get-Content $versionFile -Raw).Trim() }

function To-Ints([string]$v) {
    $v = $v.TrimStart('v')
    $parts = $v.Split('.')
    $out = @(0, 0, 0)
    for ($i = 0; $i -lt [Math]::Min(3, $parts.Count); $i++) {
        $n = 0
        if ([int]::TryParse(($parts[$i] -replace '[^0-9].*', ''), [ref]$n)) { $out[$i] = $n }
    }
    return $out
}

try {
    $headers = @{ 'User-Agent' = 'zapret-discord-updater'; 'Accept' = 'application/vnd.github+json' }
    $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/artuasova/zapret-discord/releases/latest' -Headers $headers -TimeoutSec 20
} catch {
    Write-Host "update check failed: $($_.Exception.Message)"
    exit 2
}

$remoteTag = $rel.tag_name
$remoteUrl = $rel.html_url
$l = To-Ints $local
$r = To-Ints $remoteTag

$newer = $false
for ($i = 0; $i -lt 3; $i++) {
    if ($r[$i] -gt $l[$i]) { $newer = $true; break }
    if ($r[$i] -lt $l[$i]) { break }
}

if ($newer) {
    Write-Host "Update available: $local -> $remoteTag"
    Write-Host $remoteUrl
    if ($Open) { Start-Process $remoteUrl }
    exit 0
}

Write-Host "Up to date: $local (latest $remoteTag)"
exit 1
