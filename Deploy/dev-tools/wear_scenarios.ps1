param([string]$Script = "$PSScriptRoot\..\visitor-station.ps1")
# Plays visits through the station with a simulated headset (status file + stand-in mirror window) and checks
# what the visitor screen shows. No intro file, so a press goes straight to "Please put on the headset".
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class WT {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern void keybd_event(byte k, byte s, uint f, UIntPtr e);
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(POINT p);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr h, uint f);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [StructLayout(LayoutKind.Sequential)] struct POINT { public int X, Y; }
    public static uint PidAt(int x, int y) { var p = new POINT { X = x, Y = y }; uint pid; GetWindowThreadProcessId(GetAncestor(WindowFromPoint(p), 2), out pid); return pid; }
}
'@
[void][WT]::SetProcessDPIAware()
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$cx = $b.X + [int]($b.Width / 2); $cy = $b.Y + [int]($b.Height / 2)
$sp = Split-Path $MyInvocation.MyCommand.Path
$status = Join-Path $sp "sim_status.txt"
$script:fails = 0

function Set-Status($s) { [IO.File]::WriteAllText("$status.tmp", $s); Move-Item "$status.tmp" $status -Force }
function Press { [WT]::keybd_event(0x78, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 150; [WT]::keybd_event(0x78, 0, 2, [UIntPtr]::Zero) }
function Check($label, $ok) { if ($ok) { "  PASS  $label" } else { "  FAIL  $label"; $script:fails++ } }

$log = Join-Path (Split-Path $Script) ("logs\station-{0:yyyy-MM-dd}.log" -f (Get-Date))
$pos = if (Test-Path $log) { (Get-Item $log).Length } else { 0 }
$script:buf = ""
function Pull { try { $fs = [IO.File]::Open($log, 'Open', 'Read', 'ReadWrite'); $fs.Seek($script:pos, 'Begin') | Out-Null; $t = (New-Object IO.StreamReader($fs)).ReadToEnd(); $script:pos = $fs.Position; $fs.Close(); $script:buf += $t } catch { } }
# Seconds until the pattern shows in the log (new lines only), or $null.
function Wait-For($pattern, $secs) { $t0 = Get-Date; while (((Get-Date) - $t0).TotalSeconds -lt $secs) { Pull; if ($script:buf -match $pattern) { $script:buf = ""; return ((Get-Date) - $t0).TotalSeconds }; Start-Sleep -Milliseconds 100 }; return $null }
# True if the pattern does NOT show for that long.
function Quiet-For($pattern, $secs) { $t0 = Get-Date; while (((Get-Date) - $t0).TotalSeconds -lt $secs) { Pull; if ($script:buf -match $pattern) { return $false }; Start-Sleep -Milliseconds 200 }; return $true }
function Top { [WT]::PidAt($cx, $cy) }

# ---- start (headset asleep on the table)
Set-Status "state=Idle worn=False paused=True films=0"
$lnk = Join-Path $env:TEMP "moi_wear_test.lnk"
$sh = New-Object -ComObject WScript.Shell; $l = $sh.CreateShortcut($lnk)
$l.TargetPath = "powershell.exe"
$l.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Script`" -SimulateHeadset `"$status`" -NoLaunchApp -SerialPort none -Intro `"C:\nonexistent\none.mp4`" -WearGiveUp 40 -QuitAfter 420"
$l.WorkingDirectory = Split-Path $Script; $l.WindowStyle = 1; $l.Save()
Start-Process $lnk
$null = Wait-For '-> Waiting' 30
$station = (Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'SimulateHeadset' } | Select-Object -First 1).ProcessId
$t0 = Get-Date; $standIn = $null; $h = [IntPtr]::Zero
while (((Get-Date) - $t0).TotalSeconds -lt 15 -and $h -eq [IntPtr]::Zero) {
    Start-Sleep -Milliseconds 300
    $standIn = (Get-CimInstance Win32_Process -Filter "ParentProcessId=$station" | Where-Object { $_.CommandLine -match 'EncodedCommand' } | Select-Object -First 1).ProcessId
    if ($standIn) { $h = (Get-Process -Id $standIn).MainWindowHandle }
}
"station pid $station, stand-in mirror pid $standIn"
Start-Sleep 1

"1. Waiting, the mirror window pushes itself on top of the station screen"
Check "station screen on top at the start" ((Top) -eq $station)
[void][WT]::SetWindowPos($h, [IntPtr](-1), 0, 0, 0, 0, 0x13)
$covered = (Top) -eq $standIn
Start-Sleep -Milliseconds 700
Check "mirror got on top ($covered), station screen back within 0.7 s" ($covered -and (Top) -eq $station)
Check "logged" ($null -ne (Wait-For 'station screen was covered' 2))

"2. Button, headset asleep on the table for 25 s (the reported case)"
Press
Check "-> Wear" ($null -ne (Wait-For '-> Wear' 5))
Check "no mirror and no reset in 25 s" (Quiet-For '-> Mirror|-> Waiting' 25)
Check "station screen ('Please put on the headset') on top" ((Top) -eq $station)

"3. Visitor puts it on"
Set-Status "state=Idle worn=True paused=False films=0"
$t = Wait-For 'mirror on screen' 5
Check ("mirror on screen after {0:N1} s" -f $t) ($null -ne $t)
Start-Sleep -Milliseconds 300
Check "mirror on top" ((Top) -eq $standIn)

"4. Headset pauses the app for 12 s (lens/IPD adjustment), still worn"
Set-Status "state=Idle worn=True paused=True films=0"
Check "no reset" (Quiet-For '-> Waiting' 12)
Check "mirror still on top" ((Top) -eq $standIn)

