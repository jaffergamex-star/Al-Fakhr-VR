<#
  Mirrors every connected headset to a window on this PC using scrcpy (free, open source).
  Put the window(s) full screen on the TV / projector connected to this PC.

      powershell -ExecutionPolicy Bypass -File Deploy\mirror-headsets.ps1
      powershell -ExecutionPolicy Bypass -File Deploy\mirror-headsets.ps1 -Wireless   (after the one-time Wi-Fi setup, see DEPLOYMENT.md)

  Needs scrcpy: download from https://github.com/Genymobile/scrcpy/releases (Windows zip), unzip to
  C:\Tools\scrcpy  (or install with:  winget install Genymobile.scrcpy)
#>
param([switch]$Wireless, [int]$MaxSize = 1920, [int]$BitRateMbps = 12)

$Scrcpy = @("C:\Tools\scrcpy\scrcpy.exe", "scrcpy") | Where-Object { (Get-Command $_ -ErrorAction SilentlyContinue) } | Select-Object -First 1
if (-not $Scrcpy) { throw "scrcpy not found. Unzip it to C:\Tools\scrcpy or run: winget install Genymobile.scrcpy" }
$Adb = Join-Path (Split-Path (Get-Command $Scrcpy).Source) "adb.exe"

$devices = & $Adb devices | Select-Object -Skip 1 | Where-Object { $_ -match "\tdevice$" } | ForEach-Object { ($_ -split "\t")[0] }
if ($Wireless) { $devices = $devices | Where-Object { $_ -match ":\d+$" } }
if (-not $devices) { throw "No headsets connected." }

$i = 0
foreach ($d in $devices) {
    $i++
    Start-Process $Scrcpy -ArgumentList @(
        "-s", $d,
        "--no-control",                 # view only: nobody at the PC can press anything in the headset
        "--no-audio",
        "--max-size", $MaxSize,
        "--video-bit-rate", "$($BitRateMbps)M",
        "--window-title", "Headset $i ($d)",
        "--stay-awake"
    )
}
Write-Host "Mirroring $i headset(s). Drag each window to the screen and press Alt+F to make it full screen."
