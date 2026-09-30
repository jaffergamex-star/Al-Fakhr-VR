<#
  Replace the MOI content: the 360 film on the headset and/or the intro video on the PC.

  Desktop icons (created by SETUP, or once with -InstallShortcuts):
      "Replace intro video" / "Replace headset film"
      Double-click and choose the new .mp4 - or drag the .mp4 onto the icon.

  Or run directly:
      powershell -ExecutionPolicy Bypass -File update-content.ps1 -Intro "D:\new\intro.mp4"
      powershell -ExecutionPolicy Bypass -File update-content.ps1 -Film "D:\new\journey.mp4"
      powershell -ExecutionPolicy Bypass -File update-content.ps1 -Film "D:\new\journey.mp4" -Layout TopBottom360

  Film:  MP4, H.265 (HEVC) 8-bit, 360 equirectangular, 30 fps. Mono up to 7680x3840 (8K: measured on the Focus
         Vision at 30 fps, 0 frames dropped). A 10-bit film must be converted to 8-bit first.
         -Layout: Mono360 (default) | TopBottom360 | SideBySide360 | FlatScreen.
         Copied into the app's own folder on the headset; the next visit plays it. No app restart needed.
  Intro: MP4 (H.264) with sound, made at the screen's resolution (museum screen: 3096x1290). Replaces intro.mp4
         in this folder; the old one is kept as intro_previous.mp4. The station keeps the intro open, so it is
         stopped for the copy.
  Afterwards the VR station is started again (also if it had been closed to reach the desktop).
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Film = "",
    [ValidateSet("", "Mono360", "TopBottom360", "SideBySide360", "FlatScreen")] [string]$Layout = "",
    [string]$Intro = "",
    # Used by the desktop icons: which video to replace. The file comes from a drop onto the icon, or a picker.
    [ValidateSet("", "film", "intro")] [string]$Pick = "",
    [switch]$InstallShortcuts,
    [switch]$NoPause,
    [Parameter(ValueFromRemainingArguments = $true)] [string[]]$Dropped
)

$ErrorActionPreference = "Stop"
$Package = "com.gamex.moi.promiseofsafety"
$AppFolder = "/sdcard/Android/data/$Package/files"
$Station = Join-Path $PSScriptRoot "visitor-station.ps1"
$Desktop = [Environment]::GetFolderPath("Desktop")
$script:RestartStation = $false
$script:StationArgs = $null

# Ends the run. The window waits (Enter, or 20 s) so the result can be read; then the VR station is started
# again - after the wait, because on a one-screen PC the full-screen station would cover this message.
function Done([int]$code) {
    if (-not $NoPause) {
        Write-Host ""
        $then = if ($script:RestartStation) { "the VR station starts again" } else { "this window closes" }
        Write-Host "Press Enter to finish ($then automatically in 20 seconds)." -ForegroundColor Cyan
        $end = (Get-Date).AddSeconds(20)
        try {
            while ((Get-Date) -lt $end) {
                if ([Console]::KeyAvailable -and [Console]::ReadKey($true).Key -eq 'Enter') { break }
                Start-Sleep -Milliseconds 100
            }
        } catch { Start-Sleep -Seconds 3 }
    }
    if ($script:RestartStation) { Start-Station }
    exit $code
}

function Get-StationProcess {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object { $_.CommandLine -match "visitor-station\.ps1" -and $_.CommandLine -notmatch "-Stop|-IdentifyScreens|-ListPorts|-MirrorCropFor" } |
        Select-Object -First 1
}

# Start the station with the options it was running with, else the way the "Start VR Station" icon does.
function Start-Station {
    if (Get-StationProcess) { return }
    $icon = Join-Path $Desktop "Start VR Station.lnk"
    if ($script:StationArgs -ne $null) {
        Start-Process powershell -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Station`" $($script:StationArgs)" -WindowStyle Hidden
    } elseif (Test-Path $icon) {
        Start-Process $icon
    } else {
        Start-Process powershell -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Station`"" -WindowStyle Hidden
    }
}

