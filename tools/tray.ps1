# tray.ps1 - tray icon for zapret: Discord only.
# Installed by install.bat as a logon task with highest privileges.
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$logsDir = Join-Path $root 'tools\logs'
New-Item -ItemType Directory -Force -Path $logsDir | Out-Null
$trayLog = Join-Path $logsDir 'tray.log'
function Tray-Log([string]$m) {
    if ((Test-Path $trayLog) -and ((Get-Item $trayLog).Length -gt 512KB)) { Move-Item $trayLog ($trayLog + '.1') -Force }
    Add-Content $trayLog -Value ('[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '] ' + $m) -Encoding utf8
}

# single instance via named mutex
$mutex = New-Object System.Threading.Mutex -ArgumentList @($false, 'Local\zapret-discord-tray')
$gotMutex = $false
try { $gotMutex = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $gotMutex = $true }
if (-not $gotMutex) { Tray-Log 'another tray instance is running, exit'; exit 0 }

function New-Icon([System.Drawing.Color]$color) {
    $bmp = New-Object System.Drawing.Bitmap 16, 16
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $brush = New-Object System.Drawing.SolidBrush $color
    $g.FillEllipse($brush, 1, 1, 14, 14)
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 1.5
    $g.DrawEllipse($pen, 3, 3, 10, 10)
    $g.Dispose()
    $icon = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
    return $icon
}
$iconOn = New-Icon ([System.Drawing.Color]::FromArgb(46, 160, 67))
$iconOff = New-Icon ([System.Drawing.Color]::FromArgb(200, 60, 60))

$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = $iconOff
$notify.Text = 'zapret: Discord only'
$notify.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$itemStatus = New-Object System.Windows.Forms.ToolStripMenuItem
$itemStatus.Text = 'Статус: проверяю...'
$itemStatus.Enabled = $false
$itemCheck = New-Object System.Windows.Forms.ToolStripMenuItem
$itemCheck.Text = 'Проверить Discord'
$itemOn = New-Object System.Windows.Forms.ToolStripMenuItem
$itemOn.Text = 'Включить обход'
$itemOff = New-Object System.Windows.Forms.ToolStripMenuItem
$itemOff.Text = 'Выключить обход'
$itemBlock = New-Object System.Windows.Forms.ToolStripMenuItem
$itemBlock.Text = 'Blockcheck (автоподбор)'
$itemDiag = New-Object System.Windows.Forms.ToolStripMenuItem
$itemDiag.Text = 'Диагностика (zip)'
$itemUpdate = New-Object System.Windows.Forms.ToolStripMenuItem
$itemUpdate.Text = 'Проверить обновления'
$itemLogs = New-Object System.Windows.Forms.ToolStripMenuItem
$itemLogs.Text = 'Открыть логи'
$itemExit = New-Object System.Windows.Forms.ToolStripMenuItem
$itemExit.Text = 'Выход'
[void]$menu.Items.Add($itemStatus)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($itemCheck)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($itemOn)
[void]$menu.Items.Add($itemOff)
[void]$menu.Items.Add($itemBlock)
[void]$menu.Items.Add($itemDiag)
[void]$menu.Items.Add($itemUpdate)
[void]$menu.Items.Add($itemLogs)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($itemExit)
$notify.ContextMenuStrip = $menu

function Get-Svc { return Get-Service zapret-discord -ErrorAction SilentlyContinue }
function Balloon([string]$title, [string]$text, [string]$icon = 'Info') {
    $notify.BalloonTipTitle = $title
    $notify.BalloonTipText = $text
    $ici = [System.Windows.Forms.ToolTipIcon]::Info
    if ($icon -eq 'Error') { $ici = [System.Windows.Forms.ToolTipIcon]::Error }
    if ($icon -eq 'Warning') { $ici = [System.Windows.Forms.ToolTipIcon]::Warning }
    $notify.BalloonTipIcon = $ici
    $notify.ShowBalloonTip(5000)
}
function Update-Status {
    $s = Get-Svc
    if (-not $s) {
        $notify.Icon = $iconOff
        $itemStatus.Text = 'Статус: служба не установлена'
        $notify.Text = 'zapret: Discord only - not installed'
        return
    }
    if ($s.Status -eq 'Running') {
        $notify.Icon = $iconOn
        $itemStatus.Text = 'Статус: обход включён'
        $notify.Text = 'zapret: Discord only - ON'
    } else {
        $notify.Icon = $iconOff
        $itemStatus.Text = "Статус: обход выключен ($($s.Status))"
        $notify.Text = 'zapret: Discord only - OFF'
    }
}

$itemCheck.add_Click({
    Tray-Log 'menu: check'
    $r = & curl.exe -sS -o NUL -m 8 -w '%{http_code}' 'https://discord.com/api/v9/gateway' 2>$null
    if ($r -eq '200') { Balloon 'Discord доступен' 'API отвечает 200. Обход работает.' }
    else { Balloon 'Discord не отвечает' "API вернул '$r'. Запусти Blockcheck." 'Error' }
})
$itemOn.add_Click({
    Tray-Log 'menu: start service'
    try {
        Start-Service zapret-discord -ErrorAction Stop
        Start-Sleep -Seconds 2
        Update-Status
        Balloon 'Обход включён' 'Служба zapret-discord запущена.'
    } catch { Balloon 'Не удалось включить' "Нужны права администратора: $($_.Exception.Message)" 'Error' }
})
$itemOff.add_Click({
    Tray-Log 'menu: stop service'
    try {
        Stop-Service zapret-discord -Force -ErrorAction Stop
        Start-Sleep -Seconds 1
        Update-Status
        Balloon 'Обход выключен' 'Discord снова без обхода. Включить: меню - Включить обход.'
    } catch { Balloon 'Не удалось выключить' $_.Exception.Message 'Error' }
})
$itemBlock.add_Click({
    Tray-Log 'menu: blockcheck'
    Balloon 'Blockcheck запущен' 'Перебор стратегий, 2-5 минут. Трей может не отвечать это время.'
    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'tools\blockcheck.ps1')
})
$itemDiag.add_Click({
    Tray-Log 'menu: diagnostics'
    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'tools\collect-diagnostics.ps1')
    Balloon 'Диагностика' 'Собираю zip в tools\logs, открою папку.'
})
$itemLogs.add_Click({ Start-Process explorer.exe (Join-Path $root 'tools\logs') })
$itemUpdate.add_Click({
    Tray-Log 'menu: check-update'
    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tools\check-update.ps1') 2>&1
    $code = $LASTEXITCODE
    if ($code -eq 0) {
        $line = ($out | Where-Object { $_ -match 'Update available' } | Select-Object -First 1)
        Balloon 'Есть обновление' "$line. Открываю страницу релиза."
        Start-Process 'https://github.com/artuasova/zapret-discord/releases/latest'
    } elseif ($code -eq 1) {
        $line = ($out | Where-Object { $_ -match 'Up to date' } | Select-Object -First 1)
        Balloon 'Обновлений нет' $line
    } else {
        Balloon 'Не удалось проверить' 'Нет доступа к GitHub API.' 'Warning'
    }
})
$itemExit.add_Click({
    Tray-Log 'exit'
    $notify.Visible = $false
    $notify.Dispose()
    [System.Windows.Forms.Application]::Exit()
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 60000
$timer.add_Tick({ Update-Status })
$timer.Start()
Update-Status
Tray-Log 'tray started'
[System.Windows.Forms.Application]::Run()
try { $mutex.ReleaseMutex() } catch { }
Tray-Log 'tray stopped'
