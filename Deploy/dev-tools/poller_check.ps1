$MoiRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent   # the project folder (this file is in Deploy\dev-tools)
$f = "$MoiRoot\Deploy\visitor-station.ps1"
$src = [regex]::Match([IO.File]::ReadAllText($f), '(?s)Add-Type -TypeDefinition @"\r?\n(.*?)\r?\n"@').Groups[1].Value
try { Add-Type -TypeDefinition $src -ReferencedAssemblies System.dll -ErrorAction Stop; "C# block compiles" } catch { "C# compile error: $($_.Exception.Message)"; exit 1 }
$adb = "$MoiRoot\Delivery\MOI_VR_Station\tools\scrcpy\adb.exe"
$p = New-Object MoiHeadsetPoller($adb, "com.gamex.moi.promiseofsafety", "")
$p.Start(); Start-Sleep 3
"poller after 3 s: headset='$($p.Headset)' status='$($p.Status)' age {0:N1} s" -f ([DateTime]::Now - $p.StatusAt).TotalSeconds
$q = New-Object MoiHeadsetPoller($adb, "com.gamex.moi.promiseofsafety", "NOHEADSET")
$q.Start(); Start-Sleep 2
"poller with -Serial NOHEADSET: headset='$($q.Headset)' (expected empty)"
$p.Stop(); $q.Stop()
