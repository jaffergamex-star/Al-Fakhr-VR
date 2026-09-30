<#
  MOI mirror station: every headset on its own screen, hands-free.

  One-time, with all headsets plugged in by USB and all screens connected:
      powershell -ExecutionPolicy Bypass -File Deploy\mirror-station.ps1 -Setup
  (shows a big number on each screen and writes Deploy\mirror-config.json: headset serial -> screen number;
   edit that file to swap screens or rename headsets)

  Run (or let it start by itself at logon, see -InstallAutostart):
      powershell -ExecutionPolicy Bypass -File Deploy\mirror-station.ps1

  Check what it would do without opening any windows:
      powershell -ExecutionPolicy Bypass -File Deploy\mirror-station.ps1 -DryRun

  Start automatically when this PC logs in / stop doing so:
      ... mirror-station.ps1 -InstallAutostart
      ... mirror-station.ps1 -RemoveAutostart

  While running: each screen shows "Headset N - waiting" until that headset is connected, then its live view.
  Unplug/replug is handled automatically. Ctrl+Q on any waiting screen quits the station.

  Needs scrcpy (free):  winget install Genymobile.scrcpy   (or unzip the release to C:\Tools\scrcpy)
#>
param([switch]$Setup, [switch]$DryRun, [switch]$InstallAutostart, [switch]$RemoveAutostart)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$ConfigPath = Join-Path $PSScriptRoot "mirror-config.json"
$StartupLink = Join-Path ([Environment]::GetFolderPath("Startup")) "MOI Mirror Station.lnk"

# ---------------------------------------------------------------- autostart
if ($InstallAutostart) {
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($StartupLink)
    $link.TargetPath = "powershell.exe"
    $link.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $link.WorkingDirectory = $PSScriptRoot
    $link.Save()
    Write-Host "Mirror station will start at logon: $StartupLink"
    return
}
if ($RemoveAutostart) {
    if (Test-Path $StartupLink) { Remove-Item $StartupLink; Write-Host "Autostart removed." } else { Write-Host "Autostart was not installed." }
    return
}

# ---------------------------------------------------------------- tools
function Find-Scrcpy {
    if (Test-Path "C:\Tools\scrcpy\scrcpy.exe") { return "C:\Tools\scrcpy\scrcpy.exe" }
    $wingetRoot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    if (Test-Path $wingetRoot) {
        $hit = Get-ChildItem $wingetRoot -Directory -Filter "Genymobile.scrcpy*" -ErrorAction SilentlyContinue |
               Get-ChildItem -Recurse -Filter scrcpy.exe -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    $cmd = Get-Command scrcpy -ErrorAction SilentlyContinue
    if ($cmd) {
        $item = Get-Item $cmd.Source
        if ($item.Target) { return [string]($item.Target | Select-Object -First 1) }
        return $cmd.Source
    }
    return $null
}

$Scrcpy = Find-Scrcpy
# Use scrcpy's own adb when we have it: two different adb versions on one PC keep restarting each other.
$Adb = "C:\Program Files\Unity\Hub\Editor\6000.1.4f1\Editor\Data\PlaybackEngines\AndroidPlayer\SDK\platform-tools\adb.exe"
if ($Scrcpy -and (Test-Path (Join-Path (Split-Path $Scrcpy) "adb.exe"))) { $Adb = Join-Path (Split-Path $Scrcpy) "adb.exe" }

function Get-Headsets {
    $out = & $Adb devices 2>$null
    @($out | Select-Object -Skip 1 | Where-Object { $_ -match "\tdevice$" } | ForEach-Object { ($_ -split "\t")[0] })
}

function Get-Screens {
    # Left-to-right, then top-to-bottom, so "screen 1" is the leftmost.
    @([System.Windows.Forms.Screen]::AllScreens | Sort-Object { $_.Bounds.X }, { $_.Bounds.Y })
}

function Get-ScreenBounds($screens, $number) {
    $screens[[Math]::Max(0, [Math]::Min([int]$number, $screens.Count) - 1)].Bounds
}

function Show-ScreenNumbers($screens, [int]$seconds) {
    $forms = @()
    for ($i = 0; $i -lt $screens.Count; $i++) {
        $f = New-Object System.Windows.Forms.Form
        $f.FormBorderStyle = "None"; $f.StartPosition = "Manual"; $f.Bounds = $screens[$i].Bounds
        $f.BackColor = [System.Drawing.Color]::FromArgb(10, 30, 90); $f.TopMost = $true; $f.ShowInTaskbar = $false
        $l = New-Object System.Windows.Forms.Label
        $l.Dock = "Fill"; $l.TextAlign = "MiddleCenter"; $l.ForeColor = [System.Drawing.Color]::White
        $l.Font = New-Object System.Drawing.Font("Segoe UI", 160, [System.Drawing.FontStyle]::Bold)
        $l.Text = "$($i + 1)"
        $f.Controls.Add($l); $f.Show(); $forms += $f
    }
    $end = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $end) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 50 }
    $forms | ForEach-Object { $_.Close() }
}

