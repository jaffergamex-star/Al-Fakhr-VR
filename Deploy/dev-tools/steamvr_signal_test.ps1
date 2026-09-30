# Unit test of the PC-demo wear signals in visitor-station.ps1, without windows, app or headset: loads only
# Read-SteamVrState, Get-ProximityWorn and Poll-HeadsetStatus from the station script, feeds them a fake SteamVR log,
# a fake app status file and a fake proximity reader, and checks what the station would count as "worn". Also checks
# the proximity parser (C#, MoiProximityPoller.Parse) on the headset's real dumpsys format.
param([string]$Script = "$PSScriptRoot\..\visitor-station.ps1")
$ErrorActionPreference = "Stop"
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $Script).Path, [ref]$null, [ref]$null)
$defs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -in "Read-SteamVrState", "Poll-HeadsetStatus", "Get-ProximityWorn" }, $true)
foreach ($d in $defs) { . ([ScriptBlock]::Create($d.Extent.Text)) }
if (@($defs).Count -ne 3) { "could not find the three functions in $Script"; exit 1 }

$dir = Join-Path ([IO.Path]::GetTempPath()) "moi_steamvr_test"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$SteamVrLog = Join-Path $dir "vrmonitor.txt"
$PcStatusFile = Join-Path $dir "status.txt"
$PcApp = "test.exe"
$SimulateHeadset = ""
$script:vrRunning = $true
$script:logLines = New-Object System.Collections.Generic.List[string]
function Log($m) { $script:logLines.Add($m) }
function Handle-Headset-Line($line) { }
function Get-Process { [CmdletBinding()] param([Parameter(Position = 0)]$Name) if ($script:vrRunning) { [pscustomobject]@{ Name = $Name } } }
function New-State {
    @{ headset = "PC app"; pcAppStarted = (Get-Date).AddMinutes(-1); status = $null; statusRaw = ""; worn = $null; paused = $null
       statusAt = [DateTime]::MinValue; vrWorn = $null; vrWornAt = [DateTime]::MinValue; vrState = ""; vrLogPos = [long]0
       vrLogHead = ""; vrStateLogged = $false; appWorn = $null; appWornAt = [DateTime]::MinValue; wornNote = ""
       prox = $null; proxReading = $null; proxWorn = $null; proxProblem = ""; proxStarted = [DateTime]::MinValue }
}
# Stands in for MoiProximityPoller: State -1 none / 0 off / 1 worn, At = time of the last reading.
function FakeProx([int]$state, [double]$ageSeconds = 0, [string]$problem = "") { [pscustomobject]@{ State = $state; At = (Get-Date).AddSeconds(-$ageSeconds); Serial = "FA66TEST"; Problem = $problem } }
function Stamp($secondsFromNow = 0) { (Get-Date).AddSeconds($secondsFromNow).ToString("ddd MMM dd yyyy HH:mm:ss.fff", [Globalization.CultureInfo]::InvariantCulture) }
function VrLine($to, $secondsFromNow = 0) { "$(Stamp $secondsFromNow) [Info] - [System] Unknown Transition from 'SteamVRSystemState_X' to 'SteamVRSystemState_$to'.`r`n" }
function Append($text) { [IO.File]::AppendAllText($SteamVrLog, $text) }
function AppStatus($worn) { [IO.File]::WriteAllText($PcStatusFile, "state=Idle worn=$worn paused=False films=0") }
$fails = 0
function Check($name, $got, $want) {
    $ok = if ($null -eq $want) { $null -eq $got } else { $got -eq $want -and $null -ne $got }
    if ($ok) { "  ok    $name" } else { $script:fails++; "  FAIL  $name - got '$got', want '$want'" }
}

