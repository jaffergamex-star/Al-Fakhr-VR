$MoiRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent   # the project folder (this file is in Deploy\dev-tools)
# Full visit through the station in PC mode with the real PC app (no VR runtime on this laptop: the app runs in a
# plain window and reports worn=Unknown, so the mirror comes on the "no worn signal" timer). Checks at each step
# which window the screen really shows.
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class PS {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern void keybd_event(byte k, byte s, uint f, UIntPtr e);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(POINT p);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr h, uint f);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [StructLayout(LayoutKind.Sequential)] struct POINT { public int X, Y; }
    public struct RECT { public int L, T, R, B; }
    public static uint PidAt(int x, int y) { var p = new POINT { X = x, Y = y }; uint pid; GetWindowThreadProcessId(GetAncestor(WindowFromPoint(p), 2), out pid); return pid; }
}
'@
[void][PS]::SetProcessDPIAware()
Add-Type -AssemblyName System.Windows.Forms
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$cx = $b.X + [int]($b.Width / 2); $cy = $b.Y + [int]($b.Height / 2)
$dir = "$MoiRoot\Delivery\MOI_PC_Demo"
$log = "$dir\logs\station-{0:yyyy-MM-dd}.log" -f (Get-Date)
$pos = if (Test-Path $log) { (Get-Item $log).Length } else { 0 }
$script:buf = ""; $t0 = Get-Date; $script:fails = 0
function Pull { try { $fs = [IO.File]::Open($log, 'Open', 'Read', 'ReadWrite'); [void]$fs.Seek($script:pos, 'Begin'); $t = (New-Object IO.StreamReader($fs)).ReadToEnd(); $script:pos = $fs.Position; $fs.Close(); if ($t) { $t -split "`r?`n" | Where-Object { $_ } | ForEach-Object { "    log  $_" | Write-Host }; $script:buf += $t } } catch { } }
function Wait-For($pattern, $secs) { $w = Get-Date; while (((Get-Date) - $w).TotalSeconds -lt $secs) { Pull; if ($script:buf -match $pattern) { $script:buf = ""; return ((Get-Date) - $w).TotalSeconds }; Start-Sleep -Milliseconds 200 }; return $null }
function Check($label, $ok) { if ($ok) { "  PASS  $label" } else { "  FAIL  $label"; $script:fails++ } }
function Pid-Of($pattern) { (Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match $pattern } | Select-Object -First 1).ProcessId }