function Load-Config {
    if (-not (Test-Path $ConfigPath)) { return $null }
    Get-Content $ConfigPath -Raw | ConvertFrom-Json
}

# ---------------------------------------------------------------- setup
if ($Setup) {
    $screens = Get-Screens
    $devices = Get-Headsets
    Write-Host "Screens found: $($screens.Count)   Headsets connected: $($devices.Count)"
    if (-not $devices) { throw "No headsets connected. Plug them in, allow USB debugging in each, and run -Setup again." }

    $old = Load-Config
    $headsets = @()
    for ($i = 0; $i -lt $devices.Count; $i++) {
        $prev = $null
        if ($old) { $prev = $old.headsets | Where-Object { $_.serial -eq $devices[$i] } | Select-Object -First 1 }
        $name = "Headset $($i + 1)"; $screen = [Math]::Min($i + 1, $screens.Count)
        if ($prev) { $name = $prev.name; $screen = [int]$prev.screen }
        $headsets += [pscustomobject]@{ serial = $devices[$i]; name = $name; screen = $screen }
    }
    $config = [pscustomobject]@{ maxSize = 1920; bitRateMbps = 12; crop = ""; headsets = $headsets }
    if ($old) { $config.maxSize = $old.maxSize; $config.bitRateMbps = $old.bitRateMbps; $config.crop = $old.crop }
    $config | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 $ConfigPath

    Write-Host "Showing the screen numbers for 6 seconds..."
    Show-ScreenNumbers $screens 6
    $headsets | Format-Table name, serial, screen -AutoSize | Out-String | Write-Host
    Write-Host "Saved $ConfigPath"
    Write-Host "To swap screens, change the 'screen' numbers in that file. Put a label with the serial on each headset."
    if ($screens.Count -lt $devices.Count) { Write-Warning "More headsets than screens: some share a screen. Connect more screens and run -Setup again." }
    return
}

# ---------------------------------------------------------------- run
$config = Load-Config
if (-not $config) { throw "No $ConfigPath yet. Plug in all headsets and run with -Setup first." }
$screens = Get-Screens

