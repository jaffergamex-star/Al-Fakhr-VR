$MoiRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent   # the project folder (this file is in Deploy\dev-tools)
# PC demo, new behaviour: headset on at any time -> headset view; off for 5 s -> back to "Press the button" and the
# app restarted. This laptop has no VR runtime, so "worn" is driven by writing the app's status file (the station reads
# it every second). Uses the real Windows app from the PC demo folder.
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class PW {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern void keybd_event(byte k, byte s, uint f, UIntPtr e);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(POINT p);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr h, uint f);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [StructLayout(LayoutKind.Sequential)] struct POINT { public int X, Y; }
    public static uint PidAt(int x, int y) { var p = new POINT { X = x, Y = y }; uint pid; GetWindowThreadProcessId(GetAncestor(WindowFromPoint(p), 2), out pid); return pid; }
}
'@
[void][PW]::SetProcessDPIAware()
Add-Type -AssemblyName System.Windows.Forms
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$cx = $b.X + [int]($b.Width / 2); $cy = $b.Y + [int]($b.Height / 2)
$dir = "$MoiRoot\Delivery\MOI_PC_Demo"
$log = "$dir\logs\station-{0:yyyy-MM-dd}.log" -f (Get-Date)
$status = Join-Path $env:USERPROFILE "AppData\LocalLow\GameX\MOI Promise of Safety\status.txt"
$pos = if (Test-Path $log) { (Get-Item $log).Length } else { 0 }
$script:buf = ""; $script:fails = 0
function Pull { try { $fs = [IO.File]::Open($log, 'Open', 'Read', 'ReadWrite'); [void]$fs.Seek($script:pos, 'Begin'); $t = (New-Object IO.StreamReader($fs)).ReadToEnd(); $script:pos = $fs.Position; $fs.Close(); if ($t) { $t -split "`r?`n" | Where-Object { $_ -and $_ -notmatch 'headset: state|scrcpy: |VR screen: ' } | ForEach-Object { "    log  $_" | Write-Host }; $script:buf += $t } } catch { } }
function Wait-For($pattern, $secs) { $w = Get-Date; while (((Get-Date) - $w).TotalSeconds -lt $secs) { Pull; if ($script:buf -match $pattern) { $script:buf = ""; return ((Get-Date) - $w).TotalSeconds }; Start-Sleep -Milliseconds 200 }; return $null }
function Quiet-For($pattern, $secs) { $w = Get-Date; while (((Get-Date) - $w).TotalSeconds -lt $secs) { Pull; if ($script:buf -match $pattern) { return $false }; Start-Sleep -Milliseconds 200 }; return $true }
function Check($label, $ok) { if ($ok) { "  PASS  $label" } else { "  FAIL  $label"; $script:fails++ } }
function Worn($v, $state = "Idle", $films = 0) { [IO.File]::WriteAllText("$status.tmp", "state=$state worn=$v paused=False films=$films"); Move-Item "$status.tmp" $status -Force }
function App { Get-Process MOI_PromiseOfSafety -ErrorAction SilentlyContinue | Select-Object -First 1 }
function Top { [PW]::PidAt($cx, $cy) }

