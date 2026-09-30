<#
  MOI "The Promise of Safety" - install on a new PC and headset.
  Double-click SETUP.bat (or run this script) with the headset plugged into this PC by its cable.

  It installs the headset app and film, finds the VR screen and the button box, and creates the desktop icons
  (and optionally the start-at-sign-in). Every step can be re-run safely.

  Non-interactive use:
      powershell -ExecutionPolicy Bypass -File SETUP.ps1 -Screen 2 -Autostart
      powershell -ExecutionPolicy Bypass -File SETUP.ps1 -Screen 1 -NoAutostart -SkipFilm
#>
param(
    [int]$Screen = 0,
    [switch]$Autostart,
    [switch]$NoAutostart,
    [switch]$SkipApp,
    [switch]$SkipFilm,
    [switch]$NoPause
)

$ErrorActionPreference = "Continue"
$Root = $PSScriptRoot
$Package = "com.gamex.moi.promiseofsafety"
$AppFolder = "/sdcard/Android/data/$Package/files"
$Apk = Join-Path $Root "app\MOI_PromiseOfSafety.apk"
$Film = Join-Path $Root "content\journey.mp4"
$Adb = Join-Path $Root "tools\scrcpy\adb.exe"
$Station = Join-Path $Root "visitor-station.ps1"
$Content = Join-Path $Root "update-content.ps1"

function Step($n, $text) { Write-Host ""; Write-Host "[$n] $text" -ForegroundColor Cyan }
function Ok($text) { Write-Host "    OK  $text" -ForegroundColor Green }
function Warn($text) { Write-Host "    !!  $text" -ForegroundColor Yellow }
function Ask($q) { (Read-Host "    $q").Trim() }
function Finish($code) { if (-not $NoPause) { Write-Host ""; Read-Host "Press Enter to close" | Out-Null }; exit $code }

Write-Host "MOI VR station - setup" -ForegroundColor White
Write-Host "Package: $Root"
if (-not (Test-Path $Adb)) { Warn "tools\scrcpy is missing from the package."; Finish 1 }

# ------------------------------------------------------------------ 1. headset
Step 1 "Headset"
& $Adb start-server 2>$null | Out-Null
while ($true) {
    $lines = @(& $Adb devices 2>$null | Select-Object -Skip 1 | Where-Object { $_.Trim() })
    $ready = @($lines | Where-Object { $_ -match "\tdevice$" })
    if ($ready.Count -ge 1) { break }
    if ($lines -match "unauthorized") { Warn "Put the headset on and accept 'Allow USB debugging' (tick 'Always allow')." }
    else { Warn "No headset found. On the headset: Settings > Advanced > Developer options > USB debugging ON, then plug in its cable." }
    $a = Ask "Press Enter to check again, or type S to skip the headset steps"
    if ($a -match "^[sS]") { $SkipApp = $true; $SkipFilm = $true; break }
}
$Headset = $null
if ($ready.Count -ge 1) {
    $Headset = ($ready[0] -split "\t")[0]
    $model = ((& $Adb -s $Headset shell getprop ro.product.model 2>$null) -join "").Trim()
    Ok "$model ($Headset)"
    if ($ready.Count -gt 1) { Warn "More than one headset is connected; using $Headset. Unplug the others and run again for each." }
}

# ------------------------------------------------------------------ 2. app
if (-not $SkipApp -and $Headset) {
    Step 2 "Install the MOI app on the headset"
    $out = (& $Adb -s $Headset install -r -g "$Apk" 2>&1) -join " "
    if ($out -match "INSTALL_FAILED_UPDATE_INCOMPATIBLE") {
        Warn "An older copy of the app, built on another computer, is on the headset. It must be removed first."
        Warn "Its film will be removed with it; this setup copies the film again in the next step."
        if ((Ask "Remove it and install this one? (Y/N)") -match "^[yY]") {
            & $Adb -s $Headset uninstall $Package 2>&1 | Out-Null
            $out = (& $Adb -s $Headset install -g "$Apk" 2>&1) -join " "
        }
    }
    if ($out -match "Success") { Ok "App installed." } else { Warn "Install failed: $out" }
    # Start it once so Android creates its folder.
    & $Adb -s $Headset shell monkey -p $Package -c android.intent.category.LAUNCHER 1 2>&1 | Out-Null
    Start-Sleep -Seconds 6
}

# ------------------------------------------------------------------ 3. film
if (-not $SkipFilm -and $Headset) {
    Step 3 "Copy the 360 film to the headset"
    if (Test-Path $Film) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $Content -Film "$Film" -NoPause
    } else {
        Warn "No content\journey.mp4 in the package. Add the film later with the 'Replace headset film' icon."
    }
}

# ------------------------------------------------------------------ 4. screen
Step 4 "VR screen"
Write-Host "    A number appears on each screen for 6 seconds; the VR screen is marked."
$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $Station -IdentifyScreens $(if ($Screen -gt 0) { "-Screen"; $Screen })
$out | Where-Object { $_ -match '^Screen \d' } | ForEach-Object { Write-Host "    $_" }
$line = $out | Where-Object { $_ -match 'will use' } | Select-Object -First 1
Ok ($line -replace '^The station', 'The VR station')
if ($Screen -le 0) { Write-Host "    It finds the screen attached to this PC by itself, also if it is switched on later." }

# ------------------------------------------------------------------ 5. button box
Step 5 "Button box"
$ports = & powershell -NoProfile -ExecutionPolicy Bypass -File $Station -ListPorts
$auto = ($ports | Where-Object { $_ -match "Auto-detect would use" })
if ($auto) { Ok ($auto -replace "Auto-detect would use:", "found on") }
else { Warn "Button box not found. Plug it in; it is detected automatically whenever it is connected." }
$texts = $ports | Where-Object { $_ -match "^Button texts:" }
if ($texts) { Ok (($texts -replace "^Button texts:", "listens for") + " - a box that sends something else: edit button-commands.txt") }

# ------------------------------------------------------------------ 6. icons + autostart
Step 6 "Desktop icons"
$screenArgs = @(); if ($Screen -gt 0) { $screenArgs = @("-Screen", $Screen) }
& powershell -NoProfile -ExecutionPolicy Bypass -File $Station -InstallShortcuts @screenArgs | Out-Null
& powershell -NoProfile -ExecutionPolicy Bypass -File $Content -InstallShortcuts | Out-Null
Ok "Start VR Station, Stop VR Station, Replace headset film, Replace intro video"

if (-not $Autostart -and -not $NoAutostart) {
    $Autostart = (Ask "Start the station automatically when Windows signs in? Recommended on the museum PC. (Y/N)") -match "^[yY]"
}
if ($Autostart) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $Station -InstallAutostart @screenArgs | Out-Null
    Ok "Starts at sign-in."
} else {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $Station -RemoveAutostart | Out-Null
    Ok "Not started at sign-in (use the Start VR Station icon)."
}

# ------------------------------------------------------------------ done
Write-Host ""
Write-Host "Setup finished." -ForegroundColor Green
Write-Host "Still to do by hand (see STAFF-HANDBOOK.html and DEPLOYMENT.md):"
Write-Host "  - Windows: automatic sign-in, never sleep, display never off."
Write-Host "  - Headset: boundary 'Stationary', then Kiosk mode (single app: MOI Promise of Safety,"
Write-Host "    USB connections ON, screen capture ON). Write the passcode in the handbook."
Write-Host "  - Test: double-click Start VR Station, press the button, do one full visit."
Finish 0
