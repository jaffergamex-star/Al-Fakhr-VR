<#
  Installs the MOI app on every VIVE Focus Vision plugged into this PC (USB, USB debugging allowed).
  Plug in as many headsets as you have (a USB hub is fine) and run:

      powershell -ExecutionPolicy Bypass -File Deploy\deploy-headsets.ps1

  Optional:
      -Film "D:\film\journey.mp4"                   copy the film onto each headset (into the app's own folder)
      -Layout TopBottom360                          film format if not mono 360: Mono360 | TopBottom360 | SideBySide360 | FlatScreen
      -ManifestUrl "http://192.168.0.10:8765/manifest.json"   point each headset at the LAN content server
      -Launch                                       start the app on each headset when done
#>
param(
    [string]$Apk = "$PSScriptRoot\..\Builds\MOI_PromiseOfSafety.apk",
    [string]$Film = "",
    [ValidateSet("", "Mono360", "TopBottom360", "SideBySide360", "FlatScreen")] [string]$Layout = "",
    [string]$ManifestUrl = "",
    [switch]$Launch
)

$ErrorActionPreference = "Stop"
$Package = "com.gamex.moi.promiseofsafety"
$Adb = "C:\Program Files\Unity\Hub\Editor\6000.1.4f1\Editor\Data\PlaybackEngines\AndroidPlayer\SDK\platform-tools\adb.exe"
if (-not (Test-Path $Adb)) { $Adb = "adb" }
if (-not (Test-Path $Apk)) { throw "APK not found: $Apk  (build it with MOI > 3. Build APK)" }

$devices = & $Adb devices | Select-Object -Skip 1 | Where-Object { $_ -match "\tdevice$" } | ForEach-Object { ($_ -split "\t")[0] }
$unauthorized = & $Adb devices | Where-Object { $_ -match "unauthorized" }
if ($unauthorized) { Write-Warning "Some headsets are 'unauthorized': put them on and accept 'Allow USB debugging', then run again." }
if (-not $devices) { throw "No headsets found. Check cable, USB debugging, and the prompt inside each headset." }

Write-Host "Found $($devices.Count) headset(s): $($devices -join ', ')" -ForegroundColor Cyan

foreach ($d in $devices) {
    $model = (& $Adb -s $d shell getprop ro.product.model).Trim()
    Write-Host "`n=== $d ($model) ===" -ForegroundColor Yellow

    Write-Host "Installing APK..."
    & $Adb -s $d install -r -g $Apk
    if ($LASTEXITCODE -ne 0) { Write-Warning "Install failed on $d"; continue }

    if ($Film) {
        # Start the app once so Android creates its folder, then copy the film into it.
        & $Adb -s $d shell monkey -p $Package 1 | Out-Null
        Start-Sleep -Seconds 6
        & $Adb -s $d shell am force-stop $Package
        $dest = "/sdcard/Android/data/$Package/files"
        & $Adb -s $d shell mkdir -p $dest
        Write-Host "Copying film (a 1 GB file takes about a minute over USB)..."
        & $Adb -s $d push $Film "$dest/journey.mp4"
        if ($LASTEXITCODE -ne 0) { Write-Warning "Film copy failed on $d"; continue }
        if ($Layout) {
            $info = New-TemporaryFile
            '{ "layout": "' + $Layout + '", "yaw": 0 }' | Set-Content -Encoding ascii $info
            & $Adb -s $d push $info "$dest/film.json"
            Remove-Item $info
        }
    }

    if ($ManifestUrl) {
        $cfg = New-TemporaryFile
        '{ "manifestUrl": "' + $ManifestUrl + '", "recheckMinutes": 10 }' | Set-Content -Encoding ascii $cfg
        & $Adb -s $d shell mkdir -p "/sdcard/Android/data/$Package/files"
        & $Adb -s $d push $cfg "/sdcard/Android/data/$Package/files/moi-config.json"
        Remove-Item $cfg
        Write-Host "Content server set to $ManifestUrl"
    }

    # Keep the screen from sleeping while charging on the dock (kiosk use).
    & $Adb -s $d shell settings put global stay_on_while_plugged_in 7 | Out-Null

    if ($Launch) { & $Adb -s $d shell monkey -p $Package 1 | Out-Null; Write-Host "Launched." }
    Write-Host "Done: $d" -ForegroundColor Green
}
Write-Host "`nAll done. Label each headset with its serial so you know which is which."
