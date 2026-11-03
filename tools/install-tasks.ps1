# install-tasks.ps1 - register watchdog (every 5 min) and tray (at logon) scheduled tasks.
$ErrorActionPreference = 'Continue'

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$watchdog = Join-Path $root 'tools\watchdog.ps1'
$tray = Join-Path $root 'tools\tray.ps1'

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Write-Host 'Run as Administrator' -ForegroundColor Red; exit 1 }

Write-Host '[tasks] watchdog (every 5 min, SYSTEM)...' -ForegroundColor Cyan
$action = New-ScheduledTaskAction -Execute $ps -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $watchdog)
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName 'zapret-discord-watchdog' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

Write-Host '[tasks] tray (at logon, elevated)...' -ForegroundColor Cyan
$action2 = New-ScheduledTaskAction -Execute $ps -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $tray)
$trigger2 = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$principal2 = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
$settings2 = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName 'zapret-discord-tray' -Action $action2 -Trigger $trigger2 -Principal $principal2 -Settings $settings2 -Force | Out-Null

Write-Host 'Tasks installed:' -ForegroundColor Green
Get-ScheduledTask -TaskName 'zapret-discord-*' | Select-Object TaskName, State | Format-Table -AutoSize
