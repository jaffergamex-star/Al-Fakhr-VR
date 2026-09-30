# Mirror quality test (headset station, MOI_VR_Station): shows the headset mirror on the VR screen with several stream
# settings one after the other, while the film plays in the headset, and saves stills of each - so we can see which
# setting looks best on the real screen (the museum LED is 3096x1290).
#   1  H.264  6 Mbit/s   the station's setting until 2026-09-30
#   2  H.264 20 Mbit/s   the station's new default
#   3  H.265 20 Mbit/s
#   4  H.265 40 Mbit/s
# Same slice of the left eye and the same stream size as the station (asks visitor-station.ps1 -MirrorCropFor).
# Stills + report: Review\mirror-test-<time>\ (in the project folder).
#
# Before: close the station (only one scrcpy can show the headset). Headset on USB, the MOI app running on it.
param(
    [int]$Screen = 0,          # 1 = leftmost; default: the largest screen that is not the primary one, else the primary
    [int]$Seconds = 20,        # how long each setting is shown
    [string]$Scrcpy = "",
    # Use the mirror slice and stream size for a screen of this size instead of the real one (e.g. the museum's LED
    # 3096x1290 while testing on an office monitor): shown scaled to fit, and each stream is also saved as a video.
    [string]$Size = "",
    [switch]$NoPause           # no "press Enter" at the end (when run by a script)
)
# adb and scrcpy write normal messages to their error output: never treat those as a failure.
$ErrorActionPreference = "Continue"
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public static class MoiDpi { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }'
[void][MoiDpi]::SetProcessDPIAware()   # real pixels for the screen bounds and the stills

$deploy = Split-Path $PSScriptRoot
$project = Split-Path $deploy
function Fail($text) { Write-Host $text -ForegroundColor Red; Read-Host "Press Enter to close"; exit 1 }

# scrcpy: next to the station (package), the station package on the Desktop, C:\Tools, winget
if (-not $Scrcpy) {
    $cands = @((Join-Path $deploy "tools\scrcpy\scrcpy.exe"), (Join-Path $env:USERPROFILE "Desktop\MOI_VR_Station\MOI_VR_Station\tools\scrcpy\scrcpy.exe"), "C:\Tools\scrcpy\scrcpy.exe")
    $Scrcpy = $cands | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $Scrcpy) {
        $w = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
        if (Test-Path $w) { $Scrcpy = Get-ChildItem $w -Directory -Filter "Genymobile.scrcpy*" -ErrorAction SilentlyContinue | Get-ChildItem -Recurse -Filter scrcpy.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName }
    }
}
if (-not $Scrcpy -or -not (Test-Path $Scrcpy)) { Fail "scrcpy not found. Pass -Scrcpy <path to scrcpy.exe>." }
$adb = Join-Path (Split-Path $Scrcpy) "adb.exe"

$running = Get-Process scrcpy -ErrorAction SilentlyContinue
if ($running) { Fail "A mirror (scrcpy) is already running - close the station first (Ctrl+Shift+Q), then run this again." }
$hs = @(& $adb devices 2>$null | Select-Object -Skip 1 | Where-Object { $_ -match "\tdevice$" } | ForEach-Object { ($_ -split "\t")[0] })
if (-not $hs) { Fail "No headset on USB (or USB debugging not allowed on it)." }
$serial = $hs[0]

# screen
$list = @([System.Windows.Forms.Screen]::AllScreens | Sort-Object { $_.Bounds.X }, { $_.Bounds.Y })
if ($Screen -gt 0) { $scr = $list[[Math]::Min($Screen, $list.Count) - 1] }
else { $scr = $list | Where-Object { -not $_.Primary } | Sort-Object { -($_.Bounds.Width * $_.Bounds.Height) } | Select-Object -First 1; if (-not $scr) { $scr = $list | Where-Object { $_.Primary } | Select-Object -First 1 } }
$b = $scr.Bounds
Write-Host ("VR screen: {0}x{1} at ({2},{3}){4}" -f $b.Width, $b.Height, $b.X, $b.Y, $(if ($scr.Primary) { " - the PRIMARY screen: this window will be covered while the mirror shows" } else { "" }))

# the station's slice and stream size for this screen (or for -Size)
$target = if ($Size) { $Size } else { "{0}x{1}" -f $b.Width, $b.Height }
if ($target -notmatch '^(\d+)x(\d+)$') { Fail "Use -Size WIDTHxHEIGHT, e.g. 3096x1290" }
$tw = [int]$Matches[1]; $th = [int]$Matches[2]
$out = (& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $deploy "visitor-station.ps1") -MirrorCropFor $target) -join " "
if ($out -notmatch "mirror slice (\d+:\d+:\d+:\d+).*?up to (\d+) px") { Fail "Could not get the mirror slice from visitor-station.ps1: $out" }
$crop = $Matches[1]; $size = $Matches[2]
Write-Host "Mirror slice $crop, stream up to $size px (what the station uses on a $target screen)."
# The window: the whole screen, or the -Size shape fitted into it (bars above and below).
$win = $b
if ($Size) {
    $k = [Math]::Min($b.Width / $tw, $b.Height / $th)
    $ww = [int]($tw * $k); $wh = [int]($th * $k)
    $win = New-Object System.Drawing.Rectangle ($b.X + [int](($b.Width - $ww) / 2)), ($b.Y + [int](($b.Height - $wh) / 2)), $ww, $wh
    Write-Host ("Shown {0}x{1} on this screen (scaled {2:N2}); the full-size streams are saved as videos." -f $ww, $wh, $k)
}