function Pick-Video($title) {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = $title
    $dlg.Filter = "MP4 video (*.mp4)|*.mp4"
    $downloads = Join-Path $env:USERPROFILE "Downloads"
    $dlg.InitialDirectory = if (Test-Path $downloads) { $downloads } else { $Desktop }
    # A topmost owner keeps the picker in front of everything else.
    $owner = New-Object System.Windows.Forms.Form
    $owner.TopMost = $true; $owner.ShowInTaskbar = $false; $owner.FormBorderStyle = "None"; $owner.Opacity = 0
    $owner.StartPosition = "CenterScreen"; $owner.Size = New-Object System.Drawing.Size 1, 1
    $owner.Show(); $owner.Activate()
    $result = $dlg.ShowDialog($owner)
    $owner.Close()
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.FileName }
    return $null
}

if ($InstallShortcuts) {
    $shell = New-Object -ComObject WScript.Shell
    foreach ($item in @(@{ n = "Replace headset film"; a = "-Pick film" }, @{ n = "Replace intro video"; a = "-Pick intro" })) {
        $link = $shell.CreateShortcut((Join-Path $Desktop "$($item.n).lnk"))
        $link.TargetPath = "powershell.exe"
        # A file dropped onto the icon is appended to these arguments; without one, a picker opens.
        $link.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" $($item.a)"
        $link.WorkingDirectory = $PSScriptRoot
        $link.Description = "Double-click to choose a video, or drag a video onto this icon"
        $link.IconLocation = "$env:SystemRoot\System32\shell32.dll,115"
        $link.Save()
    }
    Write-Host "Desktop icons created: 'Replace headset film' and 'Replace intro video' (double-click, or drag a video onto them)."
    exit 0
}

