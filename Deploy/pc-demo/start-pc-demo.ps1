<#
  PC VR demo of "The Promise of Safety": the app runs on this PC and is streamed to the VIVE Focus Vision
  by VIVE Hub (VIVE Streaming) / SteamVR - whichever is set as the PC's OpenXR runtime.
  Checks the PC, then starts the visitor station (the same flow as the museum kiosk):
      "Press the button to begin" -> intro film on the screen -> "Please put on the headset"
      -> the screen shows what the visitor sees in the headset -> back to "Press the button to begin".
  The station starts the app itself and closes it when the station closes (Ctrl+Shift+Q).
      -Check     only check, don't start
      -AppOnly   just the app, full screen, without the button / intro station
      -Yes       start even if a check fails, without asking (for an autostart shortcut)
#>
param([switch]$Check, [switch]$AppOnly, [switch]$Yes)

$exe = Join-Path $PSScriptRoot "MOI_PromiseOfSafety\MOI_PromiseOfSafety.exe"
$station = Join-Path $PSScriptRoot "visitor-station.ps1"
$film = Join-Path $PSScriptRoot "MOI_PromiseOfSafety\content\journey.mp4"
$ok = $true
function Good($m) { Write-Host "  OK    $m" -ForegroundColor Green }
function Bad($m) { Write-Host "  !!    $m" -ForegroundColor Yellow; $script:ok = $false }

Write-Host ""
Write-Host "The Promise of Safety - PC VR demo" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $exe) -or -not (Test-Path $station)) { Bad "Files are missing next to this script (unzip the whole folder)"; Read-Host "Press Enter to close"; exit 1 }

# The OpenXR runtime is what carries the picture to the headset.
$runtime = try { (Get-ItemProperty "HKLM:\SOFTWARE\Khronos\OpenXR\1" -ErrorAction Stop).ActiveRuntime } catch { $null }
if (-not $runtime) {
    Bad "No VR runtime is set on this PC. SteamVR > Settings > OpenXR > Set SteamVR as OpenXR runtime"
    Write-Host "        (or the same option in VIVE Hub's settings). See README-PC-DEMO.txt."
} else {
    $name = if ($runtime -match "(?i)steamvr") { "SteamVR" } elseif ($runtime -match "(?i)vive|htc") { "VIVE" } else { Split-Path $runtime -Leaf }
    Good "VR runtime: $name ($runtime)"
}
if (Get-Process vrserver, vrmonitor -ErrorAction SilentlyContinue) { Good "SteamVR is running" }
elseif ($runtime -match "(?i)steamvr") { Write-Host "  ..    SteamVR is not running yet: connect the headset (VIVE Hub, USB) - the app goes into VR as soon as it is there" }

# The film is HEVC (H.265); Windows plays that only with Microsoft's HEVC extension.
if (Get-AppxPackage -Name "*HEVC*" -ErrorAction SilentlyContinue) { Good "HEVC video support installed" }
else { Bad "Windows can't play the film yet: install 'HEVC Video Extensions' from the Microsoft Store" }

if (Test-Path $film) { Good ("Film: content\journey.mp4 (8K, {0:N0} MB)" -f ((Get-Item $film).Length / 1MB)) }
else { Bad "No film at MOI_PromiseOfSafety\content\journey.mp4 - the demo would show 'The film is missing'" }
if (-not $AppOnly) {
    if (Test-Path (Join-Path $PSScriptRoot "intro.mp4")) { Good "Intro: intro.mp4" } else { Bad "No intro.mp4 next to this script - the station goes straight to 'Please put on the headset'" }
}

$gpu = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
if ($gpu | Where-Object { $_ -match "(?i)nvidia|geforce|rtx|gtx|radeon rx|radeon pro|arc a" }) { Good ("Graphics: " + ($gpu -join ", ")) }
else { Bad ("Graphics: " + ($gpu -join ", ") + " - built-in graphics may stream a choppy picture and stutter on the 8K film") }

Write-Host ""
if ($Check) { if ($ok) { Write-Host "All set." -ForegroundColor Green }; exit 0 }
$stationRunning = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'visitor-station\.ps1' -and $_.CommandLine -notmatch '-Stop' }
if ($stationRunning -or (Get-Process MOI_PromiseOfSafety -ErrorAction SilentlyContinue)) { Write-Host "The demo is already running."; Start-Sleep 3; exit 0 }
if (-not $ok -and -not $Yes) {
    Write-Host "Start anyway? (Type Y and Enter to start, or just Enter to stop)" -ForegroundColor Yellow
    if ((Read-Host) -notmatch '^[yY]') { exit 1 }
}

if ($AppOnly) {
    Write-Host "Starting the app full screen. Close it with Alt+F4."
    # Same as the station does: VIVE Hub's OpenXR add-on layers off for the app (it uses none of them).
    foreach ($v in "DISABLE_XR_APILAYER_VIVE_HAND_TRACKING_1", "DISABLE_XR_APILAYER_VIVE_FACIAL_TRACKING_1", "DISABLE_XR_APILAYER_VIVE_MR_1", "DISABLE_XR_APILAYER_VIVE_XRTRACKER_1") { Set-Item -Path "Env:$v" -Value "1" }
    $start = @{ FilePath = $exe; WorkingDirectory = (Split-Path $exe) }
    Start-Process @start
} else {
    Write-Host "Starting the visitor station: 'Press the button to begin' (button box, or F9 on the keyboard)."
    Write-Host "Staff: Ctrl+Shift+Q closes the station and the app."
    # Station defaults: headset on at any time = headset view (no need for the button); off for 5 s = back to "Press
    # the button" and the app back to its START screen. (-OffRestartsApp would restart the whole app each time.)
    $a = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$station`" -PcApp `"MOI_PromiseOfSafety\MOI_PromiseOfSafety.exe`""
    Start-Process powershell.exe -ArgumentList $a -WorkingDirectory $PSScriptRoot -WindowStyle Hidden
}
Start-Sleep 4