"SteamVR log reading"
$S = New-State
[IO.File]::WriteAllText($SteamVrLog, "$(Stamp -600) [Info] - vrmonitor 2.17.10 startup with PID=1`r`n" + (VrLine "Ready" -500) + (VrLine "Standby" -400))
Read-SteamVrState
Check "whole log read at start: last state Standby" $S.vrWorn $false
Check "start logged once" ($script:logLines -contains "SteamVR: Standby") $true
Append ((VrLine "Ready").TrimEnd("`r", "`n"))
Read-SteamVrState
Check "half-written line ignored" $S.vrWorn $false
Append "`r`n"
Read-SteamVrState
Check "line finished: Ready" $S.vrWorn $true
Append ("$(Stamp) [Info] - something else`r`n" + (VrLine "NotReady"))
Read-SteamVrState
Check "NotReady = no answer" $S.vrWorn $null
[IO.File]::WriteAllText($SteamVrLog, "$(Stamp) [Info] - vrmonitor 2.17.10 startup with PID=2`r`n" + (VrLine "Standby"))
Read-SteamVrState
Check "log replaced: read from the start again" $S.vrWorn $false
$script:vrRunning = $false
Read-SteamVrState
Check "SteamVR not running = no answer" $S.vrWorn $null
$script:vrRunning = $true
$big = New-Object Text.StringBuilder
$big.Append((VrLine "Ready" -900)) | Out-Null
for ($i = 0; $i -lt 30000; $i++) { $big.Append("$(Stamp -800) [Info] - filler line number $i with some text in it`r`n") | Out-Null }
$big.Append((VrLine "Standby" -5)) | Out-Null
[IO.File]::WriteAllText($SteamVrLog, "$(Stamp -1000) [Info] - vrmonitor startup with PID=3`r`n" + $big.ToString())
$S = New-State
$t = Measure-Command { Read-SteamVrState }
Check ("big log ({0:N1} MB): latest state found in {1:N0} ms" -f ((Get-Item $SteamVrLog).Length / 1MB), $t.TotalMilliseconds) $S.vrWorn $false
Check "big log: only the last 1 MB read" ($S.vrLogPos -eq (Get-Item $SteamVrLog).Length) $true

"Combining with the app's wear sensor"
$S = New-State
[IO.File]::WriteAllText($SteamVrLog, "$(Stamp -60) [Info] - start`r`n")
AppStatus "Unknown"; Read-SteamVrState; Poll-HeadsetStatus
Check "app Unknown, SteamVR no state: no answer" $S.worn $null
Append (VrLine "Ready"); Read-SteamVrState; Poll-HeadsetStatus
Check "app Unknown, SteamVR Ready: worn" $S.worn $true
Check "note logged" (($script:logLines | Where-Object { $_ -like "worn/not worn from SteamVR (Ready)*" }).Count -eq 1) $true
Append (VrLine "Standby"); Read-SteamVrState; Poll-HeadsetStatus
Check "app Unknown, SteamVR Standby: not worn" $S.worn $false

$S = New-State
[IO.File]::WriteAllText($SteamVrLog, (VrLine "Standby" -30))
AppStatus "True"; Read-SteamVrState; Poll-HeadsetStatus
Check "app True now, SteamVR Standby from before: worn" $S.worn $true
Start-Sleep -Milliseconds 50
Append (VrLine "Standby" 1); Read-SteamVrState; Poll-HeadsetStatus
Check "app stuck True, SteamVR Standby after it: off" $S.worn $false
Check "note logged" (($script:logLines | Where-Object { $_ -like "headset counted as off*" }).Count -ge 1) $true
Append (VrLine "Ready" 2); Read-SteamVrState; Poll-HeadsetStatus
Check "SteamVR Ready again: app's True counts" $S.worn $true
AppStatus "False"; Poll-HeadsetStatus
Check "app False: not worn" $S.worn $false
Append (VrLine "Ready" 3); Read-SteamVrState; Poll-HeadsetStatus
Check "app False, SteamVR Ready (picked up by hand): still not worn" $S.worn $false
AppStatus "True"; Poll-HeadsetStatus
Check "app True: worn" $S.worn $true