$m = "$env:USERPROFILE\AppData\LocalLow\GameX\MOI Promise of Safety\Content\manifest.json"
$holdM = if (Test-Path $m) { Rename-Item $m "manifest.json.hold" -PassThru; "$m.hold" } else { $null }
try {
    $lnk = Join-Path $env:TEMP "moi_pc_wear_test.lnk"
    $sh = New-Object -ComObject WScript.Shell; $l = $sh.CreateShortcut($lnk)
    $l.TargetPath = "powershell.exe"
    $l.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$dir\visitor-station.ps1`" -PcApp `"MOI_PromiseOfSafety\MOI_PromiseOfSafety.exe`" -MirrorWhenWorn -OffRestartsApp -OffReset 5 -SerialPort none -IntroSkip 100 -QuitAfter 400"
    $l.WorkingDirectory = $dir; $l.WindowStyle = 1; $l.Save()
    Start-Process $lnk
    Check "station up, app started" ($null -ne (Wait-For 'VR app started' 25))
    Check "app reports itself" ($null -ne (Wait-For 'headset: state=Idle' 25))
    $station = (Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'visitor-station\.ps1.*MirrorWhenWorn' } | Select-Object -First 1).ProcessId
    Start-Sleep 3
    Check "'Press the button' on top" ((Top) -eq $station)

    "1. Headset put on while 'Press the button' is showing -> headset view, no button needed"
    $pid1 = (App).Id
    Worn "True"
    $t = Wait-For 'straight to the headset view[\s\S]*mirror on screen' 6
    Check ("headset view after {0:N1} s" -f $t) ($null -ne $t)
    Start-Sleep 1
    Check "app window is what the screen shows" ((Top) -eq $pid1)

    "2. Headset taken off -> after 5 s back to 'Press the button' and the app restarted"
    Worn "False"
    $t = Wait-For 'headset off for 5 s[\s\S]*-> Waiting[\s\S]*VR app restarting' 12
    Check ("off -> waiting + restart after {0:N1} s" -f $t) ($t -ge 4.5 -and $t -le 8)
    Check "new app started" ($null -ne (Wait-For 'VR app started' 15))
    Start-Sleep 6
    $pid2 = (App).Id
    Check "app is a fresh process (pid $pid1 -> $pid2)" ($pid2 -and $pid2 -ne $pid1)
    Check "'Press the button' on top again" ((Top) -eq $station)
    Check "no headset view without anyone wearing it (10 s)" (Quiet-For '-> Mirror' 10)

    "3. Button pressed, then the headset put on during the intro -> intro stops, headset view"
    [PW]::keybd_event(0x78, 0x43, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 120; [PW]::keybd_event(0x78, 0x43, 2, [UIntPtr]::Zero)
    Check "intro playing" ($null -ne (Wait-For 'intro playing' 6))
    Start-Sleep 3
    Worn "True"
    $t = Wait-For 'put on during the intro[\s\S]*-> Mirror' 6
    Check ("headset view after {0:N1} s" -f $t) ($null -ne $t)
    Start-Sleep 2
    Check "app window on top" ((Top) -eq $pid2)

    "4. START pressed (film playing), headset taken off -> 5 s -> waiting + restart, film or not"
    $a = App
    for ($i = 0; $i -lt 3 -and [PW]::GetForegroundWindow() -ne $a.MainWindowHandle; $i++) { [PW]::keybd_event(0x12, 0x38, 0, [UIntPtr]::Zero); [PW]::keybd_event(0x12, 0x38, 2, [UIntPtr]::Zero); [void][PW]::SetForegroundWindow($a.MainWindowHandle); Start-Sleep -Milliseconds 400 }
    [PW]::keybd_event(0x20, 0x39, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 120; [PW]::keybd_event(0x20, 0x39, 2, [UIntPtr]::Zero)
    Check "film started" ($null -ne (Wait-For 'film started' 10))
    Start-Sleep 5
    Worn "False" "Playing" 1
    $t = Wait-For 'headset off for 5 s[\s\S]*-> Waiting[\s\S]*VR app restarting' 12
    Check ("off during the film -> waiting + restart after {0:N1} s" -f $t) ($t -ge 4.5 -and $t -le 8)
    Check "new app started" ($null -ne (Wait-For 'VR app started' 15))
    Start-Sleep 6
    Check "'Press the button' on top" ((Top) -eq $station)
    Check "app running again" ($null -ne (App))
} finally {
    Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'visitor-station\.ps1.*MirrorWhenWorn' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
    Start-Sleep 1
    Get-Process MOI_PromiseOfSafety -ErrorAction SilentlyContinue | Stop-Process -Force
    if ($holdM) { Rename-Item "$m.hold" (Split-Path $m -Leaf) }
}
"failures: $script:fails"
