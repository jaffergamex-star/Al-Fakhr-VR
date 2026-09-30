$MoiRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent   # the project folder (this file is in Deploy\dev-tools)
# The station's window calls (now asynchronous) against the real scrcpy mirror: on top of an always-on-top window,
# back from minimised, lowered, raised.
$st = "$MoiRoot\Deploy\visitor-station.ps1"
$src = [regex]::Match([IO.File]::ReadAllText($st), '(?s)Add-Type -TypeDefinition @"\r?\n(.*?)\r?\n"@').Groups[1].Value
Add-Type -TypeDefinition $src -ReferencedAssemblies System.dll
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class ST {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr h, int c);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    public struct RECT { public int L, T, R, B; }
}
'@
[void][ST]::SetProcessDPIAware()
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$cx = $b.X + [int]($b.Width / 2); $cy = $b.Y + [int]($b.Height / 2)
$pkg = "$MoiRoot\Delivery\MOI_VR_Station"
$adb = "$pkg\tools\scrcpy\adb.exe"
$hs = @(& $adb devices | Select-Object -Skip 1 | Where-Object { $_ -match "\tdevice$" } | ForEach-Object { ($_ -split "\t")[0] })
if (-not $hs) { "headset not connected - skipped"; return }
$fails = 0
function Check($label, $ok) { if ($ok) { "  PASS  $label" } else { "  FAIL  $label"; $script:fails++ } }
function Pump($ms) { $t = (Get-Date).AddMilliseconds($ms); while ((Get-Date) -lt $t) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 20 } }

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "$pkg\tools\scrcpy\scrcpy.exe"
$psi.Arguments = "-s $($hs[0]) --no-control --max-size 1280 --max-fps 30 --video-bit-rate 6M --window-title `"MOI headset`" --window-borderless --window-x $($b.X) --window-y $($b.Y) --window-width $($b.Width) --window-height $($b.Height) --no-audio --crop 2000:1248:222:600 --fullscreen"
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
$p = [System.Diagnostics.Process]::Start($psi)
$h = [IntPtr]::Zero; $t0 = Get-Date
while ($h -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 15) { Start-Sleep -Milliseconds 200; $p.Refresh(); $h = $p.MainWindowHandle }
"scrcpy pid $($p.Id), window after {0:N1} s" -f ((Get-Date) - $t0).TotalSeconds
Pump 1500

$f = New-Object System.Windows.Forms.Form
$f.FormBorderStyle = 'None'; $f.StartPosition = 'Manual'; $f.TopMost = $true; $f.ShowInTaskbar = $false
$f.Bounds = New-Object System.Drawing.Rectangle ($cx - 200), ($cy - 150), 400, 300
$f.BackColor = [System.Drawing.Color]::Orange
$f.Show(); Pump 300
Check "an always-on-top window covers the mirror" ([MoiWin]::PidAt($cx, $cy) -eq $PID)
[MoiWin]::KeepOnTop($h); Pump 400
Check "KeepOnTop: mirror back on top of it" ([MoiWin]::PidAt($cx, $cy) -eq $p.Id)

[void][ST]::ShowWindowAsync($h, 6); Pump 800   # SW_MINIMIZE
Check "mirror minimised" ([ST]::IsIconic($h))
[MoiWin]::KeepOnTop($h); Pump 1200
$r = New-Object ST+RECT; [void][ST]::GetWindowRect($h, [ref]$r)
Check ("KeepOnTop: restored, full screen again ({0}x{1}) and on top" -f ($r.R - $r.L), ($r.B - $r.T)) ((-not [ST]::IsIconic($h)) -and ($r.R - $r.L) -eq $b.Width -and ($r.B - $r.T) -eq $b.Height -and [MoiWin]::PidAt($cx, $cy) -eq $p.Id)

[MoiWin]::Lower($h); $f.TopMost = $false; $f.TopMost = $true; Pump 400
Check "Lower: the other window is above the mirror again" ([MoiWin]::PidAt($cx, $cy) -eq $PID)
[void][MoiWin]::Raise($h); Pump 400
Check "Raise: mirror on top" ([MoiWin]::PidAt($cx, $cy) -eq $p.Id)
Check "scrcpy still running" (-not $p.HasExited)

$f.Close(); $p.Kill()
"failures: $fails"