# The MOI app must run on the headset, and the film must be playing while the settings are compared.
$pkg = "com.gamex.moi.promiseofsafety"
if (-not ((& $adb -s $serial shell pidof $pkg) -join "")) {
    Write-Host "Starting the MOI app on the headset..."
    & $adb -s $serial shell monkey -p $pkg -c android.intent.category.LAUNCHER 1 2>&1 | Out-Null
    Start-Sleep -Seconds 5
}

$presets = @(
    @{ n = 1; name = "H.264  6 Mbit/s (old station setting)"; codec = "h264"; rate = "6M" },
    @{ n = 2; name = "H.264 20 Mbit/s (new default)"; codec = "h264"; rate = "20M" },
    @{ n = 3; name = "H.265 20 Mbit/s"; codec = "h265"; rate = "20M" },
    @{ n = 4; name = "H.265 40 Mbit/s"; codec = "h265"; rate = "40M" }
)
$dir = Join-Path $project ("Review\mirror-test-{0:yyyyMMdd-HHmmss}" -f (Get-Date))
New-Item -ItemType Directory -Force $dir | Out-Null
$report = New-Object System.Collections.Generic.List[string]
$report.Add(("Mirror quality test {0:yyyy-MM-dd HH:mm}, headset {1}, screen {2}x{3} ({4}), slice {5}, stream up to {6} px, 30 fps" -f (Get-Date), $serial, $b.Width, $b.Height, $target, $crop, $size))

Write-Host ""
Write-Host "Put the headset on (or let someone wear it) and press START so the FILM plays - moving pictures show the difference." -ForegroundColor Cyan
Write-Host ("The test starts by itself when the film plays (waits up to 5 minutes). Each setting shows for {0} s; 1 to 4 beeps say which one is on." -f $Seconds) -ForegroundColor Cyan
$status = "/sdcard/Android/data/$pkg/files/status.txt"
$deadline = (Get-Date).AddMinutes(5); $playing = $false
while ((Get-Date) -lt $deadline) {
    $st = (& $adb -s $serial shell cat $status 2>$null) -join " "
    if ($st -match "state=Playing") { $playing = $true; break }
    Start-Sleep -Seconds 1
}
if (-not $playing) { Fail "The film did not start in the headset within 5 minutes (status: $st)." }
Write-Host "Film is playing - starting in 3 s." -ForegroundColor Green
Start-Sleep -Seconds 3

function Still($file) {
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
    $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}

foreach ($p in $presets) {
    for ($i = 0; $i -lt $p.n; $i++) { [console]::Beep(880, 180); Start-Sleep -Milliseconds 120 }
    Write-Host ("{0:HH:mm:ss}  {1}. {2}" -f (Get-Date), $p.n, $p.name) -ForegroundColor Yellow
    $err = Join-Path $dir ("scrcpy-{0}.txt" -f $p.n)
    $sargs = @("-s", $serial, "--no-control", "--no-audio", "--max-size", $size, "--max-fps", "30", "--video-bit-rate", $p.rate,
              "--video-codec=$($p.codec)", "--crop", $crop, "--window-title", "`"MOI mirror test $($p.n)`"", "--window-borderless",
              "--window-x", $win.X, "--window-y", $win.Y, "--window-width", $win.Width, "--window-height", $win.Height, "--always-on-top",
              "--record=`"$(Join-Path $dir ('{0}-{1}-{2}.mp4' -f $p.n, $p.codec, $p.rate))`"")
    $proc = Start-Process $Scrcpy -ArgumentList $sargs -PassThru -WindowStyle Hidden -RedirectStandardError $err -RedirectStandardOutput (Join-Path $dir ("scrcpy-{0}-out.txt" -f $p.n))
    $shots = @(); $failed = $false
    $shotAt = @(7, 14)   # seconds into each setting (the stream needs a few seconds to settle)
    $start = Get-Date
    while (((Get-Date) - $start).TotalSeconds -lt $Seconds) {
        Start-Sleep -Milliseconds 500
        if ($proc.HasExited) { $failed = $true; break }
        $t = ((Get-Date) - $start).TotalSeconds
        if ($shots.Count -lt $shotAt.Count -and $t -ge $shotAt[$shots.Count]) {
            $f = Join-Path $dir ("{0}-{1}-{2}-{3:00}s.png" -f $p.n, $p.codec, $p.rate, $shotAt[$shots.Count])
            Still $f; $shots += (Split-Path $f -Leaf)
        }
    }
    # Close the window normally so the recording is finished properly (a killed scrcpy leaves a broken video).
    if (-not $proc.HasExited) { [void]$proc.CloseMainWindow(); if (-not $proc.WaitForExit(4000)) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } }
    Start-Sleep -Milliseconds 800
    if ($failed) {
        $why = (Get-Content $err -ErrorAction SilentlyContinue | Select-Object -Last 3) -join " / "
        Write-Host ("            did not run: {0}" -f $why) -ForegroundColor Red
        $report.Add(("{0}. {1}: FAILED - {2}" -f $p.n, $p.name, $why))
    } else {
        $report.Add(("{0}. {1}: shown {2} s, stills {3}" -f $p.n, $p.name, $Seconds, ($shots -join ", ")))
    }
}
[console]::Beep(660, 500)
$report.Add("")
$report.Add("Which looked best on the screen? Tell Claude the number; it sets that as the station's default (-MirrorBitRate / -MirrorCodec).")
[IO.File]::WriteAllLines((Join-Path $dir "report.txt"), $report, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ""
$report | ForEach-Object { Write-Host $_ }
Write-Host ""
Write-Host "Stills, videos and report: $dir" -ForegroundColor Green
if (-not $NoPause) { Read-Host "Press Enter to close" }