$m = "$env:USERPROFILE\AppData\LocalLow\GameX\MOI Promise of Safety\Content\manifest.json"; $hold = "$m.pcdemo-test-hold"
Rename-Item $m (Split-Path $hold -Leaf)
try {
    $lnk = Join-Path $env:TEMP "moi_pc_station_test.lnk"
    $sh = New-Object -ComObject WScript.Shell; $l = $sh.CreateShortcut($lnk)
    $l.TargetPath = "powershell.exe"
    $l.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$dir\visitor-station.ps1`" -PcApp `"MOI_PromiseOfSafety\MOI_PromiseOfSafety.exe`" -SerialPort none -IntroSkip 110 -QuitAfter 300"
    $l.WorkingDirectory = $dir; $l.WindowStyle = 1; $l.Save()
    Start-Process $lnk

    "1. Station starts, starts the VR app behind it"
    Check "VR app started" ($null -ne (Wait-For 'VR app started' 20))
    Start-Sleep 10
    $noVr = Get-Content "$env:USERPROFILE\AppData\LocalLow\GameX\MOI Promise of Safety\Player.log" | Where-Object { $_ -match '\[MOI\] (No VR runtime|VR runtime)' } | Select-Object -First 1
    Check "app knows there is no VR runtime and caps itself: $noVr" ($noVr -match '60 fps')
    $gpu = (Get-Counter "\GPU Engine(*engtype_3D)\Utilization Percentage").CounterSamples | Where-Object { $_.InstanceName -match "^pid_$((Get-Process MOI_PromiseOfSafety).Id)_" } | Measure-Object CookedValue -Sum
    Check ("app graphics load {0:N0}% (was 99% uncapped)" -f $gpu.Sum) ($gpu.Sum -lt 85)
    $station = Pid-Of 'visitor-station\.ps1.*-PcApp'
    $app = (Get-Process MOI_PromiseOfSafety -ErrorAction SilentlyContinue | Select-Object -First 1)
    $r = New-Object PS+RECT; [void][PS]::GetWindowRect($app.MainWindowHandle, [ref]$r)
    Check ("app window {0}x{1} at ({2},{3}) = the screen {4}x{5}" -f ($r.R - $r.L), ($r.B - $r.T), $r.L, $r.T, $b.Width, $b.Height) (($r.R - $r.L) -eq $b.Width -and ($r.B - $r.T) -eq $b.Height -and $r.L -eq $b.X -and $r.T -eq $b.Y)
    Check "'Press the button' screen on top of the app" ([PS]::PidAt($cx, $cy) -eq $station)

    "2. Button -> intro (last 10 s) -> 'Please put on the headset'"
    [PS]::keybd_event(0x78, 0x43, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 120; [PS]::keybd_event(0x78, 0x43, 2, [UIntPtr]::Zero)
    Check "intro" ($null -ne (Wait-For '-> Intro' 5))
    Check "station screen on top during the intro" ([PS]::PidAt($cx, $cy) -eq $station)
    Check "wear step" ($null -ne (Wait-For '-> Wear' 20))

    "3. No worn signal on this laptop (no VR runtime) -> mirror after 12 s: the app's window"
    $t = Wait-For 'mirror on screen' 20
    Check ("mirror on screen after {0:N1} s" -f $t) ($null -ne $t)
    Start-Sleep 1
    Check "the app window is what the screen shows" ([PS]::PidAt($cx, $cy) -eq $app.Id)

    "4. Visitor presses START (Space in the app) -> film"
    for ($try = 0; $try -lt 3 -and [PS]::GetForegroundWindow() -ne $app.MainWindowHandle; $try++) { [PS]::keybd_event(0x12, 0x38, 0, [UIntPtr]::Zero); [PS]::keybd_event(0x12, 0x38, 2, [UIntPtr]::Zero); [void][PS]::SetForegroundWindow($app.MainWindowHandle); Start-Sleep -Milliseconds 400 }
    [PS]::keybd_event(0x20, 0x39, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 120; [PS]::keybd_event(0x20, 0x39, 2, [UIntPtr]::Zero)
    Check "film started" ($null -ne (Wait-For 'film started' 10))
    Start-Sleep 20
    Check "app still what the screen shows during the film" ([PS]::PidAt($cx, $cy) -eq $app.Id)

    "5. Film ends -> back to 'Press the button', app keeps running behind it"
    Check "film finished -> Waiting" ($null -ne (Wait-For 'film finished[\s\S]*-> Waiting' 90))
    Start-Sleep 1
    Check "station screen on top again" ([PS]::PidAt($cx, $cy) -eq $station)
    Check "app still running (ready for the next visitor)" (-not $app.HasExited)

    "--- film playback lines from the app"
    Get-Content "$env:USERPROFILE\AppData\LocalLow\GameX\MOI Promise of Safety\Player.log" | Where-Object { $_ -match '\[MOI\] (Playing film|Film )' } | ForEach-Object { "    $_" }

    "6. Ctrl+Shift+Q is replaced here by the test's own stop: station and app closed"
    Stop-Process -Id $station -Force; Start-Sleep 1
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$dir\visitor-station.ps1" -Stop
    Start-Sleep 2
    Check "app closed by the Stop command" (-not (Get-Process MOI_PromiseOfSafety -ErrorAction SilentlyContinue))
    Remove-Item $lnk -ErrorAction SilentlyContinue
} finally {
    Get-Process MOI_PromiseOfSafety -ErrorAction SilentlyContinue | Stop-Process -Force
    Rename-Item $hold (Split-Path $m -Leaf)
    "cached manifest restored: " + (Test-Path $m)
}
"failures: $script:fails"