"5. START pressed, film plays; visitor lifts the headset for 3 s (allowed), later takes it off (visit over after 5 s)"
Set-Status "state=Playing worn=True paused=False films=1"
Check "film started" ($null -ne (Wait-For 'film started' 4))
Set-Status "state=Playing worn=False paused=False films=1"
Check "no reset while lifted 3 s" (Quiet-For '-> Waiting' 3)
Set-Status "state=Playing worn=True paused=False films=1"
Check "no reset after putting it back" (Quiet-For '-> Waiting' 2)
Check "mirror on top" ((Top) -eq $standIn)
Set-Status "state=Playing worn=False paused=False films=1"
$t = Wait-For 'headset off for 5 s[\s\S]*-> Waiting' 9
Check ("visit over {0:N1} s after taking it off, film or not" -f $t) ($t -ge 4 -and $t -le 7.5)
Start-Sleep -Milliseconds 700
Check "station screen on top" ((Top) -eq $station)
Set-Status "state=Idle worn=True paused=False films=1"
Check "headset put on again -> straight to the headset view, no button" ($null -ne (Wait-For 'straight to the headset view[\s\S]*mirror on screen' 5))
Start-Sleep 1

"6. A window that is also always-on-top opens over the mirror"
$f = New-Object System.Windows.Forms.Form
$f.FormBorderStyle = 'None'; $f.StartPosition = 'Manual'; $f.TopMost = $true; $f.ShowInTaskbar = $false
$f.Bounds = New-Object System.Drawing.Rectangle ($cx - 200), ($cy - 150), 400, 300
$f.BackColor = [System.Drawing.Color]::Orange
$f.Show(); [System.Windows.Forms.Application]::DoEvents()
$t0 = Get-Date; $seen = (Top) -eq $PID; $back = $null
while (((Get-Date) - $t0).TotalSeconds -lt 3 -and -not $back) { [System.Windows.Forms.Application]::DoEvents(); if ((Top) -eq $standIn) { $back = ((Get-Date) - $t0).TotalSeconds }; Start-Sleep -Milliseconds 50 }
$f.Close()
Check ("covered ($seen), mirror back on top after {0:N1} s" -f $back) ($seen -and $back)

"7. Film ends while the visitor still wears the headset -> waiting, then straight back into the headset view"
Set-Status "state=Playing worn=True paused=False films=2"
Check "film started" ($null -ne (Wait-For 'film started' 4))
Set-Status "state=Idle worn=True paused=False films=2"
Check "film finished -> waiting -> headset view again" ($null -ne (Wait-For 'film finished[\s\S]*-> Waiting[\s\S]*straight to the headset view' 6))
Set-Status "state=Idle worn=False paused=False films=2"
$t = Wait-For 'headset off for 5 s[\s\S]*-> Waiting' 9
Check ("taken off -> waiting after {0:N1} s" -f $t) ($t -ge 4 -and $t -le 7.5)
Start-Sleep -Milliseconds 700
Check "station screen on top" ((Top) -eq $station)

"8. Next visitor puts it on, then takes it off before pressing START"
Press
$null = Wait-For '-> Wear' 5
Set-Status "state=Idle worn=True paused=False films=1"
Check "mirror" ($null -ne (Wait-For 'mirror on screen' 5))
Set-Status "state=Idle worn=False paused=False films=1"
$t = Wait-For '-> Waiting' 14
Check ("back to waiting after {0:N1} s (expected about 5)" -f $t) ($t -ge 4 -and $t -le 7.5)

"9. Nobody puts it on (give-up set to 40 s for this test)"
Press
$null = Wait-For '-> Wear' 5
$t = Wait-For 'nobody put the headset on within 40 s[\s\S]*-> Waiting' 50
Check ("back to waiting after {0:N1} s" -f $t) ($t -ge 38 -and $t -le 43)

"10. Headset unplugged during the mirror"
Press
$null = Wait-For '-> Wear' 5
Set-Status "state=Idle worn=True paused=False films=1"
$null = Wait-For 'mirror on screen' 5
Remove-Item $status; Stop-Process -Id $standIn -Force
$t = Wait-For 'unplugged or switched off for 5 s[\s\S]*-> Waiting' 14
Check ("back to waiting after {0:N1} s" -f $t) ($null -ne $t)
Start-Sleep -Milliseconds 500
Check "station screen on top" ((Top) -eq $station)

"11. No headset at all: button -> 'Connecting to the headset...' after 12 s -> waiting 5 s later"
Press
$t1 = Wait-For 'no worn signal from the headset' 16
$t2 = Wait-For '-> Waiting' 12
Check ("mirror step after {0:N1} s, back to waiting {1:N1} s later" -f $t1, $t2) ($t1 -ge 11 -and $t2 -ge 4)

"12. Alt+F4 on the station window (sent to that window only)"
$sw = (Get-Process -Id $station).MainWindowHandle
[void][WT]::PostMessage($sw, 0x0112, [IntPtr]0xF060, [IntPtr]::Zero)   # WM_SYSCOMMAND SC_CLOSE = what Alt+F4 does
Check "ignored and logged" ($null -ne (Wait-For 'Alt\+F4 ignored' 3))
Start-Sleep 1
Check "station still running and on top" ((Get-Process -Id $station -ErrorAction SilentlyContinue) -and (Top) -eq $station)

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'SimulateHeadset' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Get-CimInstance Win32_Process -Filter "ParentProcessId=$station" -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Remove-Item $lnk, $status -ErrorAction SilentlyContinue
"failures: $script:fails"