function Get-ScrcpyArgs($h) {
    $b = Get-ScreenBounds $screens $h.screen
    $a = @("-s", $h.serial, "--no-control", "--no-audio",
           "--max-size", "$($config.maxSize)", "--video-bit-rate", "$($config.bitRateMbps)M",
           "--window-title", "`"$($h.name)`"",
           "--window-x", "$($b.X)", "--window-y", "$($b.Y)",
           "--window-width", "$($b.Width)", "--window-height", "$($b.Height)",
           "--window-borderless", "--fullscreen")
    $c = $config.crop
    if (-not $c) {
        # VR headsets render both eyes side by side; mirror the left eye only.
        $size = (& $Adb -s $h.serial shell wm size 2>$null) -join " "
        if ($size -match "(\d+)x(\d+)" -and [int]$Matches[1] -ge 2 * [int]$Matches[2] - 8) {
            # 16:9 slice through the middle of the left eye so the view fills a TV (set "crop" to override).
            $eye = [int]([int]$Matches[1] / 2); $h0 = [int]$Matches[2]
            $sliceW = [int]([Math]::Floor($eye * 0.915 / 16) * 16)
            $sliceH = [int]([Math]::Floor($sliceW * 9 / 16 / 8) * 8)
            $c = "$($sliceW):$($sliceH):$([int]([Math]::Floor($eye * 0.045 / 2) * 2)):$([int]([Math]::Floor(($h0 - $sliceH) / 4) * 2))"
        }
    }
    if ($c) { $a += @("--crop", "$c") }
    $a
}

if ($DryRun) {
    $scrcpyText = "NOT INSTALLED - run: winget install Genymobile.scrcpy"
    if ($Scrcpy) { $scrcpyText = $Scrcpy }
    Write-Host "scrcpy : $scrcpyText"
    Write-Host "adb    : $Adb"
    Write-Host "screens: $($screens.Count)"
    for ($i = 0; $i -lt $screens.Count; $i++) { Write-Host ("  screen {0}: {1}" -f ($i + 1), $screens[$i].Bounds) }
    $connected = Get-Headsets
    foreach ($h in $config.headsets) {
        $state = "not connected"
        if ($connected -contains $h.serial) { $state = "CONNECTED" }
        Write-Host ""
        Write-Host "$($h.name) [$($h.serial)] -> screen $($h.screen)  ($state)"
        Write-Host ("  scrcpy " + ((Get-ScrcpyArgs $h) -join " "))
    }
    return
}

if (-not $Scrcpy) {
    [System.Windows.Forms.MessageBox]::Show("scrcpy is not installed.`n`nRun:  winget install Genymobile.scrcpy", "MOI mirror station") | Out-Null
    exit 1
}

# One "waiting" page per headset, sitting behind its live view.
$pages = @{}
foreach ($h in $config.headsets) {
    $f = New-Object System.Windows.Forms.Form
    $f.FormBorderStyle = "None"; $f.StartPosition = "Manual"; $f.ShowInTaskbar = $false
    $f.Bounds = Get-ScreenBounds $screens $h.screen
    $f.BackColor = [System.Drawing.Color]::Black; $f.KeyPreview = $true
    $l = New-Object System.Windows.Forms.Label
    $l.Dock = "Fill"; $l.TextAlign = "MiddleCenter"; $l.ForeColor = [System.Drawing.Color]::FromArgb(90, 110, 150)
    $l.Font = New-Object System.Drawing.Font("Segoe UI", 28)
    $f.Controls.Add($l)
    $f.Add_KeyDown({ param($s, $e) if ($e.Control -and $e.KeyCode -eq "Q") { [System.Windows.Forms.Application]::Exit() } })
    $pages[$h.serial] = @{ form = $f; label = $l; proc = $null }
    $f.Show()
}

function Update-Station {
    $connected = Get-Headsets
    foreach ($h in $config.headsets) {
        $p = $pages[$h.serial]
        if ($p.proc -and -not $p.proc.HasExited) { continue }
        if ($connected -contains $h.serial) {
            $p.label.Text = "$($h.name)`nconnecting..."
            $p.proc = Start-Process -FilePath $Scrcpy -ArgumentList (Get-ScrcpyArgs $h) -WindowStyle Hidden -PassThru
        } else {
            $p.label.Text = "$($h.name)`nwaiting for headset - check the USB cable"
        }
    }
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 3000
$timer.Add_Tick({ Update-Station })
$timer.Start()
Update-Station

$context = New-Object System.Windows.Forms.ApplicationContext
[System.Windows.Forms.Application]::Run($context)

# Quit: close the live views too.
$timer.Stop()
foreach ($p in $pages.Values) { if ($p.proc -and -not $p.proc.HasExited) { $p.proc.Kill() } }
