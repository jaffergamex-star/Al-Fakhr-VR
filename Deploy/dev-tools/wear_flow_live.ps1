$MoiRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent   # the project folder (this file is in Deploy\dev-tools)
# Live test of the new flow with the real headset (museum-station mirror in place of the PC app window):
# headset on at any time -> mirror; off for 5 s -> back to "Press the button". Follows the station log, checks each
# second what the visitor screen really shows, and reports the timing of every step. Runs up to 7 minutes.
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class WL {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(POINT p);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr h, uint f);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [StructLayout(LayoutKind.Sequential)] struct POINT { public int X, Y; }
    public static uint PidAt(int x, int y) { var p = new POINT { X = x, Y = y }; uint pid; GetWindowThreadProcessId(GetAncestor(WindowFromPoint(p), 2), out pid); return pid; }
}
'@
[void][WL]::SetProcessDPIAware()
Add-Type -AssemblyName System.Windows.Forms
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$cx = $b.X + [int]($b.Width / 2); $cy = $b.Y + [int]($b.Height / 2)
$pkg = "$MoiRoot\Delivery\MOI_VR_Station"
$log = "$pkg\logs\station-{0:yyyy-MM-dd}.log" -f (Get-Date)
$pos = if (Test-Path $log) { (Get-Item $log).Length } else { 0 }
$t0 = Get-Date
function Say($m) { "{0:HH:mm:ss}  {1}" -f (Get-Date), $m }
function Pull { $t = ""; try { $fs = [IO.File]::Open($log, 'Open', 'Read', 'ReadWrite'); [void]$fs.Seek($script:pos, 'Begin'); $t = (New-Object IO.StreamReader($fs)).ReadToEnd(); $script:pos = $fs.Position; $fs.Close() } catch { }; return $t }

$lnk = Join-Path $env:TEMP "moi_wear_live.lnk"
$sh = New-Object -ComObject WScript.Shell; $l = $sh.CreateShortcut($lnk)
$l.TargetPath = "powershell.exe"
$l.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$pkg\visitor-station.ps1`" -IntroSkip 100 -QuitAfter 900"
$l.WorkingDirectory = $pkg; $l.WindowStyle = 1; $l.Save()
Start-Process $lnk
Say "station started (museum package, mirror = scrcpy) with the new defaults, for 15 minutes"

$state = "start"; $station = $null; $mirrorShown = $false; $ok = 0; $bad = 0; $badWho = @{}; $lastSample = Get-Date
$events = @()
while (((Get-Date) - $t0).TotalMinutes -lt 15) {
    foreach ($line in ((Pull) -split "`r?`n" | Where-Object { $_ -and $_ -notmatch 'scrcpy: |VR screen: ' })) {
        if ($line -match 'headset: state=') { continue }
        Say "log: $line"
        if ($line -match '-> (\w+)') { $state = $Matches[1]; if ($state -ne "Mirror") { $mirrorShown = $false } }
        if ($line -match 'mirror on screen') { $mirrorShown = $true }
        if ($line -match 'straight to the headset view|headset off for|headset put on|film started|film finished|film stopped|-> Waiting|app told to') { $events += $line }
    }
    if (-not $station) { $station = (Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'visitor-station\.ps1.*QuitAfter 900' } | Select-Object -First 1).ProcessId }
    if (((Get-Date) - $lastSample).TotalSeconds -ge 1 -and $state -in "Waiting", "Intro", "Wear", "Mirror") {
        $lastSample = Get-Date
        $scr = (Get-Process scrcpy -ErrorAction SilentlyContinue | Select-Object -First 1).Id
        $top = [WL]::PidAt($cx, $cy)
        $want = if ($state -eq "Mirror") { if ($mirrorShown) { $scr } else { $null } } else { $station }
        if ($want) { if ($top -eq $want) { $ok++ } else { $bad++; $who = try { (Get-Process -Id $top -ErrorAction Stop).ProcessName } catch { "pid $top" }; $badWho["$state/$who"]++ } }
    }
    Start-Sleep -Milliseconds 150
}
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'visitor-station\.ps1.*QuitAfter 900' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Get-Process scrcpy -ErrorAction SilentlyContinue | Stop-Process -Force
""
"=== key events"; $events | ForEach-Object { "  $_" }
"=== visitor screen checks (once a second): $ok right, $bad wrong"
$badWho.Keys | ForEach-Object { "   wrong: $_ x $($badWho[$_])" }