try {
    # The station should be running again at the end: always when this was started from a desktop icon (staff
    # may have closed the station to reach the icon), otherwise only if it was running - so SETUP, which also
    # uses this script, does not get covered by the full-screen station.
    $running = Get-StationProcess
    if ($running) { $script:StationArgs = ($running.CommandLine -split "visitor-station\.ps1`"?", 2)[1] }
    $script:RestartStation = [bool]$Pick -or [bool]$running

    if ($Pick) {
        $what = if ($Pick -eq "film") { "360 film for the headset" } else { "intro video for the screen" }
        Write-Host "Replace the $what" -ForegroundColor White
        $path = $Dropped | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
        if (-not $path) {
            Write-Host "Choose the new video in the window that opens..."
            $path = Pick-Video ("Choose the new " + $what + " (.mp4)")
        }
        if (-not $path) { Write-Host "No video chosen - nothing was changed." -ForegroundColor Yellow; Done 0 }
        if ($Pick -eq "film") { $Film = $path } else { $Intro = $path }
    }

    if (-not $Film -and -not $Intro) {
        Write-Host "Double-click 'Replace intro video' or 'Replace headset film' on the desktop and choose the video," -ForegroundColor Yellow
        Write-Host "or run this script with -Intro <file> or -Film <file>."
        Done 1
    }

    function Find-Adb {
        $bundled = Join-Path $PSScriptRoot "tools\scrcpy\adb.exe"
        if (Test-Path $bundled) { return $bundled }
        $root = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
        $hit = Get-ChildItem $root -Recurse -Filter adb.exe -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match "scrcpy" } | Select-Object -First 1
        if ($hit) { return $hit.FullName }
        if (Test-Path "C:\Tools\scrcpy\adb.exe") { return "C:\Tools\scrcpy\adb.exe" }
        return "adb"
    }

    function Check-Video($path) {
        if (-not (Test-Path $path)) { Write-Host "File not found: $path" -ForegroundColor Red; Done 1 }
        if ([IO.Path]::GetExtension($path).ToLower() -ne ".mp4") { Write-Host "Please use an .mp4 video file ($([IO.Path]::GetFileName($path)) is not one)." -ForegroundColor Red; Done 1 }
        return (Get-Item $path)
    }

    $ok = $true

    # ------------------------------------------------------------ film -> headset
    if ($Film) {
        $file = Check-Video $Film
        $adb = Find-Adb
        $ErrorActionPreference = "Continue"
        $dev = @(& $adb devices 2>$null | Select-Object -Skip 1 | Where-Object { $_ -match "\tdevice$" } | ForEach-Object { ($_ -split "\t")[0] })
        if ($dev.Count -eq 0) {
            Write-Host "The headset is not connected. Switch it on, check its cable, and try again." -ForegroundColor Red
            Done 1
        }
        $h = $dev[0]
        $status = ((& $adb -s $h shell cat "$AppFolder/status.txt" 2>$null) -join "")
        if ($status -match "state=Playing") {
            Write-Host "A visitor is watching the film right now. Try again when the headset is back at START." -ForegroundColor Yellow
            Done 1
        }
        $mb = [math]::Round($file.Length / 1MB)
        Write-Host "Copying $($file.Name) to the headset ($mb MB). This takes about $([math]::Max(1, [math]::Ceiling($mb / 1500))) minute(s) - keep the cable in..."
        & $adb -s $h shell mkdir -p $AppFolder 2>$null | Out-Null
        & $adb -s $h push "$($file.FullName)" "$AppFolder/journey.mp4.new" 2>&1 | Select-Object -Last 1 | Write-Host
        $size = ((& $adb -s $h shell stat -c %s "$AppFolder/journey.mp4.new" 2>$null) -join "").Trim()
        if ($size -ne "$($file.Length)") {
            Write-Host "The copy did not complete (headset has $size of $($file.Length) bytes). The old film is still in place." -ForegroundColor Red
            & $adb -s $h shell rm -f "$AppFolder/journey.mp4.new" 2>$null | Out-Null
            $ok = $false
        } else {
            & $adb -s $h shell mv -f "$AppFolder/journey.mp4.new" "$AppFolder/journey.mp4" 2>$null | Out-Null
            if ($Layout) {
                $tmp = New-TemporaryFile
                '{ "layout": "' + $Layout + '", "yaw": 0 }' | Set-Content -Encoding ascii $tmp
                & $adb -s $h push $tmp "$AppFolder/film.json" 2>$null | Out-Null
                Remove-Item $tmp
                Write-Host "Film format set to $Layout."
            }
            Write-Host "Headset film replaced. The next visit plays the new film." -ForegroundColor Green
        }
        $ErrorActionPreference = "Stop"
    }

    # ------------------------------------------------------------ intro -> PC
    if ($Intro) {
        $file = Check-Video $Intro
        $target = Join-Path $PSScriptRoot "intro.mp4"
        if ((Test-Path $target) -and $file.FullName -ieq (Resolve-Path $target).Path) { Write-Host "That is already the intro video - nothing to change." -ForegroundColor Yellow; Done 0 }
        # The station keeps the intro file open (that is what makes it start smoothly): stop it for the copy.
        if ($running) {
            Write-Host "Stopping the VR station for a moment..."
            & powershell -NoProfile -ExecutionPolicy Bypass -File $Station -Stop
            Start-Sleep -Seconds 2
        }
        if (Test-Path $target) { Copy-Item $target (Join-Path $PSScriptRoot "intro_previous.mp4") -Force }
        Copy-Item $file.FullName $target -Force
        Write-Host "Intro video replaced with $($file.Name) ($([math]::Round($file.Length / 1MB)) MB). The old one is kept as intro_previous.mp4." -ForegroundColor Green
    }

    if ($ok) { Done 0 } else { Done 1 }
} catch {
    Write-Host ""
    Write-Host "Something went wrong: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Nothing else was changed. If it keeps happening, send logs\ and this message to the technician."
    Done 1
}