"Proximity sensor (PC demo): decides whenever it has a reading"
$S = New-State
[IO.File]::WriteAllText($SteamVrLog, (VrLine "Ready" -30))
AppStatus "True"; Read-SteamVrState
$S.prox = FakeProx 0; $S.proxStarted = (Get-Date).AddMinutes(-1)
Poll-HeadsetStatus
Check "sensor off beats app True + SteamVR Ready (headset on the table)" $S.worn $false
Check "reading announced" (($script:logLines | Where-Object { $_ -like "headset proximity sensor: read over USB (FA66TEST)*" }).Count -eq 1) $true
Check "'taken off' logged" (($script:logLines | Where-Object { $_ -eq "headset proximity sensor: taken off" }).Count -eq 1) $true
Poll-HeadsetStatus
Check "same state again: not logged twice" (($script:logLines | Where-Object { $_ -eq "headset proximity sensor: taken off" }).Count -eq 1) $true
AppStatus "False"; $S.prox = FakeProx 1; Poll-HeadsetStatus
Check "sensor worn beats app False" $S.worn $true
Check "'worn' logged" (($script:logLines | Where-Object { $_ -eq "headset proximity sensor: worn" }).Count -eq 1) $true
AppStatus "True"; $S.prox = FakeProx 0 4; Poll-HeadsetStatus
Check "reading older than 3 s: fallback to the app (True)" $S.worn $true
Check "fallback logged" (($script:logLines | Where-Object { $_ -like "headset proximity sensor: no reading*" }).Count -eq 1) $true
$S.prox = FakeProx -1 0 "no headset over adb (USB debugging off, or the cable is out)"; Poll-HeadsetStatus
Check "no reading at all: still the app" $S.worn $true
Check "the reason is logged" (($script:logLines | Where-Object { $_ -like "*no headset over adb*" }).Count -eq 1) $true
$S.prox = FakeProx 0; Poll-HeadsetStatus
Check "reading back: sensor decides again" $S.worn $false
$S = New-State; AppStatus "True"
$S.prox = FakeProx -1; $S.proxStarted = Get-Date; $before = $script:logLines.Count
Poll-HeadsetStatus
Check "just started, headset not found yet: fallback" $S.worn $true
Check "just started: no 'no reading' note yet" (@($script:logLines | Select-Object -Skip $before | Where-Object { $_ -like "headset proximity sensor: no reading*" }).Count) 0

"Proximity parser (MoiProximityPoller.Parse, real dumpsys format of the Focus Vision)"
$src = [IO.File]::ReadAllText((Resolve-Path $Script).Path)
$a = $src.IndexOf("public class MoiProximityPoller"); $b = $src.IndexOf("`npublic class ", $a + 10); if ($b -lt 0) { $b = $src.IndexOf('"@', $a) }
Add-Type -TypeDefinition ("using System;`nusing System.Diagnostics;`nusing System.Threading;`n" + $src.Substring($a, $b - $a))
$dump = @"
0x00000052) ucs148c1 Proximity Sensor Wakeup | ultracapteur    | ver: 210 | type: android.sensor.proximity(8) | perm: n/a | flags: 0x00000003
ucs148c1 Proximity Sensor Wakeup: last 30 events
	27 (ts=3528.948507033, wall=18:16:58.101) 0.00, 0.00, 0.00,
	28 (ts=3531.608965887, wall=18:17:00.765) 1.00, 0.00, 0.00,
Active sensors:
"@
Check "last event 1.00 = off" ([MoiProximityPoller]::Parse($dump)) 0
Check "last event 0.00 = worn" ([MoiProximityPoller]::Parse($dump.Replace("18:17:00.765) 1.00", "18:17:00.765) 0.00"))) 1
Check "Windows line ends" ([MoiProximityPoller]::Parse(($dump -replace "`r?`n", "`r`n"))) 0
Check "newest by ts, not by order" ([MoiProximityPoller]::Parse($dump.Replace("ts=3528.948507033", "ts=9999.0"))) 1
Check "no proximity history = no reading" ([MoiProximityPoller]::Parse("ucs148c1 Proximity Sensor Wakeup: last 0 events`nActive sensors:")) -1
Check "nothing = no reading" ([MoiProximityPoller]::Parse("")) -1

"Headset station (no -PcApp) unchanged"
$S = New-State; $PcApp = ""; $SimulateHeadset = Join-Path $dir "sim.txt"
[IO.File]::WriteAllText($SimulateHeadset, "state=Idle worn=Unknown paused=False films=0")
Poll-HeadsetStatus
Check "headset app Unknown = not worn" $S.worn $false
[IO.File]::WriteAllText($SimulateHeadset, "state=Idle worn=True paused=False films=0")
Poll-HeadsetStatus
Check "headset app True = worn" $S.worn $true

Remove-Item -Recurse -Force $dir
""
if ($fails) { "$fails check(s) FAILED" } else { "all checks passed" }
