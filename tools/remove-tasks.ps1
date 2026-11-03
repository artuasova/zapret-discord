# remove-tasks.ps1 - remove watchdog and tray scheduled tasks.
$ErrorActionPreference = 'Continue'

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Write-Host 'Run as Administrator' -ForegroundColor Red; exit 1 }

foreach ($t in @('zapret-discord-watchdog', 'zapret-discord-tray')) {
    $task = Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue
    if ($task) {
        Unregister-ScheduledTask -TaskName $t -Confirm:$false
        Write-Host "removed task: $t" -ForegroundColor Green
    } else {
        Write-Host "task not found: $t"
    }
}

# stop a running tray instance
Get-Process powershell -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'tray\.ps1' } |
    ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }

Get-ScheduledTask -TaskName 'zapret-discord-*' -ErrorAction SilentlyContinue | Select-Object TaskName, State | Format-Table -AutoSize
